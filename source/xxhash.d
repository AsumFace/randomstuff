/+--------------------Copyright Notice------------------------+\
|      Copyright:                                              |
|  - AsumFace (asumface@gmail.com) 2019                        |
|  Distributed under the Boost Software License, Version 1.0.  |
|  See accompanying file LICENSE or copy at                    |
|      https://www.boost.org/LICENSE_1_0.txt                   |
\+------------------------------------------------------------+/

module xxhash;
import std.array : empty;
private static immutable uint[] primes32 = [2654435761u, 2246822519u, 3266489917u, 668265263u, 374761393u];
private static immutable ulong[] primes64 =
    [11400714785074694791uL, 14029467366897019727uL, 1609587929392839161uL, 9650029242287828579uL, 2870177450012600261uL];

private auto readLE(T)(const(ubyte[]) arg) pure @trusted
    if (is(T == uint) || is(T == ulong))
{
    assert(arg.length == T.sizeof);
    T result = *cast(T*)(&arg[0]);
    version(BigEndian)
    {
        import std.bitmanip : swapEndian;
        result.swapEndian;
    }
    return result;
}

auto xxHash(int type, ST)(const(ubyte[]) input, ST _seed = 0) pure @safe
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
        for (; !stripes.empty && stripes.front.length == stripeLength; stripes.popFront)
        {
            import std.stdio;
            foreach (i, lane; stripes.front[0 .. stripeLength].chunks(laneLength).map!(n => readLE!AccType(n[0 .. laneLength])).enumerate)
            {
                acc[i] = round(acc[i], lane);
            }
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
        assert(stripes.front.length < stripeLength);
        foreach (cnk; stripes.front.chunks(laneLength))
        {
            static if (type == 32)
            {
                if (cnk.length >= laneLength)
                {
                    uint lane = readLE!uint(cnk[0 .. laneLength]);
                    tacc += lane * primes[2];
                    tacc = (tacc.rol!17) * primes[3];
                    cnk = cnk[4 .. $];
                }
                if (!cnk.empty)
                {
                    assert(cnk.length != 0 && cnk.length < laneLength);
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
                    assert(cnk.length != 0 && cnk.length < 4);
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

unittest
{
    static immutable ubyte[] randomBlob = [
        101, 60, 234, 42, 251, 44, 213, 241, 233, 104, 91, 38, 28, 161, 163, 126, 211, 128, 175, 24, 143, 45, 42, 250,
        80, 139, 55, 234, 79, 120, 198, 175, 147, 181, 96, 115, 28, 173, 159, 239, 83, 248, 202, 8, 230, 22, 142, 173,
        75, 120, 70, 163, 195, 21, 191, 26, 71, 98, 67, 220, 108, 165, 227, 16, 55, 54, 29, 199, 65, 115, 123, 197, 212,
        56, 63, 153, 153, 184, 99, 108, 206, 33, 33, 49, 217, 73, 203, 233, 227, 203, 103, 148, 254, 236, 221, 76, 41,
        220, 212, 210, 118, 91, 159, 191, 14, 164, 48, 90, 101, 222, 11, 52, 97, 155, 207, 119, 213, 148, 151, 129, 37,
        89, 197, 12, 172, 101, 206, 249, 92, 52, 174, 102, 3, 193, 90, 141, 102, 126, 171, 242, 3, 116, 23, 137, 35,
        101, 176, 144, 127, 151, 88, 56, 108, 31, 222, 98, 77, 14, 21, 72, 61, 28, 106, 82, 194, 242, 61, 34, 233, 209,
        242, 203, 19, 216, 26, 144, 216, 18, 75, 198, 26, 107, 66, 163, 171, 9, 151, 112, 206, 102, 171, 178, 253, 168,
        94, 79, 67, 188, 230, 119, 204, 91, 79, 245, 173, 204, 3, 222, 214, 202, 91, 204, 81, 216, 161, 37, 98, 67, 139,
        9, 139, 251, 76, 123, 13, 215, 238, 142, 64, 194, 98, 183, 106, 63, 71, 45, 244, 81, 25, 61, 136, 111, 223, 72,
        247, 201, 144, 71, 235, 52, 104, 150, 147, 17, 131, 217, 40, 214, 138, 60, 184, 125, 144, 116, 146, 132, 12,
        170, 124, 181, 144, 228, 253, 48, 54, 54, 137, 186, 180, 126, 170, 22, 21, 43, 110, 77, 216, 180, 125, 179, 168,
        223, 251, 101, 65, 54, 73, 114, 52, 86, 167, 249, 60, 167, 162, 196, 184, 132, 102, 79, 38, 215, 143, 22, 130,
        117, 238, 15, 189, 176, 39, 246, 53, 37, 172, 16, 91, 59, 8, 51, 131, 158, 83, 163, 159, 173, 223, 235, 208, 19,
        58, 196, 166, 217, 171, 104, 91, 15, 101, 233, 44, 237, 76, 185, 191, 181, 124, 119, 181, 121, 115, 4, 132, 176,
        73, 152, 53, 187, 164, 108, 249, 71, 102, 220, 123, 229, 41, 184, 237, 107, 136, 54, 226, 90, 156, 156, 80, 118,
        221, 215, 16, 237, 230, 57, 99, 162, 132, 83, 36, 180, 240, 143, 2, 80, 3, 12, 55, 8, 49, 236, 6, 241, 3, 24,
        171, 151, 156, 248, 58, 30, 135, 161, 60, 247, 189, 171, 113, 69, 55, 54, 130, 71, 215, 244, 189, 40, 91, 17,
        157, 239, 228, 52, 62, 143, 7, 11, 242, 122, 161, 83, 223, 187, 250, 135, 169, 180, 246, 254, 79, 90, 9, 46,
        148, 131, 183, 181, 243, 63, 109, 19, 89, 201, 167, 5, 46, 207, 45, 202, 42, 102, 60, 96, 110, 138, 243, 141,
        106, 121, 211, 89, 233, 168, 134, 66, 255, 194, 243, 138, 224, 27, 16, 138, 85, 144, 128, 141, 138, 109, 160,
        104, 40, 64, 224, 133, 230, 76, 184, 244, 25, 13, 139, 110, 201, 136, 19, 129, 4, 152, 175, 175, 157, 249, 106,
        14, 153, 155, 128, 58, 208, 112, 85, 184, 102, 224, 143, 31, 167, 217, 168, 166, 186, 195, 161, 243, 50, 106,
        157, 92, 42, 113, 1, 103, 25, 138, 228, 175, 97, 248, 55, 196, 176, 187, 182, 3, 40, 24, 83, 128, 71, 121, 110,
        185, 161, 171, 42, 118, 213, 27, 250, 252, 183, 189, 35, 14, 16, 57, 123, 63, 72, 249, 100, 46, 99, 62, 97, 134,
        24, 139, 176, 15, 135, 50, 172, 112, 184, 136, 67, 0, 147, 93, 95, 96, 35, 220, 58, 113, 168, 123, 254, 72, 173,
        213, 73, 36, 201, 8, 133, 66, 14, 172, 9, 180, 77, 227, 135, 66, 27, 241, 204, 45, 253, 205, 92, 222, 227, 32,
        252, 2, 114, 251, 24, 5, 222, 99, 128, 246, 70, 151, 98, 177, 82, 146, 72, 149, 20, 237, 34, 47, 77, 2, 83, 37,
        22, 143, 18, 152, 140, 173, 91, 30, 232, 217, 33, 0, 136, 154, 90, 232, 115, 109, 129, 38, 65, 137, 154, 128,
        129, 234, 130, 211, 39, 13, 125, 33, 228, 193, 228, 77, 213, 118, 147, 1, 85, 227, 90, 177, 231, 247, 109, 84,
        253, 23, 4, 113, 97, 173, 136, 167, 38, 238, 244, 246, 133, 106, 237, 129, 235, 225, 7, 249, 20, 253, 68, 223,
        238, 237, 254, 47, 182, 22, 249, 16, 89, 103, 86, 36, 221, 57, 201, 86, 246, 35, 51, 41, 67, 33, 113, 196, 118,
        33, 106, 67, 161, 203, 80, 62, 18, 130, 9, 124, 46, 119, 100, 34, 20, 186, 174, 150, 95, 25, 239, 47, 75, 23,
        117, 88, 201, 6, 89, 241, 234, 176, 201, 136, 163, 187, 149, 185, 200, 61, 26, 238, 38, 3, 190, 162, 193, 130,
        82, 185, 28, 181, 175, 51, 203, 238, 186, 214, 162, 28, 97, 171, 202, 165, 50, 202, 108, 30, 76, 27, 96, 234,
        98, 46, 51, 250, 69, 150, 123, 115, 180, 75, 170, 123, 164, 50, 169, 191, 99, 68, 175, 28, 66, 68, 28, 242, 147,
        21, 252, 29, 11, 14, 184, 9, 229, 206, 14, 113, 169, 26, 91, 84, 121, 120, 54, 200, 180, 18, 91, 183, 125, 1,
        200, 252, 245, 68, 172, 126, 209, 243, 98, 122, 26, 143, 82, 171, 77, 70, 133, 182, 148, 119, 30, 77, 24, 219,
        212, 185, 11, 178, 206, 142, 196, 144, 21, 173, 237, 214, 127, 39, 121, 9, 132, 175, 231, 189, 38, 233, 76, 109,
        48, 197, 176, 24, 106, 184, 223, 179, 213, 49, 45, 108, 199, 211, 204, 111, 142, 215, 96, 116, 161, 188, 251,
        166, 245, 213, 86, 194, 164, 248, 236, 191, 176, 26, 54, 179, 160, 83, 37, 250, 103, 7, 147, 41, 241, 195, 28,
        177, 244, 214, 130, 89, 115, 234, 38, 125, 34, 75, 58, 205, 72, 43, 199, 197, 219, 139, 95, 92, 247, 160, 24,
        154, 118, 14];

    static immutable uint[] reference32 = [
        0xf95ad1c7, 0x11202a3f, 0x98e7670f, 0x917ba135, 0x61ac1916, 0x8091ae79, 0x33ed387a, 0x0a49e0ef,
        0x5ed0a27f, 0x511f5168, 0xb6f3f1d1, 0xb551c67b, 0x73c2238c, 0xfd30282f, 0x870cae3a, 0x1e032a93,
        0x10b0ab00, 0x35e6797f, 0x17a73931, 0xa3be1e14, 0x9ebe3d61, 0x34531696, 0x94552e71, 0x9ca13cc2,
        0x8fe93543, 0xde5175b2, 0xed79da3a, 0x56aab884, 0xa62fb8d8, 0x53547964, 0xab750bfe, 0x8931eac5,
        0xfe22cdae, 0xa584fc1b, 0x0d8a3278, 0x7e5d4383, 0x6a5d569f, 0x066bbaa5, 0x7b0d49cf, 0xd7f49032,
        0x52db53f7, 0xd8335a65, 0x37ea8ad9, 0x093ecbf1, 0xbbe49e29, 0xc26a7733, 0xf9e21177, 0x9f4b98d6,
        0xc2ebffb4, 0x941bf103, 0x54d680aa, 0x51122ad6, 0x39d00ccb, 0x2a86a04d, 0x872600db, 0xb07bd124,
        0x7dce5654, 0xbae99bf6, 0x22f10baa, 0xfd265d82, 0x52e2cf7c, 0x38ee7872, 0x8129dee9, 0xcdf3ff34,
        0x4398361d, 0x5455ed95, 0x39468e13, 0x35e88e2c, 0x30fbdf77, 0xc05b314a, 0xcb042856, 0x503c3fc9,
        0xf0e474c6, 0xa4d384c8, 0x81a4e7fa, 0x75b825fc, 0x8a7bdf9b, 0x78f30be3, 0x86267fab, 0x03400a42,
        0x8d3ed728, 0xa091caf4, 0x5b1a4ab4, 0x16d487e1, 0xd29bf7bc, 0x2f0e7fc8, 0x7d3967a6, 0x43d00fcc,
        0x5702c152, 0xa5f1173c, 0x21f0c08e, 0x1004ed2d, 0xc55ef338, 0xfcb802ab, 0xbb126d9d, 0x487c10f9,
        0x782395b0, 0x8b5e2af4, 0xa3d4cee6, 0x975e2240, 0xb12af0ea, 0x9fc9b28e, 0x075754c7, 0xb2c201d9,
        0xd21a10fe, 0x4b8ebc1f, 0xe0473889, 0xc14d9d72, 0x2145ced5, 0xfaf9b447, 0x74ebb00e, 0x5d52d8e8,
        0x05a85929, 0x57050a55, 0x529f998c, 0x89cbe9a0, 0x57aff5cf, 0xd99475e6, 0x565f08b5, 0x0b7c5f9d,
        0xad40938c, 0x0670993a, 0xf8a35ac9, 0x35b961db, 0x9a62a174, 0x1060c9cf, 0xdf07a2e0, 0xa6b7ce34,
        0x77e009b2, 0x37f59d90, 0x1fd7e7fe, 0xb0d443a5, 0xed5dacea, 0xa30b91d3, 0x5d86b600, 0x76cdc2a5,
        0x480497b0, 0xd3cb2bc6, 0xf1cf8178, 0x9c9bb6ac, 0x0669e7bd, 0x5e427d42, 0x145cfb87, 0x39efd3f1,
        0xdb6a750c, 0x38ca39c5, 0x9dffc274, 0x9ffa2c94, 0xcf535cb8, 0xeba6a105, 0xb9dbdc6a, 0x4cea44dd,
        0x0327ba57, 0x14a9ce1d, 0xa7f2977f, 0x2686ee07, 0xc89f2a18, 0x07fe5273, 0xcd71580a, 0xcbfd1717,
        0x1be1df2e, 0xe8980966, 0x7afe5ff0, 0x5de4f510, 0x3a2693cb, 0x3b6af9df, 0x1e398116, 0xffcc1c22,
        0xcec4f968, 0x2d6942c6, 0x99aae5a5, 0x5e2eca4a, 0xce87ba82, 0xdabd9776, 0xc79abdfa, 0xb0ad002f,
        0x2572719c, 0xf19637b3, 0xc657093e, 0x08f4fe38, 0xdbc1fe87, 0xa7f5f31f, 0x104337f3, 0xf8645293,
        0xdd8f316f, 0x572eec83, 0xd58b533e, 0xf55d9042, 0x56688851, 0x0e24dd3b, 0xe3be4415, 0x03823503,
        0x210fab5f, 0xde7a5e88, 0x3d98e8dc, 0x17f957dc, 0xa7d06b37, 0x0d812f8a, 0x0081c434, 0x2f455196,
        0x44395dc3, 0x173c90e0, 0xec97bc2e, 0x69a6eb83, 0x2dc0ff37, 0x0f1cf9c3, 0x14dffeaa, 0xf4d73647,
        0x6170fa79, 0x12787feb, 0x80afb0cc, 0x5b4509f1, 0x6ca72508, 0xd7d914c5, 0xb71df2b5, 0x147a6272,
        0x13c4b0f2, 0xf7a6d036, 0x3b3c2c28, 0xbc61d820, 0x6da26fba, 0xcb274247, 0x8aa50c4d, 0x37519313,
        0xe36db44f, 0xb2ef4354, 0xfeec1cf0, 0x4b0f7953, 0x376893e5, 0x7c3eec75, 0x728def0b, 0x5d6fb0a4,
        0xd23b4b30, 0xbed98ac0, 0xb9c44ccc, 0x5b8fbdbf, 0x73015edc, 0x748d188d, 0xca19f4b9, 0xc9579f5c,
        0x591ed52c, 0x19a7aea8, 0xe4f95ed4, 0x862f0a94, 0xec1d98de, 0x160b1dd9, 0x27c41dde, 0x7682be60,
        0x8a34c7b8, 0x606545a0, 0x4c5fb0b0, 0xbfac2816, 0xd228f8c1, 0x3c464484, 0xce951fc9, 0x36404272,
        0x9dd854b3, 0x211be07b, 0x78e2c6e4, 0x1026cdb4, 0xe825fa31, 0xbf2d324c, 0x9878a88d, 0x56db896a,
        0x8b081180, 0x9b837b58, 0x2e5f827d, 0x064cf782, 0x9541c352, 0x0be9d5f3, 0xce58c56f, 0xa811b96f,
        0x1b484fa7, 0x3d24fce6, 0x63ffbf33, 0x06ccb785, 0x668c80cc, 0x15ddde4c, 0xde7d72ad, 0xebb37e00,
        0x9547b69a, 0xaac5024d, 0x3272ce11, 0x9801ee3a, 0xbe86182e, 0x2e3b437c, 0x4253da3e, 0x4f8ab6f4,
        0xffbeded9, 0x3f4056e3, 0x6820c77e, 0x9c49780e, 0x5e406ffc, 0x76106c63, 0xdeab0e3f, 0x9081e235,
        0x26a97f80, 0xd413147b, 0xe6d8e645, 0xe50ceda0, 0x73f7060a, 0xda4eaf7f, 0x0f6c28c6, 0xb3006e44,
        0x1f468023, 0x16dbd57d, 0x6d47cfc2, 0x671ee53e, 0x030c86c7, 0xa5c1162f, 0x74f23f54, 0xf2a80f0a,
        0x64fcd813, 0x07904bf3, 0x7eb6561f, 0xef3f7a47, 0x993f353f, 0x0c03cf33, 0xcb86c43f, 0x3a3be7cb,
        0x956984ab, 0xb3b9a5a8, 0xd56c80d9, 0x9cc9a8c5, 0xde87d9a6, 0x4553cc9b, 0x9e81f4f1, 0x224b464d,
        0x2ebc27ed, 0x49e4cd89, 0x6c6c2655, 0x876f8799, 0x9d26c05b, 0xd3f7ba6e, 0xca7bcc73, 0x15ed306a,
        0x4c58ecf9, 0xbd671bbf, 0x85f89472, 0x638f83c8, 0x66e73add, 0x9896cff0, 0x97f21381, 0x969dcb0f,
        0x74820e1b, 0x42e020ca, 0xdc6d870c, 0xf1070009, 0x3c472fe8, 0xf13b3a84, 0x1f83df88, 0x8dd649ad,
        0xf1a811de, 0x399d82bf, 0x9e2d590c, 0xfa252f9c, 0x9a5c8cb5, 0x186b1e25, 0x260e691b, 0xbe53f13d,
        0xcfe67ff0, 0xc42cf6d0, 0xb62275f6, 0xa5c7e7a6, 0x4d2444f4, 0x162b309c, 0xa785bc04, 0x44ed6c2b,
        0x0a03fe09, 0x51e0f205, 0xac9a7262, 0x7c7dcc9b, 0x7b05a871, 0x41f47c21, 0x4c4dafc3, 0x88b60ec7,
        0x213038e1, 0x4c52445a, 0x4115192f, 0x0bb042e4, 0xa010a573, 0xd697633e, 0x2910444f, 0x333616de,
        0x564c1e81, 0xca6f7e9f, 0x18157d18, 0x7d7116a7, 0x2cd39f80, 0x1124f736, 0x32aa9fda, 0x4ee3555b,
        0x33c4513e, 0x583f2ea3, 0x8289dee0, 0x92afe355, 0x68c1d25e, 0xe7719344, 0x1dae2eab, 0x18589234,
        0x0e13db24, 0x6e6f79dd, 0xbe726d56, 0x592a6c12, 0x452475ea, 0xa3b14836, 0xac78c00f, 0xaca9be71,
        0x9942fdd9, 0xfe532b1a, 0xf948fd08, 0x0419e61d, 0x499a261f, 0x546d44aa, 0xa70573d8, 0x63b28936,
        0x42e81696, 0x2c0a6e99, 0xbb0a5aef, 0x2f51c59c, 0x591e7c12, 0xfaeaf914, 0xba011a7e, 0xa3b05d2e,
        0xc179bce4, 0x3efb9b0f, 0x9b57bf1b, 0x606996d4, 0xa93e9f2a, 0xbfbe6974, 0x7dd5ced7, 0xd0cba5a2,
        0x460e8853, 0xef098872, 0x79591d32, 0xb47de166, 0x397712ec, 0x1ee92730, 0x0a8aab85, 0x61823f36,
        0x4875a5fc, 0x58be396a, 0x9395b81b, 0x876fb1c4, 0x9ecc1b3c, 0x17153a56, 0x3b0b4c96, 0x150508fc,
        0x5d352f78, 0x905e9143, 0xc490775a, 0x892c164c, 0xc69fe43c, 0x3c7638af, 0x6673bbb2, 0x065825cb,
        0xdfc8c371, 0xc553ea9e, 0xab39239b, 0xe42c2dae, 0x250c77f7, 0x465852ca, 0x62869a64, 0xd30404aa,
        0x8d207881, 0x39035800, 0x2e90e820, 0xa5cbe943, 0x2d403e1a, 0xf1947bff, 0x657a9d86, 0x3544ae86,
        0xf1f0aa06, 0x3f3332ad, 0x9684fd4b, 0x2ee92460, 0xb66e53bf, 0xac418375, 0xd6561d6b, 0x092dc346,
        0x76854dd9, 0x69675b5c, 0x0f0a2fdc, 0xa7de0f34, 0x1df5d0ac, 0x3c29fc93, 0x12074033, 0x126f5e1c,
        0x6a2ed6ba, 0x4f070a81, 0xa0166d58, 0x68631aa1, 0x4149f5ec, 0x858ed743, 0x1097f0da, 0x1ef82d0a,
        0x85d2a18c, 0xdac46ec0, 0xcb39f696, 0x8e5cbfd3, 0x6373ec56, 0xe345751b, 0xd3749bbf, 0x9c686252,
        0x27beba5e, 0xfa50a49d, 0x4392a188, 0xdbef047d, 0x4c66009a, 0xa16829d1, 0xb01b0af5, 0x3361c92c,
        0x5f3f0f93, 0x6a743024, 0xa014ff44, 0xc9f3a3f7, 0x067b066c, 0xa19a0663, 0x95ecb673, 0x9f1123e7,
        0xad6fa60e, 0xec2c4679, 0x24de66e6, 0xa178f44a, 0x88ea8d1a, 0x330693cd, 0x965c6c09, 0xbfcf68a3,
        0xc2f16122, 0x1fd43338, 0xf90b43d1, 0x04ae9be3, 0x3cca3340, 0xd6bb01df, 0x2ae75121, 0x3b3d3810,
        0x68dc3403, 0xe62e67b2, 0xb999fc22, 0x9b1ccd52, 0x42fa4838, 0xeef8abad, 0x391eba26, 0xa01feaa1,
        0x27249d5e, 0xbf7ddd62, 0xb88c1fe8, 0xf325c436, 0xab181851, 0x6281900b, 0x4bc6cff2, 0x76017aec,
        0x0fd1eecd, 0x1fd758b3, 0xd18261d5, 0xdc1a0ce0, 0x5ca464e7, 0x9f09540a, 0xd7f7ec8c, 0x4d5d8eb9,
        0xd26956d2, 0x329e4d43, 0x5e60c142, 0xc83cd182, 0x2ec61475, 0x606e58ff, 0x5519098d, 0x43740a44,
        0x901009b9, 0x9f4f0f64, 0x540e7ec1, 0x065dbffb, 0xb0c0b8d3, 0xe3c0bfd1, 0xa4f2a4c9, 0x4785ed52,
        0xed71e26f, 0xc39e2f02, 0x036db96a, 0x3c7a12c8, 0x7d6286cb, 0x975db1be, 0xaa9b22e0, 0x07d07bde,
        0x280a3d7e, 0x6526afe1, 0xe4c9bf72, 0xbb372f3d, 0x6922e4f4, 0x597a54bc, 0xa91949c8, 0x985143c4,
        0x47aae1fd, 0x9ddf55e5, 0xc8b542f0, 0xeb4c3573, 0x57b82877, 0x0e297f58, 0x79f4d64b, 0xc074ac1f,
        0x11cb901a, 0xb53bcab6, 0x6298f6ac, 0xc60b3d2b, 0x55b049cf, 0x48c28afe, 0x56e4c663, 0xc7146ca6,
        0x0ea2aee2, 0x1b410489, 0x06900d28, 0x3a1e64dc, 0x95a5fb0f, 0x0f9107c9, 0x038c3f9a, 0x60318d90,
        0x4df3d41d, 0xa8698c36, 0xb30b71ea, 0xa2e7b623, 0x975dc902, 0x39335016, 0x7ead2393, 0xa7b552e2,
        0xe0ff8595, 0xa418102c, 0x6cab6f41, 0xd163fba0, 0x29955705, 0x569f323d, 0x34d107b2, 0x378618b4,
        0x11d0a399, 0x7ac45370, 0x96ef1e47, 0xa375046a, 0x0d023cef, 0x4dd79c08, 0x6664c8fc, 0x361574e9,
        0xf4edcf7a, 0x6f50ae1c, 0x4f945dd0, 0xb8556bac, 0x1ce512af, 0xb5c35b50, 0xfe817ca5, 0x404d95a0,
        0x0a3b3409, 0x01c9d6c7, 0x41c66e43, 0xe773c4ce, 0xdacb8e94, 0x1988a647, 0xf6152637, 0xe4e673b6,
        0xde82a4c5, 0x9bfc274f, 0x7862aad1, 0x6e592097, 0x673f1b9e, 0x86dc08ad, 0x273d1b7e, 0x395c99d9,
        0xc13b67d1, 0x87028046, 0xa418d258, 0xe8d827ce, 0x7ace37b7, 0x8984db1a, 0x5f5f27d9, 0xc5cf8ee6,
        0xdc7df164, 0x5ff9d3ac, 0xb5d78d65, 0x15439add, 0x82f27fdb, 0x7823b67b, 0x14ecc2e0, 0xa25cfc15,
        0xbd378654, 0x0fe34184, 0x9b1a6b11, 0x64b5b610, 0x84a72bb5, 0x22978ea6, 0x30b36006, 0xca2dfcdf,
        0xfe949a0a, 0xfe6d7773, 0x9d3d535a, 0x15afc022, 0x5185cd06, 0xf653d402, 0x4f093166, 0x497d4978,
        0xb70a03c9, 0x2f66036e, 0xca1e7436, 0x8a206f65, 0x7cb85304, 0x11efcf94, 0x045cd16e, 0x0cb5eae5,
        0x87e012ac, 0xf22b0358, 0x365ee1c4, 0x6fcda4a7, 0x6852d069, 0x496b5530, 0x2a7db5fa, 0x89d820c0,
        0xb6518c80, 0x003c6727, 0xb57f817d, 0x60622a46, 0x84c0c211, 0xab9ca788, 0x302117e5, 0x66d54c5f,
        0x2e80ed9d, 0x331ca9cd, 0xb84c54f2, 0x03d55bfc, 0xbd568c7d, 0x97fc022c, 0xa89db068, 0x25fc2cc7,
        0x3c23b251, 0x93a0d8aa, 0x455a1725, 0xbaab838a, 0x8004103a, 0x0719cd1a, 0x4f22fb08, 0x7cb8777e,
        0xbfc1dd52, 0xa1e6640c, 0xe70ac59a, 0x20616547, 0xd64c47bf, 0x8034dc04, 0x48394171, 0xe1c05519,
        0x19e92c54, 0x17ab3a98, 0x22427f23, 0xffb2addf, 0x6e691768, 0x98e0f768, 0x9d01dcec, 0x2c461519,
        0xae31c9e9, 0xb56ac620, 0xf09bba91, 0x764b0d4a, 0xf485c630, 0xa207fa53, 0x46774359, 0xc02f4dbb,
        0xbc7c8ae2, 0xd29fa27a, 0x99fcc010, 0xb6848b5e, 0x374b98c5, 0x2b85b599, 0x33d11b0d, 0xc8d43fef,
        0xd0e6a984, 0xf2270a46, 0x4faea09d, 0x09c272d4, 0xe46380d8, 0xbb69748b, 0x47649201, 0x1a0829cc,
        0xcadf169b, 0xc8ac4c68, 0x2ec038b6, 0x6d4bb872, 0x0bf320cb, 0xdf6d80d3, 0x3e8c5e40, 0x2210092f,
        0xd40e76d8, 0x25cc5a4f, 0xfc2cffb9, 0x695856a7, 0x3b88c0e2, 0xfd0b87e0, 0x7796a018, 0x7f35a62c,
        0xc684cc80, 0x68f441fb, 0x3fec20c4, 0x6dfdc705, 0x5289a409, 0xe097513c, 0x4977d243, 0x3dd3242d,
        0x11552c48, 0x2ff4c55d, 0xbfebe9fe, 0x01b4564a, 0x3537462f, 0xd2566005, 0xf4e79539, 0x637c7dce,
        0x2336270e, 0xca12b9ea, 0xb46d906c, 0x4d9f5fd5, 0xc921675d, 0x8cf540a1, 0xd1542b14, 0x59fdc7be,
        0xce5cde45, 0x9e72f773, 0x45505a2f, 0xd78b8934, 0x2ccc44a9, 0x600ec44c, 0x65988021, 0xa432f3c5,
        0x3722b036, 0xe3eb21bd, 0x531a3011, 0xe3e7d1d2, 0x64f402a8, 0x293b4018, 0xe2bf0c06, 0x0e0914c1,
        0x22a2d9f1, 0xa38f7f17, 0xc5cebd09, 0xa572da31, 0xe81c01cf, 0x5d100eb8, 0xea02f8b1, 0xf71189b2,
        0xf1375973, 0xdc0edec7, 0x6ca64da2, 0xfaed629a, 0x535b50f1, 0x93037c06, 0x07a169a3, 0xf92aad01,
        0x43bc4724, 0x2b2ab43b, 0xeb5e7aaa, 0x31a1fba9, 0xa4212976, 0x6e0c09a1, 0x731bcd54, 0x36820621,
        0x0d2e483a, 0x670ec3f9, 0x1d7c12b4, 0xc0a02700, 0xcb8cdd11, 0xa8e78e82, 0x5e5d6f84, 0x70d2c7f6,
        0xc1a5c062, 0x938f909e, 0xb01817d4, 0xcf09f700, 0x711b126f, 0xc6c9da61, 0x4c4c9a13, 0xd4041fcd,
        0x4373375c, 0xd6a1dc24, 0xd9642a2b, 0xb873b3f9, 0x1db60f2c, 0x168226d1, 0x53a1dd7b, 0x41235578,
        0x142d420b, 0x25a3d856, 0xe0986c99, 0xe7c93512, 0x119fd1df, 0xe615701b, 0x0b22cdcf, 0x0fcd65db,
        0x53028d9d, 0x1d0a2717, 0x46ed3c09, 0xaba8b8f3, 0xa8aec512, 0x84a7b0fb, 0x68ce43a6, 0x55fb0b5d,
        0x41095385, 0xe14022ed, 0x1aa1be5a, 0x475ccdcb, 0x3ff031b9, 0x50ac7fcd, 0xd9f12545, 0x9c25960c,
        0xaa9b9140, 0x6e4167ea, 0xcd473909, 0x9f82d523, 0xa47ed8e2, 0xa8a1e18e, 0x0469acfe, 0xfc3321e1,
        0xb32fb932, 0xbdaab776, 0x4b005bfe, 0x02c9fd25, 0xea1b1ba2, 0x4c38c80a, 0x85384f1d, 0xa71b086e,
        0xeb3bce0c, 0xb070eec8, 0x3fd3c1cd, 0x90347b07, 0x57e0c8ce, 0x4119abd9, 0xf2f63ffa, 0xcfa8f28f,
        0xa7e242c4, 0x2b6e0e3d, 0x2e0cc70f, 0xd5779471, 0x6f125a4c, 0x5fd41cd1, 0xa6ec3fd1, 0x1cfe1da7,
        0xa9047a3b, 0x919a1d17, 0xc34433bc, 0x1424b2cd, 0x142395ef, 0xa7955516, 0x21ced87a, 0x3cc84319,
        0x6c8505de, 0x71b65540, 0x4fc2c1e6, 0x1a01a0ff, 0x8a67da74, 0xabeb8e22, 0xaed4fc06, 0x3874af87,
        0x8b3a0cdd, 0x1ac96c33, 0xe7b565bb, 0x555cbb28, 0x0ea870fd, 0x436a75ba, 0x54d88e9d, 0x3b93f370,
        0x883fce58, 0x0319a127, 0xaf9bc68e, 0x5ac21826, 0x5628e82f, 0x250b97a0, 0xa34f26ef, 0x53814824,
        0xb1bdc245, 0x045d9755, 0xc1d2317d, 0x3c9f3c5d, 0xa93335be, 0xf72dd8b4, 0x7422bbfa, 0xecf8770a,
        0x18828c0d, 0x2434359e, 0x1cb65155, 0x5c029194, 0x356e4b01, 0x0c08dd7a, 0xebcbc251, 0xd9b23389,
        0xfd874ee2, 0xdadc9012, 0xeb012b19, 0x7cecf1c1, 0xe87d33b0, 0x89ee4bee, 0xca19cd66, 0xfd1e256a,
        0xdcffd993, 0x7e2dc20f, 0x8ff50acc, 0xf109fef5, 0x86f5280a, 0xf88a93c4, 0x5235dc63, 0x604d8aa6,
        0x0d2d2802, 0x634495e9, 0x785435ca, 0x241a3004, 0xf2758cd1, 0x990c95e4, 0x5f8ecaa6, 0x3d702a67,
        0xceb8eadc, 0xb170ede3, 0x0899d31a, 0x36034ad0, 0xd39f45b0, 0x18b27627, 0x657aa01b, 0x6165ace2,
        0x9210b1a9, 0x91360091, 0xf12cb107, 0x4591aefc, 0xecb18217, 0x32184480, 0xe0995a02, 0x429a651d];

    static immutable ulong[] reference64 = [
        0x49eac513f7718934, 0x431dff7e6cc526de, 0xc3e9577d6ca03c7e, 0x10534f4b80e6412f, 0x28a424fba929c612,
        0x80b1b4c64e0a1290, 0x6f1a5d44a96d04f2, 0x0c536919cae25225, 0xb2027e94c83bc852, 0x49709d14c764e346,
        0xc70442544ec80f2e, 0x2395bd8595f92c79, 0xc3146214caa05d11, 0xc7cc96e562a8f86e, 0x5b6606c43a41b260,
        0x40a5806705060de2, 0x0fe9b04143defc99, 0x80084dfbf1d53f2b, 0x8d68a996cbbb124f, 0xc65947d89dc6018e,
        0x458349de747c4903, 0x849577bb63784166, 0x0b9b506682e79429, 0x96e8cbc20325a658, 0x2b67d241eaffd705,
        0x230ac662e3464f01, 0xcf19c78c8ea60f77, 0x79373106f7897498, 0xaeae3a6b451d30ae, 0xf7d3ca8fab462eec,
        0x8ce47ee75e726d27, 0xdbee80ef029a107d, 0xf45360428f201e60, 0x181ad65607d70993, 0xbdb3aa5a9f622e57,
        0x1c78b36546cddaa4, 0xf0ef09c869bda907, 0xa32b2398cb206d54, 0x60582d38bc123ada, 0xece9535802198e31,
        0xdd95a256bcfd35c0, 0x9d6df80cb8ddb1e7, 0x006dd830b54ab5f7, 0xc8a47f4670e3f08c, 0xd80161546d2eb190,
        0x0ce52f31f7dbf508, 0x14c22b46df9a0f50, 0x387d38723da8a3cd, 0x02c4ecf3503a6e95, 0x4673643f7e9ed145,
        0x171a66b95b0ca28d, 0x2a7f11c23e048284, 0x0a165df1b445a6f3, 0xcdd04c34051c9ef8, 0x83323818fa77d095,
        0x3cff121e42d4df5f, 0x7c685edcded0d595, 0xb5e07a3bafbb4dbe, 0x25b0fd6a70a616c4, 0x93b02d03799e6e12,
        0x389e878f20cd8e47, 0x97e91e4a8dad7bba, 0x1f3f10c93b3bd8db, 0x4094d87cbac636cf, 0x78c210023f39ed79,
        0x54928eddc1b950d2, 0xd552d81a88392839, 0x5a8a06d7fa331bbe, 0x57f1079ce9be1e78, 0x530b2d21fe721cd2,
        0x2f27d1f91932abe8, 0x8789406bc1f1cc06, 0xc61bec12f09e6ed3, 0x12c11975afe9ac2c, 0xc471c23162171f3b,
        0x341c368a480d2872, 0x894d6f161b4d1467, 0xd7e5a17acea9b9e9, 0xa5631790ec3d5970, 0x9825fcdf25b1600d,
        0x35c8f83b4fb1c249, 0xeb4131322a217d02, 0x273eb46990244e34, 0x05262dd56cfaabe8, 0xc5ce7ef97f1d82e3,
        0x3f77a9bc2a5257f1, 0xf3a3ad621b018f8e, 0x48eacfe9896b1a96, 0xb339e1179b01d0e0, 0xa783cf8c16fbfd0a,
        0xba572adb34915ea9, 0x4f9d61c7e9d58fd7, 0x4ac2f10dd99bbe0e, 0x0a76e30befdd861d, 0x32ec45fc4e7630ce,
        0xd2f7ca8597c5d507, 0xfdefc1b23a82f7c3, 0x0f534a1cd88dfcfe, 0x92ca4fd5483c3e29, 0xb9978cf64a739a01,
        0x17ef1494a6804122, 0x016b7a85fe03d7e1, 0xcfa3f52e1db3bf0c, 0x330d246caee43c19, 0x33b87eb5f2fe8f04,
        0x99e93bea6e4aa2a5, 0x30ae825d7a442816, 0x365b3e82f171d20a, 0x9566b3c286e8ac97, 0x70d5bf03f3a80ac2,
        0x3ad1e722a50c7ca4, 0x162b85aac4597a47, 0x6d4ab557a8cacb81, 0xc090b9f2c0221c02, 0xde444587e22d9fe0,
        0x90755fdb2f5ea416, 0x7fb648152ce1ed9f, 0xadf22676d560d422, 0x09fc8d68f34f05d8, 0x628c9a7844bd6e43,
        0x1f2f692f4cfd7065, 0xf62255624ce46b8c, 0x9b2245662677c359, 0xd621fc89d4f464e7, 0xe36dfd8e4623cade,
        0x40e2b09a760d47e5, 0x6f76ae3719954fc0, 0xb15d6469407f0f94, 0x41df4a29bae9ed83, 0x3c281458e58502f4,
        0x8f1dc8158d4d9c76, 0xc3fff911ab76fa11, 0xb0ef72a7faef3d15, 0x32e670b86c76192f, 0xd3a63980f1fa7dac,
        0x90ac56b9a85fdf12, 0xbdd97c114658cc1e, 0x76fa931fcc6de32c, 0x7d220883ac5be79e, 0x254e33bbfa924460,
        0x9a3be5c70ce74c79, 0x8813d871f7d442af, 0x632abc34a689083e, 0x07f990aed9e9ed75, 0x3dd7dada33345983,
        0xac448a762bfbb569, 0x3d4afaf04c5398f4, 0xf2daee0a3a34cb31, 0x80ea6091e6ffcc6a, 0x4cfe162054b5499a,
        0x6a8707ee0b993866, 0xac4c5cf5e0176417, 0x2d66bae0e6f5fd1f, 0x7bbbd5f9e10e7b0d, 0xd9374b79e28c8e30,
        0x354c5df3dfb3bd40, 0x2e6662c184d95849, 0x760f692e92d03753, 0xef291e45082fed5a, 0xfdabd5e1208a5884,
        0x9dd1609a368b0c6e, 0xf323f0b51bc1a8ad, 0x191b743a7e18243f, 0x79fb57af35d37c73, 0xa449f6176ab28342,
        0x083ff1f0c7174206, 0x4113336dd323dc3c, 0x15e60f681dd77737, 0x0780d5a1190cdbec, 0xa5e3e9408e3d68ac,
        0x2462fdca6429ff11, 0xc786ab0ac82003c4, 0x0750c064ba24d7ad, 0x03a4d2dc4386f18f, 0x198fe4c34485b373,
        0x59801975e46f9640, 0x13945b912224d4eb, 0x5f9ffb8c491e3dc4, 0xed11ece739a9b378, 0x78e50328650a27df,
        0xdd91ef477eb7c6de, 0x949c51bcaf30d2b1, 0xcd182dba958b4c58, 0x8882ea995b866f79, 0x8cd2887523e2fb2a,
        0xbba8c5e8746887ec, 0xdb3f7219c58c725c, 0x2d6813926b251cba, 0xcae2ebfa1422b691, 0xfc29d1ac6180eacf,
        0x4bfc18df7a5640a4, 0xf755b2a0f8e28c85, 0xf18fee18f93af42e, 0x803d3ea2426c3621, 0x3e00bfbeed423c93,
        0x078c88426a4fc329, 0xe15c2a45918b3beb, 0x1e5addcaacf97cee, 0x8df727e0f303fe3e, 0x546e95c90159dfd4,
        0x1c6aa78dd44be13c, 0x3c21df995ffcef77, 0x07494f2084e4db0c, 0x8da4726fb70a07b5, 0x68fc5905e0fa2b5d,
        0x8137ecae097e0ec3, 0x88c44a44ead02f79, 0xecdaf3720c3d900e, 0xed1981d6023cad62, 0x0fdad92f5130b494,
        0x06acfcd5db17220b, 0x67d30466a553a9f5, 0xae40bbcff03fabe0, 0x3b4099131d3635dc, 0xcbc8217fa5d48fc7,
        0x15fed6a0d91515fc, 0x4ad7caf2cb5c68dc, 0xed76f199c3516579, 0xd7b3cc50bcc69821, 0xf7a32fd4e01692e0,
        0xe92d12400e69c467, 0x9b10fe589f79dbcc, 0x06135f1f6c7ab9ee, 0x84aa5a6a2df897ab, 0xac889c0077c04973,
        0xdff14436014fc76c, 0xa15262db0b17598d, 0xade63a30d88401fe, 0xb9dd3044446b6782, 0x47a19e1abded8b88,
        0xd72debf1c14c929d, 0x27496d4fc7d81ecf, 0x6b5b97e921ef0404, 0xa4bf00d0970bfd41, 0x3367ea2964afe4c5,
        0xffe0110fc517bf46, 0xda49c6503a58a6e6, 0xa44a66b42fb37128, 0x484b5c2a92a05f76, 0xac88f56e4a3cba80,
        0xc848a6c95e67b307, 0x4273c313fb24eb9b, 0x8771f761d2f9b29c, 0xf8d64fe63c8ba44b, 0xb88ec21a690e18ad,
        0x5c29d25977459e9e, 0x4a4ff70f91743abb, 0xcc32436b598b3cab, 0xfbec7e8589ad9072, 0xcd7e1e2a4b737c21,
        0x3b16e35a08d40f65, 0xaa83763a7ca719fc, 0xf004fd5308ac62b5, 0x297613cca879f43e, 0xb6fdffd2816a6e01,
        0x4cef1d5f9a69077e, 0x1c9254706ce7e99e, 0x3dfbce040608f84b, 0x39f566e79a35d27d, 0xd5bf07055c72dfaf,
        0x7d55ebb6b12eff0c, 0xfb1c47964b787c9c, 0xf9ce00f57e7e5df8, 0x492eed1ba3141689, 0x2a1e2cf1ce4182c0,
        0x0c4f8d6bb69c989b, 0x0aa927284ee3403b, 0xb425bd95f92069b6, 0x1b53add9c233604d, 0xe41395b4f439dc8d,
        0xd4aad9e3180d163a, 0xb5c2fe11339f354f, 0x8695164cf32a8a1d, 0x7c06e2ecb18eaaed, 0x3a35d954bda11ca6,
        0xaf466eb71cdaf63d, 0x0d4853e98e84bd60, 0xbbb7dd8784b48bec, 0x3addf7137b0e4981, 0xf08dc2db9b8496da,
        0x4e07f145b61ae090, 0x8b1e9ff5a44de3a4, 0x6ba54ad96c4c41ad, 0x3ee5ecdecee0d9a3, 0x3bc4d04cd9eefaa4,
        0x4c8381bd422b6eea, 0xdc3796beb9af6124, 0xe26a68905df00150, 0x333e7a3aa4b6a3f6, 0x3d7c1ffa78d4029f,
        0x382b71db3b28bbc3, 0x7f21df446ff76582, 0x5d566b4154af6656, 0x8360a88c0c05971d, 0x6fb48e943f28ffb8,
        0x98c245bb94fe1b4f, 0x347a556da35a2836, 0xec0f75985c563d0a, 0x9a04349b46da61bd, 0xa27061b97d7a8d4c,
        0xef67fddc843d8df5, 0xeaf4086facd7f5e2, 0x00539e7931112529, 0xc442f85a860de1b5, 0x5915d781c3c9cb9d,
        0xa9576024da5b9ec8, 0xb8aa8d395ab6f3d1, 0x94fa614d3e06b67f, 0x6c87969873aa7a46, 0xaafbfa401f8bf5e1,
        0x8d6dc25692278071, 0x559b2db1e0aa6cf6, 0x1310b32ba26533a3, 0xad4e5f92b9036087, 0x868221e34d59fce4,
        0xa7f973337463864c, 0xd0e1e917440102c2, 0x0256895375e0dfdd, 0xe85c09ae703f2a62, 0xda9dd699f31cfa90,
        0x6a0f100dea21d538, 0x05aab63ba4970318, 0x70727353dcf05a0f, 0x90ec055769888adb, 0x494d9b85508da831,
        0xd98dd36c24fd015b, 0x334002b7b0479a40, 0x67636b07a4d0fbf7, 0x0491b28dfb3b9743, 0xf10be98a884d0aa7,
        0x721c37cc0efcb844, 0x93875d616abd0f67, 0x54529b17a048ed99, 0x09f85ae703474985, 0x2cdc4c7d3c7207f8,
        0xc37c0a65c07dfd3a, 0xcacfcbe16bdd5be5, 0xd716f3ed753b96aa, 0xeeb313ee173d90ce, 0xe1e6de4235deaf13,
        0xd19484ae79d2b579, 0x6fedea7a39189aef, 0x5297b88a1bbedeef, 0xb3f0c9dd1f9441b8, 0x56d10ec4e9978b82,
        0xef53bcad146a7485, 0x3ef7070c6362bd97, 0x4be66cb2216df084, 0xfc346433be4fcb24, 0xe8eca3dddaecec6e,
        0xa822aadf6aa8b0db, 0xdc125c52ab909c7e, 0xfcf9e72939c9b78c, 0x4178bdc0fc4e6652, 0xc2ca0e20ed0817af,
        0xe1621a3074b75d70, 0x58941d11a640b768, 0xea5cbda0a1b23b4f, 0x719caec93ca2bd8e, 0xdaf8d720d8eff9d0,
        0xd41c81381eb876a1, 0x677ffac8b737d774, 0xb38f3e0cf4315a3f, 0x6a5e343c4598039c, 0xc2ebfc1801c60ccb,
        0x5c151dff196db6a2, 0x4d89acb7ab285f00, 0xd1dfb8e0d5673b8a, 0x6ba95760ec388c9f, 0xc90f0781f779172f,
        0x5fffcaf9aa3584f2, 0x9ddc9049e6c49eba, 0x60e29891c67df0ec, 0xd817e29235e801fb, 0xa7f29d848903952a,
        0xf028dd8e5ca8c991, 0x90fb4c6c399807e2, 0x8005efa6084130f9, 0x6f9cbcd1806e25a8, 0x37c5dbeae1d7601d,
        0xa288e7d93142fcfc, 0xcd4d9235bf3f4f48, 0x913da7e71b742c43, 0x9062dffb1ac2f51f, 0x934ef045ce58c2a0,
        0x7e666ba2f657791b, 0x06fbb60aaeec4cb5, 0x330c531adc1a0b2c, 0x5deb15a9b7804d2f, 0x80281a596f2ff602,
        0xe45a2c5142fe47a5, 0x92f6c03dd9b0d766, 0xf55d90c5781de80e, 0x98cc70f4d45dac70, 0x6eff98fd97844120,
        0x0941863b642d6a46, 0xf994b42b570b27ea, 0x6d29a3fc217f5bea, 0xa85a5b2d4a8271e6, 0xbdb1521b786ddbfc,
        0x919987bc4130073a, 0x3d6a2619d095d624, 0x3a789f9359751914, 0xf5a45450b9c0f148, 0xd9d00af7291c1e9c,
        0xd17d2b500b7c9c8b, 0x71711a7be8d7a2c3, 0xf877efd02539cf7b, 0xca818f1dc70e6f70, 0x01316d26e8d3525c,
        0xe992a4f73cb20f0b, 0x394e7a9c9b0074e1, 0x098729241f6ae551, 0x68281e4cb5df7e63, 0xc312169cb27a15a0,
        0xe79fc13ecd1de025, 0xff7dfb14aac49c3d, 0xe050bf2264c2aa22, 0xe1b807604a33e667, 0xacc0282692f0f506,
        0xfffae9165a79b729, 0x7cd41b34edcb78af, 0xd55e7b80fc78b009, 0xb51875f66dd48c6e, 0x92c28ea2a262397c,
        0x32e20480395da750, 0xfd9f763189c57556, 0x60ce29af3f05b567, 0x0f64b2a7c970e23c, 0xab77f3a1f5c4369a,
        0x49fe1f3ea3be5b70, 0x5d7197bcfb699b06, 0x2f1c2c413534db1e, 0xe902f71df3a5cecd, 0x644e54c00ab37869,
        0xf9abb9732811ae8e, 0xc99eebefdd9e4ebd, 0x812ae9e1d0fb2fd3, 0x51ed442a9358ae8e, 0xdcecad31fcfcf712,
        0xc8fbca12051eb910, 0x5cb45ab2615270aa, 0x1ba18a5f6433a2c5, 0x34792578c16ef564, 0x4840d59ca9945636,
        0xd519d01b5d7aa738, 0x8ec4add227b16525, 0xa8778c670f983da2, 0xaf2adfb9ada1d076, 0xec867158ad4d94fc,
        0x3c352719d7bb20bf, 0x56e97533297b2b00, 0xa95ac325eb15ab6e, 0x0f1b902251e6d97b, 0x60d5ac15ca804bbe,
        0x5dea3f5e188a5f90, 0x3edac96189ef889a, 0x2fdeea8cd7ca099d, 0xad7ea9bad74c96a9, 0xab16a424942cfc7f,
        0x392b65f57380fbc6, 0xfa4910b2d7141703, 0x630fe1ab725fdc6d, 0x7ee960c5561bb5fd, 0xaf80b5c8257a9a0a,
        0x1fcb7dc75afcf53c, 0xc1fde086d02e60b3, 0xf4f6023a02b26aaf, 0xae55b1eb6bb7b4fb, 0xf888a0a1c530170e,
        0x2bf546837cf2dda8, 0x3e1aa9612d5524d6, 0xb9a1967c27ecd717, 0xf6111ae297991c29, 0xe342995543386d7a,
        0xbbaf274fa3826f7b, 0x78c71df721ffc5af, 0x032b70f6b9d56059, 0xd28e24347f9feafc, 0x381bf62485ba3c81,
        0x43726d726295c741, 0x92b5a2a5b29360e5, 0xc5aa28b60169e66e, 0x4eac5499b225dfcc, 0x04b93e2c9ed3bab7,
        0xe1e32061128cd65d, 0x27643470d9ce64fd, 0x3224ea37ff6e5b13, 0xd54bebf2d5e8023a, 0xa38954f38c39d4e9,
        0x14d24a901ff6c656, 0x9608b92e44c118d8, 0x7e445a426677bd58, 0x64b60c5ac3c17085, 0xe0ff12d5bca50c1c,
        0x3d428c30ed1e0364, 0xff010fd449c15c01, 0x21dd33d37226bbe9, 0x678399a599d93ff1, 0xf7db3c9674ab77f6,
        0x2713457bf4353bac, 0x497fa983dc463165, 0xa97d609845a34290, 0x485e8b8ee0e0fe9f, 0x0ae16d6e50c8de25,
        0xb294bd3163f2185a, 0xfa4782dbdfe35d64, 0x920ab90e90a01290, 0x43d75d4b9d8e5ac2, 0x6ed0eb7f2f25eb89,
        0xab814a9209531870, 0x4fc8f6fd35f2b4f3, 0x662e61ef9631bbdf, 0x688fbd3d3ff78277, 0x3cdcab15bc556116,
        0x3a8f1e0f33ab2fee, 0x965ab247f3a707e9, 0x5baf5ee354edad9d, 0xed7a327619a862e1, 0xbf98f989cad040b0,
        0x2fdd8688992e064c, 0xe9076ef5fa87db8d, 0xbf816a0f086ad8b5, 0x7ca10373b002da5a, 0x8a53d55adb09cbc5,
        0xa46b33a0095d7dc0, 0xa49b7c5b023806ae, 0x38bdc431e210b709, 0x7c65e70e81de7adb, 0xafa79c954eda3b4b,
        0x8c2783f1a770c562, 0x2d2fdd48cc7580ca, 0x1809c13b52d2eea1, 0xa5d39978974c8606, 0x81e87cc6a4ffe43d,
        0xb37823c86af8df45, 0x1e4120921e24f995, 0x69e82a24636b5cfb, 0x4f7b4bd8993a33b6, 0xa2fe87cb0cb6918b,
        0xbe67c021b012bc33, 0xd25e7583c1ca8a7e, 0x71af22f56c145380, 0x4f76f2404164815f, 0x7d62b90fe45a7ebb,
        0x3f09a1edf1fe9500, 0x299d14f07dd19f3b, 0xf6d16a822cd77931, 0x07fbb5fded289ca3, 0x0c4907efcc61603d,
        0xcc8fc211e1ffe0ed, 0xd10a34bef1287644, 0xd5a633fbe119539d, 0x8647fafdfa100c88, 0xfce533d7b0417e97,
        0x0a92f0819de6affc, 0x59ebc1bab0183775, 0xeaeca10e773f8e3d, 0x162767ddda528fa6, 0x496db7bfe77520c6,
        0x7fc3f405491e253c, 0x058bf52a31cbfb5b, 0x7ba93a3e448e92b5, 0xe69e398694df9e5b, 0x5767d06ce2e89fca,
        0x503223e3fea0f487, 0xe90e52a023f92463, 0x8aaddaa72955c5df, 0x39601d27ffd96c5e, 0x3e91c05fa137efd2,
        0x00f37c76025977d3, 0xa4b1345a41c0f9fb, 0xdc5ff1f2449da46e, 0x9fc3135a6f3e9395, 0x333361d135403189,
        0xa2951bbe1e4a862f, 0x0fb70257a02ccb96, 0xe2bae4b61651a19c, 0xff26394a731a664b, 0x21a31ad572f2b9a5,
        0xa35710fd42fbd1a6, 0x96bcfa3a3a79e9fe, 0xe65f478c032c8419, 0xb84681c859e634b2, 0x23d5c8b2fa6f1b98,
        0x02f0cbea8497fbbb, 0xd5069349838d61c7, 0xb72a79022e42e6f6, 0x5091f355946bcab5, 0xe24c8702b99df26a,
        0xb4f88d832a7f0b12, 0x8ebd87368d532130, 0x71adee12c477f01e, 0x89eca94f655a40c5, 0xf0c657424dcbabad,
        0x9211f1b418449e0c, 0x064b349fc59fba6f, 0x245d594bdcab9abd, 0x5062fa4864c454c2, 0x80fba4de851a74ae,
        0x7e2aa59ff31084ff, 0x27292e68e28a410a, 0xea2a6f5804a42c1a, 0x227afca49f582623, 0xae9d32641c57748b,
        0x861451cbbbd786e2, 0x909e628485a6f27f, 0xf40b1175178ccf2b, 0xe5beb5d9bc08ad76, 0x59530fabf6229da0,
        0x689cdceef98f20cc, 0x2feded20cd04c897, 0xae4a24bb3d55f2b1, 0xc286838066b28e8b, 0xe6b830ea62569b1d,
        0x092016a38115cc81, 0x4d145362d0dd6d0b, 0x3affa0ab3e2435b4, 0x4d67c993f1a687d9, 0x22e5d40eaaa271e0,
        0xafa7f9df408dd527, 0x082cd9862805afb0, 0xa4e13660b43b4f2d, 0x452f58bb59b34c84, 0xe3234915dd1b138b,
        0xbea777758167dc32, 0xc10104acc2af46f9, 0x70c754c393aee9ae, 0x2434570e5ba7c21b, 0x8f8c9fe188b9dcf4,
        0x9a0e1ff384bad292, 0xc38e6fccc626fae5, 0x5e1f2d18c14e115d, 0x9854e4b19803f6eb, 0x42a0464b62ba251a,
        0x6972b7b6123d38ca, 0x83fd596653a060a5, 0xa354b8a4de87309f, 0x907508160bf289a0, 0x93034b20139af3f4,
        0x15d2711cc7d94733, 0xbd5ccc607f4d6470, 0xabe4c24eb522b0aa, 0xe75246cd3465ed23, 0xbafe23cc3bf031e1,
        0xa492f3f7e3995aa6, 0xab5ff3e83d329c64, 0x8d147beb547d37f6, 0xf64e61bc18c1a086, 0x06378e62fa6afe89,
        0xc6dc13571fb31bd1, 0xfeb09d326d99ce00, 0xee514a49a16bd7cb, 0xed8d09727daf55bf, 0x2581bb07d01fc661,
        0x90bcf0a4f64e3cb4, 0x5defcbef59abe3ca, 0x03e35539e856315a, 0x5bff89a3a3a9e49d, 0xad277cc0a1e596cb,
        0x1318d9f676f26351, 0xbc29a720580ffeaf, 0x64b8b9b0b78428eb, 0xb25249ef1d2afcad, 0xc92ea8b1e54b7f10,
        0xa164b1ce176a10ee, 0xea4dcf6cb0259efe, 0xdfa96017565db57a, 0xda51567d9ce2564f, 0xccd8043a0d3b2cff,
        0x6ae907c5aa1a3e83, 0xf2640d9a24bd2ba6, 0x9936ab1ac304d187, 0xa938a25ec7ad6a46, 0x2a90518dba586d16,
        0x67adce7f3015db31, 0x2d3364eb2179546e, 0xe11b30f4a623efe5, 0xffac2b143dc182cc, 0xe3308de6546acd60,
        0x3609317f103a2869, 0x05cec07daf07ab5f, 0x1bd2fa4958c02425, 0xb93c050c33a9957f, 0x8f8e3140bb2f3a53,
        0x3b863e54694b042d, 0x924c4be24abfbfd9, 0x5f814f7ca68ababc, 0xb25a8da31f1797a0, 0xc1b2f1e7bad1caf1,
        0x1582289c09806b0c, 0xe4d14158586cab47, 0xea1523130287c75e, 0x37aaa1189f3ccb01, 0xad41c84d86a61a3e,
        0x231f481916fa4500, 0xacf01bf3ca0b86c4, 0xa489ff3188f381d8, 0xef9734404393a31d, 0x060642c4f3a6904e,
        0xd69fb66c003387a4, 0xb9dee73413a5835b, 0x11cb2ae69786cdc7, 0x288ef7c4b2a26382, 0xdc32d21c3fe7d083,
        0xe2ef343d2fbacc59, 0x5ae7797d3fddcb10, 0xd97a6869e458b519, 0x9e1047f9e25b3ccc, 0xb53877254ee5ebba,
        0x543cd66e0f93c1b0, 0x2991a19e89712668, 0xf355b3495d9313b4, 0xb2436627d3ee09d1, 0x7fa4e060a7a4bd0f,
        0x704c9de88324ae90, 0xf453b3042ffae9fc, 0x4fd3462f2df62cf3, 0x4b570c2f9047dc39, 0x3e6341f68329d196,
        0xa223af1f83a9d6a3, 0x437728b757dfca61, 0x252fd8c6b2f36b02, 0xcb22fa4936ea3039, 0x5ea5cd795adf6b74,
        0x2eb25ebd50cb9af3, 0xe800dc22d7fb3d53, 0x6373973dfd5482f3, 0x02f9e9fe7dee44a0, 0xf48dbd502a044fdc,
        0x288da4b45c376a6e, 0x5d33ee3d5ed241f7, 0xbbf5dfd6592c061e, 0xe6202d7b7fe1347e, 0xc202cc15364225af,
        0x2a5087b4df258598, 0x513a09d9c5292a9b, 0xbcd454f7da9a1e72, 0x960b01eb66fbd662, 0x8588aafeccebd3f7,
        0x645bf0d2f05a0a53, 0xf6d6c739491c0129, 0x1301513b4a35c1d3, 0x6a5a93f10921c162, 0xd9421fad84c52f2f,
        0x3edef340d9aecf5a, 0x4439df2099454297, 0xe7ebca031409b819, 0x6732a414159fcd47, 0x227d858f4246217a,
        0xaf1b25e288a9064c, 0x721159362c3cecfd, 0x29878f2b6e4da5d9, 0xf601116ef9725e9e, 0x1d635686034cf279,
        0x216256269a7318f9, 0x776bbaa1e2e503ba, 0x947e65983bec8a7d, 0xc5b043ecef764569, 0xf2e857a3ed3db715,
        0x292db5173b9a33c8, 0x65f0fc5e00e12d6c, 0x15029b25cc36405f, 0x05a621a80786c283, 0xe673cf50fc806505,
        0xbfe3b5480d052c5a, 0x917c8e6fe2a7585f, 0xf13a11d49973cd98, 0x5c072370720b9f69, 0x055034d0288416b1,
        0x6f564b45f4cd504a, 0xed7f02c312e3c3fc, 0x6bbfc3bdb9048aea, 0x2a86dccfa46d8a00, 0x2431a0f2ee285ce9,
        0x3a03a6402890d387, 0x35d2184dab0d9bf2, 0xc6544434663144fd, 0x57efb5567bf9cf5d, 0xf0a3c3ed36cfead0,
        0x6e6102385832f4fa, 0x31c542bf7a7aa2b7, 0xc725bce0f6f789bc, 0x46377b6de02acb7b, 0x59c164e61502e858,
        0x3cd5214811a64d7d, 0x36ce2b4fb1f0a9fd, 0xce60bc56f33a54fc, 0xde3b0be660f2592d, 0x01ff0d81087f66b7,
        0x0a7d9c2a1e197c18, 0x98a4f2285f85c9b4, 0xd9a3f325b283aec7, 0x73bcd15839a2f3f9, 0xc67ba53209304832,
        0x8cda83250b5d6434, 0x5ca6a2ef5151ef47, 0xd2dd99b309018b3d, 0xf940e149085e4d25, 0x6f02d0c1a099ad61,
        0x0a6681626d8be642, 0x33206fbdcf3a86f3, 0x9f692d5e7beefc1e, 0xbee2432b6c688510, 0x0c2ec48d94feab54,
        0x1a41bdcc9e7a0374, 0xb55dd57aceb7eb02, 0x146cef97be06e98a, 0xb1549874c7397889, 0xf455c0df9827c305,
        0xd6e8d45f5b533728, 0xba452af43731a1c8, 0x64295ee65aa7bfb0, 0x25cdec7bd5070f24, 0xbad1b43b63bd8638,
        0x4ee70bb1d7175edc, 0x4c737a1ac655752b, 0x46f114b7d54ada52, 0x8b270093b64c13a7, 0x8f71ef9557bf1c32,
        0xb51cbf4ad2999655, 0x043b4a425d3c416b, 0xa97b642a59253371, 0x9cacff15df446531, 0x55c62ea56ed19c3b,
        0xb45cfdd32ae72d69, 0xec0dc5bc43f2f775, 0x3f19e23784b585f6, 0xdcee3908de3fe410, 0x8b5dda76f2e5b9a2,
        0x57e5f8487db7a5c9, 0xc695e6a8179434fb, 0xcdddd5316501eef7, 0x82eb3f49a66f2e15, 0x741ff5653654fbbc,
        0xe9c4c77baf881992, 0xc0083d9c41ef549f, 0xcb6fa377a1c14927, 0xfbc6903a42af163d, 0x1723d9a2906fe9f6,
        0xc5c8ffbcc35ce07d, 0xe9ab0d158924d333, 0xc7a1b95872554582, 0xe8eb0ce45eae344a, 0x63d45f3fe01824ff,
        0x3d01ed0540742e53, 0x34b84923c06f7a9a, 0x9682a590b499b604, 0x3c4485c9b17d92f2, 0x5bf0fa83a7de0ed3,
        0x1ae40bc69fb6d3b1, 0xd965318f70f7d53b, 0xff52832ddc3b1137, 0xb91c61cbd263a981, 0x50b1ea907464a756,
        0x387e6fa826f2175b, 0x105b74b1a6ab2ebd, 0x6950f9c6f1715711, 0x0a1e2dba9613b9d2, 0xb3629c9f0e64f197,
        0x1ae44a59d2d5b953, 0x359f5449e9f02e86, 0xe43e68966973b5e0, 0x9c1e4c9cc7a947fd, 0x4283c04e302cad2e,
        0x44d4eacd797b4a4a, 0x88d98500754fe0e3, 0xf06f54896ecbfed4, 0xda5137b5e4c0010a, 0xa343abd4a593f41d,
        0x6f5c47e7984386a9, 0xb0cbbf49aa84d93b, 0x4331ff5a656a51d3, 0xaddbff3a00bdd1f8, 0xb5f91d9b7aa48879,
        0x1743370a82b3a0f5, 0xacae044157eb249a, 0x44fd514f74628dec, 0x923ed74d6437a523, 0x2f7f003e3a2619e4,
        0x792ce3f87bfb83b7, 0x461ad252e33ccb4c, 0xfe6f3573ac323a77, 0xb974c496afc860d1, 0xafb0e549eeae1589,
        0x34d4705b5ff3b3f0, 0x0b6f5f5ed532533a, 0xdc538cc7f8c94bf9, 0xc788e3b955a4a740, 0x1bfae83c7c4d1fbd,
        0xdf0e14dba8436124, 0x26df8dcafa15316d, 0x3bdbf0b21f36c7ca, 0x16addd2cf578f442, 0x534bb7cb7b07c9cb,
        0x6490c2bfd165ac30, 0x5584822b730f3235, 0xe832658443372a63, 0x67c6bb64247e2a4f, 0xb80e1bf186425446,
        0x9a568afe399f973b, 0xdf4a9d7d3ab4fae6, 0xf2fbabde79b144dd, 0xbc910e65b98093f3, 0xadb2e01ed14e3cad,
        0xc12c1ff2a3ef0e82, 0x5931ec6d06eaa87a, 0x32303ed99c5e0b67, 0xf082a9d03977937b, 0x7e408edcae4d4df7,
        0x7880db90edd9b377, 0xac8349204ff2a15c, 0x36419c7e465c2c88, 0x04ae6857036376e4, 0x27dd953d172559cc,
        0xa3a93ebcfc54cf62, 0xe1ea84ba94069e26, 0x0ff8a30c00504e07, 0xbad55f66cd2b610f, 0x889a45ca4b92e564,
        0x24774df29b197df7, 0xcbb95b3cc0915250, 0xe82fc0e5ce6f8641, 0x91f91a9405974fb8, 0xb9ae93ef0c5c1ab0,
        0xb741dcac178a852d, 0x2f34952812b75d28, 0x41d68a53d443d38a, 0xc23da6f18d065682, 0xcb44a9a92c369088,
        0x8706e3387c8aceda, 0x83e3a37ac39990b1, 0x28a26a6c968d6e7c, 0x8349dc504f7cb9f1, 0x1f78fccced8e5b3d,
        0x72d04b6498dd95b1, 0x149726ff1e458377, 0x5adf15c2b22ffc6d, 0x3003a0b9e9f6629f, 0x21c15ca13e25d276,
        0xdc0e861b2ff5d31e, 0x7639c3b06f845ba1, 0xe3b0c6b5138d19b9, 0xb102a60e6f2b9543, 0xa986d527f6a788bf,
        0x0e44c62e2de0ec3c, 0x5fbc825c7b165d30, 0xd32b080b5192b517, 0x4c1b5cb08d6a79c1, 0x51d1fd14d0b2523f,
        0x882e28793ebd09a5, 0x75c6e7a76baa6df8, 0xc3d4a0f403c58136, 0x1c08c1528db13938, 0x11ec16187d55ec8b,
        0x03e0c6f1d6dafc8d, 0xec601342d774659e, 0xdde561abf7b44852, 0xea51d3659c4aa378, 0x2c6b7912219d5632,
        0xfa3b2b57e6be53a4, 0x38ca03ce5eb4a6d0, 0x6e8dafa1722456e6, 0x5d10240da37485a3, 0x965597fa0ae67275,
        0xad994f1e6f00960d, 0x958f0023d9b75153, 0x48a8783d168be3d9, 0xfa7a06deefc452eb, 0x3467bb0df4f35613,
        0x70534c46658ec93d, 0x0be5b0029abc37c3, 0x7c3a97d668491a44, 0xa012818332fae7aa, 0xb9853fac1dd57f77,
        0x4d27bd53174739d4, 0x0af6afb381dd7ef5, 0xc5b8cb2ab2cd3a03, 0x05fcd21bf9957a89, 0x50aac2d69989c156,
        0xb19e63573f06b60a, 0x6040833d783fae00, 0xb452c093e08eed12, 0x8f5f76552bebf310, 0xebccdcc0a9b92651,
        0xd9e334b569a064eb, 0x478281a44841e49d, 0x5efd32c942efa24d, 0x97d007d48f3c2247, 0x0ca2b26df091bfcc,
        0x8af623cfdb3f4220, 0x62e8db8238d860b5, 0xc1d1dc6835a6cf94, 0x8c270a7506dfb2c7, 0x4f7e078ca44c3852,
        0xde76846c59b7340f, 0x2e34146ac57edf0b, 0xfcc9c40ed5b4acbd, 0x34bbfc330d419f94, 0xa2ca2aff82ffdff3,
        0x5f2c6df0d5db8286, 0xf901ebb282fd17b1, 0x1fa5fec3fb86061d, 0xce41de5689182bf8, 0x62f8ca5a22f01e93,
        0x80877eaf479a25fc, 0x2f1f0fd7c4d43293, 0x271b2d5cace4e5af, 0x7da446d7c1b0b55f, 0x879fbdbf06420800,
        0xc933eb99a1a5add7, 0x00577e9224ed4439, 0x38f30b96dc6b275d, 0x9578377f14c9fd3d, 0xf65ea6c3e9679bf7,
        0xca7976f96a94f191, 0x9e69057c51034022, 0x9e7e1bf226f6b959, 0x129390c5692c957a, 0x08e8e46c8c4529d1,
        0xc6956ea356adde6c, 0xbf09848bf792924a, 0x6256ced0e73fddd2, 0x6bebd9ad88c05ede];

    foreach (i; 0 .. 1024)
    {
        ulong h64 = xxHash!64(randomBlob[0 .. i + 1]);
        ulong h32 = xxHash!32(randomBlob[0 .. i + 1]);

        assert(h64 == reference64[i]);
        assert(h32 == reference32[i]);
    }
}
