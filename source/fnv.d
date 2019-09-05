/+--------------------Copyright Notice------------------------+\
|      Copyright:                                              |
|  - AsumFace (asumface@gmail.com) 2019                        |
|  Distributed under the Boost Software License, Version 1.0.  |
|  See accompanying file LICENSE or copy at                    |
|      https://www.boost.org/LICENSE_1_0.txt                   |
\+------------------------------------------------------------+/

/++
This module implements all common FNV hash function for all hash lengths.
+/

module fnvhash;

import required;
import arbint;

auto fnv(T)(const(ubyte)[][] input...) @safe
    if (is(T == bool) || is(T == ubyte) || is(T == ushort) || is(T == uint) || is(T == ulong))
{
    static if (is(T == bool))
        return cast(bool)fnv!1(input);
    else
        return cast(T)fnv!(T.sizeof * 8)(input);
}

auto fnv(uint bits, string vers = "1a")(const(ubyte)[][] input...) @safe
    if (bits > 0 && bits <= 1024)
{
    import std.math : nextPow2, isPowerOf2;
    static if (bits.isPowerOf2)
        enum baseWidth = bits;
    else
    {
        static if (bits < 32)
            enum baseWidth = 32;
        else
            enum baseWidth = bits.nextPow2;
    }
    static if (baseWidth == 32)
    {
        // we of course don't need to use ArbInt here, but we still do for the sake of a uniform API
        enum offsetBasis = ArbInt!32("2166136261");
        enum prime = ArbInt!32("16777619");
    }
    else static if (baseWidth == 64)
    {
        enum offsetBasis = ArbInt!64("14695981039346656037");
        enum prime = ArbInt!64("1099511628211");
    }
    else static if (baseWidth == 128)
    {
        enum offsetBasis = ArbInt!128("309485009821345068724781371");
        enum prime = ArbInt!128("144066263297769815596495629667062367629");
    }
    else static if (baseWidth == 256)
    {
        enum offsetBasis = ArbInt!256("374144419156711147060143317175368453031918731002211");
        enum prime = ArbInt!256("100029257958052580907070968620625704837092796014241193945225284501741471925557");
    }
    else static if (baseWidth == 512)
    {
        enum offsetBasis = ArbInt!512("9659303129496669498009435400716310466090418745672637896108374329434462657994582932197716438449813051892206539805784495328239340083876191928701583869517785");
        enum prime = ArbInt!512("35835915874844867368919076489095108449946327955754392558399825615420669938882575126094039892345713852759");
    }
    else static if (baseWidth == 1024)
    {
        enum offsetBasis = ArbInt!1024("14197795064947621068722070641403218320880622795441933960878474914617582723252296732303717722150864096521202355549365628174669108571814760471015076148029755969804077320157692458563003215304957150157403644460363550505412711285966361610267868082893823963790439336411086884584107735010676915");
        enum prime = ArbInt!1024("5016456510113118655434598811035278955030765345404790744303017523831112055108147451509157692220295382716162651878526895249385292291816524375083746691371804094271873160484737966720260389217684476157468082573");
    }
    else
        static assert(0);
    ArbInt!baseWidth hash;

    static if (vers == "0")
        hash = 0;
    else
        hash = offsetBasis;
    foreach (arr; input[])
    {
        foreach (b; arr[])
        {
            static if (vers == "1" || vers == "0")
            {
                hash *= prime;
                hash ^= ArbInt!baseWidth(b);
            }
            else static if (vers == "1a")
            {
                hash ^= ArbInt!baseWidth(b);
                hash *= prime;
            }
        }
    }
    static if (baseWidth != bits) // we'll need to apply the special width reduction
    {
        static if (bits >= 16)
            ArbInt!bits result = cast(ArbInt!bits)((hash >> bits) ^ (hash & bitMask!(bits,0)));
        else
            ArbInt!bits result =
                cast(ArbInt!bits)(((hash >> ArbInt!baseWidth(bits)) ^ hash)
                & ArbInt!baseWidth(bitMask!(bits,0)));
    }
    else
        ArbInt!bits result = hash;

    return result;
}
