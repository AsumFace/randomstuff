/+--------------------Copyright Notice------------------------+\
|      Copyright:                                              |
|  - AsumFace (asumface@gmail.com) 2019                        |
|  Distributed under the Boost Software License, Version 1.0.  |
|  See accompanying file LICENSE or copy at                    |
|      https://www.boost.org/LICENSE_1_0.txt                   |
\+------------------------------------------------------------+/

module fnv;

import required;

auto fnvHash(T, string vers = "1a")(const(ubyte)[][] input...) @safe
    if ((is(T == uint) || is(T == ulong)))
{
    static if (is(T == uint))
    {
        enum uint offsetBasis = 2166136261;
        enum uint prime = 16777619;
        uint result;
    }
    static if (is(T == ulong))
    {
        enum ulong offsetBasis = 14695981039346656037uL;
        enum ulong prime = 1099511628211uL;
        ulong result;
    }

    static if (vers == "0")
        result = 0;
    else
        result = offsetBasis;
    foreach (arr; input[])
    {
        foreach (b; arr[])
        {
            static if (vers == "1" || vers == "0")
            {
                result *= prime;
                result ^= b;
            }
            else static if (vers == "1a")
            {
                result ^= b;
                result *= prime;
            }
        }
    }
    return result;
}
