module sedectree;

import zstdc;
import std.traits;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import word;
import cgfm.math;

enum ChildTypes
{
    allFalse,
    allTrue,
    thisPtr,
    compressedThis, // when decompressed, becomes thisPtr if compressed blob discarded, cache if not
    cache // cache can be converted back to compressedThis by changing to the contained pointer to the compressed data
}

struct SedecNode(AddressType)
    if (isIntegral!AddressType)
{
    private Word!(16, 0xf) _type;
    static assert(_type.sizeof == 8);
    _Type type()
    {
        return _Type(&this);
    }

    private struct _Type
    {
        SedecNode* context;

        ChildTypes opIndex(V)(V v)
        {
            return opIndex(v.x, v.y);
        }

        ChildTypes opIndex(ulong i1, ulong i2)
        {
            return cast(ChildTypes)context._type[i1 + i2 * 4].asInt;
        }

        ChildTypes opIndexAssign(ChildTypes val, ulong i1, ulong i2)
        {
            context._type[i1 + i2 * 4] = val;
            return val;
        }
    }

    union ChildStore
    {
        size_t pattern;
        size_t thisOffset;
        SedecNode* thisPtr;
        ubyte* compressed;
    }
    ChildStore[16] _children;
    _Children children()
    {
        return _Children(&this);
    }
    private struct _Children
    {
        SedecNode* context;

        ref ChildStore opIndex(V)(V v)
        {
            return opIndex(v.x, v.y);
        }

        ref ChildStore opIndex(ulong i1, ulong i2)
        {
            return context._children[i1 + i2 * 4];
        }

        ref ChildStore opIndexAssign(ChildStore val, ulong i1, ulong i2)
        {
            return context._children[i1 + i2 * 4] = val;
        }
    }
}


auto sedecTree(AddressType)()
    if (isIntegral!AddressType)
{
    return SedecTree!AddressType(ZSTD_createCCtx, ZSTD_createDCtx);
}

struct SedecTree(AddressType)
    if (isIntegral!AddressType)
{
    private ZSTD_CCtx* cctx;
    private ZSTD_DCtx* dctx;

    invariant
    {
        assert(cctx !is null);
        assert(dctx !is null);
    }

    alias NodeType = SedecNode!AddressType;

    NodeType* root;

    bool opIndex(AddressType i1, AddressType i2)
    {
        import std.math;
        NodeType* activeNode = root;
        Vector!(AddressType, 2) begin = AddressType.min;
        AddressType width = AddressType.max; // actual width is +1, a state with no width is not useful
        size_t stackOffset;
        while (true)
        {
            assert((width + 1).isPowerOf2 || width + 1 == 0); // width quartered with each step
            assert(width >= 3 && begin % 4 == 0); // smallest node covers 4x4 pixels, alignment given by nature
            auto subIdx = cast(Vector!(ubyte, 2))((Vector!(AddressType, 2)(i1, i2) - begin) / (width / 4 + 1));
            ChildTypes result = activeNode.type[subIdx];
            if (result == ChildTypes.allFalse)
                return false;
            if (result == ChildTypes.allTrue)
                return true;
            if (stackOffset == 0)
            {
                assert(result != ChildTypes.cache); // cache children only allowed in cache space
                if (result == ChildTypes.thisPtr) // just jump into the next lower division and repeat
                {
                    assert(width != 3);
                    begin += (width / 4 + 1);
                    width /= 4;
                    activeNode = activeNode.children[subIdx];
                }
                if (result == ChildTypes.compressedThis) // node is compressed
                {
                    // cache miss
                    if (cast(ubyte**)(&cache[0 .. size_t.sizeof][0]) != activeNode.children[subIdx].compressed)
                        // we discard the existing cache and create a new one
                    {
                        ubyte* compressedBlob = activeNode.children[subIdx].compressed;
                        assert(compressedBlob !is null);
                        ulong contentSize =
                            ZSTD_getFrameContentSize(compressedBlob + size_t.sizeof, *cast(size_t*)&compressedBlob);
                        if (contentSize > size_t.max)
                            assert(0);
                        assert(contentSize % size_t.sizeof == 0);
                        cache = makeArray!void(Mallocator.instance, contentSize + size_t.sizeof);
                        {
                            size_t neededSize = contentSize + size_t.sizeof;
                            bool success =
                                Mallocator.instance.reallocate(cache, neededSize + neededSize / 2);
                            if (!success)
                                assert(0);
                        }
                        assert(cache !is null); // should never fail?
                        *cast(size_t*)&cache[size_t.sizeof .. size_t.sizeof * 2][0] = contentSize;
                        ZSTD_decompressDCtx(dctx,
                            cache[].ptr + size_t.sizeof * 2, cache[].length - size_t.sizeof * 2,
                            compressedBlob + size_t.sizeof, *cast(size_t*)&compressedBlob);

                        *cast(ubyte**)&cache[0 .. size_t.sizeof][0] = activeNode.children[subIdx].compressedThis;
                    }
                    // switch to cache
                    stackOffset = *cast(size_t*)&cache[size_t.sizeof .. size_t.sizeof * 2][0] + size_t.sizeof * 2;
                    begin += (width / 4 + 1);
                    width /= 4;
                    activeNode = cast(NodeType*)&cache[size_t.sizeof * 2 .. size_t.sizeof * 2 + NodeType.sizeof][0];
                    continue;
                }
            }
            else
            {
                if (result == ChildTypes.thisPtr) // in cache we need to calculate the pointer from the stored offset
                    // storing offsets instead of pointers directly has the advantage of not requiring
                    //   post processing after decompression and allows reallocation without an intermediate
                    //   representation change which would also require processing passes
                {
                    assert(width != 3);
                    begin += (width / 4 + 1);
                    width /= 4;
                    // we want the data to be correctly aligned
                    assert(cache[].ptr % size_t.sizeof == 0);
                    assert(activeNode.children[subIdx].thisOffset % size_t.sizeof == 0);

                    activeNode = cast(NodeType*)(activeNode.children[subIdx].thisOffset + cache[].ptr);
                    continue;
                }
                if (result == ChildTypes.compressedThis)
                    // instead of discarding all cache, we only discard the mismatching compression branch
                {
                    size_t nextOffset = activeNode.children.thisOffset;
                    void[] dst = calcFreeRange(cache[stackOffset .. $], activeNode);

                    ubyte* compressedBlob = activeNode.children[subIdx].compressed;
                    assert(compressedBlob !is null);

                    ulong contentSize = 0;

                    // if the data can fit and the pointers match, we have a cache hit
                    if (dst[].length >= size_t.sizeof * 2 + NodeType.sizeof
                        && *cast(ubyte**)&dst[0] == activeNode.children[subIdx].compressedThis)
                    {
                        activeNode =
                            cast(NodeType*)&(dst[size_t.sizeof * 2 .. size_t.sizeof * 3 + NodeType.sizeof][0]);
                        stackOffset += *cast(size_t)&dst[size_t.sizeof .. size_t.sizeof * 2][0];
                        begin += (width / 4 + 1);
                        width /= 4;
                        continue;
                    }

                    // cache miss
                    ulong contentSize =
                        ZSTD_getFrameContentSize(compressedBlob + size_t.sizeof, *cast(size_t*)&compressedBlob);
                    size_t neededSize = contentSize + size_t.sizeof * 2;
                    if (dst[].length < neededSize)
                        // reallocate to make space
                    {
                        if (contentSize > size_t.max)
                            assert(0);
                        assert(contentSize % size_t.sizeof == 0);
                        {
                            ptrdiff_t activeOffset = cast(void*)activeNode - cache.ptr;

                            bool success =
                                Mallocator.instance.reallocate(cache, neededSize + neededSize / 2);
                            if (!success)
                                assert(0);
                            activeNode = cast(NodeType*)(cache.ptr + activeOffset);
                        }
                    }

                    assert(dst !is null); // should never fail
                    *cast(ubyte**)&dst[0 .. size_t.sizeof][0] = compressedBlob;
                    *cast(size_t*)&dst[size_t.sizeof .. size_t.sizeof * 2][0] = contentSize;
                    ZSTD_decompressDCtx(dctx,
                        dst.ptr + size_t.sizeof * 2, dst.length - size_t.sizeof * 2,
                        compressedBlob + size_t.sizeof, *cast(size_t*)&compressedBlob);
                    activeNode = cast(NodeType*)(activeNode.children[subIdx].thisOffset + cache[].ptr);
                    {
                        size_t newStackOffset = dst[].ptr - cache[].ptr + neededSize;
                        assert(newStackOffset == stackOffset + neededSize);
                    }
                    begin += (width / 4 + 1);
                    width /= 4;
                    stackOffset += neededSize;
                    continue;
                }
            }
            unreachable;
        }
    }

    // src is the pointer to the compressed blob
    // dst to the cache buffer
    void[] cache;


    bool opIndexAssign(bool val, AddressType i1, AddressType i2)
    {
    }


    ~this()
    {
        ZSTD_freeCCtx(cctx);
        ZSTD_freeDCtx(dctx);
        Mallocator.instance.dispose(cache);
    }

    void[] calcFreeRange(void[] p, void* currPos)
    {
        assert(currPos >= p.ptr && currPos < p.ptr + p.length); // currPos must be in range
        while (true)
        {
            if (p.length < (size_t.sizeof * 2 + NodeType.sizeof) // no space for further data
                || *cast(size_t*)p[0 .. size_t.sizeof] == 0 // next ID or offset indicates no further data
                || p.ptr > currPos) // we may only want the next valid address range
                break;
            size_t offset = *cast(size_t*)p[size_t.sizeof .. size_t.sizeof * 2].ptr;
            totalOffset += offset;

            p = p[offset + size_t.sizeof * 2 .. $];
        }
        return p;
    }
}

alias auie = SedecTree!uint;
