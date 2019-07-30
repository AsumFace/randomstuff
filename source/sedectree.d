module sedectree;

import zstdc;
import std.traits;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import word;
import required;
import cgfm.math;
import std.typecons;
import std.format;
import std.string : fromStringz;
import std.stdio;
import std.meta;

struct AllocInfo
{
    ulong sourceLine;
    ulong size;
}

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

//alias SedecAllocator = Mallocator;
alias sedecAllocator = Mallocator.instance;

/+debug
    enum ulong byOffsetFlag = 0b1000;
else
    enum ulong byOffsetFlag = 0;
+/
struct SedecNode(AddressType)
    if (isIntegral!AddressType)
{
    private Word!(16, 0xf) _type;
    private ChildStore[16] _children;
    debug ulong _protector = 0xdeadbeef;

    static assert(_type.sizeof == 8); // should be packed exactly with no padding
    invariant
    {
        debug assert(&this is null || _protector == 0xdeadbeef, format("protector has been corrupted! %08x, this at %x", _protector, &this));
        assert(null is cast(void*)0, "null pointer does not point to 0. this code assumes that");
        //assert(cast(size_t)&this < 0xff00000000000000);
        foreach (i; 0 .. 16)
        {
            import std.stdio;
            import std.algorithm;
            //stderr.writefln("%x", &this);
            assert(&this is null || _type[i].asInt.among(EnumMembers!ChildTypes), format!"0b%04b in %s is not a valid ChildTypes value"(_type[i].asInt, i));

            with (ChildTypes) if (_type[i].asInt.among(thisPtr, compressedThis))
            {
                /+debug assert((_type[i].asInt & byOffsetFlag) > 0
                    || _children[i].thisPtr ! is null, format!"byOffset: %s | ptr: %s"((_type[i].asInt & byOffsetFlag) != 0, _children[i].thisPtr));
            +/}
            else
            {
                //assert((_type[i].asInt & byOffsetFlag) == 0, format!"byOffset in %s is incorrectly set; %s"(i, _toString));
                //assert(_children[i].raw == 0, format!"type: %s | value: %s | byOffset: %s"(cast(ChildTypes)(_type[i].asInt&0b111), _children[i].raw, (_type[i].asInt & byOffsetFlag) != 0));
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
        import std.conv;
        import std.algorithm;
        string pstring;
        debug
        {
            if (_protector != 0xdeadbeef)
                pstring = format("%x", _protector);
            else
                pstring = "";
        }
        else
            pstring = "";

        string result;
        with (ChildTypes) result =
            format(
                "%s{%(%(%c%),%)}{",
                pstring,
                _type[].map!(n => n.predSwitch(
                    allTrue, "T",
                    allFalse, "F",
                    pending, "p",
                    thisPtr, "r",
                    compressedThis, "c",
                    n.to!string)));
        foreach (i, ref e; _children[])
        {
            result ~= format("%x", e.thisPtr);
            if (i + 1 != _children[].length)
                result ~= ",";
        }
        result ~= format("}{%x}", &this);
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

    auto opSlice(ulong begin, ulong end)
        in(begin <= 15)
        in(end <= 16)
    {
        struct NodeRange
        {
            ubyte end;
            invariant(context !is null);
            invariant(idx <= end);
            invariant(idx >= begin);
            SedecNode* context;
            private ubyte idx;
            bool empty() const
            {
                return idx >= end;
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
                return cast(ubyte)(end - idx);
            }
        }
        return NodeRange(cast(ubyte)end, &this, cast(ubyte)begin);
    }

    auto opIndex()
    {
        return opSlice(0, 16);
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

            /+bool byOffset() const
                in((context._type[i].asInt & 0b111).among(ChildTypes.thisPtr, ChildTypes.compressedThis))
            {
                static assert(byOffsetFlag != 0, "byOffset flag is only available in debug mode");
                return (context._type[i].asInt & byOffsetFlag) != 0;
            }+/

            ChildTypes type() const
                in(((context._type)[i].asInt).among(EnumMembers!ChildTypes),
                     format("%04b is not a ChildTypes value %s", context._type[i].asInt, context.toString))
            {
                return cast(ChildTypes)(context._type[i].asInt);
            }

            ref SedecNode* thisPtr()
                in(type == ChildTypes.thisPtr)
                out(r; r !is null, format("null pointer in %s: %s", i, context._toString))
            {
                //debug assert(byOffset == false);
                return context._children[i].thisPtr;
            }

            auto thisOffset()
                in(type == ChildTypes.thisPtr)
            {
                //debug assert(byOffset == true);
                return context._children[i].thisOffset;
            }

            ref ubyte* compressedThis()
                in(type == ChildTypes.compressedThis)
                out(r; r !is null)
            {
                //debug assert(byOffset == false);
                return context._children[i].compressed;
            }

            ulong compressedOffset()
                in(type == ChildTypes.compressedThis)
            {
                //debug assert(byOffset == true);
                return context._children[i].compressedOffset;
            }

            import std.algorithm : among;
            ChildTypes type(ChildTypes val)
                in(val.among(ChildTypes.allTrue, ChildTypes.allFalse, ChildTypes.pending),
                    format("A type with payload must be set implicitly by assigning"
                    ~ " the desired value using one of the setters. Attempted to set type to %s", val))
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
                context._type[i] = ChildTypes.thisPtr;// | byOffsetFlag;
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
                context._type[i] = ChildTypes.compressedThis;// | byOffsetFlag;
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


auto sedecTree(AddressType, alias calc, bool zCache)()
    if (isIntegral!AddressType)
{
    auto result = SedecTree!(AddressType, calc, zCache)(ZSTD_createCCtx, ZSTD_createDCtx);
    result.root = make!(result.NodeType)(sedecAllocator);
    if (result.root is null)
        assert(0);
    return result;
}

struct SedecTree(AddressType, alias calc, bool zCache)
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
        static if (zCache)
            size_t offsetBase = 0; // if offsetBase is greater than 0, we are operating in cache
        else
            enum offsetBase = 0;
        while (true)
        {
            import std.range;
            assert((width + 1).isPowerOf2 || width + 1 == 0); // width quartered with each step
            assert(width >= 3 && begin % 4 == 0); // smallest node covers 4x4 pixels, alignment given by nature
            //auto subIdx = cast(Vector!(ubyte, 2))((Vector!(AddressType, 2)(i1, i2) - begin) / (width / 4 + 1));
            Vector!(ubyte, 2) subIdx;
            {
                import core.bitop;
                auto tt = Vector!(AddressType, 2)(i1, i2);
                tt -= begin;
                //assert(width > 7, format("%s", width));
                auto divisor = (width / 4 + 1);
                assert(divisor.isPowerOf2);
                assert(divisor >= 1, format("%s", divisor));
                auto tt2 = tt / divisor; // correct reference solution
                tt >>= bsf(divisor);
                assert(tt == tt2, format("%s %s", tt, tt2));
                subIdx = cast(typeof(subIdx))tt;
            }
            //stderr.writefln("w%s d%s %s", width, depth, (*activeNode).toString);
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
            if (offsetBase == 0)
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
                    static if (zCache)
                    {
                        auto cacheResponse = zcache.query((*activeNode)[subIdx].compressedThis);
                        if (cacheResponse is null) // cache miss
                            // we reuse any existing memory but overwrite the containing data
                        {
                            ubyte* compressedBlob = (*activeNode)[subIdx].compressedThis;
                            assert(compressedBlob !is null);
                            ulong contentSize =
                                ZSTD_getFrameContentSize(compressedBlob + ulong.sizeof, *cast(ulong*)&compressedBlob);
                            if (contentSize > size_t.max)
                                assert(0);
                            assert(contentSize % ulong.sizeof == 0);

                            ulong neededSize = contentSize + size_t.sizeof;
                            if (zcache.store.length < neededSize + ulong.sizeof * 2) // 2*8 bytes zero termination!
                            {
                                if (zcache.store is null)
                                {
                                    zcache.store = sedecAllocator.makeArray!ubyte(neededSize + ulong.sizeof * 2);
                                    if (zcache.store is null)
                                        assert(0);
                                }
                                if (!sedecAllocator.expandArray(zcache.store, neededSize + ulong.sizeof * 2))
                                    assert(0, format("could not allocate additional %s bytes", neededSize + ulong.sizeof * 2));
                            }

                            ZSTD_decompressDCtx(dctx,
                                zcache.store.ptr + ulong.sizeof, zcache.store.length - ulong.sizeof,
                                compressedBlob + ulong.sizeof, cast(size_t)*cast(ulong*)&compressedBlob);

                            // set data origin
                            *cast(ubyte**)&zcache.store[0 .. ulong.sizeof][0] = (*activeNode)[subIdx].compressedThis;

                            //if (zcache.store.length >= ulong.sizeof)
                            //    stderr.writefln!"%(%(%02x %)\n####\n%)"(zcache.store[ulong.sizeof * 2 .. $].chunks(NodeType.sizeof));

                            cacheResponse = zcache.query((*activeNode)[subIdx].compressedThis);
                            assert(cacheResponse !is null);
                        }

                        // switch to cache
                        offsetBase = ulong.sizeof;
                        nextStep(begin, width, subIdx);
                        depth += 1;
                        activeNode = cacheResponse;
                        continue;
                    }
                    else
                    {
                        extract(activeNode, subIdx);
                        nextStep(begin, width, subIdx);
                        depth += 1;
                        activeNode = (*activeNode)[subIdx].thisPtr;
                        continue;
                    }
                }
                unreachable;
            }
            else
            {
                static if (zCache)
                {
                    if (result == ChildTypes.thisPtr)
                        // In cache we need to calculate the pointer from the stored offset.
                        /+ Storing offsets instead of pointers directly has the advantage of not requiring
                           post processing after decompression and allows reallocation without an intermediate
                           representation change which would also require processing passes. +/
                    {
                        assert(width != 3);
                        nextStep(begin, width, subIdx);
                        // we want the data to be correctly aligned
                        assert(cast(ulong)&zcache.store[0] % ulong.sizeof == 0);
                        assert((*activeNode)[subIdx].thisOffset % ulong.sizeof == 0);

                        activeNode = cast(NodeType*)(&zcache.store
                            [offsetBase .. $]
                            [(*activeNode)[subIdx].thisOffset .. $]
                            [0 .. NodeType.sizeof][0]);
                        continue;
                    }
                    if (result == ChildTypes.compressedThis)
                        // instead of discarding all cache, we only discard the mismatching compression branch
                    {
                        offsetBase = zcache.nextStripBase(offsetBase);

                        ulong compressedBlob = (*activeNode)[subIdx].compressedOffset;
                        assert(compressedBlob != 0);

                        ulong contentSize = 0;

                        // if the offsets match, we have a cache hit
                        ulong cachedOffset = *cast(ulong*)zcache.store[offsetBase - ulong.sizeof .. offsetBase][0];
                        if (cachedOffset == compressedBlob)
                        {
                            activeNode =
                                cast(NodeType*)&(zcache.store[offsetBase .. $][ulong.sizeof .. $][0 .. NodeType.sizeof][0]);
                            nextStep(begin, width, subIdx);
                            continue;
                        }

                        // cache miss
                        contentSize = ZSTD_getFrameContentSize(
                            &zcache.store[offsetBase + compressedBlob + ulong.sizeof .. $][0],
                            *cast(ulong*)zcache.store[offsetBase + compressedBlob .. $][0 .. ulong.sizeof][0]);
                        size_t neededSize = contentSize + ulong.sizeof;

                        if (zcache.store.length < neededSize + ulong.sizeof * 2) // 2*8 bytes zero termination!
                        {
                            ptrdiff_t origOffset = cast(ubyte*)activeNode - &zcache.store[0];
                            if (!sedecAllocator.expandArray(zcache.store, neededSize + ulong.sizeof * 2))
                                assert(0);
                            assert(contentSize % ulong.sizeof == 0);

                            // recalculate activeNode pointer since the node might have been relocated
                            // (commented because the pointer is not needed anymore)
                            // activeNode = cast(NodeType*)(&zcache.store[0] + activeOffset);
                        }

                        *cast(ulong*)&zcache.store[offsetBase - ulong.sizeof .. offsetBase][0] = compressedBlob;

                        dctx.ZSTD_decompressDCtx(
                            &zcache.store[offsetBase .. $][0], zcache.store[offsetBase .. $ - ulong.sizeof].length,
                            &zcache.store[offsetBase + compressedBlob + ulong.sizeof],
                            cast(size_t)*cast(ulong*)&zcache.store[offsetBase + compressedBlob .. $][0 .. ulong.sizeof][0]);
                        activeNode = cast(NodeType*)&zcache.store[offsetBase .. $][0 .. NodeType.sizeof][0];
                        nextStep(begin, width, subIdx);
                        continue;
                    }
                    unreachable;
                }
            }
            unreachable;
        }
    }

    void nextStep(V)(ref Vector!(AddressType, 2) begin, ref AddressType width, V pos)
    {
        begin += cast(Vector!(AddressType, 2))pos * (width / 4 + 1);
        width /= 4;
    }

    void recursiveFree(ref NodeType* node)
        in(node !is null)
        in(&*node)
    {
        with (ChildTypes) foreach (child; (*node)[])
        {
            if (child.type == thisPtr)
            {
                auto target = child.thisPtr;
                child.type = pending;
                recursiveFree(target);
            }
            else if (child.type == compressedThis)
            {
                auto target = child.compressedThis;
                child.type = pending;
                sedecAllocator.dispose(target);
            }
        }
        assert(&*node);

        sedecAllocator.dispose(node);
    }

    bool opIndexAssign(V)(bool val, V v)
    {
        return opIndexAssign(val, v.x, v.y);
    }

    bool opIndexAssign(bool val, AddressType i1, AddressType i2)
    {
        with (ChildTypes) setPixel(
            root,
            Vector!(AddressType, 2)(i1, i2),
            AddressType.max / 4 + 1,
            Vector!(AddressType, 2)(0, 0),
            val ? allTrue : allFalse);
        return val;
    }


    Tuple!(Vector!(ulong, 2), "coor", NodeType*, "node") aCache;
    ubyte aDepth = 0;
    import std.algorithm : all, among;
    void setPixel(
            NodeType* node,
            Vector!(AddressType, 2) coor,
            AddressType fWidth,
            Vector!(AddressType, 2) begin,
            ChildTypes value)
        in(node !is null)
        in(fWidth > 0 && fWidth.isPowerOf2)
        in(fWidth != 1 || (*node)[].all!(n => !n.type.among(ChildTypes.compressedThis, ChildTypes.thisPtr)))
    {
        import core.bitop;
        enum cacheLevel = 16;
        static assert(cacheLevel.isPowerOf2);

        if (aCache.node !is null && (coor & (ulong.max << bsf(cacheLevel) + 2)) == aCache.coor)
        {
            node = aCache.node;
            begin = aCache.coor;
            fWidth = cacheLevel;
        }
        start:

        if (fWidth == cacheLevel)
        {
            aCache.node = node;
            aCache.coor = begin;
        }


        import core.bitop : bsf;
        debug auto should_subIdx = (coor - begin) / fWidth;
        auto subIdx = (coor - begin) >> bsf(fWidth);
        debug assert(should_subIdx == subIdx);
        //stderr.writefln("%s %s %s %s", fWidth, subIdx, begin, coor);
        if (fWidth == 1)
        {
            /* We simply set the value. Since passing a node with references is disallowed by the contract, we never
               need to free anything. */
            with (ChildTypes)
                (*node)[subIdx].type = value;
            return;
        }

        auto type = (*node)[subIdx].type;
        with (ChildTypes) if (type.among(allTrue, allFalse, pending))
        {
            auto newNode = sedecAllocator.make!NodeType;
            if (newNode is null)
                assert(0);

            foreach (child; (*newNode)[]) // make it equivalent to the current child
                 child.type = type;

            (*node)[subIdx].thisPtr = newNode;
        }
        else if (type == ChildTypes.compressedThis)
        {
            extract(node, subIdx);
        }

        // by now the relevant field should be switchable to
        assert((*node)[subIdx].type == ChildTypes.thisPtr);

        node = (*node)[subIdx].thisPtr;
        begin += fWidth * subIdx;
        fWidth /= 4;
        goto start; // ldc2 doesn't optimize the tail call! wtf!
//        setPixel((*node)[subIdx].thisPtr, coor, fWidth / 4, begin + fWidth * subIdx, value);
    }

    void extract(V)(NodeType* node, V subIdx)
        in(subIdx.x < 4)
        in(subIdx.y < 4)
        in(node !is null)
        in(&*node)
        in((*node)[subIdx].type == ChildTypes.compressedThis)
        out(;(*node)[subIdx].type == ChildTypes.thisPtr)
        out(;&*(*node)[subIdx].thisPtr)
        out(;&*node)
    {
        dctx.ZSTD_initDStream;
        ubyte* blob = (*node)[subIdx].compressedThis;
        ZSTD_inBuffer srcBuf;
        srcBuf.src = blob + ulong.sizeof;
        srcBuf.size = *cast(ulong*)blob;

        ZSTD_outBuffer dstBuf;
        ulong garbage;
        dstBuf.dst = &garbage;
        dstBuf.size = ulong.sizeof;
        auto status = dctx.ZSTD_decompressStream(&dstBuf, &srcBuf);
        //stderr.writeln("garbage reads ", garbage);
        assert(!ZSTD_isError(status), ZSTD_getErrorName(status).fromStringz);
        assert(dstBuf.pos == dstBuf.size); // must have written exactly 8 bytes
        // the extracted length info is for zCache only, we ignore it in this function
        (*node)[subIdx].thisPtr = extractThisPtr(srcBuf);

        sedecAllocator.dispose(blob);
    }

    NodeType* extractThisPtr(ref ZSTD_inBuffer srcBuf)
    {
        ZSTD_outBuffer dstBuf;
        NodeType* target = sedecAllocator.make!NodeType;
        dstBuf.dst = target;
        dstBuf.size = NodeType.sizeof;
        if (dstBuf.dst is null)
            assert(0);
        auto status = dctx.ZSTD_decompressStream(&dstBuf, &srcBuf);
        assert(!ZSTD_isError(status), ZSTD_getErrorName(status).fromStringz);
        assert(dstBuf.pos == dstBuf.size); // must have written exactly 8 bytes
        //stderr.writeln((*target)._toString);
        assert(&*target);

        foreach (child; (*target)[])
        {
            with (ChildTypes) final switch (child.type)
            {
                case allTrue:
                case allFalse:
                case pending:
                    break;
                case thisPtr:
                    child.thisPtr = extractThisPtr(srcBuf);
                    break;
                case compressedThis:
                    child.compressedThis = extractBlob(srcBuf);
                    break;
            }
        }

        return target;
    }

    ubyte* extractBlob(ref ZSTD_inBuffer srcBuf)
    {
        ZSTD_outBuffer dstBuf;
        ulong contentSize;
        dstBuf.dst = &contentSize;
        dstBuf.size = ulong.sizeof;
        dctx.ZSTD_decompressStream(&dstBuf, &srcBuf); // retrieve extracted blob size
        assert(dstBuf.pos == ulong.sizeof);
        assert(contentSize >= NodeType.sizeof);

        ubyte[] target = sedecAllocator.makeArray!ubyte(contentSize + ulong.sizeof);
        if (target is null)
            assert(0, format("failed to allocate %s", formatBytes(contentSize + ulong.sizeof)));
        objcpy(contentSize, target[0 .. ulong.sizeof]);

        dstBuf.dst = &target[0];
        dstBuf.size = target.length;
        // pos field has already been set by the previous decompression!
        auto status = dctx.ZSTD_decompressStream(&dstBuf, &srcBuf); // write blob
        assert(!ZSTD_isError(status), ZSTD_getErrorName(status).fromStringz);
        assert(dstBuf.pos == dstBuf.size);

        return cast(ubyte*)dstBuf.dst;
    }

    ~this()
    {
        ZSTD_freeCCtx(cctx);
        ZSTD_freeDCtx(dctx);
        zcache.free;
        if (root !is null)
            recursiveFree(root);
    }

    static if (zCache)
        ZCache zcache;

    void _print(NodeType* node, int depth = 0)
    {
        import std.format;
        import std.range;
        import std.algorithm;
        writefln("%(%(%c%)%)%s", "|".repeat(depth), (*node)._toString);
        with (ChildTypes) foreach (child; (*node)[])
        {
            if (child.type == thisPtr)
                _print(child.thisPtr, depth + 1);
        }
    }

    struct ZCache
    {
        /+ the cache can be thought of a stack of cache strips, the first encountered compressed blob is extracted and
         put to the bottom of the stack, each subsequently encountered direct or indirect compressed child is extracted
         and put ontop +/
        // each cache strip consists of source pointer/offset + non-inclusive packed length + packed data
        // packed length is contained within the compressed data and will be placed upon extraction
        // all cache strips are placed inside one single allocation, freeing `store` drops the entire cache

        import std.algorithm : all;
        invariant(store is null || (cast(size_t)store.ptr) % ulong.sizeof == 0); // we want a specific alignment
        invariant(store.length == 0 || store[$ - ulong.sizeof * 2 .. $].all!(n => n == 0));
        ubyte[] store;

        ubyte* source(ubyte* blob)
        {
            return cast(ubyte*)*cast(ulong*)blob;
        }

        ulong source(ulong offset)
        {
            return *cast(ulong*)&store[offset .. $][0 .. ulong.sizeof][0];
        }

        ulong len(ubyte* blob)
        {
            return *cast(ulong*)(blob + ulong.sizeof);
        }

        Tuple!(NodeType*, "head", ulong, "base") query(ulong sourceOffset, ulong skip = 0)
            in(store.length == 0 || skip <= (store.length - ulong.sizeof * 2))
        {
            auto result = typeof(return)(null, 0);
            ulong offset = skip;
            while (source(offset) != 0)
            {
                assert(offset % ulong.sizeof == 0);
                if (source(offset) == sourceOffset) // we have a match
                {
                    ulong packLen = len(&store[offset]);
                    result = typeof(return)(cast(NodeType*)(&store[0] + offset + ulong.sizeof * 2), offset + ulong.sizeof);
                    break;
                }
                else // jump to the next strip
                {
                    ulong packLen = len(&store[offset]);
                    offset += ulong.sizeof * 2 + packLen;
                }
                assert(offset < store.length);
            }
            return result;
        }

        NodeType* query(ubyte* blob)
            in(blob !is null)
        {
            if (store is null)
                return null;
            if (blob == *cast(ubyte**)store)
                return cast(NodeType*)&store[ulong.sizeof * 2 .. $][0 .. NodeType.sizeof][0];
            return null;
        }

        ulong nextStripBase(ulong base) // result will point to the length field
        {
            auto step = *cast(ulong*)&store[base .. $][0 .. ulong.sizeof][0];
            return base + step + ulong.sizeof;
        }

        void free()
        {
            if (store !is null)
            {
                sedecAllocator.dispose(store);
                store = null;
            }
        }

        void dropAll()
        {
            *cast(void**)&store[0 .. ulong.sizeof][0] = null;
        }
    }

    ubyte[] calcFreeRange(ubyte[] p, void* currPos)
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
        auto oldptr = dst.ptr;
        auto oldlen = dst.length;

        sedecAllocator.shrinkArray(dst, dst.length - written - ulong.sizeof);

        return dst;
    }

    ulong pack(bool freeCopied)(NodeType* node, ref ubyte[] dst, ulong pos)
        in(node !is null)
        in(pos <= dst.length)
    {
        //stderr.writefln("dstl: %s; pos: %s", dst.length, pos);
        if (dst.length - pos < NodeType.sizeof)
        {
            import std.algorithm : max;
            assert(dst !is null);
            auto oldptr = dst.ptr;
            auto oldlen = dst.length;
            if (!sedecAllocator.expandArray(dst, max(dst.length / 2, NodeType.sizeof)))
                assert(0, format("could not allocate additional %s bytes", max(dst.length / 2, NodeType.sizeof)));
        }
        ulong occupied = 0;

        objcpy(*node, dst[pos .. $]);
        assert(&*cast(NodeType*)&dst[pos]);
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
                ulong written = pack!(freeCopied)((*currNode)[idx].thisPtr, dst, pos + occupied);
                static if (zCache)
                    (*currNode)[idx].thisOffset = pos + occupied;
                else
                    (*currNode)[idx].thisOffset = 0;
                occupied += written;
                static if (freeCopied)
                    sedecAllocator.dispose(orig);
            }
            else if (type == compressedThis)
            {
                ubyte* orig = (*currNode)[idx].compressedThis;
                ulong written = pack!freeCopied((*currNode)[idx].compressedThis, dst, pos + occupied);
                static if (zCache)
                    (*currNode)[idx].compressedOffset = pos + occupied;
                else
                    (*currNode)[idx].compressedOffset = 0;
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
        //stderr.writefln("%s", pos);
        ulong blobLength = *cast(ulong*)blob;

        assert((blobLength + ulong.sizeof) % ulong.sizeof);

        if (dst.length - pos >= ulong.sizeof + blobLength)
        {
            import std.algorithm : max;
            auto oldptr = dst.ptr;
            auto oldlen = dst.length;
            if (!sedecAllocator.expandArray(dst, max(dst.length / 2, ulong.sizeof + blobLength)))
                assert(0);
        }
        ulong occupied = 0;

        dst[pos .. $][0 .. ulong.sizeof + blobLength] = blob[0 .. ulong.sizeof + blobLength];
        occupied += ulong.sizeof + blobLength;

        return occupied;
    }

    ChildTypes optimize(NodeType* node = root)
        in(node !is null)
    {
        aCache.node = null;
        ChildTypes result = (*node)[0].type; // compressedThis is a catch-all for non-optimizable data here
        foreach (child; (*node)[])
        {
            auto childType = child.type;
            if (childType == ChildTypes.thisPtr)
            {
                auto equivalentType = optimize(child.thisPtr);
                with (ChildTypes) if (equivalentType.among(allTrue, allFalse, pending))
                {
                    auto garbage = child.thisPtr;
                    child.type = equivalentType;
                    sedecAllocator.dispose(garbage);
                }
            }
            if (child.type != result)
                result = ChildTypes.compressedThis;
        }
        return result;
    }

    void compress(Flags...)(NodeType* node, Vector!(ubyte, 2) idx)
        in(node !is null)
        in(idx.x < 4)
        in(idx.y < 4)
        out(;(*node)[idx].type == ChildTypes.compressedThis)
    {
        aCache.node = null;
        import std.algorithm : among;
        ChildTypes type = (*node)[idx].type;
        with (ChildTypes) assert (!type.among(compressedThis, allFalse, allTrue, pending));
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

            //            import std.range;
            // stderr.writefln!"PRINT%(%(%02x %)\n&&&&\n%)"(packed[ulong.sizeof * 1 .. $].chunks(NodeType.sizeof));

            ubyte[] dst = sedecAllocator.makeArray!ubyte(((packed.length / 4) + (8 - ((packed.length / 4) % 8)) % 8)); // we assume that 75 % reduction is realistic

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
            auto oldptr = dst.ptr;
            auto oldlen = dst.length;
            ulong newSize = dstBuf.pos + (8 - (dstBuf.pos % 8)) % 8;

            if (newSize > dst.length)
            {
                assert(0);
                if (!sedecAllocator.expandArray(dst, newSize - dst.length))
                    assert(0);
            }
            else if (dst.length > newSize)
            {
                if (!sedecAllocator.shrinkArray(dst, dst.length - newSize))
                    assert(0);
            }
            else
                writeln("nothing");
            //registerRealloc(oldptr, dst.ptr, newSize);

            assert(dst.length % 8 == 0);

            (*node)[idx].compressedThis = dst.ptr;
            stderr.writefln!"compressed %s bytes down to %s (%5.3s %%)"(formatBytes(packed.length), formatBytes(dst.length),
                cast(double)dst.length/cast(double)packed.length*100.0);
            // free source buffer
            sedecAllocator.dispose(packed);

            return;
        }
        unreachable;
    }
}

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
    //stderr.writefln("%s written to %x (%d) %s", src, cast(size_t)dst.ptr, T.sizeof, ll);
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


struct formatBytes
{
    static immutable prefixLUT = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"];
    ulong value;
    void toString(W)(W w)
    {
        import std.format;
        double tmp = value;
        ubyte cnt = 0;
        while (tmp >= 10_000.0)
        {
            cnt += 1;
            tmp /= 1024;
        }
        w.formattedWrite("%5.4s %s", tmp, prefixLUT[cnt]);
    }
}
