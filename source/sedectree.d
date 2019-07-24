module sedectree;

import zstdc;
import std.traits;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.experimental.allocator.building_blocks.stats_collector;
import word;
import required;
import cgfm.math;
import std.typecons;
import std.format;
import std.string : fromStringz;
import std.stdio;

static assert(size_t.sizeof <= ulong.sizeof,
     "platforms with more than 64 bit address space aren't supported :p");

enum ChildTypes
{
    pending = 0b0000,
    allTrue = 0b0001,
    allFalse = 0b0010,
    thisPtr = 0b0111,
    compressedThis = 0b0100, // contents are compressed, pointer to data stored
}

alias SedecAllocator = StatsCollector!(Mallocator, Options.all);
auto sedecAllocator = SedecAllocator();

debug
    enum ulong byOffsetFlag = 0b1000;
else
    enum ulong byOffsetFlag = 0;

struct SedecNode(AddressType)
    if (isIntegral!AddressType)
{
    private Word!(16, 0xf) _type;
    private ChildStore[16] _children;
    debug ulong _protector = 0xdeadbeef;

    static assert(_type.sizeof == 8); // should be packed exactly with no padding
    invariant
    {
        debug assert(_protector == 0xdeadbeef, format("protector has been corrupted! %08x, this at %x", _protector, &this));
        assert(null is cast(void*)0, "null pointer does not point to 0. this code assumes that");
        //assert(cast(size_t)&this < 0xff00000000000000);
        foreach (i; 0 .. 16)
        {
            import std.stdio;
            import std.algorithm;
            //stderr.writefln("%x", &this);
            assert((_type[i].asInt & 0b111).among(EnumMembers!ChildTypes), format!"0b%04b in %s is not a valid ChildTypes value"(_type[i].asInt, i));

            with (ChildTypes) if ((_type[i].asInt & 0b111).among(thisPtr, compressedThis))
            {
                debug assert((_type[i].asInt & byOffsetFlag) > 0
                    || _children[i].thisPtr ! is null, format!"byOffset: %s | ptr: %s"((_type[i].asInt & byOffsetFlag) != 0, _children[i].thisPtr));
            }
            else
            {
                assert((_type[i].asInt & byOffsetFlag) == 0, format!"byOffset in %s is incorrectly set; %s"(i, _toString));
                assert(_children[i].raw == 0, format!"type: %s | value: %s | byOffset: %s"(cast(ChildTypes)(_type[i].asInt&0b111), _children[i].raw, (_type[i].asInt & byOffsetFlag) != 0));
            }
        }
    }
    private union ChildStore
    {
        ulong raw;
        void[8] data;
        ulong thisOffset;
        ulong compressedOffset;
        SedecNode* thisPtr;
        ubyte* compressed;
    }

    private string _toString() const
    {
        import std.format;
        import std.algorithm;
        auto result = format("%x{%(%04b,%)}{", _protector, _type[]);
        foreach (i, ref e; _children[])
        {
            if ((_type[i].asInt & byOffsetFlag) > 0)
                result ~= format("%d", e.thisOffset);
            else
                result ~= format("%x", e.thisPtr);
            if (i + 1 != _children[].length)
                result ~= ",";
        }
        result ~= "}";
        return result;
    }

    string toString() const
    {
        return _toString;
    }

    auto opIndex(ulong x, ulong y)
    {
        return opIndex(vec2l(x, y));
    }

    auto opIndex(V)(V v)
        if (isInstanceOf!(Vector, V))
        in(v.x < 4)
        in(v.y < 4)
    {
        return opIndex(v.x + 4 * v.y);
    }

    auto opIndex()
    {
        struct NodeRange
        {
            invariant(context !is null);
            invariant(idx <= 16);
            SedecNode* context;
            private ubyte idx;
            bool empty() const
            {
                return idx >= 16;
            }

            void popFront()
                in(!empty)
            {
                idx += 1;
            }

            auto front()
                in(!empty)
            {
                return context.opIndex(idx);
            }

            ubyte length() const
            {
                return cast(ubyte)(16 - idx);
            }
        }
        return NodeRange(&this, 0);
    }

    auto opIndex(I)(I i)
        if (isIntegral!I)
        in(i < 16, format!"index %s is out of bounds! ([0 .. 16])"(i))
    {
        struct ChildObject
        {
            SedecNode* context;
            invariant(context !is null);
            immutable(ubyte) i;

            bool byOffset() const
                in((context._type[i].asInt & 0b111).among(ChildTypes.thisPtr, ChildTypes.compressedThis))
            {
                static assert(byOffsetFlag != 0, "byOffset flag is only available in debug mode");
                return (context._type[i].asInt & byOffsetFlag) != 0;
            }

            ChildTypes type() const
                in((context._type[i].asInt & 0b111).among(EnumMembers!ChildTypes))
            {
                return cast(ChildTypes)(context._type[i].asInt & 0b111);
            }

            ref SedecNode* thisPtr()
                in(type == ChildTypes.thisPtr)
                out(r; r !is null)
            {
                debug assert(byOffset == false);
                return context._children[i].thisPtr;
            }

            auto thisOffset()
                in(type == ChildTypes.thisPtr)
            {
                debug assert(byOffset == true);
                return context._children[i].thisOffset;
            }

            ref ubyte* compressedThis()
                in(type == ChildTypes.compressedThis)
                out(r; r !is null)
            {
                debug assert(byOffset == false);
                return context._children[i].compressed;
            }

            ulong compressedOffset()
                in(type == ChildTypes.compressedThis)
            {
                debug assert(byOffset == true);
                return context._children[i].compressedOffset;
            }

            import std.algorithm : among;
            ChildTypes type(ChildTypes val)
                in(val.among(ChildTypes.allTrue, ChildTypes.allFalse, ChildTypes.pending),
                    "A type with payload must be set implicitly by assigning"
                    ~ " the desired value using one of the setters")
            {
                context._type[i] = val;
                context._children[i].raw = 0;
                return val;
            }

            auto thisPtr(SedecNode* val)
                in(val !is null)
                out(; type == ChildTypes.thisPtr)
            {
                context._children[i].thisPtr = val;
                context._type[i] = ChildTypes.thisPtr;
                return val;
            }

            auto thisOffset(ulong val)
                out(; type == ChildTypes.thisPtr)
            {
                context._children[i].thisOffset = val;
                context._type[i] = ChildTypes.thisPtr | byOffsetFlag;
                return val;
            }

            auto compressedThis(ubyte* val)
                in(val !is null)
                out(; type == ChildTypes.compressedThis)
            {
                context._children[i].compressed = val;
                context._type[i] = ChildTypes.compressedThis;
                return val;
            }

            auto compressedOffset(ulong val)
                out(; type() == ChildTypes.compressedThis)
            {
                context._children[i].compressedOffset = val;
                context._type[i] = ChildTypes.compressedThis | byOffsetFlag;
                return val;
            }

            void[] data()
                in(!type.among(ChildTypes.allTrue, ChildTypes.allFalse, ChildTypes.pending))
            {
                return context._children[i].data[];
            }
        }
        return ChildObject(&this, cast(ubyte)i);
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
        int depth = 0;
        assert(root !is null);
        NodeType* activeNode = root;
        assert(&*activeNode);
        Vector!(AddressType, 2) begin = AddressType.min;
        AddressType width = AddressType.max; // actual width is +1, a state with no width is not useful
        size_t stackOffset;
        while (true)
        {
            assert((width + 1).isPowerOf2 || width + 1 == 0); // width quartered with each step
            assert(width >= 3 && begin % 4 == 0); // smallest node covers 4x4 pixels, alignment given by nature
            auto subIdx = cast(Vector!(ubyte, 2))((Vector!(AddressType, 2)(i1, i2) - begin) / (width / 4 + 1));
            stderr.writefln("w%s d%s %s", width, depth, (*activeNode).toString);
            assert(activeNode !is null);
            ChildTypes result = (*activeNode)[subIdx].type;

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
                    nextStep(begin, width, subIdx); depth += 1;
                    activeNode = (*activeNode)[subIdx].thisPtr;
                    continue;
                }
                if (result == ChildTypes.compressedThis) // node is compressed
                {
                    // cache miss
                    if (cache is null
                        ||*cast(ubyte**)(&cache[0 .. ulong.sizeof][0]) != (*activeNode)[subIdx].compressedThis)
                        // we discard the existing cache and create a new one
                    {
                        ubyte* compressedBlob = (*activeNode)[subIdx].compressedThis;
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

                        *cast(ubyte**)&cache[0 .. ulong.sizeof][0] = (*activeNode)[subIdx].compressedThis;
                    }
                    // switch to cache
                    stackOffset =
                        cast(size_t)*cast(ulong*)&cache[ulong.sizeof .. ulong.sizeof * 2][0] + ulong.sizeof * 2;
                    nextStep(begin, width, subIdx); depth += 1;
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
                    assert((*activeNode)[subIdx].thisOffset % ulong.sizeof == 0);

                    activeNode = cast(NodeType*)((*activeNode)[subIdx].thisOffset + cache[].ptr);
                    continue;
                }
                if (result == ChildTypes.compressedThis)
                    // instead of discarding all cache, we only discard the mismatching compression branch
                {
                    void[] dst = calcFreeRange(cache[stackOffset .. $], activeNode);

                    ubyte* compressedBlob = (*activeNode)[subIdx].compressedThis;
                    assert(compressedBlob !is null);

                    ulong contentSize = 0;

                    // if the data can fit and the pointers match, we have a cache hit
                    if (dst[].length >= ulong.sizeof * 2 + NodeType.sizeof
                        && *cast(ubyte**)&dst[0] == (*activeNode)[subIdx].compressedThis)
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
                    activeNode = cast(NodeType*)((*activeNode)[subIdx].thisOffset + cache[].ptr);
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
            ChildTypes result = (*activeNode)[subIdx].type;

            if (width == 3)
            {
                (*activeNode)[subIdx].type = val ? ChildTypes.allTrue : ChildTypes.allFalse;
                with (ChildTypes) switch ((*activeNode)[subIdx].type)
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
                (*activeNode)[subIdx].thisPtr = make!NodeType(sedecAllocator);
                activeNode = (*activeNode)[subIdx].thisPtr;
                foreach (ii; 0 .. 16)
                {
                    (*activeNode)[ii].type = result;
                }
                nextStep(begin, width, subIdx);
                continue;
            }
            if (result == ChildTypes.thisPtr)
            {
                nextStep(begin, width, subIdx);
                activeNode = (*activeNode)[subIdx].thisPtr;
                continue;
            }
            if (result == ChildTypes.compressedThis)
            {
                dctx.ZSTD_initDStream;
                ZSTD_inBuffer srcBuf;
                ZSTD_outBuffer dstBuf;

                ubyte* blob = (*activeNode)[subIdx].compressedThis;
                srcBuf.src = blob + ulong.sizeof;
                srcBuf.size = *cast(ulong*)blob;
                //assert(srcBuf.size >= NodeType.sizeof);

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
                auto status = dctx.ZSTD_decompressStream(&dstBuf, &srcBuf);
                assert(!ZSTD_isError(status), ZSTD_getErrorName(status).fromStringz);
                assert(dstBuf.pos == dstBuf.size); // must have written exactly 8 bytes
                mainLoop: while (true)
                {
                    while (addrStack[depth] >= 16)
                    {
                        if (depth == 0)
                            break mainLoop;
                        depth -= 1;
                    }
                    assert(addrStack[depth] < 16);
                    assert(depth < nodeStack.length);
                    type = (*nodeStack[depth])[addrStack[depth]].type;
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
                        (*nodeStack[depth - 1])[addrStack[depth - 1] - 1].thisPtr = nodeStack[depth];
                        dstBuf.dst = nodeStack[depth];
                        dstBuf.size = nodeStack[depth].sizeof;
                        dstBuf.pos = 0;

                        status = dctx.ZSTD_decompressStream(&dstBuf, &srcBuf);
                        assert(!ZSTD_isError(status), ZSTD_getErrorName(status).fromStringz);
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

                        status = dctx.ZSTD_decompressStream(&dstBuf, &srcBuf); // write blob
                        assert(!ZSTD_isError(status), ZSTD_getErrorName(status).fromStringz);

                        // reference it
                        (*nodeStack[depth])[addrStack[depth]].compressedThis = cast(ubyte*)dstBuf.dst;

                        addrStack[depth] += 1;
                        continue;
                    }
                    unreachable;
                }
                sedecAllocator.dispose(blob);
                continue;
            }
            unreachable;
        }
        unreachable;
        return bool.init;
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

    ubyte[] packNode(Flags...)(NodeType* node)
        if (allSatisfy!(isFlag, typeof(Flags)))
    {
        enum freeCopied = flagValue!(Flags)("freeCopied");
        assert(freeCopied != -1, "Please specify whether packNode should automatically free nodes!");
        ubyte[] dst = makeArray!ubyte(sedecAllocator, 1024);
        if (dst is null)
            assert(0);
        ulong written = pack!(freeCopied)(node, dst, ulong.sizeof);
        objcpy(written, dst[0 .. ulong.sizeof]);
        static if (freeCopied)
            sedecAllocator.dispose(node);
        sedecAllocator.shrinkArray(dst, dst.length - written);
        return dst;
    }

    ulong pack(bool freeCopied)(NodeType* node, ref ubyte[] dst, ulong pos)
        in(node !is null)
        in(pos <= dst.length)
    {
        if (dst.length - pos >= NodeType.sizeof)
        {
            import std.algorithm : max;
            if (!sedecAllocator.expandArray(dst, max(dst.length / 2, NodeType.sizeof)))
                assert(0);
        }
        ulong occupied = 0;

        objcpy(*node, dst[pos .. $]);
        occupied += NodeType.sizeof;

        // we only know the offset in the array, the array may be relocated by subsequent packing
        NodeType* currNode()
        {
            return cast(NodeType*)&dst[pos];
        }

        with (ChildTypes) foreach (idx; 0 .. 16)
        {
            import std.algorithm : among;
            ChildTypes type = (*currNode)[idx].type;
            if (type == thisPtr)
            {
                NodeType* orig = (*currNode)[idx].thisPtr;
                ulong written = pack!freeCopied((*currNode)[idx].thisPtr, dst, pos + occupied);
                (*currNode)[idx].thisOffset = pos + occupied;
                occupied += written;
                static if (freeCopied)
                    sedecAllocator.dispose(orig);
            }
            else if (type == compressedThis)
            {
                ubyte* orig = (*currNode)[idx].compressedThis;
                ulong written = pack!freeCopied((*currNode)[idx].compressedThis, dst, pos + occupied);
                (*currNode)[idx].compressedOffset = pos + occupied;
                occupied += written;
                static if (freeCopied)
                    sedecAllocator.dispose(orig);
            }
            else if (type.among(pending, allTrue, allFalse))
            {}
        }
        return occupied;
    }

    ulong pack(bool freeCopied)(ubyte* blob, ref ubyte[] dst, ulong pos)
        in(blob !is null)
        in(pos <= dst.length)
    {
        ulong blobLength = *cast(ulong*)blob;

        assert((blobLength + ulong.sizeof) % ulong.sizeof);

        if (dst.length - pos >= ulong.sizeof + blobLength)
        {
            import std.algorithm : max;
            if (!sedecAllocator.expandArray(dst, max(dst.length / 2, ulong.sizeof + blobLength)))
                assert(0);
        }
        ulong occupied = 0;

        dst[pos .. $][0 .. ulong.sizeof + blobLength] = blob[0 .. ulong.sizeof + blobLength];
        occupied += ulong.sizeof + blobLength;

        return occupied;
    }



    void compress(V)(NodeType* node, V idx)
        in(node !is null)
        in(idx.x < 4)
        in(idx.y < 4)
    {
        import std.algorithm : among;
        ChildTypes type = (*node)[idx].type;
        with (ChildTypes) if (type.among(compressedThis, allFalse, allTrue, pending))
            return;
        if (type == ChildTypes.thisPtr)
        {
            ubyte[] packed = packNode!(Yes.freeCopied)((*node)[idx].thisPtr);

            cctx.ZSTD_initCStream(5);
            assert(packed.length % 8 == 0);
            cctx.ZSTD_CCtx_setPledgedSrcSize(packed.length);

            ZSTD_inBuffer srcBuf;
            ZSTD_outBuffer dstBuf;

            srcBuf.src = packed.ptr;
            srcBuf.size = packed.length;

            ubyte[] dst = sedecAllocator.makeArray!ubyte(packed.length / 4); // we assume that 75 % reduction is realistic
            dstBuf.dst = dst.ptr;
            dstBuf.size = dst.length;
            dstBuf.pos = ulong.sizeof; // reserve space for the length prefix

            while (true)
            {
                auto status = cctx.ZSTD_compressStream2(&dstBuf, &srcBuf, ZSTD_EndDirective.ZSTD_e_continue);
                assert(!ZSTD_isError(status), ZSTD_getErrorName(status).fromStringz);
                if (srcBuf.pos == srcBuf.size) // we only need to finish the frame
                {
                    break;
                }
                if (dstBuf.size - dstBuf.pos < status) // allocate new memory
                {
                    if (!sedecAllocator.expandArray(dst, dst.length / 2))
                        assert(0);
                    dstBuf.dst = dst.ptr;
                    dstBuf.size = dst.length;
                }
            }
            // everything has been read, source buffer can be discarded

            while (true) // finish frame
            {
                auto status = cctx.ZSTD_compressStream2(&dstBuf, &srcBuf, ZSTD_EndDirective.ZSTD_e_end);
                assert(!ZSTD_isError(status), ZSTD_getErrorName(status).fromStringz);
                if (status == 0) // we are done
                    break;
                import std.math : nextPow2;
                if (!sedecAllocator.expandArray(dst, status.nextPow2))
                    assert(0);
                dstBuf.dst = dst.ptr;
                dstBuf.size = dst.length;
            }

            import std.stdio;
            objcpy(cast(ulong)(dstBuf.pos - ulong.sizeof), dst[0 .. ulong.sizeof]);
            // trim the destination buffer
            // ensure that everything aligns properly in further runs
            void[] arr = cast(void[])dst;
            sedecAllocator.reallocate(arr, dstBuf.pos + (8 - (dstBuf.pos % 8)) % 8);

            dst = cast(ubyte[])arr;
            assert(dst.length % 8 == 0);

            (*node)[idx].compressedThis = dst.ptr;

            // free source buffer
            sedecAllocator.dispose(packed);

            return;
        }
        unreachable;
    }
}

alias auie = SedecTree!(uint, e => true);

void printBuf(ubyte[] buf)
{
    import std.range;
    import std.stdio;
    writefln!"[%s%(%02x %)]"(buf.length > 400 ? "… " : "", buf.take(400));
}

ubyte[] objcpy(T)(auto ref T src, ubyte[] dst, ulong ll = __LINE__)
    in(T.sizeof <= dst[].length)
{
import std.conv;
    stderr.writefln("%s written to %x (%d) %s", src, cast(size_t)dst.ptr, T.sizeof, ll);
    dst[0 .. T.sizeof] = *(cast(ubyte[T.sizeof]*)&src);
    return dst[T.sizeof .. $];
}

alias isFlag(F) = isInstanceOf!(Flag, F);
template flagName(F)
{
    static assert(isFlag!F, "Type is not a Flag!");
    enum string flagName = TemplateArgsOf!(F)[0];
}

int flagValue(Flags...)(string name)
{
    import std.meta;
    import std.algorithm : countUntil;
    import std.functional : not;
    static assert(!anySatisfy!(isType, Flags));
    alias FlagTypes = typeof(Flags);
    alias flagNames = staticMap!(flagName, FlagTypes);
    ptrdiff_t idx = [flagNames].countUntil!(n => n == name);
    if (idx == -1)
        return -1; // default
    else
    {
        static foreach (i, f; Flags)
        {
            if (idx == i)
                return Flags[i] ? 1 : 0;
        }
    }
    unreachable;
    return int.min;
}
