/+--------------------Copyright Notice------------------------+\
|      Copyright:                                              |
|  - AsumFace (asumface@gmail.com) 2018 - 2019                 |
|  Distributed under the Boost Software License, Version 1.0.  |
|  See accompanying file LICENSE or copy at                    |
|      https://www.boost.org/LICENSE_1_0.txt                   |
\+------------------------------------------------------------+/

struct Point
{
    import cgfm.math;
    //float mass = 1.0;
    Vector!(long, 2) position;
    Vector!(double, 2) momentum;
    Colors polarity;
    string toString()
    {
        import std.format;
        return format!"%s %s %s %s"(position.x, position.y, momentum.x, momentum.y);
    }

    ref typeof(this) opOpAssign(string op, T)(T rhs)
    {
        import std.algorithm.iteration : each;
        static if (is(T : typeof(this)))
        {
            mixin("position " ~ op ~ "= rhs.position;");
            mixin("momentum " ~ op ~ "= rhs.momentum;");
        }
        else
        {
            mixin("position.v[].each!((ref n) => n " ~ op ~ "= rhs);");
            mixin("momentum.v[].each!((ref n) => n " ~ op ~ "= rhs);");
        }
        return this;
    }

    auto opBinary(string op, T)(T rhs)
    {
        typeof(this) result = this;
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


    Point[] points = new Point[200];
    Point[] rkPoints = new Point[200];
    Point[] assumePoints = new Point[200];
    Point[] tmpPoints = new Point[200];

    import xxhash;

    char[] da = "12345678123456781234567812345678e".dup;

    writefln!"%16x"(xxHash!64(*(cast(ubyte[]*)&da)));
    da = "12345678".dup;

    writefln!"%16x"(xxHash!64(*(cast(ubyte[]*)&da)));

    /+foreach (i, ref p; points)
    {
        import std.complex;
        final switch (i % 4)
        {
        case 0:
            p.polarity = Colors.orange;
            break;
        case 1:
            p.polarity = Colors.blue;
            break;
        case 2:
            p.polarity = Colors.purple;
            break;
        case 3:
            p.polarity = Colors.green;
            break;
        }
        p.position = vec2l(uniform!int(gen), uniform!int(gen));
        p.momentum = vec2d(0, 0);
    }

    import rk;

    ulong t = 0;

    File file = File(format!"trees/%08s.svg"(t++), "w");
    auto writer = file.lockingTextWriter;
    writer.writeSVGHeader;
    foreach (i, ref p; points)
    {
        writer.writeDot(i, p, 5.0);
    }
    writer.writeSVGFooter;
    file.close;

    import std.parallelism;
    void diffEq(const(Point[]) input, Point[] output, const(double) t)
    {
        foreach (i; iota(0, input.length).parallel(12))
        {

            //writeln(input[i].momentum);
            output[i].position = vec2l(0,0);
            output[i].momentum = vec2f(0,0);
            output[i].position = cast(vec2l)(input[i].momentum * t) * 5;

            foreach (ii; 0 .. input.length)
            {
                if (input[i].position == input[ii].position)
                    continue;
                auto relLocL = input[ii].position - input[i].position;
                auto relLocD = cast(vec2d)(relLocL);
                output[i].polarity = input[i].polarity;

                if (relLocD.squaredMagnitude < (20e6^^2.0))
                {
                    output[i].momentum -= relLocD.normalized * 2.5e-8 * (20e6^^2 - relLocD.squaredMagnitude);
                }
                else if (force(input[i].polarity, input[ii].polarity) == 1) // attraction
                {
                    output[i].momentum +=
                        relLocD.normalized * 31e19 / max(relLocD.squaredMagnitude, 1e15);
                }
                else if (force(input[i].polarity, input[ii].polarity) == -1) // repulsion
                {
                    output[i].polarity = input[i].polarity;
                    output[i].momentum -=
                        relLocD.normalized * 60e19 / max(relLocD.squaredMagnitude, 1e15);
                }
            }
            output[i].momentum -= input[i].momentum * 0.05;
        }
    }

    while (t < 20000)
    {
        writeln(t);

        assumePoints[] = points[];
        diffEq(assumePoints[], tmpPoints[], 0.0);
        foreach (i; 0 .. points[].length) // 1st
        {
            rkPoints[i] = tmpPoints[i] * 1.0/6.0;
            assumePoints[i] = points[i] + tmpPoints[i] * 0.5;
        }
        diffEq(assumePoints[], tmpPoints[], 0.5);
        foreach (i; 0 .. points[].length) // 2nd
        {
            rkPoints[i] += tmpPoints[i] * 1.0/3.0;
            assumePoints[i] = points[i] + tmpPoints[i] * 0.5;
        }
        diffEq(assumePoints[], tmpPoints[], 0.5);
        foreach (i; 0 .. points[].length) // 3rd
        {
            rkPoints[i] += tmpPoints[i] * 1.0/3.0;
            assumePoints[i] = points[i] + tmpPoints[i] * 1.0;
        }
        diffEq(assumePoints[], tmpPoints[], 1.0);
        foreach (i; 0 .. points[].length) // 4th
        {
            rkPoints[i] += tmpPoints[i] * 1.0/6.0;
        }
        points[] += rkPoints[];

        file = File(format!"trees/%08s.svg"(t++), "w");
        writer = file.lockingTextWriter;
        writer.writeSVGHeader;
        foreach (i, ref p; points)
        {
            writer.writeDot(i, p, 5.0);
        }
        writer.writeSVGFooter;
        file.close;
    }+/
}

void writeSVGHeader(W)(W w)
{
    import std.format;

    w.formattedWrite!`<?xml version="1.0" encoding="UTF-8" standalone="no"?>
    <svg
       xmlns:dc="http://purl.org/dc/elements/1.1/"
       xmlns:cc="http://creativecommons.org/ns#"
       xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
       xmlns:svg="http://www.w3.org/2000/svg"
       xmlns="http://www.w3.org/2000/svg"
       id="svg8"
       version="1.1"
       viewBox="-1000 -1000 2000 2000"
       height="1000"
       width="1000">
      <defs
         id="defs2" />
      <metadata
         id="metadata5">
        <rdf:RDF>
          <cc:Work
             rdf:about="">
            <dc:format>image/svg+xml</dc:format>
            <dc:type
               rdf:resource="http://purl.org/dc/dcmitype/StillImage" />
            <dc:title></dc:title>
          </cc:Work>
        </rdf:RDF>
      </metadata>
      <g
         transform="translate(0,0)"
         id="layer1">
      <rect x="-1000" y="-1000" width="200%%" height="200%%" fill="white"/>`;
}

int force(Colors a, Colors o)
{
    if (a == o)
        return -1;
    with (Colors)
    {
        if (a == blue && (o == orange || o == green))
        {
            return 1;
        }
        if (a == orange && (o == purple || o == blue))
        {
            return 1;
        }
        if (a == purple && (o == green || o == orange))
        {
            return 1;
        }
        if (a == green && (o == blue || o == purple))
        {
            return 1;
        }
    }
    return 0;
}

enum Colors : string
{
    blue = "#0078ff",
    orange = "#fd6600",
    purple = "#9d00ff",
    green = "#99ff00"
}

void writeDot(W)(W w, size_t id, Point point, double radius)
{
    import std.format;

    w.formattedWrite!`
    <circle
    r="%s"
    cy="%s"
    cx="%s"
    id="path%s"
    style="opacity:1;fill:%(%c%);fill-opacity:1;fill-rule:nonzero;stroke:#000000;stroke-width:1.0;stroke-miterlimit:4;stroke-dasharray:none;stroke-opacity:1;paint-order:markers fill stroke" />`(radius, point.position.x/(cast(double)(int.max/1000)), point.position.y/(cast(double)(int.max/1000)), id, point.polarity);
}

void writeSVGFooter(W)(W w)
{
    import std.format;

    w.formattedWrite!`
    </g>
    </svg>`;
}
