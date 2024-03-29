/**
  This module implements a generic axis-aligned bounding box (AABB).
 */
module cgfm.math.box;

import required;
import std.math,
       std.traits,
       std.conv,
       std.string;

import cgfm.math.vector,
       cgfm.math.funcs;

/// N-dimensional half-open interval [a, b[.
struct Box(T, int N)
{
    static assert(N > 0);

    public
    {
        alias Vector!(T, N) bound_t;

        bound_t min; // not enforced, the box can have negative volume
        bound_t max;

        /// Construct a box which extends between 2 points.
        /// Boundaries: min is inside the box, max is just outside.
        this(bound_t min_, bound_t max_) pure
        {
            min = min_;
            max = max_;
        }

        static if (N == 1)
        {
            this(T min_, T max_)
            {
                min.x = min_;
                max.x = max_;
            }
        }

        static if (N == 2)
        {
            this(T min_x, T min_y, T max_x, T max_y)
            {
                min = bound_t(min_x, min_y);
                max = bound_t(max_x, max_y);
            }
        }

        static if (N == 3)
        {
            this(T min_x, T min_y, T min_z, T max_x, T max_y, T max_z)
            {
                min = bound_t(min_x, min_y, min_z);
                max = bound_t(max_x, max_y, max_z);
            }
        }


        @property
        {
            /// Returns: Dimensions of the box.
            bound_t size() const pure
            {
                return max - min;
            }

            /// Returns: Center of the box.
            bound_t center() const pure
            {
                return (min + max) / 2;
            }

            /// Returns: Width of the box, always applicable.
            static if (N >= 1)
            T width() const @property pure
            {
                return max.x - min.x;
            }

            /// Returns: Height of the box, if applicable.
            static if (N >= 2)
            T height() const @property pure
            {
                return max.y - min.y;
            }

            /// Returns: Depth of the box, if applicable.
            static if (N >= 3)
            T depth() const @property pure
            {
                return max.z - min.z;
            }

            /// Returns: Signed volume of the box.
            T volume() const pure
            {
                T res = 1;
                bound_t size = size();
                for(int i = 0; i < N; ++i)
                    res *= size[i];
                return res;
            }

            /// Returns: true if empty.
            bool empty() const pure
            {
                bound_t size = size();
                mixin(generateLoopCode!("if (min[@] == max[@]) return true;", N)());
                return false;
            }
        }

        /// Returns: true if it contains point.
        bool contains(bound_t point) const pure
        {
            require(isSorted());
            for(int i = 0; i < N; ++i)
                if ( !(point[i] >= min[i] && point[i] < max[i]) )
                    return false;

            return true;
        }

        /// Returns: true if it contains box other.
        bool contains(Box other) const pure
        {
            require(isSorted());
            require(other.isSorted());

            mixin(generateLoopCode!("if ( (other.min[@] < min[@]) || (other.max[@] > max[@]) ) return false;", N)());
            return true;
        }

        /// Euclidean squared distance from a point.
        /// See_also: Numerical Recipes Third Edition (2007)
        real squaredDistance(bound_t point) const pure
        {
            require(isSorted());
            real distanceSquared = 0;
            for (int i = 0; i < N; ++i)
            {
                if (point[i] < min[i])
                    distanceSquared += (point[i] - min[i]) ^^ 2;

                if (point[i] > max[i])
                    distanceSquared += (point[i] - max[i]) ^^ 2;
            }
            return distanceSquared;
        }

        /// Euclidean distance from a point.
        /// See_also: squaredDistance.
        real distance(bound_t point) const pure
        {
            return sqrt(squaredDistance(point));
        }

        /// Euclidean squared distance from another box.
        /// See_also: Numerical Recipes Third Edition (2007)
        real squaredDistance(Box o) const pure
        {
            require(isSorted());
            require(o.isSorted());
            real distanceSquared = 0;
            for (int i = 0; i < N; ++i)
            {
                if (o.max[i] < min[i])
                    distanceSquared += (o.max[i] - min[i]) ^^ 2;

                if (o.min[i] > max[i])
                    distanceSquared += (o.min[i] - max[i]) ^^ 2;
            }
            return distanceSquared;
        }

        /// Euclidean distance from another box.
        /// See_also: squaredDistance.
        real distance(Box o) const pure
        {
            return sqrt(squaredDistance(o));
        }

        /// Assumes sorted boxes.
        /// This function deals with empty boxes correctly.
        /// Returns: Intersection of two boxes.
        Box intersection(Box o) const pure
        {
            require(isSorted());
            require(o.isSorted());

            // Return an empty box if one of the boxes is empty
            if (empty())
                return this;

            if (o.empty())
                return o;

            Box result = void;
            for (int i = 0; i < N; ++i)
            {
                T maxOfMins = (min.v[i] > o.min.v[i]) ? min.v[i] : o.min.v[i];
                T minOfMaxs = (max.v[i] < o.max.v[i]) ? max.v[i] : o.max.v[i];
                result.min.v[i] = maxOfMins;
                result.max.v[i] = minOfMaxs >= maxOfMins ? minOfMaxs : maxOfMins;
            }
            return result;
        }

        /// Assumes sorted boxes.
        /// This function deals with empty boxes correctly.
        /// Returns: Intersection of two boxes.
        bool intersects(Box other) const pure
        {
            Box inter = this.intersection(other);
            return inter.isSorted() && !inter.empty();
        }

        /// Extends the area of this Box.
        Box grow(bound_t space) const pure
        {
            Box res = this;
            res.min -= space;
            res.max += space;
            return res;
        }

        /// Shrink the area of this Box. The box might became unsorted.
        Box shrink(bound_t space) const pure
        {
            return grow(-space);
        }

        /// Extends the area of this Box.
        Box grow(T space) const pure
        {
            return grow(bound_t(space));
        }

        /// Translate this Box.
        Box translate(bound_t offset) const pure
        {
            return Box(min + offset, max + offset);
        }

        /// Shrinks the area of this Box.
        /// Returns: Shrinked box.
        Box shrink(T space) const pure
        {
            return shrink(bound_t(space));
        }

        /// Expands the box to include point.
        /// Returns: Expanded box.
        Box expand(bound_t point) const pure
        {
            import cgfm.math.vector;
            import std.range : lockstep;
            Box result;
            result.min = minByElem(min, point);

            foreach (i; 0 .. N) // lockstep works but isn't pure
            {
                if (point[i] >= max[i])
                {
                    import std.traits;
                    static if (isFloatingPoint!T)
                    {
                        import std.math : nextUp;
                        result.max[i] = point[i].nextUp;
                    }
                    else
                        result.max[i] = point[i] + 1;
                }
                else
                    result.max[i] = max[i];
            }
            return result;
        }

        /// Expands the box to include another box.
        /// This function deals with empty boxes correctly.
        /// Returns: Expanded box.
        Box expand(Box other) const pure
        {
            require(isSorted());
            require(other.isSorted());

            // handle empty boxes
            if (empty())
                return other;
            if (other.empty())
                return this;

            Box result = void;
            for (int i = 0; i < N; ++i)
            {
                T minOfMins = (min.v[i] < other.min.v[i]) ? min.v[i] : other.min.v[i];
                T maxOfMaxs = (max.v[i] > other.max.v[i]) ? max.v[i] : other.max.v[i];
                result.min.v[i] = minOfMins;
                result.max.v[i] = maxOfMaxs;
            }
            return result;
        }

        /// Returns: true if each dimension of the box is >= 0.
        bool isSorted() const pure
        {
            for(int i = 0; i < N; ++i)
            {
                if (min[i] > max[i])
                    return false;
            }
            return true;
        }

        /// Assign with another box.
        ref Box opAssign(U)(U x) pure if (isBox!U)
        {
            static if(is(U.element_t : T))
            {
                static if(U._size == _size)
                {
                    min = x.min;
                    max = x.max;
                }
                else
                {
                    static assert(false, "no conversion between boxes with different dimensions");
                }
            }
            else
            {
                static assert(false, "no conversion from " ~ U.element_t.stringof ~ " to " ~ element_t.stringof);
            }
            return this;
        }

        /// Returns: true if comparing equal boxes.
        bool opEquals(U)(U other) const pure if (is(U : Box))
        {
            return (min == other.min) && (max == other.max);
        }

        /// Cast to other box types.
        U opCast(U)() const pure if (isBox!U)
        {
            U b = void;
            for(int i = 0; i < N; ++i)
            {
                b.min[i] = cast(U.element_t)(min[i]);
                b.max[i] = cast(U.element_t)(max[i]);
            }
            return b; // return a box where each element has been casted
        }

        static if (N == 2)
        {
            /// Helper function to create rectangle with a given point, width and height.
            static Box rectangle(T x, T y, T width, T height)
            {
                return Box(x, y, x + width, y + height);
            }
        }
    }

    private
    {
        enum _size = N;
        alias T element_t;
    }
}

/// Instanciate to use a 2D box.
template box2(T)
{
    alias Box!(T, 2) box2;
}

/// Instanciate to use a 3D box.
template box3(T)
{
    alias Box!(T, 3) box3;
}


alias box2!int box2i; /// 2D box with integer coordinates.
alias box3!int box3i; /// 3D box with integer coordinates.
alias box2!float box2f; /// 2D box with float coordinates.
alias box3!float box3f; /// 3D box with float coordinates.
alias box2!double box2d; /// 2D box with double coordinates.
alias box3!double box3d; /// 3D box with double coordinates.

unittest
{
    box2i a = box2i(1, 2, 3, 4);
    assert(a.width == 2);
    assert(a.height == 2);
    assert(a.volume == 4);
    box2i b = box2i(vec2i(1, 2), vec2i(3, 4));
    assert(a == b);

    box2f bf = cast(box2f)b;
    assert(bf == box2f(1.0f, 2.0f, 3.0f, 4.0f));

    box2i c = box2i(0, 0, 1,1);
    assert(c.translate(vec2i(3, 3)) == box2i(3, 3, 4, 4));
    assert(c.contains(vec2i(0, 0)));
    assert(!c.contains(vec2i(1, 1)));
    assert(b.contains(b));
    box2i d = c.expand(vec2i(3, 3));
    assert(d.contains(vec2i(2, 2)));

    assert(d == d.expand(d));

    assert(!box2i(0, 0, 4, 4).contains(box2i(2, 2, 6, 6)));

    assert(box2f(0, 0, 0, 0).empty());
    assert(!box2f(0, 2, 1, 1).empty());
    assert(!box2f(0, 0, 1, 1).empty());

    assert(box2i(260, 100, 360, 200).intersection(box2i(100, 100, 200, 200)).empty());

    // union with empty box is identity
    assert(a.expand(box2i(10, 4, 10, 6)) == a);

    // intersection with empty box is empty
    assert(a.intersection(box2i(10, 4, 10, 6)).empty);

    assert(box2i.rectangle(1, 2, 3, 4) == box2i(1, 2, 4, 6));
}

/// True if `T` is a kind of Box
enum isBox(T) = is(T : Box!U, U...);

unittest
{
    static assert( isBox!box2f);
    static assert( isBox!box3d);
    static assert( isBox!(Box!(real, 2)));
    static assert(!isBox!vec2f);
}

/// Get the numeric type used to measure a box's dimensions.
alias DimensionType(T : Box!U, U...) = U[0];

///
unittest
{
    static assert(is(DimensionType!box2f == float));
    static assert(is(DimensionType!box3d == double));
}

private
{
    static string generateLoopCode(string formatString, int N)()
    {
        string result;
        for (int i = 0; i < N; ++i)
        {
            string index = ctIntToString(i);
            // replace all @ by indices
            result ~= formatString.replace("@", index);
        }
        return result;
    }

    // Speed-up CTFE conversions
    static string ctIntToString(int n)
    {
        static immutable string[16] table = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"];
        if (n < 10)
            return table[n];
        else
            return to!string(n);
    }
}
