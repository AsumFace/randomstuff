module arbint;

import required;
import std.traits;
import std.range : ElementType;
import word : bitMask;


version(BigEndian)
{
    static assert(0, "Support for big endian has not been implemented yet!");
}

version(LDC)
{
    import ldc.llvmasm;
    private enum intrinsics = true;
}
else
{
    private enum intrinsics = false;
}

struct ArbInt(uint bits, bool signed = false)
    if (bits > 0)
{
    @trusted:
    // type determination logic adapted from word.d
    private alias StoreTypes = AliasSeq!(ubyte, ushort, uint, ulong); // shall be sorted short to large!
    static foreach (T; StoreTypes[])
    {
        static if (bits <= (T.sizeof * 8) && !is(StoreType))
            private alias StoreType = T;
    }
    static if (!is(StoreType))
        private alias StoreType = ulong;
    private StoreType[bits / (StoreType.sizeof * 8) + (bits % (StoreType.sizeof * 8) > 0 ? 1 : 0)] store;

    import std.format : format;
    import std.array : empty;

    private static lastMask()
    {
        static if (StoreType.sizeof * 8 == bits)
            return cast(StoreType)(0uL - 1);
        else
            return bitMask!((bits % (StoreType.sizeof * 8)), 0);
    }

    ref typeof(this) opOpAssign(string op)(const(typeof(this)) rhs)
    {
        if (!__ctfe && intrinsics)
        {
            version(LDC)
            {
                enum opTypes
                {
                    add,
                    sub,
                    mul,
                    udiv,
                    sdiv,
                    urem,
                    srem,
                    xor,
                    and,
                    or,
                    ashr,
                    lshr,
                    shl
                }
                static if (op == "+")
                    enum instr = opTypes.add;
                else static if (op == "-")
                    enum instr = opTypes.sub;
                else static if (op == "*")
                    enum instr = opTypes.mul;
                else static if (op == "/" && signed == false)
                    enum instr = opTypes.udiv;
                else static if (op == "/" && signed == true)
                    enum instr = opTypes.sdiv;
                else static if (op == "%" && signed == false)
                    enum instr = opTypes.urem;
                else static if (op == "%" && signed == true)
                    enum instr = opTypes.srem;
                else static if (op == ">>" && signed == true)
                    enum instr = opTypes.ashr;
                else static if (op == ">>>" || op == ">>" && signed == false)
                    enum instr = opTypes.lshr;
                else static if (op == "<<")
                    enum instr = opTypes.shl;
                else static if (op == "^")
                    enum instr = opTypes.xor;
                else static if (op == "|")
                    enum instr = opTypes.or;
                else static if (op == "&")
                    enum instr = opTypes.and;
                import std.format : format;
                __ir!(format!"
                %%cast0 = bitcast i8* %%0 to i%1$s*
                %%cast1 = bitcast i8* %%1 to i%1$s*
                %%a = load i%1$s, i%1$s* %%cast0
                %%b = load i%1$s, i%1$s* %%cast1
                %%r = %2$s i%1$s %%a, %%b
                store i%1$s %%r, i%1$s* %%cast0"(bits, instr), void, void*, const(void*))(store.ptr, rhs.store.ptr);
            }
        }
        else
        {
            static if (op == ">>>")
            {
                Unqual!(typeof(this)) result = this;
                result >>= rhs;
                if (rhs == typeof(this)(0))
                    return this;
                else
                    result = ~(typeof(this)(1) << typeof(this)(bits - 1)) >> rhs - typeof(this)(1);
                this = result;
                return this;
            }
            else
            {
                import std.bigint;
                BigInt ilhs;
                foreach (i, a; store[])
                {
                    BigInt tmp;
                    tmp |= a;
                    tmp <<= i * StoreType.sizeof * 8;
                    ilhs |= tmp;
                }
                BigInt irhs;
                foreach (i, a; rhs.store[])
                {
                    BigInt tmp;
                    tmp |= a;
                    tmp <<= i * StoreType.sizeof * 8;
                    irhs |= tmp;
                }
                static if (op == "<<" || op == ">>")
                    mixin("ilhs = ilhs " ~ op ~ " irhs.toLong;");
                else
                    mixin("ilhs = ilhs " ~ op ~ " irhs;");
                foreach (i, ref a; store[])
                {
                    BigInt tmp;
                    if (i == store[].length - 1)
                        tmp = ilhs & lastMask;
                    else
                        tmp = ilhs & bitMask!(StoreType.sizeof * 8, 0);
                    ilhs >>= StoreType.sizeof * 8;

                    a = cast(StoreType)tmp.toLong;
                }
                return this;
            }
        }
        return this;
    }

    typeof(this) opBinary(string op)(const(typeof(this)) rhs) const
    {
        Unqual!(typeof(this)) result = this;
        result.opOpAssign!op(rhs);
        return result;
    }

    ref typeof(this) opUnary(string op)()
        if (op == "++" || op == "--")
    {
        if (!__ctfe && intrinsics)
        {
            version(LDC)
            {
                enum opTypes
                {
                    add,
                    sub
                }
                static if (op == "++")
                    enum instr = opTypes.add;
                else static if (op == "--")
                    enum instr = opTypes.sub;
                __ir!(format!"
                %%a = load i%1$s, i%1$s* %%0
                %% = %2$s %%b, i%1$s 1
                store i%1$s %%r, i%1$s* %%0"(bits, instr), void, void*)(store.ptr);
                return this;
            }
        }
        else
        {
            static if (op == "++")
                return this += 1;
            else static if (op == "--")
                return this -= 1;
        }
    }

    typeof(this) opUnary(string op)() const
        if (op == "~")
    {
        if (!__ctfe && intrinsics)
        {
            version(LDC)
            {
                Unqual!(typeof(this)) result = this;
                __ir!(format!"
                %%cast0 = bitcast i8* %%0 to i%1$s*
                %%a = load i%1$s, i%1$s* %%cast0
                %%b = add i%1$s 0, 0
                %%c = sub i%1$s %%b, 1
                %%r = xor i%1$s %%a, %%c
                store i%1$s %%r, i%1$s* %%cast0"(bits), void, void*)(result.store.ptr);
                return result;
            }
        }
        else
        {
            Unqual!(typeof(this)) result = this;
            foreach (i, ref a; result.store[])
            {
                a = ~a;
                if (i == store[].length - 1)
                    a &= lastMask;
            }
            return result;
        }
    }

    typeof(this) opUnary(string op)() const
        if (op == "-" && signed == true)
    {
        if (!__ctfe && intrinsics)
        {
            version(LDC)
            {
                Unqual!(typeof(this)) result = this;
                __ir!(format!"
                %%a = load i%1$s, i%1$s* %%0
                %%r = sub i%1$s 0, %%a
                store i%1$s %%r, i%1$s* %%0"(bits), void, void*)(result.store.ptr);
            }
        }
        else
        {
            import std.bigint;
            Unqual!(typeof(this)) result = this;
            BigInt iresult;
            foreach (i, a; store[])
            {
                BigInt tmp;
                tmp |= a;
                tmp <<= i * StoreType.sizeof * 8;
                iresult |= tmp;
            }
            iresult = 0 - iresult;
            foreach (i, ref a; result.store[])
            {
                BigInt tmp;
                if (i == store[].length - 1)
                    tmp = iresult & lastMask;
                else
                    tmp = iresult & bitMask!(StoreType.sizeof * 8, 0);
                iresult >>= StoreType.sizeof * 8;

                a = cast(StoreType)tmp.toLong;
            }
            return result;
        }
    }

    int opCmp(const(typeof(this)) rhs) const
    {
        if (!__ctfe && intrinsics)
        {
            version(LDC)
            {
                enum Sgn
                {
                    s,
                    u
                }
                static if (signed == true)
                    enum sgn = Sgn.s;
                else static if (signed == false)
                    enum sgn = Sgn.u;
                return __ir!(format!"
                %%cast0 = bitcast i8* %%0 to i%1$s*
                %%cast1 = bitcast i8* %%1 to i%1$s*
                %%a = load i%1$s, i%1$s* %%cast0
                %%b = load i%1$s, i%1$s* %%cast1
                %%gt = icmp %2$sgt i%1$s %%a, %%b
                %%lt = icmp %2$slt i%1$s %%a, %%b
                br i1 %%gt, label %%Gt, label %%Cont0
                Cont0:
                br i1 %%lt, label %%Lt, label %%Cont1
                Cont1:
                ret i32 0
                Gt:
                ret i32 1
                Lt:
                ret i32 -1"(bits, sgn), int, const(void*), const(void*))(store.ptr, rhs.store.ptr);
            }
        }
        else
        {
            import std.range : lockstep, StoppingPolicy;
            foreach_reverse (i, ca, cb; lockstep(store[], rhs.store[], StoppingPolicy.requireSameLength))
            {
                StoreType a = ca;
                StoreType b = cb;
                if (i == store[].length - 1)
                {
                    a &= lastMask;
                    b &= lastMask;
                }
                if (a > b)
                    return 1;
                else if (a < b)
                    return -1;
            }
            return 0;
        }
        assert(0);
    }

    bool opEquals(const(typeof(this)) rhs) const
    {
        if (!__ctfe && intrinsics)
        {
            version(LDC)
            {
                return __ir!(format!"
                %%cast0 = bitcast i8* %%0 to i%1$s*
                %%cast1 = bitcast i8* %%1 to i%1$s*
                %%a = load i%1$s, i%1$s* %%cast0
                %%b = load i%1$s, i%1$s* %%cast1
                %%r = icmp eq i%1$s %%a, %%b
                ret i1 %%r"(bits), bool, const(void*), const(void*))(store.ptr, rhs.store.ptr);
            }
        }
        else
        {
            import std.range : lockstep;
            foreach (i, ca, cb; lockstep(store[], rhs.store[]))
            {
                StoreType a = ca;
                StoreType b = cb;
                if (i == store[].length - 1)
                {
                    a &= lastMask;
                    b &= lastMask;
                    return a == b;
                }
                if (a != b)
                    return false;
            }
            return true;
        }
        assert(0);
    }

    T opCast(T)() const
        if (isIntegral!T || isInstanceOf!(TemplateOf!(typeof(this)), T))
    {
        if (!__ctfe && intrinsics)
        {
            version(LDC)
            {
                enum Sgn
                {
                    z,
                    s
                }
                static if (isSigned!T == true)
                    enum sgn = Sgn.s;
                else static if (isSigned!T == false)
                    enum sgn = Sgn.z;
                else static if (isInstanceOf!(ArbInt, T) && TemplateArgsOf!T[1] == true)
                    enum sgn = Sgn.s;
                else static if (isInstanceOf!(ArbInt, T) && TemplateArgsOf!T[1] == false)
                    enum sgn = Sgn.z;
                T result;
                static if (isIntegral!T)
                {
                    enum tbits = T.sizeof * 8;
                    auto tstore = &result;
                }
                else static if (isInstanceOf!(TemplateOf!(typeof(this)), T))
                {
                    enum tbits = TemplateArgsOf!T[0];
                    auto tstore = result.store[].ptr;
                }

                static if (tbits > bits)
                    __ir!(format!"
                    %%cast0 = bitcast i8* %%0 to i%1$s*
                    %%cast1 = bitcast i8* %%1 to i%2$s*
                    %%val0 = load i%1$s, i%1$s* %%cast0
                    %%a = %3$sext i%1$s %%val0 to i%2$s
                    store i%2$s %%a, i%2$s* %%cast1
                    "(bits, tbits, sgn), void, const(void*), void*)(store.ptr, tstore);
                else static if (tbits < bits)
                    __ir!(format!"
                    %%cast0 = bitcast i8* %%0 to i%1$s*
                    %%cast1 = bitcast i8* %%1 to i%2$s*
                    %%val0 = load i%1$s, i%1$s* %%cast0
                    %%a = trunc i%1$s %%val0 to i%2$s
                    store i%2$s %%a, i%2$s* %%cast1
                    "(bits, tbits), void, const(void*), void*)(store.ptr, tstore);
                else static if (tbits == bits)
                    __ir!(format!"
                    %%cast0 = bitcast i8* %%0 to i%1$s*
                    %%cast1 = bitcast i8* %%1 to i%2$s*
                    %%val0 = load i%1$s, i%1$s* %%cast0
                    store i%1$s %%val0, i%2$s* %%cast1
                    "(bits, tbits), void, const(void*), void*)(store.ptr, tstore);
                return result;
            }
        }
        else
        {
            static if (isIntegral!T)
                return cast(T)store[0];
            else static if (isInstanceOf!(TemplateOf!(typeof(this)), T))
            {
                import std.range : lockstep;
                T result;
                foreach (i, ref a, b; lockstep(result.store[], store[]))
                {
                    a = cast(ElementType!(typeof(result.store[])))b;
                    static if (result.store.length < store.length)
                    {
                        if (i == result.store[].length - 1)
                            a &= lastMask;
                    }
                }
                return result;
            }
        }
        assert(0);
    }

    this(T)(T arg)
        if (isIntegral!T)
    {
        if (!__ctfe && intrinsics)
        {
            version(LDC)
            {
                enum Sgn
                {
                    z,
                    s
                }
                static if (signed == true)
                    enum sgn = Sgn.s;
                else static if (signed == false)
                    enum sgn = Sgn.z;
                static if (arg.sizeof * 8 < bits)
                    __ir!(format!"
                    %%a = %3$sext i%2$s %%1 to i%1$s
                    %%cast0 = bitcast i8* %%0 to i%1$s*
                    store i%1$s %%a, i%1$s* %%cast0
                    "(bits, T.sizeof * 8, sgn), void, const(void*), T)(store.ptr, arg);
                else static if (arg.sizeof * 8 > bits)
                    __ir!(format!"
                    %%a = trunc i%2$s %%1 to i%1$s
                    %%cast0 = bitcast i8* %%0 to i%1$s*
                    store i%1$s %%a, i%1$s* %%cast0
                    "(bits, T.sizeof * 8), void, const(void*), T)(store.ptr, arg);
                else static if (arg.sizeof * 8 == bits)
                    __ir!(format!"
                    %%cast0 = bitcast i8* %%0 to i%1$s*
                    store i%2$s %%1, i%1$s* %%cast0
                    "(bits, T.sizeof * 8), void, const(void*), T)(store.ptr, arg);
            }
        }
        else
        {
            Unqual!(typeof(arg)) tmp = arg;
            import std.algorithm.comparison : stdmin = min;
            tmp &= bitMask!(stdmin(bits, ulong.sizeof * 8), 0);
            store[0] = cast(StoreType)tmp;
        }
    }

    this(const(char)[] arg)
    {
        require(!arg.empty);
        int sign;
        if (arg[0] == '-')
        {
            arg = arg[1 .. $];
            sign = -1;
        }
        else
            sign = 1;
        require(sign == -1 && signed == true || sign == 1);

        foreach_reverse (i, dec; arg[])
        {
            ubyte digit = cast(ubyte)(dec - '0');
            auto extended = typeof(this)(digit);
            foreach (n; 0 .. arg[].length - i)
                extended *= typeof(this)(10);
            this += extended;
        }
    }

    void toString(W)(W w) const
    {
        import std.format;
        Unqual!(typeof(this)) tmp = this;
        static if (signed == true)
            if (tmp < typeof(this)(0))
                w.formattedWrite!"-";
        Unqual!(typeof(this)) divisor = max10e;
        bool print = false;
        while (divisor != typeof(this)(0))
        {
            import std.math : abs;
            auto quot = (tmp / divisor);
            tmp -= divisor * quot;
            static if (bits <= 3 && signed == false || bits <= 4 && signed == true)
                divisor = typeof(this)(0);
            else
                divisor /= typeof(this)(10);
            if (quot != typeof(this)(0) || divisor == typeof(this)(1))
                print = true;
            if (print)
                w.formattedWrite!"%s"(abs(cast(byte)quot));
        }
    }

    static typeof(this) max()
    {
        static if (signed == false)
            return typeof(this)(0) - typeof(this)(1);
        else static if (signed == true)
            return typeof(this)(-1) >>> typeof(this)(1);
    }

    static typeof(this) min()
    {
        static if (signed == false)
            return typeof(this)(0);
        else static if (signed == true)
            return ~max;
    }

    private static typeof(this) max10e()
    {
        static if (bits <= 3 && signed == false || bits <= 4 && signed == true)
            return typeof(this)(1);

        auto tmp = Unqual!(typeof(this))(1);
        while ((max / tmp) > typeof(this)(9))
        {
            tmp *= typeof(this)(10);
        }
        return tmp;
    }
}
unittest
{
    /+assert(ArbInt!8("256") == ArbInt!8(0));
    assert(ArbInt!8(256) == ArbInt!8("512"));
    assert(ArbInt!9(256) + ArbInt!9(1) == ArbInt!9(257));

    static foreach (i; 1 .. 5)
    {{
        enum w = 9 ^^ i;
        enum a = ArbInt!w(3) * ArbInt!w(4);
        auto b = ArbInt!w(4) * ArbInt!w(3);
        assert(a == b);
        assert(a == ArbInt!w(12));

        enum c = ArbInt!(w, true)(3) * ArbInt!(w, true)(4);
        auto d = ArbInt!(w, true)(4) * ArbInt!(w, true)(3);
        assert(c == d);
        assert(c == ArbInt!(w, true)(12));
    }}
    static foreach (i; 1 .. 3)
    {{
        enum w = 9 ^^ i;

        enum a = ArbInt!(w, true)("255")
            * ArbInt!(w, true)("254");
        auto b = ArbInt!(w, true)("254")
            * ArbInt!(w, true)("255");
        import std.stdio;
        writeln(a);
        writeln(b);
        assert(a == b);
    }}+/
}
