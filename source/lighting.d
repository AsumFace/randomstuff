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
    int y = -c[1] + 1;
    uint pos = x + y * 3;
    static immutable uint[] lut = [
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

alias light_field = Slice!(ubyte*, 2, Universal);

interface light_affector
{
    void compute(light_field ingress, light_field egress);
}

class light_source_t : light_affector
{
    void compute(light_field ingress, light_field egress)
    {
        egress[0 .. $, 0 .. $] = cast(ubyte)200;
    }
}

void equalize(ref ubyte a, ref ubyte b)
{
    import std.math : sgn;
    int diff = a - b;
    a -= diff.sgn;
    b += diff.sgn;
}

class air_t : light_affector
{
    void compute(light_field ingress, light_field egress)
    {
        //foreach (i1; 0 .. 8)
        //    foreach (i2; 0 .. 3)
        //        result[i1][i2] -= (result[i1][i2] > 0 ? 1 : 0);
        foreach (c; 0 .. 3)
        {
            int[8] buf;
            foreach (i; 0 .. 8)
            {
                while (ingress[i, c] > 2)
                {
                    uint primary = ingress[i, c] * 6_197_471 / (1u << 24); // approx 1/(1/sqrt(2)+2)
                    uint secondary = ingress[i, c] * 4_382_274 / (1u << 24); // approx (1/sqrt(2)+2)/sqrt(2)
                    ingress[i, c] -= primary + secondary * 2;
                    buf[(i + 7) % 8] += secondary;
                    buf[(i + 1) % 8] += secondary;
                    buf[i] += primary;
                }
                buf[i] += ingress[i, c];
            }
            foreach (i; 0 .. 8)
            {
                egress[i, c] = cast(ubyte)(buf[i] > 255 ? 255 : buf[i]);
            }
        }
    }
}

class vert_mirror_t : light_affector
{
    void compute(light_field ingress, light_field egress)
    {
        import std.algorithm : swap;
        egress[dir(0, -1,0), 0 .. $] = ingress[dir(0,1,0), 0 .. $];
        egress[dir(0,-1,-1), 0 .. $] = ingress[dir(0,1,-1), 0 .. $];
        egress[dir(0, -1,1), 0 .. $] = ingress[dir(0,1,1), 0 .. $];
        egress[dir(0,1,0), 0 .. $] = ingress[dir(0, -1,0), 0 .. $];
        egress[dir(0,1,-1), 0 .. $] = ingress[dir(0,-1,-1), 0 .. $];
        egress[dir(0,1,1), 0 .. $] = ingress[dir(0, -1,1), 0 .. $];
        egress[dir(0, 0, -1), 0 .. $] = ingress[dir(0, 0, -1), 0 .. $];
        egress[dir(0, 0, 1), 0 .. $] = ingress[dir(0, 0, 1), 0 .. $];

    }
}

class vert_diffuse_t : light_affector
{
    void compute(light_field ingress, light_field egress)
    {
        import std.algorithm : swap;
        egress[dir(0, -1,0), 0 .. $] = ingress[dir(0,1,0), 0 .. $];
        egress[dir(0,-1,-1), 0 .. $] = ingress[dir(0,1,-1), 0 .. $];
        egress[dir(0, -1,1), 0 .. $] = ingress[dir(0,1,1), 0 .. $];
        egress[dir(0,1,0), 0 .. $] = ingress[dir(0, -1,0), 0 .. $];
        egress[dir(0,1,-1), 0 .. $] = ingress[dir(0,-1,-1), 0 .. $];
        egress[dir(0,1,1), 0 .. $] = ingress[dir(0, -1,1), 0 .. $];
        egress[dir(0, 0, -1), 0 .. $] = ingress[dir(0, 0, -1), 0 .. $];
        egress[dir(0, 0, 1), 0 .. $] = ingress[dir(0, 0, 1), 0 .. $];

    }
}

class hori_mirror_t : light_affector
{
    void compute(light_field ingress, light_field egress)
    {
        ubyte[8*3] backing_store;
        auto r = backing_store[].sliced(ingress.lengths);
        r[0 .. $, 0 .. $] = ingress[0 .. $, 0 .. $];
        import std.algorithm : swap;
        each!swap(r[dir(0, 1,1), 0 .. $], r[dir(0,1,-1), 0 .. $]);
        each!swap(r[dir(0, 0,1), 0 .. $], r[dir(0,0,-1), 0 .. $]);
        each!swap(r[dir(0,-1,1), 0 .. $], r[dir(0,-1,-1), 0 .. $]);
        r[dir(0, -1, 0), 0 .. $] = cast(ubyte)0;
        r[dir(0, 1, 0), 0 .. $] = cast(ubyte)0;
        egress[0 .. $, 0 .. $] = r[0 .. $, 0 .. $];
    }
}
void main()
{
    auto map_data = read_map("/tmp/field.png");
    immutable size_t color_cnt = 3;
    immutable size_t direction_cnt = 8;
    auto ingress_data_a = slice!ubyte(direction_cnt, map_data.length!1, map_data.length!0, color_cnt);
    auto egress_data_a =  slice!ubyte(direction_cnt, map_data.length!1, map_data.length!0, color_cnt);
    auto ingress_data = ingress_data_a.transposed!(2, 1, 0, 3);
    auto egress_data = egress_data_a.transposed!(2, 1, 0, 3);

    auto material_table = slice!light_affector(map_data.lengths);

    auto air = new air_t;
    auto light_source = new light_source_t;
    auto vmirror = new vert_mirror_t;
    auto hmirror = new hori_mirror_t;

    material_table.each!((ref n) => n = air);
    ndiota(1, 1).each!((c)
    {
        material_table[(vec2ul(c)+vec2ul(200,200)).v[]] = light_source;
    });

    ndiota(1, 400).each!((c)
    {
        material_table[(vec2ul(c)+vec2ul(198,50)).v[]] = vmirror;
    });
    ndiota(1, 150).each!((c)
    {
        material_table[(vec2ul(c)+vec2ul(220,50)).v[]] = vmirror;
    });
    /+ndiota(52, 1).each!((c)
    {
        material_table[(vec2ul(c)+vec2ul(198,50)).v[]] = hmirror;
        material_table[(vec2ul(c)+vec2ul(198,450)).v[]] = hmirror;
    });+/
    foreach (i; 0 .. 2000)
    {
        import std.stdio;
        ndiota(map_data.lengths).each!((c) // specific egress calculation
        {
            material_table[c].compute(ingress_data[c[0], c[1], 0 .. $, 0 .. $],
                egress_data[c[0], c[1], 0 .. $, 0 .. $]);
            ingress_data[c[0], c[1], 0 .. $, 0 .. $] = cast(ubyte)0;
        });

        bool within_bounds(size_t[2] c...)
        {
            static foreach (i; 0 .. 2)
                if (c[i] >= map_data.length!i)
                    return false;
            return true;
        }

        //ndiota(egress_data.length!3, egress_data.length!0, egress_data.length!1, egress_data.length!2).each!((_input) // generic ingress calculation
        foreach (int dir_e; 0 .. direction_cnt)
        foreach (y; 0 .. egress_data.length!1)
        foreach (x; 0 .. egress_data.length!0)
        foreach (int color; 0 .. color_cnt)
        {
            //size_t x = _input[0];
            //size_t y = _input[1];
            //int dir_e = cast(int)_input[2];
            auto dir_v = dirs[dir_e];

            //int color = cast(int)_input[3];

            if (!within_bounds((dir_v + vec2ul(x, y)).v[]))
                continue;

            int energy = egress_data[x, y, dir_e, color];
            while (energy > 2) // terminates after max 3 iterations
            {
                //uint primary = energy * 12 / 32; // approx 1/(1/sqrt(2)+2)
                //uint primary = energy * 6_197_471 / (1u << 24); // approx 1/(1/sqrt(2)+2)
                uint secondary = energy * 4_382_274 / (1u << 24); // approx (1/sqrt(2)+2)/sqrt(2)
                uint primary = energy;
                foreach (rot; [0])
                {
                    uint val;

                    if (rot == 0)
                        val = primary;
                    else
                        val = secondary;
                    energy -= val;

                    auto t_coor = (vec2ul(x, y) + dirs[dir(rot, dir_v)]).v[];
                    uint prev_val = ingress_data[t_coor[0], t_coor[1], dir(rot, dir_v), color];

                    if (cast(ubyte)(prev_val + val) < prev_val)
                    {
                        energy += 255 - prev_val;
                        val = 255;
                    }
                    else
                        val = prev_val + val;
                    ingress_data[t_coor[0], t_coor[1], dir(rot, dir_v), color] = cast(ubyte)val;
                }
                assert(energy >= 0);
            }

            while (energy > 0)
            {
                int rot = 0;
                Vector!(int, 2) shift = dirs[dir(rot, dir_v)];
                Vector!(size_t, 2) target;
                target.x = x;
                target.y = y;
                target += shift;
                uint curr_val = ingress_data[target.x, target.y, dir(0, shift), color];
                if (curr_val < 255)
                {
                    curr_val += 1;
                    ingress_data[target.x, target.y, dir(0, shift), color] = cast(ubyte)curr_val;

                }
                energy -= 1;
            }
        }

        ndiota(map_data.lengths).each!((c)
        {
            import std.algorithm : dfold = fold;
            uint[3] light_value;
            auto light_slice = light_value[].sliced;
            ingress_data[c[0], c[1], 0 .. $, 0 .. $].byDim!0.each!((v){light_slice[] += v[];});
            foreach (i; 0 .. 3)
                map_data[c][i] = cast(ubyte)(light_value[i] > 255 ? 255 : light_value[i]);
        });

        import std.format;
        writeln(cnt);
        write_map(map_data, format!"/tmp/result%06d.png"(cnt++));
    }
}
ulong cnt;