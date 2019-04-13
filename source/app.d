/+--------------------Copyright Notice------------------------+\
|      Copyright:                                              |
|  - AsumFace (asumface@gmail.com) 2018 - 2019                 |
|  Distributed under the Boost Software License, Version 1.0.  |
|  See accompanying file LICENSE or copy at                    |
|      https://www.boost.org/LICENSE_1_0.txt)                  |
\+------------------------------------------------------------+/

struct Point
{
    import cgfm.math;
    //float mass = 1.0;
    Vector!(long, 2) position;
    Vector!(double, 2) momentum;
    string toString()
    {
        import std.conv;
        return position[0].to!string;
    }

    auto opOpAssign(string op, T)(T rhs)
    {
        import std.algorithm.iteration : each;
        static if (is(T : typeof(this)))
        {
            mixin("position " ~ op ~ "= rhs.position;");
            mixin("momentum " ~ op ~ "= rhs.momentum;");
        }
        else
        {
            mixin("position.each!((ref n) => n " ~ op ~ "= rhs);");
            mixin("momentum.each!((ref n) => n " ~ op ~ "= rhs);");
        }
        return this;
    }

    auto opBinary(string op, T)(T rhs)
    {
        typeof(this) result;
        result.opOpAssign!(op, T)(rhs);
        return result;
    }
}

void main()
{
    import std.algorithm;
    import rtree;
    import std.random;
    import std.math;
    import cgfm.math;
    import std.stdio;
    import std.format;
    import core.thread;
    import std.datetime;
    import std.file;
    import std.range;
    Mt19937 gen;
    gen.seed(0);
    //finn;

    dirEntries("trees/", SpanMode.shallow, false).each!(std.file.remove);


    Point[] points = new Point[10000];
    Point[][4] rkPoints;
    Point[] assumePoints = new Point[10000];
    Point[] tmpPoints = new Point[10000];
    foreach (ref e; rkPoints)
        e = new Point[10000];

    //points[0].position = vec2l(int.max/2,0);
    //points[0].momentum = vec2d(0, 50_000_00);
    foreach (i, ref p; points)
    {
        p.position = vec2l(uniform!int(gen), uniform!int(gen));
        //p.mass = 1;
        p.momentum = vec2d(0,0);
    }

    import rk;

    ulong t = 0;

    File file = File(format!"trees/%08s.asy"(t++), "w");
    auto writer = file.lockingTextWriter;
    writer.formattedWrite!"settings.outformat=\"png\";\n";
    writer.formattedWrite!"unitsize(0.001mm);\nsize(20cm, 20cm, (-3e9,-3e9), (3e9, 3e9));\n";
    foreach (ref p; points)
    {
        writer.formattedWrite!"dot((%s, %s));\n"(p.position.x, p.position.y);
    }
    writer.formattedWrite!"clip(box((-3e9,-3e9), (3e9, 3e9)));\nfixedscaling((-3e9,-3e9), (3e9, 3e9));\n";
    file.close;

    import std.parallelism;
    void diffEq(Point[] input, Point[] output)
    {
        foreach (i; iota(0, input.length).parallel(64))
        {

            //writeln(input[i].momentum);
            output[i].position = vec2l(0,0);
            output[i].momentum = vec2f(0,0);
            output[i].position = cast(vec2l)input[i].momentum;
            foreach (ii; 0 .. input.length)
            {
                if (input[i].position == input[ii].position)
                    continue;
                auto relLocL = input[ii].position - input[i].position;
                auto relLocD = cast(vec2d)(relLocL);
                output[i].momentum +=
                    relLocD.normalized * max((10000.0/((relLocD*5.0/int.max).squaredMagnitude)
                                                - 1000.0/((relLocD*5.0/int.max).squaredMagnitude ^^ 2)), -10000000.0);
            }
            output[i].momentum -= input[i].momentum * 0.05;
        }
    }

    while (t < 2000)
    {
        //Thread.sleep(100.msecs);
        writeln(t);
        foreach (i; 0 .. rk4t.order)
            rkPoints[i][] = Point.init;
        foreach (i; 0 .. rk4t.order)
        {
            assumePoints[] = points[];
            foreach (ii; 0 .. rk4t.matrix[i][].length)
            {
                tmpPoints[] = rkPoints[ii][];
                tmpPoints[].each!((ref n) => n *= rk4t.matrix[i][ii]);
                assumePoints[] += tmpPoints[];
            }
            //writeln(assumePoints, rkPoints);
            diffEq(assumePoints[], rkPoints[i][]);
        }
        foreach (i; 0 .. rk4t.order)
        {
            //writeln(rkPoints, rk4t.weights[i]);
            rkPoints[i][].each!((ref n) => n *= rk4t.weights[i]);
            //writeln(rkPoints);

            points[] += rkPoints[i][];
        }

        file = File(format!"trees/%08s.asy"(t++), "w");
        writer = file.lockingTextWriter;
        writer.formattedWrite!"settings.outformat=\"png\";\n";
        writer.formattedWrite!"unitsize(0.001mm);\nsize(20cm, 20cm, (-3e9,-3e9), (3e9, 3e9));\n";
        foreach (ref p; points)
        {
            writer.formattedWrite!"dot((%s, %s));\n"(p.position.x, p.position.y);
        }
        writer.formattedWrite!"clip(box((-3e9,-3e9), (3e9, 3e9)));\nfixedscaling((-3e9,-3e9), (3e9, 3e9));\n";
        file.close;
    }
}

