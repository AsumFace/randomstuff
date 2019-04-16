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


    Point[] points = new Point[1000];
    Point[][4] rkPoints;
    Point[] assumePoints = new Point[1000];
    Point[] tmpPoints = new Point[1000];
    foreach (ref e; rkPoints)
        e = new Point[1000];

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

    File file = File(format!"trees/%08s.svg"(t++), "w");
    auto writer = file.lockingTextWriter;
    writer.writeSVGHeader;
    foreach (i, ref p; points)
    {
        writer.writeDot(i, p, i < 500 ? Colors.orange : Colors.blue);
    }
    writer.writeSVGFooter;
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
            bool tcol = false;
            bool ocol = false;
            if (i < 500)
                tcol = true;
            else
                tcol = false;
            foreach (ii; 0 .. input.length)
            {
                if (ii < 500)
                    ocol = true;
                else
                    ocol = false;
                if (input[i].position == input[ii].position)
                    continue;
                auto relLocL = input[ii].position - input[i].position;
                auto relLocD = cast(vec2d)(relLocL);
                if (tcol != ocol) // attraction
                {
                    output[i].momentum +=
                        relLocD.normalized * max((10000.0/((relLocD*9.0/int.max).squaredMagnitude)
                                                - 10000.0/((relLocD*9.0/int.max).squaredMagnitude ^^ 2)), -10000000.0);
                }
                else // repulsion
                {
                    output[i].momentum +=
                        relLocD.normalized * max(-5000.0/((relLocD*9.0/int.max).squaredMagnitude), -10000000.0);
                }
            }
            output[i].momentum -= input[i].momentum * 0.001;
        }
    }

    while (t < 16000)
    {
        //Thread.sleep(100.msecs);
        writeln(t);
        foreach (i; 0 .. rk4t.order)
            rkPoints[i][] = Point.init;
        static foreach (i; 0 .. rk4t.order)
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

        file = File(format!"trees/%08s.svg"(t++), "w");
        writer = file.lockingTextWriter;
        writer.writeSVGHeader;
        foreach (i, ref p; points)
        {
            writer.writeDot(i, p, i < 500 ? Colors.orange : Colors.blue);
        }
        writer.writeSVGFooter;
        file.close;
    }
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

enum Colors
{
    blue = "#0078ff",
    gray = "#424242",
    orange = "#fd6600"
}

void writeDot(W)(W w, size_t id, Point point, Colors color)
{
    import std.format;

    w.formattedWrite!`
    <circle
    r="3.0"
    cy="%s"
    cx="%s"
    id="path%s"
    style="opacity:1;fill:%(%c%);fill-opacity:1;fill-rule:nonzero;stroke:#000000;stroke-width:1.0;stroke-miterlimit:4;stroke-dasharray:none;stroke-opacity:1;paint-order:markers fill stroke" />`(point.position.x/(cast(double)(int.max/1000)), point.position.y/(cast(double)(int.max/1000)), id, color);
}

void writeSVGFooter(W)(W w)
{
    import std.format;

    w.formattedWrite!`
    </g>
    </svg>`;
}
