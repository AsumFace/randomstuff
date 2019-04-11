/+--------------------Copyright Notice------------------------+\
|      Copyright:                                              |
|  - AsumFace (asumface@gmail.com) 2019                        |
|  Distributed under the Boost Software License, Version 1.0.  |
|  See accompanying file LICENSE or copy at                    |
|      https://www.boost.org/LICENSE_1_0.txt)                  |
\+------------------------------------------------------------+/

module sqbox;


import required;

import cgfm.math.box;
import cgfm.math.vector;
//import cgfm.math.funcs;

/// N-dimenional cube
struct SqBox(T, int N)
{
    static assert(N > 0, "SqBox cannot have no or negative dimensions!");

    alias Coordinate = Vector!(T, N);

    Coordinate center;
    T radius;

    this(return ref inout(typeof(this)) rhs)
    {}

    this(Coordinate center, T radius)
    {
        this.center = center;
        this.radius = radius;
    }

    T width() const @property
    {
        return radius * 2;
    }

    alias height = width;
    alias depth = width;

    T volume() const @property
    {
        return width ^^ N;
    }

    bool empty() const
    {
        return radius == 0;
    }

    auto size() const
    {
        alias Dimensions = Coordinate;
        Dimensions result;
        foreach (ref e; result)
            e = radius * 2;
        return result;
    }

    // point on the outline are considered to be outside
    bool contains(Coordinate arg) const
    {
        auto delta = center - arg;
        foreach (v; delta[])
        {
            import std.math : abs;
            if (abs(v) >= radius)
                return false;
        }
        return true;
    }

    // a non-empty box contains itself
    bool contains(typeof(this) arg) const
    {
        import std.math : abs;
        import std.algorithm : maxElement, map;
        if (empty || arg.empty)
            return false;
        if (!contains(arg.center))
            return false;
        auto maxMag = (center - arg.center)[].map!abs.maxElement;
        if (maxMag + arg.radius <= radius)
            return true;
        else
            return false;
    }

    Box!(T, N) intersection(typeof(this) arg) const
    {
        if (empty || arg.empty)
            return typeof(return).init;

        return toBox.intersection(arg.toBox);
    }

    Box!(T, N) toBox() const
    {
        import std.range : lockstep;
        typeof(return) result;
        foreach (c, ref mi, ref ma; lockstep(center[], result.min[], result.max[]))
        {
            mi = (c - radius).prev;
            ma = c + radius;
        }
        return result;
    }

    typeof(this) translate(Coordinate offset) const
    {
        return typeof(return)(center + offset, radius);
    }


    typeof(this) expand(Coordinate point) const
    {
        import std.algorithm.searching : maxElement;
        if (contains(point))
            return this;
        auto box = toBox.expand(point);
        auto result = typeof(return)(this);
        result.center = box.center;
        result.radius = (box.max - result.center)[].maxElement.next;
        require(result.contains(point));
        require(result.contains(this));
        return result;
    }

    typeof(this) expand(typeof(this) arg) const
    {
        import std.algorithm.searching : maxElement;
        if (empty)
            return arg;
        if (arg.empty)
            return this;
        if (contains(arg))
            return this;
        auto box = toBox.expand(arg.toBox);
        auto result = typeof(return)(this);
        result.center = box.center;
        result.radius = (box.max - result.center)[].maxElement.next;
        require(result.contains(arg));
        require(result.contains(this));
        return result;
    }
}

private auto next(T)(T arg)
{
    import std.math : nextUp;
    static if (__traits(compiles, arg.nextUp))
        return arg.nextUp;
    else
        return arg + 1;
}

private auto prev(T)(T arg)
{
    import std.math : nextDown;
    static if (__traits(compiles, arg.nextDown))
        return arg.nextDown;
    else
        return arg - 1;
}

