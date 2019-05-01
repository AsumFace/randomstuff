module xxhash;
import required;
import std.array : empty;
private static immutable uint[] primes32 = [2654435761u, 2246822519u, 3266489917u, 668265263u, 374761393u];
private static immutable ulong[] primes64 =
    [11400714785074694791uL, 14029467366897019727uL, 1609587929392839161uL, 9650029242287828579uL, 2870177450012600261uL];

private auto readLE(T)(const(ubyte[]) arg)
    if (is(T == uint) || is(T == ulong))
{
    require(arg.length == T.sizeof);
    T result = *cast(T*)(arg.ptr);
    version(BigEndian)
    {
        import std.bitmanip : swapEndian;
        result.swapEndian;
    }
    return result;
}

auto xxHash(int type, ST)(const(ubyte[]) input, ST _seed = 0)
    if (type == 32 || type == 64)
{
    import core.bitop : rol;
    static if (type == 32)
    {
        alias primes = primes32;
        enum stripeLength = 16u;
        enum laneLength = 4u;
        alias AccType = uint;
        AccType seed = _seed;

        static AccType round(AccType acc, AccType lane)
        {
            acc += lane * primes[1];
            acc = acc.rol!13;
            acc *= primes[0];
            return acc;
        }

        static AccType finalize(AccType acc)
        {
            acc ^= acc >> 15;
            acc *= primes[1];
            acc ^= acc >> 13;
            acc *= primes[2];
            acc ^= acc >> 16;
            return acc;
        }
    }
    else static if (type == 64)
    {
        alias primes = primes64;
        enum stripeLength = 32u;
        enum laneLength = 8u;
        alias AccType = ulong;
        AccType seed = _seed;

        static AccType round(AccType acc, AccType lane)
        {
            acc += lane * primes[1];
            acc = acc.rol!31;
            acc *= primes[0];
            return acc;
        }

        static AccType finalize(AccType acc)
        {
            acc ^= acc >> 33;
            acc *= primes[1];
            acc ^= acc >> 29;
            acc *= primes[2];
            acc ^= acc >> 32;
            return acc;
        }
    }


    AccType tacc;
    import std.range : chunks, enumerate;
    auto stripes = input[].chunks(stripeLength);
    if (input.length >= stripeLength)
    {
        AccType[4] acc;
        acc[0] = seed + primes[0] + primes[1];
        acc[1] = seed + primes[1];
        acc[2] = seed;
        acc[3] = seed - primes[0];

        import std.algorithm.iteration : map;
        /+for (; !stripes.empty && stripes.front.length == stripeLength; stripes.popFront)
        {
            import std.stdio;
            foreach (i, lane; stripes.front[0 .. stripeLength].chunks(laneLength).map!(n => readLE!AccType(n[0 .. laneLength])).enumerate)
            {
                writeln(lane);
                acc[i] = round(acc[i], lane);
            }
            writeln("-");
        }+/
        while (!stripes.empty)
        {
            if (stripes.front.length < stripeLength)
                break;
            require(stripes.front.length == stripeLength);
            acc[0] = round(acc[0], stripes.front[0 .. laneLength].readLE!AccType);
            acc[1] = round(acc[1], stripes.front[laneLength .. laneLength * 2].readLE!AccType);
            acc[2] = round(acc[2], stripes.front[laneLength * 2 .. laneLength * 3].readLE!AccType);
            acc[3] = round(acc[3], stripes.front[laneLength * 3 .. laneLength * 4].readLE!AccType);
            stripes.popFront;
        }

        tacc = (acc[0].rol!1) + (acc[1].rol!7) + (acc[2].rol!12) + (acc[3].rol!18);
        static if (type == 64)
        {
            static AccType mergeAcc(AccType tacc, AccType acc)
            {
                tacc ^= round(0, acc);
                tacc *= primes[0];
                return tacc + primes[3];
            }
            foreach (a; acc[])
            {
                tacc = mergeAcc(tacc, a);
            }
        }
    }
    else
    {
        tacc = seed + primes[4];
    }
    tacc += cast(AccType)input.length;

    if (!stripes.empty)
    {
        require(stripes.front.length < stripeLength);
        foreach (cnk; stripes.front.chunks(laneLength))
        {
            static if (type == 32)
            {
                if (cnk.length >= laneLength)
                {
                    import std.stdio;
                    uint lane = readLE!uint(cnk[0 .. laneLength]);
                    writefln!"%(%x, %); %(%x, %)"(cnk[], *cast(ubyte[4]*)&lane);
                    tacc += lane * primes[2];
                    tacc = (tacc.rol!17) * primes[3];
                    cnk = cnk[4 .. $];
                }
                if (!cnk.empty)
                {
                    require(cnk.length != 0 && cnk.length < laneLength);
                    foreach (bt; cnk[])
                    {
                        tacc += bt * primes[4];
                        tacc = (tacc.rol!11) * primes[0];
                    }
                }
            }
            else static if (type == 64)
            {

                if (cnk.length >= laneLength)
                {
                    ulong lane = readLE!ulong(cnk[0 .. laneLength]);
                    tacc ^= round(0, lane);
                    tacc = (tacc.rol!27) * primes[0];
                    tacc += primes[3];
                    cnk = cnk[8 .. $];
                }
                if (cnk.length >= 4)
                {
                    ulong lane = readLE!uint(cnk[0 .. 4]);
                    tacc ^= lane * primes[0];
                    tacc = (tacc.rol!23) * primes[1];
                    tacc += primes[2];
                    cnk = cnk[4 .. $];
                }
                if (!cnk.empty)
                {
                    require(cnk.length != 0 && cnk.length < 4);
                    foreach (bt; cnk[])
                    {
                        tacc ^= bt * primes[4];
                        tacc = (tacc.rol!11) * primes[0];
                    }
                }
            }
        }

    }
    tacc = finalize(tacc);
    return tacc;
}
