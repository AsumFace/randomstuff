struct Point
{
    import gfm.math;
    immutable double mass = 1.0;
    Vector!(double, 2)[5] position;
    Vector!(double, 2)[5] momentum;
}

void step(RTree)(Point* point, const(RTree) tree)
{
    
}

void main()
{
    import std.algorithm;
    import rtree;
    import std.random;
    import std.math;
    import gfm.math;
    import std.stdio;
    Point[] points = new Point[1_000];
    RTree!(Point, (Point* p) => Box!(double, 2)(p.position[0].x, p.position[0].y,
                                                p.position[0].x.nextUp, p.position[0].y.nextUp),
           2, 16, 4, double) tree;
    tree.initialize;

    foreach (ref p; points)
    {
        p.position[] = vec2d(uniform01, uniform01);
        p.momentum[] = vec2d(0.0, 0.0);
        tree.insert(&p);
    }

    
}
