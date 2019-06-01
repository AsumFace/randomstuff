/+--------------------Copyright Notice------------------------+\
|      Copyright:                                              |
|  - AsumFace (asumface@gmail.com) 2018 - 2019                 |
|  Distributed under the Boost Software License, Version 1.0.  |
|  See accompanying file LICENSE or copy at                    |
|      https://www.boost.org/LICENSE_1_0.txt                   |
\+------------------------------------------------------------+/

pragma(msg, __VERSION__);

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

    enum Values : byte // values chosen to match ASCII as well as possible
    {
        A = 65,
        B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,
        n0 = 48,
        n1,n2,n3,n4,n5,n6,n7,n8,n9,
        dot = 46, comma = 44, colon = 58, semicolon = 59, question = 63, minus = 45, underscore = 95,
        parensOpen = 40, parensClose = 41, apostrope = 39, equals = 61, plus = 43, slash = 47, at = 64,
        ampersand = 38, dollar = 36, quote = 34, exclamation = 33, end = 4, error = 24, invite = 5,
        newPage = 12, ack = 6, wait = 19, space = 32, SOS = -1
    }

    import fnv;

    Values[][32] keys;
    ubyte[32] iTable;

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
