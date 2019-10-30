/+--------------------Copyright Notice------------------------+\
|      Copyright:                                              |
|  - AsumFace (asumface@gmail.com) 2019                        |
|  Distributed under the Boost Software License, Version 1.0.  |
|  See accompanying file Boost1_0 or copy at                   |
|      https://www.boost.org/LICENSE_1_0.txt                   |
\+------------------------------------------------------------+/

/+ testing some block lighting algos +/
import mir.ndslice;
import cgfm.math;
import std.typecons;
import xxhash;

alias color_t = Vector!(ubyte, 3);

auto lengths(S)(S slice) // helper because who could possibly need that?
{
    size_t[S.N] result;
    static foreach (d; 0 .. S.N)
        result[d] = slice.length!d;
    return result;
}

auto read_map(const(char)[] filename)
{
    import arsd.png;
    import std.conv;
    auto image = readPng(filename.idup).getAsTrueColorImage;
    auto result = slice!color_t(image.width, image.height);
    ndiota(result.lengths).each!(coor => result[coor].v[] = image.getPixel(coor[0].to!int, coor[1].to!int).components[0 .. 3]);
    return result;
}

auto write_map(S)(S data, const(char)[] filename)
{
    import arsd.png;
    import std.array;
    import std.conv;
    import std.algorithm : map, joiner;
    writePng(filename.idup, data.transposed.flattened.map!((ref n) => n.v[]).joiner.array, data.length!0.to!int, data.length!1.to!int, PngType.truecolor);
}

alias light_field = Vector!(color_t, 8);

size_t dir(int rot, Vector!(int, 2) v)
{
    return dir(rot, v.v[]);
}

size_t dir(int rot, int[2] c...)
    in (c[].all!(n => n >= -1 && n <= 1))
    in (c[0] != 0 || c[1] != 0)
    out (r; r < 8)
{
    int x = c[0] + 1;
    int y = c[1] + 1;
    uint pos = x + y * 3;
    immutable uint[] lut = [
        0, 7,   6,
        1, 255, 5,
        2, 3,   4
    ];
    uint result = lut[pos];
    assert(result < 8);
    result = (result + rot) % 8; // 8 is a power of two so this works

    return result;
}

struct dirs
{
    static immutable table = [
        vec2i(-1,  1),
        vec2i(-1,  0),
        vec2i(-1, -1),
        vec2i( 0, -1),
        vec2i( 1, -1),
        vec2i( 1,  0),
        vec2i( 1,  1),
        vec2i( 0,  1)
    ];
    static opIndex()
    {
        import std.algorithm : dmap = map;
        import std.range : diota = iota;
        return diota(table.length).dmap!(n => opIndex(n));
    }

    static Vector!(int, 2) opIndex(size_t num)
    {
        return table[num];
    }
}

auto apply_fun(alias fun, arg_ts...)(args)
{
    import std.meta;
    ApplyLeft!(LightConstOf, iterator_ts) results;
    static foreach (i, sym; args)
        results[i] = fun(args[i]);
    return results;
}

auto bounded_access(S, F)(S slice, F fallback)
{
    bounded_access_t!(S, typeof(slice[size_t[slice.N].init])) result;
    result.slice = slice;
    result.fallback = fallback;
    return result;
}

struct bounded_access_t(S, F)
{
    S slice;

    alias element_t = F;

    element_t fallback;

    static element_t fb;

    ref element_t opIndex(size_t[2] c...)
    {
        bool within_bounds = true;
        static foreach (i; 0 .. slice.N)
        {
            assert(slice.length!i > 0);
            if (c[i] >= slice.length!i)
                within_bounds = false;
        }
        if (within_bounds)
            return slice[c];
        else
            return fb = fallback;
    }

    ref element_t opIndexAssign(T)(T val, size_t[slice.N] c...)
    {
        bool within_bounds = true;
        static foreach (i; 0 .. slice.N)
            if (c[i] >= slice.length!i)
                within_bounds = false;
        if (within_bounds)
        {
            return slice[c] = val;
        }
        else
            return fallback;
    }
}

auto p4(Vector!(uint, 3) v)
{
    v *= 3;
    v /= 10;
    return v;
}

auto p3(Vector!(uint, 3) v)
{
    v *= 4;
    v /= 10;
    return v;
}

color_t saturate(Vector!(uint, 3) v)
{
    color_t result;
    foreach (i, e; v.v[])
        result.v[i] = cast(ubyte)(e > 255 ? 255 : e);
    return result;
}

interface light_affector
{
    void compute(ref in const(light_field) ingress, out light_field egress);
}

class light_source_t : light_affector
{
    void compute(ref in const(light_field) ingress, out light_field egress)
    {
        foreach (i; 0 .. 8)
            egress[i] = cast(color_t)vec3i(200, 200, 200);
    }
}

class air_t : light_affector
{
    void compute(ref in const(light_field) ingress, out light_field egress)
    {
        light_field result;
        result = ingress;
        //foreach (i1; 0 .. 8)
        //    foreach (i2; 0 .. 3)
        //        result[i1][i2] -= (result[i1][i2] > 0 ? 1 : 0);
        egress = result;
    }
}

class vert_mirror_t : light_affector
{
    void compute(ref in const(light_field) ingress, out light_field egress)
    {
        light_field r = ingress;
        import std.algorithm : swap;
        swap(r[dir(0, -1,1)], r[dir(0,1,1)]);
        swap(r[dir(0, -1,0)], r[dir(0,1,0)]);
        swap(r[dir(0,-1,-1)], r[dir(0,1,-1)]);
        r[dir(0, 0, -1)] = color_t.init;
        r[dir(0, 0, 1)] = color_t.init;
        egress = r;
    }
}

class hori_mirror_t : light_affector
{
    void compute(ref in const(light_field) ingress, out light_field egress)
    {
        light_field r = ingress;
        import std.algorithm : swap;
        swap(r[dir(0, 1,1)], r[dir(0,1,-1)]);
        swap(r[dir(0, 0,1)], r[dir(0,0,-1)]);
        swap(r[dir(0,-1,1)], r[dir(0,-1,-1)]);
        r[dir(0, -1, 0)] = color_t.init;
        r[dir(0, 1, 0)] = color_t.init;
        egress = r;
    }
}

void main()
{
    auto map_data = read_map("/tmp/field.png");
    auto ingress_data = slice!light_field(map_data.lengths);
    auto egress_data = slice!light_field(map_data.lengths);
    auto material_table = slice!light_affector(map_data.lengths);

    auto air = new air_t;
    auto light_source = new light_source_t;
    auto vmirror = new vert_mirror_t;
    auto hmirror = new hori_mirror_t;

    material_table.each!((ref n) => n = air);
    ndiota(10, 1).each!((c)
    {
        material_table[(vec2ul(c)+vec2ul(200,200)).v[]] = light_source;
    });

    ndiota(1, 400).each!((c)
    {
        material_table[(vec2ul(c)+vec2ul(250,50)).v[]] = vmirror;
        material_table[(vec2ul(c)+vec2ul(198,50)).v[]] = vmirror;
    });
    ndiota(52, 1).each!((c)
    {
        material_table[(vec2ul(c)+vec2ul(198,50)).v[]] = hmirror;
        material_table[(vec2ul(c)+vec2ul(198,450)).v[]] = hmirror;
    });
    foreach (i; 0 .. 2000)
    {
        import std.stdio;
        ndiota(map_data.lengths).each!((c) // specific egress calculation
        {
            material_table[c].compute(ingress_data[c], egress_data[c]);
            ingress_data[c] = light_field.init;
        });

        ndiota(map_data.lengths).each!((c) // generic ingress calculation
        {
            foreach (d; dirs[])
            {
                foreach (channel; 0 .. 3)
                {
                    int energy = egress_data[c][dir(0, d)][channel];
                    while (energy > 2) // terminates after max 3 iterations (empirically tested)
                    {
                        //uint primary = energy * 12 / 32; // approx 1/(1/sqrt(2)+2)
                        uint primary = energy * 6_197_471 / (1u << 24); // approx 1/(1/sqrt(2)+2)
                        uint secondary = energy * 4_382_274 / (1u << 24); // approx (1/sqrt(2)+2)/sqrt(2)
                        foreach (rot; [0, -1, 1])
                        {
                            uint val;

                            if (rot == 0)
                                val = primary;
                            else
                                val = secondary;
                            energy -= val;

                            uint prev_val = ingress_data.bounded_access(color_t.init)[(vec2ul(c) + dirs[dir(1, d)]).v[]][dir(rot, d)][channel];

                            if (cast(ubyte)(prev_val + val) < prev_val)
                            {
                                energy += 255 - prev_val;
                                val = 255;
                            }
                            else
                                val = prev_val + val;
                            ingress_data.bounded_access(color_t.init)[(vec2ul(c) + dirs[dir(1, d)]).v[]][dir(rot, d)][channel] = cast(ubyte)val;
                        }
                        assert(energy >= 0);
                    }
                    while (energy > 0) // distribute remaining energy randomly
                    {
                        import std.random;
                        int rot = xxHash!32((*cast(ubyte[c.sizeof]*)&c)[], i) % 3 - 1;
                        uint prev_val = ingress_data.bounded_access(color_t.init)[(vec2ul(c) + dirs[dir(1, d)]).v[]][dir(rot, d)][channel];
                        if (prev_val < 255)
                            prev_val += 1;
                        ingress_data.bounded_access(color_t.init)[(vec2ul(c) + dirs[dir(1, d)]).v[]][dir(rot, d)][channel] = cast(ubyte)prev_val;
                        energy -= 1;
                        assert(energy >= 0);
                    }
                }
            }
        });

        ndiota(map_data.lengths).each!((c)
        {
            import std.algorithm : dfold = fold;
            auto light_value = ingress_data[c].dfold!((a, b) => a + b)(Vector!(uint, 3)());
            import std.stdio;
            foreach (i; 0 .. 3)
                map_data[c][i] = cast(ubyte)(light_value[i] > 255 ? 255 : light_value[i]);
        });

        import std.format;
        writeln(cnt);
        write_map(map_data, format!"/tmp/result%06d.png"(cnt++));
    }
}
ulong cnt;