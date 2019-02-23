struct Point
{
    import gfm.math;
    size_t id;
    double mass = 1.0;
    Vector!(double, 2)[5] position;
    Vector!(double, 2)[5] momentum;
    string toString()
    {
        import std.conv;
        return position[0].to!string;
    }
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
    import std.format;
    import core.thread;
    import std.datetime;
    Mt19937 gen;
    gen.seed(0);

/+
    Point[] points = new Point[1_000];
    RTree!(Point, (ref Point p) => Box!(double, 2)(p.position[0].x, p.position[0].y,
                                                p.position[0].x.nextUp, p.position[0].y.nextUp),
           2, 6, 3, double) tree;
    tree.initialize;

    foreach (i, ref p; points)
    {
        p.position[] = vec2d(uniform01(gen)+1, uniform01(gen)+1);
//        writeln(p.position);
        p.id = i;
        p.mass = 1;
l        p.momentum[] = vec2d(0.0, 0.0);
        writefln!"INSERT %s"(i);
        tree.insert(p);
        auto file = File(format!"trees/tree%06s.asy"(i), "w");
        auto file2 = File(format!"trees/tree%06s.dot"(i), "w");
        auto writer = file.lockingTextWriter;
        auto writer2 = file2.lockingTextWriter;
        assert(i + 1 == tree.drawTree(writer, writer2));
        file.close;
        file2.close;
    }
+/}
