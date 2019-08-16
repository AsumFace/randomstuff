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
debug import std.random;

import std.datetime;
typeof(MonoTime.currTime) trig;

static this()
{
    trig = MonoTime.currTime;
}

static assert(size_t.sizeof <= ulong.sizeof,
     "platforms with more than 64 bit address space aren't supported :p");

enum FillValue
{
    none = 0,
    allTrue = 1,
    mixed = -1
}

enum ChildTypes
{
    allFalse = 0b0000,
    allTrue = 0b0001, // a bool cast to this enum shall produce either allFalse or allTrue depending on its value
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
struct SedecNode(AddressType, AddressType _fWidth)
    if (isIntegral!AddressType && isUnsigned!AddressType)
{
    alias fWidth = _fWidth;
    static assert(fWidth.isPowerOf2);
    static assert(this.sizeof % ulong.sizeof == 0);
    static if (fWidth > 1)
    {
        alias isBottom = Alias!false;
        alias ChildNodeType = SedecNode!(AddressType, fWidth / 4);
    }
    else
        alias isBottom = Alias!true;
    debug ulong _protector = 0xdeadbeef01cecafe;
    debug ulong _fWidth_check = fWidth;
    debug ulong ident;
    debug enum _Kinds : ubyte {
        uninitialized,
        nil,
        offset,
        pointer
    }
    debug _Kinds[16] _kind;
    debug ulong[16] _srcLines;
    private Word!(16, 0xf) _type;
    private ChildStore[16] _children;

    static assert(_type.sizeof == 8); // should be packed exactly with no padding
    invariant
    {
        debug assert(cast(size_t)&this % ulong.sizeof == 0, "Node does not have proper alignment");
        debug assert(_protector == 0xdeadbeef01cecafe, format("protector has been corrupted! %08x, %s", _protector, _toString));
        debug assert(_fWidth_check == fWidth, format("node should have fWidth %s, but has %s", fWidth, _fWidth_check));
        assert(null is cast(void*)0, "null pointer does not point to 0. this code assumes that");
        //assert(cast(size_t)&this < 0xff00000000000000);
        foreach (i; 0 .. 16)
        {
            import std.stdio;
            import std.algorithm;
            //stderr.writefln("%x", &this);
            assert(_type[i].asInt.among(EnumMembers!ChildTypes), format!"0b%04b in %s is not a valid ChildTypes value"(_type[i].asInt, i));

      //      with (ChildTypes) if (_type[i].asInt == compressedThis)
      //      {
      //          assert(*cast(ulong*)_children[i].compressed >= ulong.sizeof);
      //      }
        }
    }

    private union ChildStore
    {
        ulong raw;
        void[8] data;

        static if (!isBottom)
        {
            ulong compressedOffset;
            ulong thisOffset;
            SedecNode!(AddressType, fWidth / 4)* thisPtr;
            ubyte* compressed;
        }
    }

    private string _toString() const
    {
        import std.format;
        import std.conv;
        import std.algorithm;
        string pstring;
        debug
        {
            if (_protector != 0xdeadbeef01cecafe)
                pstring = format("%x", _protector);
            else
                pstring = "";
        }
        else
            pstring = "";

        string result;
        with (ChildTypes) result =
            format(
                "%s[%x]{%(%(%c%),%)}{",
                pstring,
                ident,
                _type[].map!(n => n.predSwitch(
                    allTrue, "T",
                    allFalse, "F",
                    thisPtr, "r",
                    compressedThis, "c",
                    n.to!string)));
        static if (!isBottom)
        {
            foreach (i, ref e; _children[])
            {
                result ~= format("%x", e.thisPtr);
                if (i + 1 != _children[].length)
                    result ~= ",";
            }
        }
        result ~= format("}{%x}", &this);
        return result;
    }

    string toString() const
    {
        return _toString;
    }

    auto opIndex(I)(I i1, I i2)
    {
        return opIndex(Vector!(I, 2)(i1, i2));
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

            import std.algorithm : among;
            ChildTypes type(ChildTypes val)
                in(val.among(ChildTypes.allTrue, ChildTypes.allFalse),
                    format("A type with payload must be set implicitly by assigning"
                    ~ " the desired value using one of the setters. Attempted to set type to %s", val))
            {
                debug context._kind[i] = _Kinds.nil;
                context._type[i] = val;
                context._children[i].raw = 0;
                return val;
            }
            ChildTypes type() const
                in(((context._type)[i].asInt).among(EnumMembers!ChildTypes),
                     format("%04b is not a ChildTypes value %s", context._type[i].asInt, context.toString))
            {
                return cast(ChildTypes)(context._type[i].asInt);
            }
            static if (!isBottom)
            {
                ref ChildNodeType* thisPtr()
                    in(type == ChildTypes.thisPtr)
                    out(r; r !is null, format("null pointer in %s: %s", i, context._toString))
                {
                    debug assert(context._kind[i] == _Kinds.pointer, format("attempted to read %s %x, assigned here %s", context._kind[i], context._children[i].thisPtr, context._srcLines[i]));
                    return context._children[i].thisPtr;
                }

                auto thisOffset()
                    in(type == ChildTypes.thisPtr)
                {
                    debug assert(context._kind[i] == _Kinds.offset, format("attempted to read %s %x, assigned here %s", context._kind[i], context._children[i].thisPtr, context._srcLines[i]));
                    return context._children[i].thisOffset;
                }

                ref ubyte* compressedThis()
                    in(type == ChildTypes.compressedThis)
                    out(r; r !is null)
                {
                    debug assert(context._kind[i] == _Kinds.pointer, format("attempted to read %s %x, assigned here %s",
                    context._kind[i], context._children[i].thisPtr, context._srcLines[i]));
                    debug assert(ZBlob(context._children[i].compressed).contentSize > 0);
                    return context._children[i].compressed;
                }

                ulong compressedOffset()
                    in(type == ChildTypes.compressedThis)
                {
                    debug assert(context._kind[i] == _Kinds.offset, format("attempted to read %s %x, assigned here %s", context._kind[i], context._children[i].thisPtr, context._srcLines[i]));
                    return context._children[i].compressedOffset;
                }

                ChildNodeType* thisPtr(ChildNodeType* val, ulong line = __LINE__)
                    in(val !is null)
                    out(; type == ChildTypes.thisPtr)
                {
                    debug context._srcLines[i] = line;
                    debug context._kind[i] = _Kinds.pointer;
                    context._children[i].thisPtr = val;
                    context._type[i] = ChildTypes.thisPtr;
                    return val;
                }

                auto thisOffset(ulong val, ulong line = __LINE__)
                    out(; type == ChildTypes.thisPtr)
                {
                    debug context._srcLines[i] = line;
                    debug context._kind[i] = _Kinds.offset;
                    context._children[i].thisOffset = val;
                    context._type[i] = ChildTypes.thisPtr;
                    return val;
                }

                auto compressedThis(ubyte* val, ulong line = __LINE__)
                    in(val !is null)
                    out(; type == ChildTypes.compressedThis)
                {
                    debug context._srcLines[i] = line;
                    debug context._kind[i] = _Kinds.pointer;
                    debug assert(ZBlob(val).contentSize > 0);
                    context._children[i].compressed = val;
                    context._type[i] = ChildTypes.compressedThis;
                    return val;
                }

                auto compressedOffset(ulong val, ulong line = __LINE__)
                    out(; type() == ChildTypes.compressedThis)
                {
                    debug context._srcLines[i] = line;
                    debug context._kind[i] = _Kinds.offset;
                    context._children[i].compressedOffset = val;
                    context._type[i] = ChildTypes.compressedThis;// | byOffsetFlag;
                    return val;
                }
            }
            void[] data()
                in(!type.among(ChildTypes.allTrue, ChildTypes.allFalse))
            {
                return context._children[i].data[];
            }
        }
        return ChildObject(&this, cast(ubyte)i);
    }
}


auto sedecTree(AddressType, bool zCache)()
    if (isIntegral!AddressType)
{
    auto result = SedecTree!(AddressType, zCache)(ZSTD_createCCtx, ZSTD_createDCtx);
    result.root = make!(result.TopNodeType)(sedecAllocator);
    debug result.root.ident = uniform!ulong;
    if (result.root is null)
        assert(0);
    return result;
}

struct SedecTree(AddressType, bool zCache)
    if (isIntegral!AddressType)
{
    private ZSTD_CCtx* cctx;
    private ZSTD_DCtx* dctx;

    invariant
    {
        assert(cctx !is null);
        assert(dctx !is null);
    }

    alias TopNodeType = SedecNode!(AddressType, AddressType.max / 4 + 1);

    TopNodeType* root;

    ChildTypes opIndex(V)(V v)
    {
        return opIndex(v.x, v.y);
    }

    ChildTypes opIndex(I)(I i1, I i2)
        in(i1 <= AddressType.max)
        in(i2 <= AddressType.max)
    {
        return _opIndex(cast(AddressType)i1, cast(AddressType)i2,
            root,
            Vector!(AddressType, 2)(AddressType.min),
            0,
            null);
    }

    ChildTypes _opIndex(NT)(AddressType i1, AddressType i2, NT* activeNode, Vector!(AddressType, 2) begin, int depth, ubyte[] currCache)
        if (isInstanceOf!(SedecNode, NT))
        in(activeNode !is null && &*activeNode)
    {
        stderr.writefln!"depth: %s zcache store: %(%x,%)"(depth, cast(ulong[])zcache.store);
        stderr.writefln("activeNode: %s", *activeNode);
        import std.math;
        static if (!zCache)
            assert(currCache is null);
        while (true)
        {
            import std.range;
            Vector!(AddressType, 2) subIdx = (Vector!(AddressType, 2)(i1, i2) - cast(Vector!(AddressType, 2))begin) / NT.fWidth;

            ChildTypes result = (*activeNode)[subIdx].type;

            static if (NT.isBottom)
                with (ChildTypes) assert(result.among(allTrue, allFalse));
            if (result == ChildTypes.allFalse)
                return result;
            if (result == ChildTypes.allTrue)
                return result;
            static if (NT.isBottom)
            {
                unreachable;
                return cast(ChildTypes)-1;
            }
            else
            {
                if (currCache == null)
                {
                    if (result == ChildTypes.thisPtr) // just jump into the next lower division and repeat
                    {
                        return _opIndex(i1, i2, (*activeNode)[subIdx].thisPtr, begin + NT.fWidth * subIdx, depth + 1, currCache);
                    }
                    if (result == ChildTypes.compressedThis) // node is compressed
                    {
                        static if (zCache)
                        {
                            NT.ChildNodeType* cacheResponse = zcache.query!(NT.ChildNodeType)((*activeNode)[subIdx].compressedThis);
                            if (cacheResponse is null) // cache miss
                                // we reuse any existing memory but overwrite the containing data
                            {
                                //writefln("zcache miss (primary)");
                                ubyte* compressedBlob = (*activeNode)[subIdx].compressedThis;
                                assert(compressedBlob !is null);
                                ulong contentSize =
                                    ZSTD_getFrameContentSize(compressedBlob + ulong.sizeof, *cast(ulong*)&compressedBlob);
                                if (contentSize > size_t.max)
                                    assert(0);
                                assert(contentSize > 0);
                                assert(contentSize % ulong.sizeof == 0);

                                ulong neededSize = contentSize + size_t.sizeof * 2;
                                if (zcache.store.length < neededSize)
                                {
                                    if (zcache.store is null)
                                    {
                                        zcache.store = sedecAllocator.makeArray!ubyte(neededSize);
                                        if (zcache.store is null)
                                            assert(0);
                                    }
                                    if (!sedecAllocator.expandArray(zcache.store, neededSize - zcache.store.length))
                                        assert(0, format("could not allocate additional %s bytes", neededSize - zcache.store.length));
                                }

                                assert(*cast(ulong*)compressedBlob
                                    == ZSTD_findFrameCompressedSize(compressedBlob + ulong.sizeof, ulong.max));

                                auto status = ZSTD_decompressDCtx(dctx,
                                    &zcache.store[0] + ulong.sizeof, zcache.store.length - ulong.sizeof,
                                    compressedBlob + ulong.sizeof, *cast(ulong*)compressedBlob);
                                assert(!ZSTD_isError(status), ZSTD_getErrorName(status).fromStringz);

                                // set data origin
                                *cast(ubyte**)&zcache.store[0 .. ulong.sizeof][0] = (*activeNode)[subIdx].compressedThis;

                                cacheResponse = zcache.query!(NT.ChildNodeType)((*activeNode)[subIdx].compressedThis);
                                assert(cacheResponse !is null);
                            }

                            // switch to cache
                            assert(&*cacheResponse);
                            return _opIndex(i1, i2, cacheResponse, begin + NT.fWidth * subIdx, depth + 1, zcache.store);
                        }
                        else
                        {
                            extract(activeNode, subIdx);
                            return _opIndex(i1, i2, (*activeNode)[subIdx].thisPtr, begin + NT.fWidth * subIdx, depth + 1, zcache.store);
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
                            // we want the data to be correctly aligned
                            assert(cast(ulong)&zcache.store[0] % ulong.sizeof == 0);
                            assert((*activeNode)[subIdx].thisOffset % ulong.sizeof == 0);
                            writefln!"currCache: %(%x,%)"(cast(ulong[])currCache);
                            NT.ChildNodeType* nextNode = cast(NT.ChildNodeType*)(&currCache
                                [(*activeNode)[subIdx].thisOffset + ulong.sizeof .. $]
                                [0 .. NT.ChildNodeType.sizeof][0]);
                            assert(&*nextNode);
                            return _opIndex(i1, i2, nextNode, begin + NT.fWidth * subIdx, depth + 1, zcache.store);
                        }
                        if (result == ChildTypes.compressedThis)
                            // instead of discarding all cache, we only discard the mismatching compression branch
                        {
                            auto prevCache = currCache;
                            currCache = zcache.nextStrip(currCache);

                            ulong compressedBlob = (*activeNode)[subIdx].compressedOffset;
                            assert(compressedBlob != 0);


                            ulong contentSize = 0;

                            // if the offsets match, we have a cache hit
                            if (currCache.length > 0)
                            {
                                //writefln("zcache hit (secondary)");
                                ulong cachedOffset = *cast(ulong*)&currCache[0 .. ulong.sizeof][0];
                                if (false && cachedOffset == compressedBlob)
                                {
                                    NT.ChildNodeType* nextNode =
                                        cast(NT.ChildNodeType*)&(currCache[ulong.sizeof * 2 .. $][0 .. NT.ChildNodeType.sizeof][0]);
                                    assert(&*nextNode);
                                    return _opIndex(i1, i2, nextNode, begin + NT.fWidth * subIdx, depth + 1, zcache.store);
                                }
                            }
                            debug currCache[] = 0;

                            assert(*cast(ulong*)&prevCache[compressedBlob + ulong.sizeof]
                                == ZSTD_findFrameCompressedSize(&prevCache[compressedBlob + ulong.sizeof * 2], ulong.max),
                                format("our coded size %s is not equal to zstd's size %s", formatBytes(*cast(ulong*)&prevCache[compressedBlob + ulong.sizeof]),
                                formatBytes(ZSTD_findFrameCompressedSize(&prevCache[compressedBlob + ulong.sizeof * 2], ulong.max))));
                            // cache miss
                            //writefln("zcache miss (secondary)");
                            contentSize = ZSTD_getFrameContentSize(
                                &prevCache[compressedBlob + ulong.sizeof * 2 .. $][0],
                                *cast(ulong*)&prevCache[compressedBlob + ulong.sizeof .. $][0 .. ulong.sizeof][0]);
                            assert(contentSize != ZSTD_CONTENTSIZE_UNKNOWN, "content size could not be determined");
                            assert(contentSize != ZSTD_CONTENTSIZE_ERROR, "error decoding frame");
                            assert(contentSize > 0);
                            size_t neededSize = contentSize + ulong.sizeof; // contentSize already includes length field
                            if (currCache.length - ulong.sizeof < neededSize)
                            {
                                size_t origOffset = cast(size_t)&zcache.store[0];
                                if (!sedecAllocator.expandArray(zcache.store, neededSize))
                                    assert(0);
                                ptrdiff_t offsetChange = cast(size_t)&zcache.store[0] - origOffset;
                                assert(contentSize % ulong.sizeof == 0);

                                currCache = (currCache.ptr + offsetChange)[0 .. currCache.length + neededSize];
                                prevCache = (prevCache.ptr + offsetChange)[0 .. prevCache.length];
                                // do not use activeNode beyond this point, it may have been relocated
                            }

                            // set the blob origin
                            *cast(ulong*)&currCache[0 .. ulong.sizeof][0] = compressedBlob;

                            auto status = dctx.ZSTD_decompressDCtx(
                                &currCache[ulong.sizeof .. $][0], currCache[ulong.sizeof .. $].length,
                                &prevCache[compressedBlob + ulong.sizeof * 2 .. $][0],
                                *cast(ulong*)&prevCache[compressedBlob + ulong.sizeof .. $][0 .. ulong.sizeof][0]);
                            assert(!ZSTD_isError(status), ZSTD_getErrorName(status).fromStringz);
                            NT.ChildNodeType* nextNode = cast(NT.ChildNodeType*)&currCache[ulong.sizeof * 2 .. $][0 .. NT.ChildNodeType.sizeof][0];
                            assert(&*nextNode);
                            return _opIndex(i1, i2, nextNode, begin + NT.fWidth * subIdx, depth + 1, zcache.store);
                        }
                        unreachable;
                    }
                }
            }
            unreachable;
        }
    }

    void recursiveFree(NT)(ref NT* node)
        in(node !is null)
        in(&*node)
    {
        static if (!NT.isBottom)
        {
            with (ChildTypes) foreach (child; (*node)[])
            {
                if (child.type == thisPtr)
                {
                    auto target = child.thisPtr;
                    child.type = allFalse;
                    recursiveFree(target);
                }
                else if (child.type == compressedThis)
                {
                    auto target = child.compressedThis;
                    child.type = allFalse;
                    sedecAllocator.dispose(target);
                }
            }
        }
        assert(&*node);

        sedecAllocator.dispose(node);
    }

    ChildTypes opIndexAssign(V)(ChildTypes val, V v)
    {
        return opIndexAssign(val, v.x, v.y);
    }

    ChildTypes opIndexAssign(I)(ChildTypes val, I i1, I i2)
    {
        return opIndexAssign(val, cast(AddressType)i1, cast(AddressType)i2);
    }

    ChildTypes opIndexAssign(ChildTypes val, AddressType i1, AddressType i2)
    {
        with (ChildTypes) setPixel(
            root,
            Vector!(AddressType, 2)(i1, i2),
            Vector!(AddressType, 2)(cast(AddressType)0, cast(AddressType)0),
            val);
        return val;
    }


    Tuple!(Vector!(AddressType, 2), "coor", void*, "node") aCache;
    ubyte aDepth = 0;
    import std.algorithm : all, among;
    void setPixel(NT)(
            NT* node,
            Vector!(AddressType, 2) coor,
            Vector!(AddressType, 2) begin,
            ChildTypes value)
        in(node !is null)
        in(NT.fWidth > 0 && NT.fWidth.isPowerOf2)
        in(NT.fWidth != 1 || (*node)[].all!(n => !n.type.among(ChildTypes.compressedThis, ChildTypes.thisPtr)))
    {
        import core.bitop;
        enum cacheLevel = 64;
        static assert(cacheLevel.isPowerOf2);

        static if (is(NT == TopNodeType))
        {
            if (aCache.node !is null && (coor % cast(AddressType)cacheLevel) == aCache.coor)
            {
                setPixel(cast(SedecNode!(AddressType, 64)*)aCache.node, coor, aCache.coor, value);
                return;
            }
        }
        if (NT.fWidth == cacheLevel)
        {
            aCache.node = node;
            aCache.coor = begin;
        }

        import core.bitop : bsf;
        import std.algorithm;
        Vector!(AddressType, 2) subIdx = (coor - begin) / NT.fWidth;
        static if (NT.isBottom)
        {
            with (ChildTypes)
                (*node)[subIdx].type = value;
            return;
        }
        else
        {
            auto type = (*node)[subIdx].type;
            static if (!NT.isBottom)
            {
                with (ChildTypes) if (type.among(allTrue, allFalse))
                {
                    subdivide(node, subIdx);
                }
                else if (type == ChildTypes.compressedThis)
                {
                    extract(node, subIdx);
                }
            }
            // by now the relevant field should be switchable to
            assert((*node)[subIdx].type == ChildTypes.thisPtr);

            setPixel!(NT.ChildNodeType)((*node)[subIdx].thisPtr, coor, begin + NT.fWidth * subIdx, value);
        }
    }

    void subdivide(NT, V)(NT* node, V subIdx)
        in((*node)[subIdx].type.among(ChildTypes.allTrue, ChildTypes.allFalse))
        out(;(*node)[subIdx].type == ChildTypes.thisPtr)
    {
        static assert(NT.fWidth > 1);
        auto newNode = sedecAllocator.make!(NT.ChildNodeType);
        debug newNode.ident = uniform!ulong;
        if (newNode is null)
            assert(0);

        foreach (child; (*newNode)[]) // make it equivalent to the current child
             child.type = (*node)[subIdx].type;

        (*node)[subIdx].thisPtr = newNode;
    }

    void extract(NT, V)(NT* node, V subIdx)
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
        auto blob = ZBlob((*node)[subIdx].compressedThis);
        ZSTD_inBuffer srcBuf;
        srcBuf.src = &blob.zData[0];
        srcBuf.size = blob.zSize;

        ZSTD_outBuffer dstBuf;
        ulong len;
        dstBuf.dst = &len;
        dstBuf.size = ulong.sizeof;
        ulong status = dctx.ZSTD_decompressStream(&dstBuf, &srcBuf);
        assert(!ZSTD_isError(status), ZSTD_getErrorName(status).fromStringz);
        assert(dstBuf.pos == dstBuf.size);
        // len is not useful in this function

        (*node)[subIdx].thisPtr = extractThisPtr!(NT.ChildNodeType)(srcBuf);
        //writefln("extracted %s from %x to %x", subIdx, node, (*node)[subIdx].thisPtr);

        void* disp = blob.ptr;
        blob.destroy;
        sedecAllocator.dispose(blob.ptr);
    }

    NT* extractThisPtr(NT)(ref ZSTD_inBuffer srcBuf)
        out(r; r !is null)
    {
        ZSTD_outBuffer dstBuf;
        NT* target = sedecAllocator.make!(NT);
        dstBuf.dst = target;
        dstBuf.size = NT.sizeof;
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
                    break;
                case thisPtr:
                    static if (NT.isBottom)
                        unreachable;
                    else
                        child.thisPtr = extractThisPtr!(NT.ChildNodeType)(srcBuf);
                    break;
                case compressedThis:
                    static if (NT.isBottom)
                        unreachable;
                    else
                        child.compressedThis = extractBlob(srcBuf);
                    break;
            }
        }

        return target;
    }

    ubyte* extractBlob(ref ZSTD_inBuffer srcBuf)
    {
        ZSTD_outBuffer dstBuf;


        ulong len;
        dstBuf.dst = &len;
        dstBuf.size = ulong.sizeof;
        ulong status = dctx.ZSTD_decompressStream(&dstBuf, &srcBuf);
        assert(!ZSTD_isError(status), ZSTD_getErrorName(status).fromStringz);
        assert(dstBuf.pos == dstBuf.size);

        ubyte[] target = sedecAllocator.makeArray!ubyte(alignSize(len, 8) + ulong.sizeof);
        if (target is null)
            assert(0, format("failed to allocate %s", formatBytes(alignSize(len, 8) + ulong.sizeof)));

        objcpy(len, target[0 .. ulong.sizeof]);
        dstBuf.dst = &target[0];
        dstBuf.size = target[].length;
        //writefln("read size: %s", len);
        status = dctx.ZSTD_decompressStream(&dstBuf, &srcBuf);
        assert(!ZSTD_isError(status), ZSTD_getErrorName(status).fromStringz);
        assert(dstBuf.pos == dstBuf.size, format("position %s should have been at %s", dstBuf.pos, dstBuf.size));
        assert(ZBlob(&target[0]).contentSize > 0);

        return &target[0];
    }

    ~this()
    {
        ZSTD_freeCCtx(cctx);
        ZSTD_freeDCtx(dctx);
        static if (zCache)
            zcache.free;
        if (root !is null)
            recursiveFree(root);
    }

    static if (zCache)
        ZCache zcache;

    void _print(NT)(NT* node, int depth = 0)
    {
        import std.format;
        import std.range;
        import std.algorithm;
        writefln("%(%(%c%)%)%s", "|".repeat(depth), (*node)._toString);
        static if (!NT.isBottom) with (ChildTypes) foreach (child; (*node)[])
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

        NT* query(NT)(ubyte* blob)
        {
            return query!NT(blob, store);
        }

        NT* query(NT)(ubyte* blob, ubyte[] store)
            in(blob !is null)
            out(r; r is null || &*r)
        {
            if (store is null)
                return null;
            if (blob == *cast(ubyte**)&store[0 .. ulong.sizeof][0])
                return cast(NT*)&store[ulong.sizeof * 2 .. $][0 .. NT.sizeof][0];
            return null;
        }

        ubyte[] nextStrip(ubyte[] buf)
        {
            auto step = *cast(ulong*)&buf[ulong.sizeof .. ulong.sizeof * 2][0];
            stderr.writefln("nextStrip: %(%x,%)", buf[ulong.sizeof + step .. $]);
            return buf[ulong.sizeof + step .. $];
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

    ubyte[] packNode(NT, Flags...)(NT* node)
        if (allSatisfy!(isFlag, typeof(Flags)))
    {
        enum freeCopied = flagValue!(Flags)("freeCopied");
        static assert(freeCopied != -1, "Please specify whether packNode should automatically free nodes!");
        ubyte[] dst = makeArray!ubyte(sedecAllocator, 8);
        if (dst is null)
            assert(0);
        ulong packSize = 8; // length prefix
        packSize += pack!(freeCopied)(node, dst, ulong.sizeof);
        objcpy(packSize, dst[0 .. ulong.sizeof]);
        static if (freeCopied)
            sedecAllocator.dispose(node);

        sedecAllocator.shrinkArray(dst, dst.length - packSize);
        return dst;
    }

    ulong pack(bool freeCopied, NT)(NT* node, ref ubyte[] dst, ulong pos)
        in(node !is null)
        in(pos <= dst.length)
    {
        //stderr.writefln("dstl: %s; pos: %s", dst.length, pos);
        if (dst.length - pos < NT.sizeof)
        {
            import std.algorithm : max;
            assert(dst !is null);
            if (!sedecAllocator.expandArray(dst, max(dst.length / 2, NT.sizeof)))
                assert(0, format("could not allocate additional %s bytes", max(dst.length / 2, NT.sizeof)));
        }
        ulong occupied = 0;

        objcpy(*node, dst[pos .. $]);
        assert(&*cast(NT*)&dst[pos]);
        occupied += NT.sizeof;
        // we only know the offset in the array, the array may be relocated by subsequent packing
        sNT* currNode(sNT)()
        {
            assert(&*cast(sNT*)&dst[pos]);
            return cast(sNT*)&dst[pos];
        }

        with (ChildTypes) foreach (idx; 0 .. 16)
        {
            import std.algorithm : among;
            ChildTypes type = (*currNode!NT)[idx].type;
            if (type == thisPtr)
            {
                static if (NT.isBottom)
                    unreachable;
                else
                {
                    NT.ChildNodeType* orig = (*currNode!NT)[idx].thisPtr;
                    ulong written = pack!(freeCopied)((*currNode!NT)[idx].thisPtr, dst, pos + occupied);
                    static if (zCache)
                    {
                        (*currNode!NT)[idx].thisOffset = pos + occupied;
                    }
                    else
                        (*currNode!NT)[idx].thisOffset = 0;
                    occupied += written;
                    static if (freeCopied)
                        sedecAllocator.dispose(orig);
                }
            }
            else if (type == compressedThis)
            {
                static if (NT.isBottom)
                    unreachable;
                else
                {
                    ubyte* orig = (*currNode!NT)[idx].compressedThis;
                    ulong written = pack!freeCopied((*currNode!NT)[idx].compressedThis, dst, pos + occupied);
                    static if (zCache)
                        (*currNode!NT)[idx].compressedOffset = pos + occupied;
                    else
                        (*currNode!NT)[idx].compressedOffset = 0;
                    occupied += written;
                    static if (freeCopied)
                        sedecAllocator.dispose(orig);
                }
            }
            else if (type.among(allTrue, allFalse))
            {}
        }
        return occupied;
    }

    ulong pack(bool freeCopied)(ubyte* blob, ref ubyte[] dst, ulong pos)
        in(blob !is null)
        in(pos <= dst.length, format("position %s is outside of destination buffer %s", pos, dst.length))
    {
        ulong copyLength = *cast(ulong*)blob + ulong.sizeof;
        if (dst.length - pos < alignSize(copyLength, 8))
        {
            import std.algorithm : max;
            auto oldptr = dst.ptr;
            auto oldlen = dst.length;
            if (!sedecAllocator.expandArray(dst, max(dst.length / 2, alignSize(copyLength, 8) - (dst.length - pos))))
                assert(0, format("could not allocate additional %s",
                    formatBytes(max(dst.length / 2, alignSize(copyLength, 8) - (dst.length - pos)))));
        }
        ulong occupied = 0;

        dst[pos .. $][0 .. copyLength] = blob[0 .. copyLength];
        occupied += alignSize(copyLength, 8);
        assert(occupied % 8 == 0);

        return occupied;
    }

    ChildTypes optimizeTree()
    {
        return optimize(root);
    }

    ChildTypes optimize(NT)(NT* node)
        in(node !is null)
    {
        expireCache;
        ChildTypes result = (*node)[0].type; // compressedThis is a catch-all for non-optimizable data here
        foreach (child; (*node)[])
        {
            auto childType = child.type;
            if (childType == ChildTypes.thisPtr)
            {
                static if (NT.isBottom)
                    unreachable;
                else
                {
                    auto equivalentType = optimize(child.thisPtr);
                    with (ChildTypes) if (equivalentType.among(allTrue, allFalse))
                    {
                        auto garbage = child.thisPtr;
                        child.type = equivalentType;
                        sedecAllocator.dispose(garbage);
                    }
                }
            }
            if (child.type != result)
                result = ChildTypes.compressedThis;
        }
        return result;
    }

    void expireCache()
    {
        aCache.node = null;
        static if (zCache)
            if (zcache.store !is null)
                sedecAllocator.dispose(zcache.store);
    }

    void compress(NT, Flags...)(NT* node, Vector!(ubyte, 2) idx)
        in(node !is null)
        in(idx.x < 4)
        in(idx.y < 4)
        out(;&*node)
        out(;(*node)[idx].type == ChildTypes.compressedThis)
    {
        expireCache;
        import std.algorithm : among;
        ChildTypes type = (*node)[idx].type;
        with (ChildTypes) assert (!type.among(compressedThis, allFalse, allTrue));
        if (type == ChildTypes.thisPtr)
        {
            ubyte[] packed = packNode!(NT.ChildNodeType, Yes.freeCopied)((*node)[idx].thisPtr);
            cctx.ZSTD_initCStream(5);
            assert(packed.length % 8 == 0);
            cctx.ZSTD_CCtx_setPledgedSrcSize(packed.length);

            ZSTD_inBuffer srcBuf;
            ZSTD_outBuffer dstBuf;

            srcBuf.src = packed.ptr;
            srcBuf.size = packed.length;

            //            import std.range;
            // stderr.writefln!"PRINT%(%(%02x %)\n&&&&\n%)"(packed[ulong.sizeof * 1 .. $].chunks(NodeType.sizeof));

            ubyte[] dst = sedecAllocator.makeArray!ubyte(alignSize(packed.length / 4, 8)); // we assume that 75 % reduction is realistic

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

            /+ write the length prefix, this is the exact size of the compressed blob,
               i. e. excludes trailing alignment padding +/
            objcpy(cast(ulong)dstBuf.pos - ulong.sizeof, dst[0 .. ulong.sizeof]);
            //writeln(cast(ulong)(dstBuf.pos - ulong.sizeof));

            // trim the destination buffer
            // ensure that everything aligns properly in further runs
            ulong newSize = alignSize(dstBuf.pos, 8);
            assert(newSize % ulong.sizeof == 0);

           // debug assert(ZBlob(dst.ptr).contentSize > 0);
            if (newSize > dst.length)
            {
                if (!sedecAllocator.expandArray(dst, newSize - dst.length))
                    assert(0);
            }
            else if (dst.length > newSize)
            {
                if (!sedecAllocator.shrinkArray(dst, dst.length - newSize))
                    assert(0);
            }
            //else
            //    writeln("nothing");

            assert(dst.length % 8 == 0);
            //writefln("pack length: %s", packed.length);
            //writefln("%s %s %s", cast(ulong[])dst[0 .. 16], ZBlob(dst.ptr).zSize, ZBlob(dst.ptr).contentSize);
            (*node)[idx].compressedThis = dst.ptr;

            stderr.writefln!"compressed %s down to %s (%5.3s %%)"(formatBytes(packed.length),
                formatBytes(dst.length - ulong.sizeof),
                cast(double)(dst.length - ulong.sizeof)/cast(double)packed.length*100.0);
            // free source buffer
            sedecAllocator.dispose(packed);

            return;
        }
        unreachable;
    }

    static struct Rectangle
    {
        enum isSolidBody = true;
        Vector!(AddressType, 2) low;
        Vector!(AddressType, 2) high;

        this(Vector!(AddressType, 2) low, Vector!(AddressType, 2) high)
        {
            this.low = low;
            this.high = high;
        }

        FillValue opCall(AddressType fWidth, Vector!(AddressType, 2) begin)
        {
            if (fWidth == 1)
                return begin.x >= low.x && begin.x <= high.x && begin.y >= low.y && begin.y <= high.y
                    ? FillValue.allTrue
                    : FillValue.none;


            bool outside = false;
            if (low.x > begin.x + fWidth - 1)
                outside = true;
            if (high.x < begin.x)
                outside = true;
            if (low.y > begin.y + fWidth - 1)
                outside = true;
            if (high.y < begin.y)
                outside = true;
            if (outside)
                return FillValue.none;
            bool enclosed = true;
            if (!(low.x <= begin.x && high.x >= begin.x + fWidth - 1))
                enclosed = false;
            if (!(low.y <= begin.y && high.y >= begin.y + fWidth - 1))
                enclosed = false;
            if (enclosed)
            {
                return FillValue.allTrue;
            }
            return FillValue.mixed;
        }
    }

    void rectangleFill(
            Vector!(AddressType, 2) low,
            Vector!(AddressType, 2) high, // inclusive bound
            bool val)
        in(low.x <= high.x)
        in(low.y <= high.y)
    {
        genericFill(Rectangle(low, high), val);
    }

    static struct Circle
    {
        enum isSolidBody = true;
        Vector!(AddressType, 2) center;
        AddressType radius;

        this(Vector!(AddressType, 2) center, AddressType radius)
        {
            this.center = center;
            this.radius = radius;
        }

        FillValue opCall(AddressType fWidth, Vector!(AddressType, 2) begin)
        {
            import std.algorithm;
            alias V = Vector!(Signed!AddressType, 2);

            if (fWidth == 1)
            {
                auto sqDistance = (cast(V)(begin - center))[].fold!((a, b) => a + cast(uint)(b) ^^ 2)(0u);
                auto contained = sqDistance <= cast(ulong)radius ^^ 2;
                if (contained)
                    return FillValue.allTrue;
                else
                    return FillValue.none;
            }

            V[4] fCorners;
            fCorners[0] = begin;
            fCorners[1] = cast(V)vec2ul(begin.x, begin.y + fWidth);
            fCorners[2] = begin + fWidth;
            fCorners[3] = cast(V)vec2ul(begin.x + fWidth, begin.y);
            //fCorners[].each!((ref e) => e -= center);
            foreach (ref c; fCorners[])
                c -= center;
            int nContained = 0;
            foreach (v; fCorners[])
            {
                import std.bigint;
                auto sqDistance = v[].fold!((a, b) => a + cast(uint)(b) ^^ 2)(0u);
                auto contained = sqDistance <= cast(uint)radius ^^ 2;
                if (contained)
                    nContained += 1;
            }
            //writefln("fCorners: %s; nContained: %s", fCorners[], nContained);
            if (nContained == 4)
                return FillValue.allTrue;
            if (fWidth == 1)
                unreachable;
            if (nContained > 0)
                return FillValue.mixed;

            V[4] bCorners;
            bCorners[0] = center - radius;
            bCorners[1] = cast(V)vec2ul(center.x - radius, center.y + radius);
            bCorners[2] = center + radius;
            bCorners[3] = cast(V)vec2ul(center.x + radius, center.y - radius);

            bool xCrosses0 = fCorners[0].x <= 0 && fCorners[2].x >= 0;
            bool yCrosses0 = fCorners[0].y <= 0 && fCorners[2].y >= 0;
            bool ySecant = fCorners[0].y >= bCorners[0].y && fCorners[0].y <= bCorners[2].y
                           || fCorners[2].y >= bCorners[0].y && fCorners[2].y <= bCorners[2].y;
            bool xSecant = fCorners[0].x >= bCorners[0].x && fCorners[0].x <= bCorners[2].x
                           || fCorners[2].x >= bCorners[0].x && fCorners[2].x <= bCorners[2].x;

            if (xCrosses0 && xSecant)
                return FillValue.mixed;
            if (yCrosses0 && ySecant)
                return FillValue.mixed;
            if (yCrosses0 && xCrosses0)
                return FillValue.mixed;
            return FillValue.none;
        }
    }

    void circleFill(
        Vector!(AddressType, 2) center,
        AddressType radius,
        bool value)
    {
        genericFill(Circle(center, radius), value);
    }

    void genericFill(F)(F testFun, bool value)
        if (isCallable!F)
    {
        fillCost = 0;
        filledPixels = 0;
        expireCache; // this function might invalidate cache

        genericFill(root, cast(Vector!(AddressType, 2))vec2ul(0, 0), testFun, value);
    }
    ulong fillCost;
    ulong filledPixels;
    import arsd.nanovega;
    import arsd.color;
    import bindbc.opengl;
    import bindbc.glfw;
    NVGImage img;
    MemoryImage target;
    NVGContext nvg;
    GLFWwindow* window;
    ulong cnt;
    void genericFill(F, NT)(NT* node, Vector!(AddressType, 2) begin, F testFun, bool value)
    {
        import std.random;
        import std.range;
        foreach (i; 0 .. 16)
        {
            fillCost += 1;
            auto subIdx = cast(Vector!(AddressType, 2))vec2ul(i % 4, i / 4);
            auto subBegin = begin + NT.fWidth * subIdx;
            auto result = testFun(cast(AddressType)NT.fWidth, subBegin);

            import arsd.color;
            void draw(int col)
            {
                return;
/+                import core.thread;
                //Thread.sleep(100.usecs);
                if (MonoTime.currTime > trig)
                {
                    writeln(trig);

                }
                else
                    return;
                import core.bitop;
                glFinish();
                glClearColor(0, 0, 0, 0);
                glClear(glNVGClearFlags);
                import std.algorithm : predSwitch;

                //if (fWidth == 16)
                {
                /+foreach (y; 0 .. target.height)
                {
                    foreach (x; 0 .. target.width)
                    {
                        if (!(x >= begin.x && x <= begin.x + fWidth * 4 - 1 && y >= begin.y && y <= begin.y + fWidth * 4 - 1))
                            continue;
                        import std.algorithm;
                        import std.math;
                        Color baseColor = this[x, y].predSwitch(0, Color.black, 1,
                            Color(cast(int)((cos(cast(float)ldep)+1)*127),
                            cast(int)((cos(cast(float)(ldep + 2*PI/3))+1)*127),
                            cast(int)((cos(cast(float)(ldep + 4*PI/3)))+1)*127), Color.purple);
                        if (x >= subBegin.x && y >= subBegin.y && x <= subBegin.x + fWidth - 1 && y <= subBegin.y + fWidth - 1)
                            baseColor = Color.white;
                        else if ((x == begin.x || y == begin.y || x == begin.x + fWidth * 4 - 1 || y == begin.y + fWidth * 4 - 1)
                            && (x >= begin.x && x <= begin.x + fWidth * 4 - 1 && y >= begin.y && y <= begin.y + fWidth * 4 - 1))
                            baseColor = Color.green;
                        target.setPixel(x, y, baseColor);
                    }
                }+/

                nvg.beginFrame(1500, 1000);
                img = nvg.createImageFromMemoryImage(target, NVGImageFlag.NoFiltering);
                nvg.beginPath();
                nvg.rect(0, 0, 15000, 1000);
                nvg.fillPaint = nvg.imagePattern(0, 0, 1500, 1000, 0, img);
                nvg.fill();
                nvg.endFrame;


                glfwSwapBuffers(window);

                }import core.bitop;
                /+writefln("depth: %s; fillCost: %s; filledPixels: %s",
                    (AddressType.sizeof * 8 / 2) - bsf(fWidth) / 2,
                    fillCost,
                    filledPixels);
                +/import core.thread;
                trig = MonoTime.currTime + 100.msecs;
                //Thread.sleep((min(20 * fWidth, fWidth > 500 ? 20 : 500)).msecs);
 +/              // Thread.sleep(20.msecs);
            }

            if (NT.fWidth == 1)
                assert(result >= 0, "test with fWidth == 1 returned uncertain result!");
            auto type = (*node)[subIdx].type;
            if (result < 0) // block is not completely filled
            {
                if (type == cast(ChildTypes)value)
                { // the block is already filled with the desired value
                }
                else
                {
                    static if (NT.isBottom)
                        unreachable;
                    else
                    {
                        with (ChildTypes) if (type.among(allTrue, allFalse))
                            subdivide(node, subIdx);
                        else if (type == compressedThis)
                            extract(node, subIdx);
                        genericFill((*node)[subIdx].thisPtr, subBegin, testFun, value);
                        if (false)
                        {
                            optimize((*node)[subIdx].thisPtr);
                            compress(node, cast(Vector!(ubyte, 2))subIdx);
                        }
                    }
                }
            }
            else if (result > 0) // block is filled
            {
                void* garbage;
                if (type == ChildTypes.thisPtr)
                {
                    static if (NT.isBottom)
                        unreachable;
                    else
                        garbage = (*node)[subIdx].thisPtr;
                }
                else if (type == ChildTypes.compressedThis)
                {
                    static if (NT.isBottom)
                        unreachable;
                    else
                        garbage = (*node)[subIdx].compressedThis;
                }
                (*node)[subIdx].type = cast(ChildTypes)value;
                import std.algorithm;
                import std.math;
                /+        Color baseColor = (cast(ChildTypes)value).predSwitch(0, Color.black, 1,
                            Color(cast(int)((cos(fillCost / 100000.0)+1)*127),
                            cast(int)((cos((fillCost / 100000.0 + 2*cast(double)PI/3))+1)*127),
                            cast(int)((cos((fillCost / 100000.0 + 4*cast(double)PI/3)))+1)*127), Color.purple);
                +/    filledPixels += NT.fWidth ^^ 2;

                if (garbage !is null)
                    sedecAllocator.dispose(garbage);
            }
            draw(0);
        }
    }

    static auto UnionBody(T...)(T bodies)
    {
        import std.functional;
        _UnionBody!(bodies.length, Filter!(templateNot!isPointer, T[])) result;
        static foreach (i, dlg; bodies)
        {
            static assert(dlg.isSolidBody);
            static if (isPointer!(typeof(dlg)))
                result.bodies[i] = &(dlg.opCall);
            else
            {
                result.aux[Filter!(templateNot!isPointer, T[0 .. i]).length] = dlg;
                result.bodies[i] = &(result.aux[Filter!(templateNot!isPointer, T[0 .. i]).length].opCall);
            }
        }
        return result;
    }

    static struct _UnionBody(uint num, T...)
    {
        enum isSolidBody = true;
        T aux;
        FillValue delegate(AddressType, Vector!(AddressType, 2))[num] bodies;
        uint vCache = 0;
        FillValue opCall(AddressType fWidth, Vector!(AddressType, 2) begin)
        {
            auto result = FillValue.none;
            FillValue dresult = bodies[vCache](fWidth, begin);
            if (dresult == FillValue.allTrue)
            {
                return dresult;
            }
            if (dresult == FillValue.mixed)
                result = dresult;
            foreach (i, b; bodies)
            {
                if (i == vCache)
                    continue;
                dresult = b(fWidth, begin);
                if (dresult == FillValue.allTrue)
                {
                    vCache = cast(uint)i;
                    return dresult;
                }
                if (dresult == FillValue.mixed)
                    result = dresult;
            }
            return result;
        }
    }

    void unionFill(T...)(T bodies, bool value)
    {
        static foreach (i, b; bodies)
            static assert(b.isSolidBody, format("argument %s is not a solid body", i));
        UnionBody!T b;
        static foreach (i, bd; bodies)
            b.bodies[i] = bd;
        genericFill(b, value);
    }

    static _DifferenceBody!(A, B) DifferenceBody(A, B)(A bodyA, B bodyB)
    {
        _DifferenceBody!(A, B) result;
        result.bodyA = bodyA;
        result.bodyB = bodyB;
        return result;
    }

    static struct _DifferenceBody(A, B)
    {
        enum isSolidBody = true;
        A bodyA;
        B bodyB;
        FillValue opCall(AddressType fWidth, Vector!(AddressType, 2) begin)
        {
            FillValue result;
            static if (isPointer!A)
                result = (*bodyA)(fWidth, begin);
            else
                result = bodyA(fWidth, begin);

            if (result == FillValue.none)
                return result;

            FillValue bresult;
            static if (isPointer!A)
                bresult = (*bodyB)(fWidth, begin);
            else
                bresult = bodyB(fWidth, begin);

            if (bresult == FillValue.allTrue)
                return FillValue.none;

            if (result == FillValue.allTrue && bresult == FillValue.none)
                return FillValue.allTrue;
            return FillValue.mixed;
        }
    }

    void differenceFill(A, B)(A bodyA, B bodyB, bool value)
    {
        static assert(bodyA.isSolidBody, "bodyA is not a solid body");
        static assert(bodyB.isSolidBody, "bodyB is not a solid body");

        genericFill(DifferenceBody(bodyA, bodyB), value);
    }
}

void printBuf(ubyte[] buf)
{
    import std.range;
    import std.stdio;
    writefln!"[%s%(%02x %)]"(buf.length > 400 ? "… " : "", buf.take(400));
}

ubyte[] objcpy(T)(auto ref T src, ubyte[] dst)
    in(T.sizeof <= dst[].length)
{
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

ulong alignSize(ulong size, ulong alignment = platformAlignment)
    out(r; r % alignment == 0)
{
    return size + (alignment - (size % alignment)) % alignment;
}

struct ZBlob
{
    invariant(ptr !is null);
    ubyte* ptr;

    this(ubyte* ptr)
    {
        this.ptr = ptr;
    }

    ulong zSize() const
    {
        version(assert)
        {
            ulong solution1 = ZSTD_findFrameCompressedSize(ptr + ulong.sizeof, ulong.max);
            assert(!ZSTD_isError(solution1), ZSTD_getErrorName(solution1).fromStringz);
        }
        ulong solution2 = *cast(ulong*)ptr;
        version(assert)
        {
            assert(solution1 == solution2,
                format("zstd determined the compressed frame size to be %s while we coded %s", solution1, solution2));
        }
        return solution2;
    }

    ulong contentSize() const
        in(zSize > 0)
    {
        ulong solution1 = ZSTD_getFrameContentSize(ptr + ulong.sizeof, ulong.max);
        assert(!ZSTD_isError(solution1), ZSTD_getErrorName(solution1).fromStringz);

        version (assert)
        {
            ulong solution2;
            ZSTD_DCtx* dctx = ZSTD_createDStream();
            dctx.ZSTD_initDStream;
            ZSTD_outBuffer dstBuf;
            ZSTD_inBuffer srcBuf;
            dstBuf.dst = &solution2;
            dstBuf.size = ulong.sizeof;
            srcBuf.src = ptr + ulong.sizeof;
            srcBuf.size = zSize;
            ulong status = dctx.ZSTD_decompressStream(&dstBuf, &srcBuf);
            assert(!ZSTD_isError(status), ZSTD_getErrorName(status).fromStringz);
            assert(dstBuf.pos == dstBuf.size);
            assert(solution2 == solution1,
                format("zstd determined the content size to be %s while we coded %s", solution2, solution1));
            ZSTD_freeDStream(dctx);
        }
        return solution1;
    }

    ubyte[] zData()
    {
        return ptr[ulong.sizeof .. zSize + ulong.sizeof];
    }
}
