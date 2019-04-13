module rk;

struct ButcherTableau(T, T[][] _coeffs)
{
    import std.range : frontTransversal, drop;
    import std.array : array;
    import std.algorithm.iteration : map;
    enum order = _coeffs[].length - 1;
    alias coeffs = _coeffs;
    enum weights = coeffs[$ - 1];
    enum steps = coeffs[0 .. order].frontTransversal.array;
    enum matrix = coeffs[0 .. order].array.map!("a.drop(1).array").array; // string as workaround for issue #17547
}

import std.traits;
auto step(BT, alias diffEq, T)(partT val, T time, T timStep)
    if (isInstanceOf!(ButcherTableau, BT))
{
    import std.algorithm.iteration : fold;
    import std.range : zip;
    T[BT.order] results;
    static foreach (i; 0 .. BT.order)
    {{
        import std.algorithm.iteration : map;
        import std.range : take;

        T assumeVal = zip(results[], BT.matrix[i][]).fold!"a + b[0] * b[1]"(val);
        /+T[BT.order] mulTable;
        mulTable[] = 0.0;
        static foreach (ii; 0 .. BT.matrix[i][].length)
        {
            mulTable[ii] = BT.matrix[i][ii] * results[ii];
        }
        T assumeVal = mulTable[].take(i).fold!"a + b"(val);
        +/results[i] = diffEq(assumeVal, time + BT.steps[i] * timStep) * timStep;
    }}
    results[] *= BT.weights[];
    import std.algorithm.iteration : fold;
    return results[].fold!"a + b";
}

alias rk4t = ButcherTableau!(double,
[[0.0],
 [0.5, 0.5],
 [0.5, 0.0,   0.5],
 [1.0, 0.0,   0.0,   1.0],
      [1.0/6, 1.0/3, 1.0/3, 1.0/6]]);

alias rk38t = ButcherTableau!(double,
[[0.0],
 [1.0/3,  1.0/3],
 [2.0/3, -1.0/3,  1.0],
 [1.0,    1.0,   -1.0,   1.0],
         [1.0/8,  3.0/8, 3.0/8, 1.0/8]]);
