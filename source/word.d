/+--------------------Copyright Notice------------------------+\
|      Copyright:                                              |
|  - AsumFace (asumface@gmail.com) 2019                        |
|  Distributed under the Boost Software License, Version 1.0.  |
|  See accompanying file LICENSE or copy at                    |
|      https://www.boost.org/LICENSE_1_0.txt                   |
\+------------------------------------------------------------+/

module word;

import required;
import std.meta : AliasSeq;
import std.traits;

private uint ceilLog2(ulong num) pure @safe
{
    require(num != 0);
    ulong n = 0b1; // set LSb
    uint bitCount;
    while (n < num && n != 0) // shift bit one over until the mininimum neccessary to represent base num is found
    {
        bitCount += 1;
        n <<= 1;
    }
    return bitCount;
}

private template bitsNeeded(ulong num)
{
    static if (num == 0)
        enum bitsNeeded = 0;
    static if (num == ulong.max)
        enum bitsNeeded = ulong.sizeof * 8;
    else
        enum bitsNeeded = ceilLog2(num + 1);
}

private alias StoreTypes = AliasSeq!(ubyte, ushort, uint, ulong); // shall be sorted short to large!

private ulong ceilDiv(ulong a, ulong b) pure @safe
{
    ulong result = a / b;
    if (a % b != 0)
        result += 1;
    return result;
}


private T fillBits(T)(uint num) pure @safe
{
    T result;
    foreach (i; 0 .. num)
    {
        result |= 1uL << i;
    }
    return result;
}

ulong bitMask(uint num, uint shift) pure @safe
{
    require((num + shift) <= (ulong.sizeof * 8));
    return fillBits!ulong(num) << shift;
}

template bitMask(uint num, uint shift)
    if ((num + shift) <= (StoreTypes[$ - 1].sizeof * 8))
{
    static foreach (T; StoreTypes[])
    {
        static if ((num + shift) <= (T.sizeof * 8) && !is(MaskType))
        {
            alias MaskType = T;
        }
    }
    enum MaskType bitMask = fillBits!MaskType(num) << shift;
}

struct WrappingDigit(ulong B = 1)
{
    @safe:
    enum max = B;
    enum min = 0uL;
    static if (B == 0)
        alias StoreType = ubyte[0];
    else
    {
        static foreach (T; StoreTypes[])
        {
            static if (bitsNeeded!B <= (T.sizeof * 8) && !is(StoreType))
                alias StoreType = T;
        }
    }
    private StoreType store;

    ref typeof(this) opBinaryAssign(string op, T)(T rhs)
        if (isIntegral!T)
    {
        typeof(this) tmp = rhs;
        return opBinaryAssign!op(tmp);
    }

    ref typeof(this) opBinaryAssign(string op)(const(typeof(this)) rhs)
        if (B == 1 && (op == "&" || op == "|")
            || op == "+" || op == "-")
    {
        static if (op == "&" || op == "|")
        {
            mixin("store " ~ op ~ "= rhs.store;");
        }
        else static if (truncPow2(B + 1) == B + 1)
            // we can exploit the internal representation for wrapping
        {
            mixin("store " ~ op ~ "= rhs.store;");
            store &= bitMask!(bitsNeeded!B, 0);
        }
        else if (op == "+")
        {
            immutable oldStore = store;
            store += rhs.store;
            if (store > B || store < oldStore)
                store -= (B + 1);
        }
        else if (op == "-")
        {
            immutable oldStore = store;
            store -= rhs.store;
            if (store > B || store > oldStore)
                store += (B + 1);
        }
        return this;
    }

    this(T)(T arg)
        if (isIntegral!T)
    {
        this.opAssign(arg);
    }

    ref typeof(this) opAssign(T)(const(T) rhs)
        if (isIntegral!T || is(T : typeof(this)))
    {
        static if (isIntegral!T)
        {
            require(rhs <= B);
            store = cast(StoreType)rhs;
        }
        else
            store = rhs.store;
        return this;
    }

    ref typeof(this) opUnary(string op)()
        if (op == "++" || op == "--")
    {
        static if (op == "+")
            this += 1;
        else static if (op == "-")
            this -= 1;
        return this;
    }

    typeof(this) opUnary(string op)() const
        if (op == "+" || op == "-" || op == "~" && B == 1)
    {
        typeof(this) result = this;
        static if (op == "+")
            return result;
        static if (B == 1 && op == "~" || op == "-")
        {
            result.store = B - store;
            return result;
        }
    }

    void toString(W)(W w) const
    {
        import std.format;
        w.formattedWrite!"%s"(store);
    }

    int opCmp(const(typeof(this)) rhs) const
    {
        if (store < rhs.store)
            return -1;
        else if (store > rhs.store)
            return 1;
        else
            return 0;
    }
}

struct Word(ulong N, ulong B = 1)
    if (B != 0)
{
    @safe:
    private:
    static if (B == 0)
        ubyte[0] store;
    else
    {
        import std.algorithm.comparison : min;
        enum totalSize = bitsNeeded!B * N; // total payload bits
        enum digitsPerAlign = min(totalSize, ulong.sizeof * 8) / bitsNeeded!B; // max digits per aligned segment
        enum fittedSize = digitsPerAlign * bitsNeeded!B; // max payload bits per aligned segment
        static foreach (T; StoreTypes[])
        {
            static if (fittedSize <= (T.sizeof * 8) && !is(StoreAlignType))
            {
                alias StoreAlignType = T;
            }
        }
        StoreAlignType[ceilDiv(totalSize, fittedSize)] store;

        alias DigitType = WrappingDigit!B;

        public:

        DigitType opIndex(ulong idx) const
        {
            require(idx < N);
            immutable segment = idx / digitsPerAlign;
            immutable subSegment = idx % digitsPerAlign;

            DigitType result = (store[segment] >> (subSegment * bitsNeeded!B)) & bitMask!(bitsNeeded!B, 0);
            return result;
        }

        DigitType opIndexAssign(T)(T value, ulong idx)
        {
            return opIndexAssign(DigitType(value), idx);
        }

        DigitType opIndexAssign(DigitType value, ulong idx)
        {
            require(value.store <= B);
            require(idx < N);
            immutable segment = idx / digitsPerAlign;
            immutable subSegment = idx % digitsPerAlign;

            import std.stdio;
            import std.format;
            import std.range;
            import std.algorithm;

            auto tmp = store[segment];
            tmp &= ~bitMask(bitsNeeded!B, bitsNeeded!B * subSegment);
            tmp |= cast(StoreAlignType)value.store << (bitsNeeded!B * subSegment);
            store[segment] = tmp;

            //StoreAlignType ss;
            //ss = tmp;
            //import std.utf;
            //auto rstring = format!"%0*b"(StoreAlignType.sizeof * 8, ss).dup.reverse;
            //auto cnks = rstring.byCodeUnit.chunks(bitsNeeded!B).map!(n => n.byCodeUnit.array).array.reverse;
            //foreach (ref n; cnks)
            //    n.reverse;
            //writefln("%s %s %(%(%c%)|%) %08b %s", segment, subSegment, cnks, value.store, value);
            return value;
        }

        typeof(this) opBinaryAssign(string op)(typeof(this) rhs)
            if (B == 1 && (op == "&" || op == "|")
                || op == "+" || op == "-")
        {
            foreach (i; 0 .. N)
            {
                mixin("this[i] = this[i] " ~ op ~ " rhs[i]");
            }
            return this;
        }

        typeof(this) opBinary(string op)(typeof(this) rhs) const
            if (B == 1 && (op == "&" || op == "|")
                || op == "+" || op == "-")
        {
            typeof(this) result = this;
            mixin("result " ~ op ~ "= rhs;");
            return result;
        }

        typeof(this) opUnary(string op)() const
        {
            static if (op == "~" || op == "-")
            {
                import std.math : truncPow2;
                static if (truncPow(B + 1) == (B + 1)) // we can exploit the internal representation
                {
                    foreach (ref s; store[])
                        s = ~s; // simply invert all bits, including padding
                }
                else
                {
                    foreach (i; 0 .. N)
                        this[i] = -this[i];
                }
            }
        }
    }
    void toString(W)(W w)
    {
        import std.format;
        w.formattedWrite!"[";
        foreach (i; 0 .. N - 1)
            w.formattedWrite!"%s, "(this[i]);
        w.formattedWrite!"%s]"(this[N - 1]);
    }
}
unittest
{
    import std.stdio;

    enum prime = 1609587929392839161uL;
    static foreach (i; 1 .. 90)
    {{
        Word!(8, i) a;
        foreach (e; 0 .. 8)
        {
            immutable val = (prime * (e + 1)) % (i + 1);
            a[e] = val;
            assert(a[e] == a.DigitType(val));
        }
    }}
    static foreach (i; 1 .. 90)
    {
        static foreach (T; AliasSeq!(
            Word!(i, 500),
            Word!(i, ubyte.max),
            Word!(i, uint.max),
            Word!(i, uint.max - 7uL),
            Word!(i, ulong.max - 13uL),
            Word!(i, ulong.max))[])
        {{
            T s;
            foreach (e; 0 .. i)
            {
                immutable val = (prime * (e + 1)) % s.DigitType.max;
                s[e] = val;
            }
            foreach (e; 0 .. i)
            {
                immutable val = (prime * (e + 1)) % s.DigitType.max;
                assert(s[e] == s.DigitType(val));
            }
        }}
    }
}
