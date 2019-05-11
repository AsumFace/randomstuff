/+--------------------Copyright Notice------------------------+\
|      Copyright:                                              |
|  - AsumFace (asumface@gmail.com) 2019                        |
|  Distributed under the Boost Software License, Version 1.0.  |
|  See accompanying file LICENSE or copy at                    |
|      https://www.boost.org/LICENSE_1_0.txt                   |
\+------------------------------------------------------------+/

module supersequence;

import required;
import std.traits;
import std.range : ElementType;

import std.experimental.allocator;
import std.experimental.allocator.gc_allocator;
import std.experimental.allocator.mallocator;
import core.exception : OutOfMemoryError;

T[] findSupersequence(T)(T[] arrs...)
{
    return findSupersequence(GCAllocator.instance, arrs);
}

struct Overlap(T)
{
    T a;
    T b;
    size_t bOffset;
    size_t worth;
}

Overlap!T calcOverlap(T)(T a, T b) @safe pure
{
    require(!a.empty && !b.empty, "a");
    Overlap!T result;
    size_t run = 0;
    while (true)
    {
        foreach (i; run .. a.length)
        {
            import std.range : zip;
            import std.algorithm.searching : all;
            import std.algorithm.comparison : min;
            if (a[i .. $].length < result.worth) // worth can't be further improved in this run
                break;
            if(zip(a[i .. $], b[]).all!"a[0] == a[1]")
            {
                immutable worth = min(b[].length, a[i .. $].length);
                result = typeof(return)(a, b, i, worth);
            }
        }
        import std.algorithm.mutation : swap;
        run += 1;
        if (run == 1)
            swap(a, b);
        else
            break;
    }
    return result;
}
unittest
{
    alias O = Overlap!dstring;
    dstring a = "abcdefg";
    dstring b = "cdefgh";
    auto ov = calcOverlap(a, b);
    assert(ov == O(a, b, 2, 5));
    dstring c = "abcabc";
    ov = calcOverlap(a, c);
    assert(ov == O(c, a, 3, 3));
    ov = calcOverlap(b, c);
    assert(ov == O(c, b, 5, 1));
    dstring d = "bc";
    ov = calcOverlap(d, c);
    assert(ov == O(c, d, 1, 2) || ov == O(c, d, 4, 2));
    ov = calcOverlap(d, b);
    assert(ov == O(d, b, 1, 1));
    dstring e = "Anna geht zu Anna";
    dstring f = "Anna kommt zu Anna";
    ov = calcOverlap(e, f);
    assert(ov == O(e, f, 13, 4) || ov == O(f, e, 14, 4));
}

private Overlap!T findBestPair(T)(const(T[]) arr) @safe
{
    import std.range : take, enumerate, drop;
    Overlap!T bestWorth;
    foreach (i, ref e1; arr[].take(arr[].length - 1).enumerate) // find best overlap
    {
        if (e1[].length <= bestWorth.worth) // no higher worth can be found in this loop
            break;
        foreach (ref e2; arr[].drop(i + 1))
        {
            if (e2[].length <= bestWorth.worth) // no higher worth can be found in this loop
                break;
            auto ov = calcOverlap(e1, e2);
            if (bestWorth.worth < ov.worth)
                bestWorth = ov;
        }
    }
    // if bestWorth has not been set by now, no overlaps exist
    return bestWorth;
}

private Unqual!(ElementType!T)[] iterativeMerging(T, UA, TA)(ref UA userAllocator, ref TA tmpAllocator, T[] tmp)
{
    import std.algorithm.comparison : max;
    import std.range : take, drop, enumerate, ElementType;
    import std.algorithm.mutation : copy, remove, bringToFront;
    import std.algorithm.sorting : multiSort, assumeSorted, isSorted, sort;
    import std.algorithm.searching : find;
    import std.algorithm.iteration : map, sum, joiner;
    import std.typecons : Tuple, Ternary;

    alias lengthPred = (a, b) => a[].length > b[].length;
    alias valuePred = (a, b) => a < b;

    tmp.multiSort!(lengthPred, valuePred);

    Overlap!T bestWorth;
    import std.stdio;
    writeln(tmp[]);
    while (true)
    {
        bestWorth = findBestPair(tmp[]); // find two sequences to merge
        if (bestWorth.worth == 0)
            break;
        writefln!"chosen to merge %s and %s"(bestWorth.a, bestWorth.b);
        with (bestWorth)
        {
            Unqual!(ElementType!T)[] mergedSequence =
                makeArray!(Unqual!(ElementType!T))(
                    tmpAllocator,
                    max(bOffset + b[].length,
                        a[].length));
            if (mergedSequence is null)
                throw new OutOfMemoryError;
            {
                auto rem = a[].copy(mergedSequence[]);
                rem = b[].drop(a[bOffset .. $].length).copy(rem);
                require(rem.empty);
                writefln!"merged to %s"(mergedSequence);
            }
            {
                size_t aLoc =
                    assumeSorted!((a, b) => lengthPred(a.value, b.value))(tmp[].enumerate)
                    .equalRange(Tuple!(ulong, "index", T, "value")(0, a))
                    .find!(n => n.value == a).front.index;
                tmp[].remove(aLoc);
                // the elements need to be removed separately to avoid indexing issues with duplicate elements
                size_t bLoc =
                    assumeSorted!((a, b) => lengthPred(a.value, b.value))(tmp[].enumerate)
                    .equalRange(Tuple!(ulong, "index", T, "value")(0, b))
                    .find!(n => n.value == b).front.index;
                tmp[].remove(bLoc);

                tmp = tmp[0 .. $ - 1]; // shorten range only by one…
                tmp[$ - 1] = cast(immutable)mergedSequence[]; // …so we can immediately reuse one slot
            }
            {
                auto right =
                    tmp[0 .. $ - 1]
                        .assumeSorted!((a, b) =>
                                       lengthPred(a, b) == lengthPred(b, a)
                                       ? valuePred(a, b)
                                       : lengthPred(a, b))
                        .upperBound(mergedSequence[]); // determine which elements should be on the right
                bringToFront(right, tmp[$ - 1 .. $]); // move element to its appropriate location
                require(tmp[].isSorted!((a, b) =>
                                        lengthPred(a, b) == lengthPred(b, a)
                                        ? valuePred(a, b)
                                        : lengthPred(a, b)));
            }
            if (tmpAllocator.owns(cast(Unqual!(ElementType!T)[])a[]) == Ternary.yes)
                dispose(tmpAllocator, cast(Unqual!(ElementType!T)[])a[]);
            if (tmpAllocator.owns(cast(Unqual!(ElementType!T)[])b[]) == Ternary.yes)
                dispose(tmpAllocator, cast(Unqual!(ElementType!T)[])b[]);
        }
        writeln(tmp[]);
    }
    require(!tmp[].empty);
    // concat all remaining sequences using user-provided-allocator allocated buffer, ideally that's just one sequence
    auto result = makeArray!(Unqual!(ElementType!T))(userAllocator, tmp[].map!(n => n[].length).sum);
    if (result is null)
        throw new OutOfMemoryError;
    tmp[].joiner.copy(result[]);
    return result;
}

auto findSupersequence(Allocator, T)(ref Allocator allocator, const(T[]) arrs...) @trusted
    if (isArray!T)
{
    import std.experimental.allocator.building_blocks.allocator_list;
    import std.experimental.allocator.building_blocks.bitmapped_block;

    T[] tmp = makeArray!(T)(Mallocator.instance, arrs);
    if (tmp is null)
        throw new OutOfMemoryError;
    const(T[]) baseArray = tmp[];


    alias allocatorFactory = (size_t size)
    {
        import std.math : nextPow2;
        import std.algorithm.comparison : max;
        return BitmappedBlock!(
            nextPow2(ElementType!T.sizeof * 16),
            platformAlignment,
            Mallocator)(
            max(ElementType!T.sizeof * 128, size));
    };
    auto tmpAllocator = AllocatorList!(allocatorFactory, Mallocator)();

    auto result = iterativeMerging!T(allocator, tmpAllocator, tmp);

    return result;
}
unittest
{
    import std.stdio;
    dstring[] arr = ["catgc"d, "ctaagt", "gcta", "ttca", "atgcatc"];

    auto result = findSupersequence(Mallocator.instance, arr);
    assert(result == "gctaagttcatgcatc"d);
}


