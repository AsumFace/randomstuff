module sedectree;

import zstdc;
import std.traits;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.experimental.allocator.building_blocks.stats_collector;
import word;
import required;
import cgfm.math;

static assert(size_t.sizeof <= ulong.sizeof,
     "platforms with more than 64 bit address space aren't supported :p");

enum ChildTypes
{
    pending = 0b0000,
    allTrue = 0b0001,
    allFalse = 0b0010,
    thisPtr = 0b0111,
    compressedThis = 0b0100 // contents are compressed, pointer to data stored
}

alias SedecAllocator = StatsCollector!(Mallocator, Options.all);
auto sedecAllocator = SedecAllocator();

struct SedecNode(AddressType)
    if (isIntegral!AddressType)
{
    private Word!(16, 0xf) _type;
    ChildStore[16] _children;
    static assert(_type.sizeof == 8); // should be packed exactly with no padding
    debug bool inCache;
    invariant
    {
        foreach (i; 0 .. 16)
        {
            import std.algorithm;
            assert(_type[i].asInt.among(EnumMembers!ChildTypes));

            with (ChildTypes) if (_type[i].asInt.among(thisPtr, compressedThis))
                assert(_children[i].thisPtr !is null);
            else
                assert(_children[i].pattern == 0);
        }
    }
    private union ChildStore
    {
        ulong raw;
        ulong thisOffset;
        ulong compressedOffset;
        SedecNode* thisPtr;
        ubyte* compressed;
    }

    auto opIndex(ulong x, ulong y)
    {
        return opIndex(vec2l(x, y));
    }

    auto opIndex(V)(V v)
        in(v.x < 4)
        in(v.y < 4)
    {
        return opIndex(v.x + 4 * v.y);
    }

    auto opIndex(I)(I i)
        in(i < 16)
    {
        struct ChildObject
        {
            SedecNode* context;
            invariant(context !is null);
            immutable(ubyte) i;

            ChildTypes type() const
            {
                return context._type[i].asInt;
            }

            auto thisPtr() const
                in(type == ChildTypes.thisPtr)
            {
                return context._children[i].thisPtr;
            }

            auto thisOffset() const
                in(type == ChildTypes.thisPtr)
            {
                return context._children[i].thisOffset;
            }

            auto compressedThis() const
                in(type == ChildTypes.compressed)
            {
                return context._children[i].compressed;
            }

            auto compressedOffset() const
                in(type == ChildTypes.compressed)
            {
                return context._children[i].compressedOffset;
            }

            ChildTypes type(ChildTypes val)
                in(val.among(ChildTypes.allTrue, ChildTypes.allFalse, ChildTypes.pending))
            {
                context._type[i] = val;
                context._children[i].thisPtr = null;
                return val;
            }

            auto thisPtr()
                in(type == ChildTypes.thisPtr)
            {
                return context._children[i].thisPtr;
            }

            auto thisOffset()
                in(type == ChildTypes.thisPtr)
            {
                return context._children[i].thisOffset;
            }

            auto compressedThis()
                in(type == ChildTypes.compressed)
            {
                return context._children[i].compressed;
            }

            auto compressedOffset()
                in(type == ChildTypes.compressed)
            {
                return context._children[i].compressedOffset;
            }
        }
    }

}


auto sedecTree(AddressType, alias calc)()
    if (isIntegral!AddressType)
{
    auto result = SedecTree!(AddressType, calc)(ZSTD_createCCtx, ZSTD_createDCtx);
    result.root = make!(result.NodeType)(sedecAllocator);
    return result;
}

struct SedecTree(AddressType, alias calc)
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

    bool opIndex(V)(V v)
    {
        return opIndex(v.x, v.y);
    }

    bool opIndex(AddressType i1, AddressType i2)
    {
        import std.math;
        assert(root !is null);
        NodeType* activeNode = root;
        Vector!(AddressType, 2) begin = AddressType.min;
        AddressType width = AddressType.max; // actual width is +1, a state with no width is not useful
        size_t stackOffset;
        while (true)
        {
            assert((width + 1).isPowerOf2 || width + 1 == 0); // width quartered with each step
            assert(width >= 3 && begin % 4 == 0); // smallest node covers 4x4 pixels, alignment given by nature
            auto subIdx = cast(Vector!(ubyte, 2))((Vector!(AddressType, 2)(i1, i2) - begin) / (width / 4 + 1));

            assert(activeNode !is null);
            ChildTypes result = activeNode.type[subIdx].childType;

            if (result == ChildTypes.pending)
            {
                return calc(Vector!(AddressType, 2)(i1, i2));
            }
            if (result == ChildTypes.allFalse)
                return false;
            if (result == ChildTypes.allTrue)
                return true;
            if (stackOffset == 0)
            {
                if (result == ChildTypes.thisPtr) // just jump into the next lower division and repeat
                {
                    assert(width != 3);
                    nextStep(begin, width, subIdx);
                    activeNode = activeNode.children[subIdx].thisPtr;
                    continue;
                }
                if (result == ChildTypes.compressedThis) // node is compressed
                {
                    // cache miss
                    if (*cast(ubyte**)(&cache[0 .. ulong.sizeof][0]) != activeNode.children[subIdx].compressed)
                        // we discard the existing cache and create a new one
                    {
                        ubyte* compressedBlob = activeNode.children[subIdx].compressed;
                        assert(compressedBlob !is null);
                        ulong contentSize =
                            ZSTD_getFrameContentSize(compressedBlob + ulong.sizeof, *cast(ulong*)&compressedBlob);
                        if (contentSize > size_t.max)
                            assert(0);
                        assert(contentSize % ulong.sizeof == 0);
                        cache = makeArray!void(sedecAllocator, contentSize + ulong.sizeof);
                        {
                            size_t neededSize = contentSize + size_t.sizeof;
                            bool success =
                                sedecAllocator.reallocate(cache, neededSize + neededSize / 2);
                            if (!success)
                                assert(0);
                        }
                        assert(cast(ubyte[])cache !is null); // should never fail?
                        *cast(ulong*)&cache[ulong.sizeof .. ulong.sizeof * 2][0] = contentSize;
                        ZSTD_decompressDCtx(dctx,
                            cache[].ptr + ulong.sizeof * 2, cache[].length - ulong.sizeof * 2,
                            compressedBlob + ulong.sizeof, cast(size_t)*cast(ulong*)&compressedBlob);

                        *cast(ubyte**)&cache[0 .. ulong.sizeof][0] = activeNode.children[subIdx].compressed;
                    }
                    // switch to cache
                    stackOffset =
                        cast(size_t)*cast(ulong*)&cache[ulong.sizeof .. ulong.sizeof * 2][0] + ulong.sizeof * 2;
                    nextStep(begin, width, subIdx);
                    activeNode = cast(NodeType*)&cache[ulong.sizeof * 2 .. ulong.sizeof * 2 + NodeType.sizeof][0];
                    continue;
                }
                unreachable;
            }
            else
            {
                if (result == ChildTypes.thisPtr) // in cache we need to calculate the pointer from the stored offset
                    // storing offsets instead of pointers directly has the advantage of not requiring
                    //   post processing after decompression and allows reallocation without an intermediate
                    //   representation change which would also require processing passes
                {
                    assert(width != 3);
                    nextStep(begin, width, subIdx);
                    // we want the data to be correctly aligned
                    assert(cast(ulong)cache[].ptr % ulong.sizeof == 0);
                    assert(activeNode.children[subIdx].thisOffset % ulong.sizeof == 0);

                    activeNode = cast(NodeType*)(activeNode.children[subIdx].thisOffset + cache[].ptr);
                    continue;
                }
                if (result == ChildTypes.compressedThis)
                    // instead of discarding all cache, we only discard the mismatching compression branch
                {
                    void[] dst = calcFreeRange(cache[stackOffset .. $], activeNode);

                    ubyte* compressedBlob = activeNode.children[subIdx].compressed;
                    assert(compressedBlob !is null);

                    ulong contentSize = 0;

                    // if the data can fit and the pointers match, we have a cache hit
                    if (dst[].length >= ulong.sizeof * 2 + NodeType.sizeof
                        && *cast(ubyte**)&dst[0] == activeNode.children[subIdx].compressed)
                    {
                        activeNode =
                            cast(NodeType*)&(dst[ulong.sizeof * 2 .. ulong.sizeof * 2 + NodeType.sizeof][0]);
                        stackOffset += *cast(ulong*)&dst[ulong.sizeof .. ulong.sizeof * 2][0];
                        nextStep(begin, width, subIdx);
                        continue;
                    }

                    // cache miss
                    contentSize =
                        ZSTD_getFrameContentSize(compressedBlob + ulong.sizeof, *cast(ulong*)&compressedBlob);
                    size_t neededSize = contentSize + ulong.sizeof * 2;
                    if (dst[].length < neededSize)
                        // reallocate to make space
                    {
                        if (contentSize > size_t.max)
                            assert(0);
                        assert(contentSize % ulong.sizeof == 0);
                        {
                            ptrdiff_t activeOffset = cast(void*)activeNode - cache.ptr;

                            bool success =
                                sedecAllocator.reallocate(cache, neededSize + neededSize / 2);
                            if (!success)
                                assert(0);
                            activeNode = cast(NodeType*)(cache.ptr + activeOffset);
                        }
                    }

                    assert(cast(ubyte[])dst !is null); // should never fail
                    *cast(ubyte**)&dst[0 .. ulong.sizeof][0] = compressedBlob;
                    *cast(ulong*)&dst[ulong.sizeof .. ulong.sizeof * 2][0] = contentSize;
                    ZSTD_decompressDCtx(dctx,
                        dst.ptr + ulong.sizeof * 2, dst.length - ulong.sizeof * 2,
                        compressedBlob + ulong.sizeof, cast(size_t)*cast(ulong*)&compressedBlob);
                    activeNode = cast(NodeType*)(activeNode.children[subIdx].thisOffset + cache[].ptr);
                    {
                        size_t newStackOffset = dst[].ptr - cache[].ptr + neededSize;
                        assert(newStackOffset == stackOffset + neededSize);
                    }
                    nextStep(begin, width, subIdx);
                    stackOffset += neededSize;
                    continue;
                }
                unreachable;
            }
            unreachable;
        }
    }

    void nextStep(V)(ref Vector!(AddressType, 2) begin, ref AddressType width, V pos)
    {
        begin += cast(Vector!(AddressType, 2))pos * (width / 4 + 1);
        width /= 4;
    }

    // src is the pointer to the compressed blob
    // dst to the cache buffer
    void[] cache;

    //NodeType*[AddressType.sizeof * 8 / 2] stack;

    /+void optimize()
    {
        NodeType*[AddressType.sizeof * 8 / 2] stack;
        ubyte[AddressType.sizeof * 8 / 2] idx;
        ubyte depth = 0;

        stack[depth] = root;

        while (true)
        {
            if (depth > 0)
            {
                import std.algorithm;
                if (stack[depth]._type.all!(n => n.asInt == ChildTypes.allTrue))
                {
                    stack[depth - 1]._type[idx[depth - 1]] = ChildTypes.allTrue;

                    // this field has no meaning, is however seen by the compressor
                    stack[depth - 1]._children[idx[depth - 1]].thisOffset = 0;
                    recursiveFree(stack[depth]);
                    depth -= 1;
                }
                else if (stack[depth]._type.all!(n => n.asInt == ChildTypes.allFalse))
                {
                    stack[depth - 1]._type[idx[depth - 1]] = ChildTypes.allFalse;
                    stack[depth - 1]._children[idx[depth - 1]].thisOffset = 0;
                    recursiveFree(stack[depth]);
                    depth -= 1;
                }
            }
            ChildTypes result = cast(ChildTypes)stack[depth]._type[idx[depth]];

        }
    }+/

    void recursiveFree(NodeType* node)
    {}

    bool opIndexAssign(V)(bool val, V v)
    {
        return opIndexAssign(val, v.x, v.y);
    }

    bool opIndexAssign(bool val, AddressType i1, AddressType i2)
    {
        NodeType* activeNode = root;
        Vector!(AddressType, 2) begin = AddressType.min;
        AddressType width = AddressType.max;
        ubyte stackIdx = 0;

        while (true)
        {
            assert(width >= 3 && begin % 4 == 0);
            auto subIdx = cast(Vector!(ubyte, 2))((Vector!(AddressType, 2)(i1, i2) - begin) / (width / 4 + 1));
            ChildTypes result = activeNode.type[subIdx].childType;

            if (width == 3)
            {
                activeNode.type[subIdx].childType = val ? ChildTypes.allTrue : ChildTypes.allFalse;
                with (ChildTypes) switch (activeNode.type[subIdx].childType)
                {
                case allFalse:
                    return false;
                case allTrue:
                    return true;
                default:
                    unreachable;
                }
            }

            // early exit to avoid degradation of the tree
            if (result == (val ? ChildTypes.allTrue : ChildTypes.allFalse))
            {
                return val;
            }

            if (result == ChildTypes.allFalse || result == ChildTypes.allTrue || result == ChildTypes.pending)
            {
                activeNode.type[subIdx].childType = ChildTypes.thisPtr;
                activeNode.children[subIdx].thisPtr = make!NodeType(sedecAllocator);
                activeNode = activeNode.children[subIdx].thisPtr;
                foreach (ii; 0 .. 16)
                {
                    activeNode._type[ii] = result;
                }
                nextStep(begin, width, subIdx);
                continue;

            }
            if (result == ChildTypes.thisPtr)
            {
                nextStep(begin, width, subIdx);
                activeNode = activeNode.children[subIdx].thisPtr;
                continue;
            }
            if (result == ChildTypes.compressedThis)
            {
                dctx.ZSTD_initDStream;
                ZSTD_inBuffer srcBuf;
                ZSTD_outBuffer dstBuf;

                srcBuf.src = activeNode.children[subIdx].compressed + ulong.sizeof;
                srcBuf.size = *cast(ulong*)activeNode.children[subIdx].compressed;
                assert(srcBuf.size >= NodeType.sizeof);

                NodeType*[AddressType.sizeof * 8 / 2] nodeStack;
                ubyte[AddressType.sizeof * 8 / 2] addrStack;
                ubyte depth = 0;

                ChildTypes type = ChildTypes.thisPtr;
                addrStack[depth] = 0;
                nodeStack[depth] = make!NodeType(sedecAllocator);
                if (nodeStack[depth] is null)
                    assert(0);
                dstBuf.dst = nodeStack[depth];
                dstBuf.size = nodeStack[depth].sizeof;
                dctx.ZSTD_decompressStream(&dstBuf, &srcBuf);
                assert(dstBuf.pos == dstBuf.size); // must have written exactly 8 bytes
                while (true)
                {
                    if (addrStack[depth] == 16)
                    {
                        if (depth == 0)
                            break;
                        depth -= 1;
                    }
                    type = cast(ChildTypes)nodeStack[depth]._type[addrStack[depth]].asInt;
                    if (type == ChildTypes.allFalse || type == ChildTypes.allTrue || type == ChildTypes.pending)
                    {
                        addrStack[depth] += 1;
                        continue;
                    }
                    if (type == ChildTypes.thisPtr)
                    {
                        addrStack[depth] += 1;
                        depth += 1;
                        assert(depth < addrStack[].length); // last depth mustn't contain thisPtr
                        addrStack[depth] = 0;
                        nodeStack[depth] = make!NodeType(sedecAllocator);
                        if (nodeStack[depth] is null)
                            assert(0);

                        // back reference
                        nodeStack[depth - 1]._children[addrStack[depth - 1] - 1].thisPtr = nodeStack[depth];
                        dstBuf.dst = nodeStack[depth];
                        dstBuf.size = nodeStack[depth].sizeof;
                        dstBuf.pos = 0;
                        dctx.ZSTD_decompressStream(&dstBuf, &srcBuf);
                        assert(dstBuf.pos == dstBuf.size); // must have written exactly 8 bytes
                        continue;
                    }
                    if (type == ChildTypes.compressedThis)
                    {
                        ulong size;
                        dstBuf.dst = &size;
                        dstBuf.size = ulong.sizeof;
                        dstBuf.pos = 0;
                        dctx.ZSTD_decompressStream(&dstBuf, &srcBuf); // retrieve blob size
                        assert(dstBuf.pos == dstBuf.size);

                        void[] target = makeArray!void(sedecAllocator, size + ulong.sizeof);
                        if (target is null)
                            assert(0);
                        *cast(ulong*)target[0 .. ulong.sizeof].ptr = size; // place size prefix
                        dstBuf.dst = &target[ulong.sizeof];
                        dstBuf.size = size;
                        assert(size == target[ulong.sizeof .. $].length);
                        dstBuf.pos = 0;

                        dctx.ZSTD_decompressStream(&dstBuf, &srcBuf); // write blob

                        // reference it
                        nodeStack[depth]._children[addrStack[depth]].compressed = cast(ubyte*)dstBuf.dst;

                        addrStack[depth] += 1;
                        continue;
                    }
                    unreachable;
                }
                continue;
            }
            unreachable;
        }
    }

    ~this()
    {
        ZSTD_freeCCtx(cctx);
        ZSTD_freeDCtx(dctx);
        sedecAllocator.dispose(cache);
    }

    void[] calcFreeRange(void[] p, void* currPos)
    {
        assert(currPos >= p.ptr && currPos < p.ptr + p.length); // currPos must be in range
        while (true)
        {
            if (p.length < (ulong.sizeof * 2 + NodeType.sizeof) // no space for further data
                || *cast(ulong*)p[0 .. ulong.sizeof] == 0 // next ID or offset indicates no further data
                || p.ptr > currPos) // we may only want the next valid address range
                break;
            size_t offset = cast(size_t)*cast(ulong*)p[ulong.sizeof .. ulong.sizeof * 2].ptr;

            p = p[offset + ulong.sizeof * 2 .. $];
        }
        return p;
    }

    ubyte[] packNode(NodeType* node)
    {
        import std.algorithm.mutation;
        import std.algorithm.comparison;
        NodeType*[AddressType.sizeof * 8 / 2] stack;
        ubyte[AddressType.sizeof * 8 / 2] idx;
        ubyte depth = 0;
        ubyte[] dst = makeArray!ubyte(sedecAllocator, 1024);
        ulong written = 0;

        (*cast(ubyte[NodeType.sizeof]*)node)[].copy(dst[written .. $]);
        written += ulong.sizeof;

        stack[depth] = cast(NodeType*)&dst[0 .. ulong.sizeof][0];

        with (ChildTypes) while (true)
        {
            assert(depth <= stack.length);
            if (idx[depth] == 16)
            {
                if (depth == 0)
                    break;
                depth -= 1;
                continue;
            }
            ChildTypes type = cast(ChildTypes)stack[depth]._type[idx[depth]].asInt;
            if (type.among(allFalse, allTrue, pending))
            {
                idx[depth] += 1;
                continue;
            }
            if (type == thisPtr)
            {
                if (dst[].length < written + NodeType.sizeof) // data doesn't fit
                {
                    const(ubyte*) orig = dst.ptr;
                    assert(dst[].length / 2 >= NodeType.sizeof);
                    if (!expandArray(sedecAllocator, dst, dst[].length / 2))
                        assert(0);
                    foreach (ref e; stack[])
                        e += orig - dst.ptr;
                }

                // extract pointer and change it to the offset in the new packed blob
                import std.stdio;
                import std.algorithm;
                writefln("[%(%s,%)][%(%s,%)]",
                     stack[depth]._type[].map!(n => cast(ChildTypes)n),
                     stack[depth]._children[].map!(n => n.thisOffset));

                assert(stack[depth]._children[idx[depth]].thisPtr !is null);
                ubyte[] data = (*cast(ubyte[ulong.sizeof]*)(stack[depth]._children[idx[depth]].thisPtr))[];
                stack[depth]._children[idx[depth]].thisOffset = written;

                assert(data.ptr !is null);
                assert(data.length == 8);
                assert(dst.ptr !is null);
                assert(dst[written .. $].length >= 8);

                data[].copy(dst[written .. $]);

                idx[depth] += 1;
                depth += 1;
                idx[depth] = 0;
                stack[depth] = cast(NodeType*)&dst[written .. $][0 .. ulong.sizeof][0];

                written += NodeType.sizeof;
                continue;
            }
            if (type == compressedThis)
            {
                // extract pointer and change it to the offset in the new packed blob
                ubyte* blob = stack[depth]._children[idx[depth]].compressed;
                stack[depth]._children[idx[depth]].thisOffset = written;

                assert(blob !is null);
                assert(written <= dst[].length);
                ulong compressedLength = *cast(ulong*)blob;
                if (dst[].length < written + compressedLength + ulong.sizeof) // data doesn't fit
                {
                    const(ubyte*) orig = dst.ptr;
                    if (!expandArray(sedecAllocator, dst, max(compressedLength + ulong.sizeof, dst[].length / 2)))
                        assert(0);
                    foreach (ref e; stack[])
                        e += orig - dst.ptr;
                }
                blob[0 .. compressedLength + ulong.sizeof].copy(dst[written .. $]);
                written += compressedLength + ulong.sizeof;
                idx[depth] += 1;
                continue;
            }
            unreachable;
        }
        return dst;
    }
}

alias auie = SedecTree!(uint, e => true);

