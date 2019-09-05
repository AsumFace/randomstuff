/+--------------------Copyright Notice------------------------+\
|      Copyright:                                              |
|  - AsumFace (asumface@gmail.com) 2019                        |
|  Distributed under the Boost Software License, Version 1.0.  |
|  See accompanying file Boost1_0 or copy at                   |
|      https://www.boost.org/LICENSE_1_0.txt                   |
\+------------------------------------------------------------+/


/++
This module provides a datastructure meant to be used for in-memory manipulations of huge, sparsely filled,
  binary images. It is in experimental state and might change substantially, but the basic functionality is
  there and works.
+/

module sedectree;

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
    thisPtr = 0b0010,
}

alias SedecAllocator = Mallocator;
alias sedecAllocator = SedecAllocator.instance;

/+debug
    enum ulong byOffsetFlag = 0b1000;
else
    enum ulong byOffsetFlag = 0;
+/
struct SedecNode(AddressType, AddressType _fWidth, uint _divisor)
    if (isIntegral!AddressType && isUnsigned!AddressType)
{
    alias divisor = _divisor;
    static assert(divisor.isPowerOf2 && divisor != 0);
    alias fWidth = _fWidth;
    static assert(fWidth.isPowerOf2);
    static assert(this.sizeof % ulong.sizeof == 0);

    static if (fWidth > 1)
    {
        enum isBottom = false;
        static if (fWidth / divisor == 0)
        {
            alias ChildNodeType = SedecNode!(AddressType, 1, fWidth);
        }
        else
        {
            alias ChildNodeType = SedecNode!(AddressType, fWidth / divisor, divisor);
        }
    }
    else
        enum isBottom = true;

    debug ulong _protector = 0xdeadbeef01cecafe;
    debug ulong _fWidth_check = fWidth;
    debug enum _Kinds : ubyte {
        uninitialized,
        nil,
        pointer
    }
    debug _Kinds[divisor ^^ 2] _kind;
    debug ulong[divisor ^^ 2] _srcLines;
    private Word!(divisor ^^ 2, 0xf) _type;
    static if (!isBottom)
        private ChildStore[divisor ^^ 2] _children;

    static assert(divisor != 16 || _type.sizeof == 128);
    static assert(divisor != 8 || _type.sizeof == 32);
    static assert(divisor != 4 || _type.sizeof == 8); // should be packed exactly with no padding
    static assert(divisor != 2 || _type.sizeof == 2);
    invariant
    {
        debug assert(cast(size_t)&this % ulong.sizeof == 0, "Node does not have proper alignment");
        debug assert(_protector == 0xdeadbeef01cecafe, format("protector has been corrupted! %08x, %s", _protector, _toString));
        debug assert(_fWidth_check == fWidth, format("node should have fWidth %s, but has %s", fWidth, _fWidth_check));
        assert(null is cast(void*)0, "null pointer does not point to 0. this code assumes that");
        //assert(cast(size_t)&this < 0xff00000000000000);
        foreach (i; 0 .. divisor ^^ 2)
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
        static if (!isBottom)
        {
            ChildNodeType* thisPtr;
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
                "%s{%(%(%c%),%)}{",
                pstring,
                _type[].map!(n => n.predSwitch(
                    allTrue, "T",
                    allFalse, "F",
                    thisPtr, "r",
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
        in(v.x < divisor)
        in(v.y < divisor)
    {
        return opIndex(v.x + divisor * v.y);
    }

    auto opSlice(ulong begin, ulong end)
        in(begin < divisor ^^ 2)
        in(end <= divisor ^^ 2)
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
        return opSlice(0, divisor ^^ 2);
    }

    auto opIndex(I)(I i)
        if (isIntegral!I)
        in(i < divisor ^^ 2, format!"index %s is out of bounds! ([0 .. %s])"(i, divisor))
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
                static if (!isBottom)
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
            }
        }
        return ChildObject(&this, cast(ubyte)i);
    }
}


auto sedecTree(AddressType, uint divisor)()
    if (isIntegral!AddressType)
{
    auto result = SedecTree!(AddressType, divisor)();
    result.root = make!(result.TopNodeType)(sedecAllocator);
    if (result.root is null)
        assert(0, "allocation failure");
    return result;
}

struct SedecTree(AddressType, uint divisor)
     if (isIntegral!AddressType)
{
    static assert(divisor.isPowerOf2 && divisor != 0);
    alias TopNodeType = SedecNode!(AddressType, AddressType.max / divisor + 1, divisor);

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
            Vector!(AddressType, 2)(AddressType.min));
    }
    ChildTypes _opIndex(NT)(AddressType i1, AddressType i2, NT* activeNode, Vector!(AddressType, 2) begin)
        if (isInstanceOf!(SedecNode, NT))
        in(activeNode !is null && &*activeNode)
    {
        import std.math;
        static assert(cacheLevel.isPowerOf2);

        static if (is(NT == TopNodeType))
        {
            //writefln!"aCache.coor: %s; ours: %s"(aCache.coor, Vector!(AddressType, 2)(i1, i2) & ~(cast(AddressType)cacheLevel - 1));
            if (aCache.node !is null && (Vector!(AddressType, 2)(i1, i2) & ~(cast(AddressType)cacheLevel - 1)) == aCache.coor)
            {
                //writeln("cache hit ", cache_hits++);
                return _opIndex(i1, i2, cast(SedecNode!(AddressType, cacheLevel, divisor)*)aCache.node, aCache.coor);
            }
        }
        //writeln(NT.fWidth);
        static if (NT.fWidth == cacheLevel)
        {
            aCache.node = activeNode;
            aCache.coor = begin;
        }
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
            else if (result == ChildTypes.thisPtr) // just jump into the next lower division and repeat
                return _opIndex(i1, i2, (*activeNode)[subIdx].thisPtr, begin + NT.fWidth * subIdx);
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
    enum cacheLevel = 16 ^^ 2;
    import std.algorithm : all, among;
    void setPixel(NT)(
            NT* node,
            Vector!(AddressType, 2) coor,
            Vector!(AddressType, 2) begin,
            ChildTypes value)
        in(node !is null)
        in(NT.fWidth > 0 && NT.fWidth.isPowerOf2)
        in(NT.fWidth != 1 || (*node)[].all!(n => !n.type.among(ChildTypes.thisPtr)))
    {
        import core.bitop;
        static assert(cacheLevel.isPowerOf2);

        static if (is(NT == TopNodeType))
        {
            if (aCache.node !is null && (coor & ~(cast(AddressType)cacheLevel - 1)) == aCache.coor)
            {
                setPixel(cast(SedecNode!(AddressType, cacheLevel, divisor)*)aCache.node, coor, aCache.coor, value);
                return;
            }
        }
        static if (NT.fWidth == cacheLevel)
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
        //stderr.writefln!"%s"(cast(ulong)newNode);
        if (newNode is null)
            assert(0, "allocation failure");

        foreach (child; (*newNode)[]) // make it equivalent to the current child
             child.type = (*node)[subIdx].type;

        (*node)[subIdx].thisPtr = newNode;
    }


    ~this()
    {
        if (root !is null)
            recursiveFree(root);
    }

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

    ChildTypes optimizeTree()
    {
        return optimize(root);
    }

    ChildTypes optimize(NT)(NT* node)
        in(node !is null)
    {
        expireCache;
        ChildTypes result = (*node)[0].type;
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
                result = ChildTypes.thisPtr;
        }
        return result;
    }

    void expireCache()
    {
        aCache.node = null;
    }

    static class Rectangle : solid_body
    {
        Vector!(AddressType, 2) low;
        Vector!(AddressType, 2) high;

        this(Vector!(AddressType, 2) low, Vector!(AddressType, 2) high)
        {
            this.low = low;
            this.high = high;
        }

        override FillValue opCall(AddressType fWidth, Vector!(AddressType, 2) begin)
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

    static class Circle : solid_body
    {
        Vector!(AddressType, 2) center;
        AddressType radius;

        this(Vector!(AddressType, 2) center, AddressType radius)
        {
            this.center = center;
            this.radius = radius;
        }

        override FillValue opCall(AddressType fWidth, Vector!(AddressType, 2) begin)
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
        foreach (i; 0 .. NT.divisor ^^ 2)
        {
            fillCost += 1;
            auto subIdx = cast(Vector!(AddressType, 2))vec2ul(i % NT.divisor, i / NT.divisor);
            auto subBegin = begin + NT.fWidth * subIdx;
            auto result = testFun(cast(AddressType)NT.fWidth, subBegin);

            import arsd.color;
            void draw(int col)
            {
                return;
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
                        genericFill((*node)[subIdx].thisPtr, subBegin, testFun, value);
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

    static class solid_body
    {
        abstract FillValue opCall(AddressType fWidth, Vector!(AddressType, 2) begin);
    }

    static class negation_body : solid_body
    {
        solid_body base_body;
        this(solid_body bb)
        {
            base_body = bb;
        }
        override FillValue opCall(AddressType fWidth, Vector!(AddressType, 2) begin)
        {
            FillValue result = base_body(fWidth, begin);
            assert(fWidth > 1 || result != FillValue.mixed);
            with (FillValue) final switch (result)
            {
            case mixed:
                return mixed;
            case allTrue:
                return none;
            case none:
                return allTrue;
            }
        }
    }

    import std.algorithm : among;
    static FillValue conditional_negate(FillValue result, bool q)
        in(result.among(EnumMembers!FillValue))
    {
        if (!q)
            return result;
        with (FillValue) final switch (result)
        {
        case mixed:
            return mixed;
        case allTrue:
            return none;
        case none:
            return allTrue;
        }
    }

    static class conjunction_body : solid_body
    {
        solid_body[] base_bodies;
        bool[] negations;
        ubyte[] indices;
        this(solid_body[] bb...)
        {
            base_bodies ~= bb;
        }
        override FillValue opCall(AddressType fWidth, Vector!(AddressType, 2) begin)
        {
            auto result = FillValue.allTrue;
            foreach (i, b; base_bodies)
            {
                FillValue dresult = conditional_negate(base_bodies[indices[i]](fWidth, begin), negations[indices[i]]);
                if (dresult == FillValue.none)
                {
                    import std.algorithm;
                    bringToFront(indices[0 .. i], indices[i .. i + 1]);
                    return dresult;
                }
                if (dresult == FillValue.mixed)
                    result = dresult;
            }
            return result;
        }
    }

    alias union_body = disjunction_body;
    alias intersection_body = conjunction_body;

    static class disjunction_body : solid_body
    {
        solid_body[] base_bodies;
        bool[] negations;
        ubyte[] indices;
        override FillValue opCall(AddressType fWidth, Vector!(AddressType, 2) begin)
        {
            auto result = FillValue.none;
            foreach (i, b; base_bodies)
            {
                FillValue dresult = conditional_negate(base_bodies[indices[i]](fWidth, begin), negations[indices[i]]);
                if (dresult == FillValue.allTrue)
                {
                    import std.algorithm;
                    bringToFront(indices[0 .. i], indices[i .. i + 1]);
                    return dresult;
                }
                if (dresult == FillValue.mixed)
                    result = dresult;
            }
            return result;
        }
    }

    static class difference_body : solid_body
    {
        solid_body bodyA;
        solid_body bodyB;
        int sel;
        this(solid_body a, solid_body b)
        {
            bodyA = a;
            bodyB = b;
        }
        override FillValue opCall(AddressType fWidth, Vector!(AddressType, 2) begin)
        {
            bool first = true;

            FillValue aresult;
            FillValue bresult;
            FillValue result;
            bool evalA()
            {
                aresult = bodyA(fWidth, begin);
                if (aresult == FillValue.none)
                {
                    sel = 0;
                    result = aresult;
                    return true;
                }
                return false;
            }
            bool evalB()
            {
                bresult = bodyB(fWidth, begin);
                if (bresult == FillValue.allTrue)
                {
                    sel = 1;
                    result = FillValue.none;
                    return true;
                }
                return false;
            }
            if (sel == 0)
            {
                if (evalA || evalB) return result;
            }
            else
            {
                if (evalB || evalA) return result;
            }
            if (aresult == FillValue.allTrue && bresult == FillValue.none)
                return FillValue.allTrue;
            return FillValue.mixed;
        }
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
