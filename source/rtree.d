module rtree;

version(LittleEndian)
{}
else
{
    static assert(0, "support for non-little endian platforms has not been confirmed/implemented yet");
}

class AllocationFailure : Exception
{
    import std.exception;
    mixin basicExceptionCtors;
}

import required;
import cgfm.math;
import stack;
import std.traits;
import std.experimental.allocator.common;
import std.experimental.allocator.building_blocks.allocator_list;
import std.experimental.allocator.building_blocks.bitmapped_block;
import std.experimental.allocator.mallocator;
import std.experimental.allocator;

/**
A range to search for matching elements within an `RTree`. `ref` access is provided in order to be able to change
element data, however the bounding box must never increase in size, a decrease is tolerable but might result in a
suboptimal tree structure. In general, a removal and reinsertion is to be preferred if the bounds may change.
The range can either accept dynamically exchangable, or static predicate callables. If a second parameter is accepted,
it shall have the type of a common data storage type, such as a `Tuple`. This auxiliary data is returned by `front` as
part of a `Tuple` and is meant to make basic data exchange between the predicates and the range interface possible.
*/
private struct RTreeRange(RTree, bool dynamic, A...)

{
    // *BLING* *BLING* useful error messages!
    static assert(A.length == 2, "wrong number of template arguments (need 4, got " ~ (A.length + 2).stringof ~ ")");
    static assert(isCallable!(A[0]), A[0].stringof ~ " is not a callable");
    static assert(isCallable!(A[1]), A[1].stringof ~ " is not a callable");
    static assert(arity!(A[0]) == 1 || arity!(A[1]) == 2, A[0].stringof
                  ~ " takes wrong number of arguments (must take 1 or 2, takes " ~ arity!(A[0]).stringof ~ ")");
    static assert(arity!(A[1]) == 1 || arity!(A[1]) == 2, A[1].stringof
                  ~ " takes wrong number of arguments (must take 1 or 2, takes " ~ arity!(A[1]).stringof ~ ")");
    static assert(is(Parameters!(A[0])[0] : RTree.BoxType),
                  A[0].stringof ~ " doesn't accept " ~ RTree.BoxType.stringof);
    static assert(is(Parameters!(A[1])[0] : RTree.ElementType),
                  A[1].stringof ~ " doesn't accept " ~ RTree.ElementType.stringof);
    static assert(is(ReturnType!(A[0]) : bool), A[0].stringof ~ " doesn't return a bool compatible type");
    static assert(is(ReturnType!(A[1]) : bool), A[1].stringof ~ " doesn't return a bool compatible type");

    static if (arity!(A[0]) == 2 || arity!(A[1]) == 2) // provide auxiliary storage
    {
        static if ((arity!(A[0]) == 2 && arity!(A[1]) == 2))
        {
            import std.algorithm.comparison : among;
            static assert (is(Parameters!(A[0])[1] == Parameters!(A[1])[1]),
                           "second parameters of predicates don't take the same type");
            static if (is(A[0] == struct) || is(A[0] == class) || is(A[0] == interface))
                static assert (among("ref", __traits(getParameterStorageClasses, A[0].opCall, 1)),
                               "second parameter of " ~ A[0].stringof ~ " isn't ref");
            else
                static assert (__traits(getParameterStorageClasses, A[0], 1).any("ref"),
                               "second parameter of " ~ A[0].stringof ~ " isn't ref");
            static if (is(A[1] == struct) || is(A[1] == class) || is(A[1] == interface))
                static assert (among("ref", __traits(getParameterStorageClasses, A[1].opCall, 1)),
                               "second parameter of " ~ A[1].stringof ~ " isn't ref");
            else
                static assert (__traits(getParameterStorageClasses, A[1], 1).any("ref"),
                               "second parameter of " ~ A[1].stringof ~ " isn't ref");
        }
        static if (arity!(A[0]) == 2)
            alias AuxDataType = Parameters!(A[0])[1];
        else static if (arity!(A[1]) == 2)
            alias AuxDataType = Parameters!(A[1])[1];

        AuxDataType aux;
    }

    alias ReferenceType = RTree.ReferenceType;
    alias ElementType = RTree.ElementType;
    alias BoxType = RTree.BoxType;
    alias SeT = Tuple!(ReferenceType, "nd", size_t, "skip");
    private Stack!SeT vs;
    private ElementType* _front;

    ~this()
    {
        destroy;
    }

    void destroy()
    {
        vs.destroy;
    }

    static if (dynamic)
    {
        A[0] shouldEnterBox;
        A[1] matchesPattern;

        this(RTree tree, A[0] a, A[1] b)
        {
            vs = Stack!SeT(8);
            vs.pushFront(SeT(ReferenceType(*tree.rootPtr), 0));
            shouldEnterBox = a;
            matchesPattern = b;
            _popFront;
        }
    }
    else
    {
        //static assert(__traits(compiles, A[0](RTree.BoxType.init)));
        //auto see = (){ElementType n; A[1](n);}();
        //static assert(__traits(compiles, (){ElementType n; A[1](n);}()));
        alias shouldEnterBox = A[0];
        alias matchesPattern = A[1];

        this(RTree tree)
        {
            vs = Stack!SeT(8);
            vs.pushFront(SeT(ReferenceType(*tree.rootPtr), 0));
            _popFront;
        }
    }

    void popFront()
    {
        require(_front !is null);
        _popFront;
    }
    private void _popFront()
    {
        import std.algorithm.searching : countUntil;
        while (!vs.empty)
        {
            if (vs.front.nd.type == ReferenceType.Types.leaf)
            {
                static if (arity!(A[1]) == 1)
                    alias pm = (ref ElementType n) => matchesPattern(n);
                else
                    alias pm = (ref ElementType n) => matchesPattern(n, aux);
                auto c = vs.front.nd.leaf[].drop(vs.front.skip).countUntil!pm;
                if (c == -1) // no matching elements left in leaf
                {
                    vs.popFront;
                    continue;
                }
                auto index = vs.front.skip + c;
                _front = &(vs.front.nd.leaf[index]);
                vs.front.skip += c + 1;
                if (vs.front.skip >= RTree.maxChildrenPerNode)
                    vs.popFront;
                return;
            }
            else
            {
                static if (arity!(A[0]) == 1)
                    alias sb = (ref ReferenceType n) => shouldEnterBox(n.box);
                else
                    alias sb = (ref ReferenceType n) => shouldEnterBox(n.box, aux);
                auto c = vs.front.nd.node[].drop(vs.front.skip).countUntil!sb;
                if (c == -1) // no boxes to enter left in node
                {
                    vs.popFront;
                    continue;
                }
                auto index = vs.front.skip + c;
                auto selectedRef = vs.front.nd.node[index];
                vs.front.skip += c + 1;
                if (vs.front.skip >= RTree.maxChildrenPerNode)
                    vs.popFront;
                vs.pushFront(SeT(selectedRef, 0));
            }
        }
        _front = null;
    }

    private ref ElementType efront()
    {
        require(_front !is null);
        return *_front;
    }


    bool empty()
    {
        return _front is null;
    }

    typeof(this) save()
    {
        typeof(this) result;
        result._front = _front;
        result.vs = vs.dup;
        return result;
    }
}

private struct Leaf(_ElementType, uint _childCount, BoxType)
{
    alias ElementType = _ElementType;
    alias childCount = _childCount;
    BoxType box;
    size_t length;
    auto opSlice()
    {
        return elements[0 .. length];
    }
    ref opIndex(size_t arg)
    {
        return elements[arg];
    }
    ElementType[childCount] elements;
    alias children = elements;
    void toString(W)(ref W w) const
    {
        import std.format;
        w.formattedWrite!"<%s, %s; %s, %s>{%s}"(box.min.x, box.min.y, box.max.x, box.max.y, length);
    }
    invariant
    {
        import std.conv : to;
        //length.should.be.less.equal(_childCount);
    }
}
private struct Reference(NodeType_, LeafType_)
{
    alias NodeType = NodeType_;
    alias LeafType = LeafType_;
    enum Types : ubyte
    {
        leaf = 0b0,
        nonLeaf = 0b1
    }
    union
    {
        void* _raw;
        NodeType* _nodePtr;
        LeafType* _leafPtr;
        Types _refType;
    }
    ref NodeType node() @property
    {
        require((_refType & 0b1) == Types.nonLeaf);
        require(_raw - Types.nonLeaf !is null);
        return *cast(NodeType*)(cast(void*)_nodePtr - Types.nonLeaf);
    }
    ref LeafType leaf() @property
    {
        require((_refType & 0b1) == Types.leaf);
        require(_raw - Types.leaf !is null);
        return *cast(LeafType*)(cast(void*)_leafPtr - Types.leaf);
    }
    Types type() @property
    {
        return cast(Types)(_refType & 1);
    }
    ref NodeType node(ref NodeType node) @property
    {
        require((cast(size_t)&node & 0b1) == 0, "Address not aligned or garbage!");
        _nodePtr = cast(NodeType*)(cast(void*)&node + Types.nonLeaf);
        return node;
    }
    ref LeafType leaf(ref LeafType leaf) @property
    {
        require((cast(size_t)&leaf & 0b1) == 0, "Address not aligned or garbage!");
        _leafPtr = cast(LeafType*)(cast(void*)&leaf + Types.leaf);
        return leaf;
    }
    bool isNull()
    {
        return _raw is null || (_raw - 1) is null;
    }
    void erase()
    {
        _raw = null;
    }
    auto box() @property
    {
        final switch (type)
        {
        case Types.nonLeaf:
            return node.box;
        case Types.leaf:
            return leaf.box;
        }
    }
    auto box(typeof(box) box) @property
    {
        final switch (type)
        {
        case Types.nonLeaf:
            return node.box = box;
        case Types.leaf:
            return leaf.box = box;
        }
    }
    this(ref NodeType ptr)
    {
        node(ptr);
    }
    this(ref LeafType ptr)
    {
        leaf(ptr);
    }
    this(typeof(this) reference)
    {
        _raw = reference._raw;
    }
    void toString(W)(ref W w)
    {
        import std.format;
        if (_raw is null)
            w.formattedWrite!"null";
        else
            w.formattedWrite!"%s@%s"(type, _raw - type);
    }
}

private struct Node(ElementType, uint _childCount, BoxType)
{
    alias childCount = _childCount;
    auto opSlice()
    {
        import std.algorithm.searching : countUntil;
        ptrdiff_t ccount = children[].countUntil!(n => n.isNull);
        return children[0 .. ccount == -1 ? $ : ccount];
    }
    ref opIndex(size_t arg)
    {
        require(!children[arg].isNull);
        return children[arg];
    }
    BoxType box;
    alias ReferenceType = Reference!(typeof(this), Leaf!(ElementType, childCount, BoxType));
    auto nodes() @property
    {
        import std.algorithm.iteration : filter;
        return this[].filter!(n => n.type == n.Types.nonLeaf);
    }
    auto leaves() @property
    {
        import std.algorithm.iteration : filter;
        return this[].filter!(n => n.type == n.Types.leaf);
    }
    ReferenceType[childCount] children;
    void toString(W)(ref W w)
    {
        import std.format;
        w.formattedWrite!"<%s, %s; %s, %s>[%(%s, %)]"(box.min.x, box.min.y, box.max.x, box.max.y, children);
    }
}

/**
The root data structure of any R-Tree implemented by this module. The tree does not reference external data by itself,
but manages the elements by value while providing `ref` access.

Params:
    _ElementType = the type of the elements to be held within the tree
    BFun = a callable that calculates the bounding box of a given element
    _dimensionCount = the number of spacial dimensions that the tree manages
    _maxChildrenPerNode = the absolute maximum number of children that each node can have
    _minChildenPerNode = the minimum number of children that a node may hold without merging into others
    _ManagementType = the type that each dimensional axis shall have

BFun:
    The callable needs to be defined as follows:
    It must accept a single element typed `ElementType`, either by reference or value.
    It must return the bounding box typed as `Box!(ManagementType, dimensionCount)` aka. `BoxType`.
    Assigning sane values to the `BoxType` is crucial, each dimension is defined by an interval of the form [a, b), this
    implies that if a equals b, the dimension is empty and thus unusable for the tree, it must never occur.
    If a > b, the interval is malformed and unusable.
    Infinite values as are possible with floating point types
    are acceptable and treated correctly, NaN however is illegal.
    Any wrapping overflow behavior as the inbuilt integer types experience are not regarded and to be prevented.
*/
struct RTree(_ElementType, alias BFun, uint _dimensionCount, uint _maxChildrenPerNode = 16,
             uint _minChildrenPerNode = 6, _ManagementType = float)
{
    alias ElementType = _ElementType;
    alias BoxType = Box!(ManagementType, dimensionCount);
    alias dimensionCount = _dimensionCount;
    alias ManagementType = _ManagementType;
    alias maxChildrenPerNode = _maxChildrenPerNode;
    alias minChildrenPerNode= _minChildrenPerNode;
    static assert(minChildrenPerNode <= (maxChildrenPerNode / 2),
                   "minChildrenPerNode must not be larger than half of maxChildrenPerNode");
    import std.traits;
    static assert(isCallable!BFun);
    static assert(is(ReturnType!BFun == BoxType));
    static assert(is(Parameters!BFun[0] == ElementType));
    alias calcElementBounds = BFun;
    alias LeafType = Leaf!(ElementType, maxChildrenPerNode, BoxType);
    alias NodeType = Node!(ElementType, maxChildrenPerNode, BoxType);
    alias ReferenceType = Reference!(NodeType, LeafType);
    NodeType* rootPtr;
    alias nodeAllocator = Mallocator.instance;
    import std.experimental.allocator.building_blocks.free_tree;

    //FreeTree!Mallocator nodeAllocator;
    //alias pageAllocator = stackAllocator;
    void initialize()
    {
        import std.exception;
        require(rootPtr is null);
        rootPtr = make!NodeType(nodeAllocator);
        enforce(rootPtr !is null, new AllocationFailure("Initialization of RTree failed due to allocation failure"));
    }

    void destroy()
    {
        auto nodeStack = Stack!(NodeType*)(8);
        scope(exit)
            nodeStack.destroy;
        nodeStack.pushFront(rootPtr);
    }

/+TODO:    RTreeRange!(typeof(this), SearchModes.all, false) opSlice()
    {
        return typeof(return)(this);
    }+/

    /**
    Convenience function to calculate the bounding box of any given element
    */
    static BoxType getBox(T)(ref T entry)
        if (is(T == NodeType)
            || is(T == LeafType)
            || is(T == ReferenceType))
    {
        return entry.box;
    }

    static if (ParameterStorageClassTuple!calcElementBounds[0] == ParameterStorageClass.ref_)
    {
        static BoxType getBox(T)(ref T entry)
            if (is(T == ElementType))
        {
            mixin(_getBox_body);
        }
    }
    else
    {
        static BoxType getBox(T)(T entry)
            if (is(T == ElementType))
        {
            mixin(_getBox_body);
        }
    }
    enum string _getBox_body =
    q{
        import std.algorithm;
        import std.math;
        BoxType result = calcElementBounds(entry);
        static if (isFloatingPoint!(typeof(result.min[0])))
        {
            require(result.min[].all!(n => !n.isNaN) && result.max[].all!(n => !n.isNaN));
        }
        return result;
    };
}

private size_t drawTree(RTree, W, W2)(ref RTree tree, ref W w, ref W2 w2)
{
    import std.format;
    import std.range;
    import std.algorithm;
    import std.typecons;
    import std.stdio;
    alias NodeType = RTree.NodeType;
    alias LeafType = RTree.LeafType;
    alias ReferenceType = RTree.ReferenceType;
    w.formattedWrite!`settings.outformat="pdf";`;
    w.formattedWrite!"\nunitsize(10cm);\n";
    w2.formattedWrite!`digraph tree { graph [fontname="osifont", layout="dot", overlap=false]%s`("\n");
    w2.formattedWrite!`node [fontname="osifont", shape="rectangle", fixedsize=false]%s`("\n");
    w2.formattedWrite!`edge [fontname="osifont"]%s`("\n");
    alias Ve = Tuple!(ReferenceType, "node", size_t, "skip");
    auto vs = Stack!Ve(8);
    scope(exit)
        vs.destroy;
    size_t itemCount;
    //writeln((*tree.rootPtr)[]);
    vs.pushFront(tuple!("node", "skip")(ReferenceType(*tree.rootPtr), size_t.max));
    {
        auto rb = tree.rootPtr.box;
        w.formattedWrite!"draw(box((%s, %s), (%s, %s)), hsv(284, 1.0, 1.0)+linewidth(2mm));\n"
                (rb.min[0], rb.min[1], rb.max[0], rb.max[1]);
        w2.formattedWrite!`"N%s"[color=violet]%s`(tree.rootPtr, "\n");
    }
    //w.formattedWrite!"draw(box((%s, %s), (%s, %s)), hsv(0.0, 1.0, %s)+linewidth(1mm));\n"(
    //    entryBox.min.x, entryBox.min.y, entryBox.max.x, entryBox.max.y);
    while (!vs.empty)
    {
        if (vs.front.node.type == ReferenceType.Types.nonLeaf)
        {
            if (vs.front.skip == size_t.max)
            {
                foreach (a; vs.front.node.node[])
                {
                    string nstring;
                    if (a.type == tree.ReferenceType.Types.nonLeaf)
                    {
                        w2.formattedWrite!`"N%s" [color=red]%s`(&(a.node()), "\n");
                        nstring = format!"N%s"(&(a.node()));
                    }
                    else
                    {
                        w2.formattedWrite!`"L%s" [color=blue]%s`(&(a.leaf()), "\n");
                        nstring = format!"L%s"(&(a.leaf()));
                    }
                    w2.formattedWrite!`"N%s" -> "%s"%s`(&(vs.front.node.node()), nstring, "\n");
                }
                foreach (b; vs.front.node.node[].map!((ref n) => tuple(n.box, n.type)))
                {
                    require(vs.front.node.box.contains(b[0]),
                        format!"%s does not contain %s of %s | diff: %s %s"(vs.front.node.box, b[0], b[1],
                            b[0].min - vs.front.node.box.min, vs.front.node.box.max - b[0].max));
                    //w.formattedWrite!"draw(box((%s, %s), (%s, %s)), hsv(0, 1.0, %s)+linewidth(1mm));\n"
                    //    (b[0].min[0], b[0].min[1], b[0].max[0], b[0].max[1], vs.length / 20.0);
                }
            }
            vs.front.skip += 1;
            if (vs.front.skip < vs.front.node.node[].walkLength)
            {
                vs.pushFront(Ve(vs.front.node.node.children[vs.front.skip], size_t.max));
            }
            else
                vs.popFront;
        }
        else if (vs.front.node.type == ReferenceType.Types.leaf)
        {
            require(vs.front.skip == size_t.max);
            foreach (ref a, b; lockstep(vs.front.node.leaf[],
                                    vs.front.node.leaf[].map!((ref n) => RTree.getBox(n))))
            {
                w2.formattedWrite!`"E%s" [color = green]%s`(&a, "\n");
                w2.formattedWrite!`"L%s" -> "E%s"%s`(&(vs.front.node.leaf()), &a, "\n");
                require(vs.front.node.box.contains(b));
                w.formattedWrite!"draw(box((%s, %s), (%s, %s)), hsv(%s, 1.0, 0.5)+linewidth(1mm));\n"
                    (b.min[0], b.min[1], b.max[0], b.max[1], a.color == Color.green ? 120 : 200);
                itemCount += 1;
            }
            vs.popFront;
        }
    }
    w2.formattedWrite!"}\n";
    return itemCount;
}

private void check(RTree)(ref RTree tree)
{
    import std.format;
    import std.range;
    import std.algorithm;
    import std.typecons;
    import std.stdio;
    alias NodeType = RTree.NodeType;
    alias LeafType = RTree.LeafType;
    alias ReferenceType = RTree.ReferenceType;
    alias Ve = Tuple!(ReferenceType, "node", size_t, "skip");
    auto vs = Stack!Ve(8);
    scope(exit)
        vs.destroy;
    vs.pushFront(tuple!("node", "skip")(ReferenceType(*tree.rootPtr), size_t.max));
    while (!vs.empty)
    {
        if (vs.front.node.type == ReferenceType.Types.nonLeaf)
        {
            if (vs.front.skip == size_t.max)
            {
                if (vs.length > 1)
                    require(!vs.front.node.node[].empty);
                foreach (b; vs.front.node.node[].map!((ref n) => tuple(n.box, n.type)))
                {
                    require(vs.front.node.box.contains(b[0]),
                        format!"%s does not contain %s of %s | diff: %s %s"(vs.front.node.box, b[0], b[1],
                            b[0].min - vs.front.node.box.min, vs.front.node.box.max - b[0].max));
                }
            }
            vs.front.skip += 1;
            if (vs.front.skip < vs.front.node.node[].walkLength)
            {
                vs.pushFront(Ve(vs.front.node.node.children[vs.front.skip], size_t.max));
            }
            else
                vs.popFront;
        }
        else if (vs.front.node.type == ReferenceType.Types.leaf)
        {
            require(vs.front.skip == size_t.max);
            foreach (ref a, b; lockstep(vs.front.node.leaf[],
                                    vs.front.node.leaf[].map!((ref n) => RTree.getBox(n))))
            {
                require(vs.front.node.box.contains(b));
            }
            vs.popFront;
        }
    }
}

private void eraseNode(NodeType)(ref NodeType node)
    if (isInstanceOf!(Leaf, NodeType)
        || isInstanceOf!(Node, NodeType))
{
    import std.range : ElementType;
    node.children[] = ElementType!(typeof(node.children)).init;
    static if (isInstanceOf!(Leaf, NodeType))
    {
        node.length = 0;
    }
    node.box = typeof(node.box).init;
}

private void removeEntryFromNode(NodeType)(ref NodeType node, size_t index)
    if (isInstanceOf!(Leaf, NodeType)
        || isInstanceOf!(Node, NodeType))
{
    require(index != size_t.max);
    import std.algorithm.mutation : stdremove = remove, SwapStrategy;

    static if (isInstanceOf!(Leaf, NodeType))
    {
        node.elements[].stdremove!(SwapStrategy.stable)(index);
        node.elements[$ - 1] = typeof(node.elements[0]).init;
        require(node.length > 0 && node.length <= node.childCount);
        node.length -= 1;
    }
    else static if (isInstanceOf!(Node, NodeType))
    {
        node.children[].stdremove!(SwapStrategy.stable)(index);
        node.children[$ - 1] = typeof(node.children[0]).init;
    }
    else
        static assert(0);
}

private size_t addEntryToNode(NodeType, EntryType)(ref NodeType node, ref EntryType entry)
    if (isInstanceOf!(Leaf, NodeType)
        && is(EntryType == NodeType.ElementType)
        || isInstanceOf!(Node, NodeType)
        && (is(EntryType == NodeType)
            || is(EntryType == NodeType.ReferenceType.LeafType)
            || is(EntryType == NodeType.ReferenceType)))
{
    size_t entryCount;
    static if (isInstanceOf!(Leaf, NodeType))
    {
        entryCount = node.length;
        require(entryCount < node.childCount);
        node.elements[entryCount] = entry;
        require(node.length >= 0 && node.length < node.childCount);
        node.length += 1;
        return entryCount;
    }
    else static if (isInstanceOf!(Node, NodeType))
    {
        import std.range : chain, walkLength;
        entryCount = node[].walkLength;
        require(entryCount < node.childCount);
        node.children[entryCount] = NodeType.ReferenceType(entry);
        return entryCount;
    }
    else
        static assert(0);
}

private void insert(RTree, R)(ref RTree tree, ref R datum, size_t level = size_t.max)
    if(is(R == RTree.LeafType)
       || is(R == RTree.NodeType))
{
    insert(tree, datum, level, Stack!(RTree.ReferenceType).init);
}

/**
Inserts an element into the specified tree. Duplicates are allowed.
May invalidate pointers to elements.

Asserts:
    Well-formedness of bounding box

Params:
    tree = the tree to operate on
    datum = the element to insert
    level = to be ignored, never specify

*/

void insert(RTree, R)(ref RTree tree, ref R datum, size_t level = size_t.max)
    if (is(R == RTree.ElementType)
        || is(R == RTree.ReferenceType))
{
    insert(tree, datum, level, Stack!(RTree.ReferenceType).init);
}

private void insert(RTree, R, S)(ref RTree tree, auto ref R datum, size_t level, S orphanStack)
{
    insert(tree, datum, level, orphanStack, null);
}


//TODO: make this ugly piece of shit function nice
private void insert(RTree, R, S, B)(ref RTree tree, auto ref R datum,
                                    size_t level, S orphanStack, B preSubTree)
    if (is(R == RTree.ElementType)
        || is(R == RTree.LeafType)
        || is(R == RTree.NodeType)
        || is(R == RTree.ReferenceType))
{
    static if (is(R == RTree.ReferenceType))
    {
        //writef!"inserting Reference by ";
        if (datum.type == RTree.ReferenceType.Types.leaf)
            insert(tree, datum.leaf, level, orphanStack);
        else if (datum.type == RTree.ReferenceType.Types.nonLeaf)
            insert(tree, datum.node, level, orphanStack);
        else
            require(0);
    }
    else
    {
        //tree.elementCount += 1;
        //static if (is(R == RTree.ElementType))
            //writef!"inserting Element, ";
        //else
            //writef!"inserting %s %s, "(R.stringof, &datum);
        alias ReferenceType = tree.ReferenceType;
        alias NodeType = tree.NodeType;
        alias LeafType = tree.LeafType;
        alias BoxType = tree.BoxType;
        alias ElementType = tree.ElementType;
        auto datumBox = RTree.getBox(datum);

        static if (is(B == typeof(null)))
            auto subTree = tree.chooseSubTree!(R)(datumBox);
        else
            auto subTree = preSubTree;
        scope(exit)
            subTree.destroy;

        require(&(subTree.back.node()) is tree.rootPtr);
        static if (!is(R == RTree.ElementType))
            if (subTree.front.type == ReferenceType.Types.leaf)
                subTree.popFront;
        immutable originalSubTreeLength = subTree.length;

        if (subTree.front.type == ReferenceType.Types.leaf)
        {
            static if (is(R == RTree.ElementType))
            {
                if (subTree.front.leaf.length < tree.maxChildrenPerNode)
                {
                    subTree.front.leaf.addEntryToNode(datum);
                    while (!subTree.empty)
                    {
                        auto oldBox = subTree.front.box;
                        subTree.front.box = subTree.front.box.expand(datumBox);
                        if (subTree.front.box == oldBox) // no boxes would expanded anymore, terminate early
                            break;
                        subTree.popFront;
                    }
                    //tree.updateBoxes(subTree);

                    if (!orphanStack.empty)
                    {
                        import std.stdio;
                        writefln!"orphanstack len: %s"(orphanStack.length);
                        if (orphanStack.front.type == RTree.ReferenceType.Types.leaf)
                        {
                            auto o = orphanStack.front.leaf;
                            orphanStack.popFront;
                            insert(tree, o, originalSubTreeLength, orphanStack);
                        }
                        else if (orphanStack.front.type == RTree.ReferenceType.Types.nonLeaf)
                        {
                            auto o = orphanStack.front.node;
                            orphanStack.popFront;
                            insert(tree, o, originalSubTreeLength, orphanStack);
                        }
                        else
                            require(0);
                        return;
                    }
                    else
                        orphanStack.destroy;
                }
                else // split
                {
                    import std.algorithm.searching : countUntil;
                    auto deadNode = subTree.front;
                    auto newNodes = tree.splitFull(subTree.front.leaf);

                    subTree.popFront;
                    size_t deadNodeIndex = subTree.front.node[].countUntil!(n => n == deadNode);
                    require(deadNodeIndex != size_t.max);
                    subTree.front.node.removeEntryFromNode(deadNodeIndex);

                    orphanStack.pushFront(ReferenceType(*newNodes[0]));
                    // insert datum into one of the new nodes
                    {
                        import std.algorithm.iteration : map, fold;
                        auto volumeCostA = newNodes[0].box
                            .expand(datumBox).volume - newNodes[0].box.expand(datumBox).volume;
                        auto volumeCostB = newNodes[1].box
                            .expand(datumBox).volume - newNodes[1].box.expand(datumBox).volume;
                        if (volumeCostA < volumeCostB)
                        {
                            (*newNodes[0]).addEntryToNode(datum);
                            newNodes[0].box = (*newNodes[0])[]
                                .map!((ref n) => RTree.getBox(n))
                                .fold!((a, b) => a.expand(b));
                            require(newNodes[0].box.contains(datumBox));
                        }
                        else
                        {
                            (*newNodes[1]).addEntryToNode(datum);
                            newNodes[1].box = (*newNodes[1])[]
                                .map!((ref n) => RTree.getBox(n))
                                .fold!((a, b) => a.expand(b));
                            require(newNodes[1].box.contains(datumBox));
                        }
                    }
                    tree.pruneEmpty(subTree, orphanStack);

                    /+import std.stdio;
                    import std.range;
                    import std.format;
                    auto file = File(format!"trees/g%06s.dot"(cnt++), "w");
                    auto w = file.lockingTextWriter;
                    tree.drawTree(nullSink, w);
                    +/
                    insert(tree, *newNodes[1], originalSubTreeLength, orphanStack);
                    return;
                }
            }
            else
                require(0, "dead end 2");
        }
        else if (subTree.front.type == ReferenceType.Types.nonLeaf)
        {
            static if (!is(R == RTree.ElementType))
            {
                import std.range : walkLength;
                if (subTree.front.node[].walkLength < tree.maxChildrenPerNode)
                {
                    subTree.front.node.addEntryToNode(datum);
                    while (!subTree.empty)
                    {
                        auto oldBox = subTree.front.box;
                        subTree.front.box = subTree.front.box.expand(datumBox);
                        if (subTree.front.box == oldBox) // no boxes would expanded anymore, terminate early
                            break;
                        subTree.popFront;
                    }
                    //tree.updateBoxes(subTree);

                    if (!orphanStack.empty)
                    {
                        if (orphanStack.front.type == RTree.ReferenceType.Types.leaf)
                        {
                            auto o = orphanStack.front;
                            orphanStack.popFront;
                            insert(tree, o, originalSubTreeLength, orphanStack);
                        }
                        else if (orphanStack.front.type == RTree.ReferenceType.Types.nonLeaf)
                        {
                            auto o = orphanStack.front;
                            orphanStack.popFront;
                            insert(tree, o, originalSubTreeLength, orphanStack);
                        }
                        else
                            require(0);
                        return;
                    }
                    else
                        orphanStack.destroy;
                }
                else if (subTree.length < level && false) // reinsertion
                {
                    import std.stdio;
                    import std.range : enumerate;
                    import std.algorithm.iteration : map, fold, sum;
                    RTree.ManagementType worstDistance;
                    size_t worstChildIndex;
                    foreach (i, child; subTree.front.node[].enumerate)
                    {
                        RTree.ManagementType distance = (child.box.center - subTree.front.node.box.center).v[].sum;
                        if (distance > worstDistance || i == 0)
                        {
                            worstDistance = distance;
                            worstChildIndex = i;
                        }
                    }
                    if (worstDistance > (datum.box.center - subTree.front.node.box.center).v[].sum) // new node is better
                    {
                        import std.range : drop;
                        ReferenceType orphan = subTree.front.node[].drop(worstChildIndex).front;
                        subTree.front.node.removeEntryFromNode(worstChildIndex);
                        subTree.front.node.addEntryToNode(datum);

                        tree.updateBoxes(subTree);
                        insert(tree, orphan, originalSubTreeLength, orphanStack);
                        return;
                    }
                    else
                        goto split;
                }
                else // split
                {
                split:
                    import std.algorithm.searching : countUntil;
                    import std.algorithm.iteration : map, fold, sum;
                    orphanStack.pushFront(ReferenceType(datum));
                    auto deadNode = subTree.front;
                    auto newNodes = tree.splitFull(subTree.front.node);
                    if (subTree.length > 1)
                    {
                        subTree.popFront;
                        size_t deadNodeIndex = subTree.front.node[].countUntil!(n => n == deadNode);
                        require(deadNodeIndex != size_t.max);
                        subTree.front.node.removeEntryFromNode(deadNodeIndex);

                        tree.pruneEmpty(subTree, orphanStack);
                        tree.updateBoxes(subTree);
                    }

                    orphanStack.pushFront(ReferenceType(*newNodes[0]));
                    insert(tree, *newNodes[1], originalSubTreeLength, orphanStack);
                    return;
                }
            }
            else
            {
                auto newLeaf = make!LeafType(tree.nodeAllocator);
                (*newLeaf).addEntryToNode(datum);
                newLeaf.box = datumBox;
                insert(tree, *newLeaf, subTree.length, orphanStack, subTree.reap);
                return;
            }
        }
        else
            require(0, "dead end 3");
    }
}

private auto chooseSubTree(T, RTree, BoxType)(ref RTree tree, BoxType searchBox)
    if (is(BoxType == tree.BoxType))
{
    return chooseSubTree!T(tree, searchBox, tree.ReferenceType(*tree.rootPtr));
}
private auto chooseSubTree(T, RTree, BoxType, ReferenceType)(ref RTree tree, BoxType searchBox, ReferenceType begin)
    if (is(BoxType == RTree.BoxType)
        && is(ReferenceType == RTree.ReferenceType))
{
    import std.typecons : Tuple, tuple;
    alias BoxType = tree.BoxType;
    alias ManagementType = tree.ManagementType;
    alias ReferenceType = tree.ReferenceType;
    ReferenceType activeNode = begin;
    auto nodeStack = Stack!ReferenceType(8);
    nodeStack.pushFront(activeNode);

    while (true)
    {
        import std.math : ceil;
        import core.stdc.math : logf;
        if (activeNode.type == ReferenceType.Types.leaf)
            return nodeStack;
        else if (activeNode.node[].walkLength < tree.maxChildrenPerNode
                 && (is(T == RTree.NodeType)))// || is(T == RTree.LeafType)))
//                 && (ceil(logf(tree.elementCount)/logf(tree.maxChildrenPerNode)) + 1) > nodeStack.length)
            return nodeStack;
        else if (!activeNode.node.nodes.empty)
        {
            import std.range : enumerate;
            ReferenceType bestNode;
            ManagementType bestVolumeCost;
            foreach (i, ref node; activeNode.node.nodes.enumerate)
            {
                ManagementType volumeCost = node.box.expand(searchBox).volume - node.box.volume;
                if (volumeCost < bestVolumeCost || i == 0)
                {
                    bestVolumeCost = volumeCost;
                    bestNode = node;
                }
            }
            nodeStack.pushFront(bestNode);
            activeNode = bestNode;
            // ditto regarding ties
        }
        else if (!activeNode.node.leaves.empty)
        {
            import std.range : enumerate;
            ReferenceType bestNode;
            ManagementType bestOverlapCost;
            foreach (i, leaf; activeNode.node.leaves.enumerate)
            {
                ManagementType overlapCost = 0;
                foreach (i2, leaf2; activeNode.node.leaves.enumerate)
                {
                    if (leaf == leaf2)
                        continue;
                    overlapCost +=
                        leaf.box.expand(searchBox).intersection(leaf2.box).volume
                        - leaf.box.intersection(leaf2.box).volume;
                }
                if (overlapCost < bestOverlapCost || i == 0)
                {
                    bestOverlapCost = overlapCost;
                    bestNode = leaf;
                }
            }
            nodeStack.pushFront(bestNode);
            activeNode = bestNode;
            // we assume that ties are very improbable and resolve them by simply taking the first best match
        }
        else
            return nodeStack;
    }

}

private void updateBoxes(RTree, NodeStackType)(ref RTree tree, ref NodeStackType nodeStack)
{
    import std.algorithm.iteration : fold, map;
    alias BoxType = RTree.BoxType;
    require(!nodeStack.empty);

    BoxType oldBox = nodeStack.front.box;

    if (nodeStack.front.type == tree.ReferenceType.Types.leaf)
    {
        nodeStack.front.leaf.box = nodeStack.front.leaf[]
            .map!((ref n) => RTree.getBox(n))
            .fold!((a, b) => a.expand(b));
        if (nodeStack.front.leaf.box == oldBox)
            return;
        nodeStack.popFront;
    }

    while (!nodeStack.empty)
    {
        oldBox = nodeStack.front.node.box;
        nodeStack.front.node.box = nodeStack.front.node[]
            .map!((ref n) => RTree.getBox(n))
            .fold!((a, b) => a.expand(b));
        if (nodeStack.front.node.box == oldBox)
            return;
        nodeStack.popFront;
    }
}

private void pruneEmpty(RTree, NodeStackType)(
        ref RTree tree,
        ref NodeStackType nodeStack,
        ref NodeStackType orphanStack)
{
    import std.algorithm.searching : countUntil;
    import std.range : walkLength;
    alias ReferenceType = RTree.ReferenceType;
    require(nodeStack.front.type != tree.ReferenceType.Types.leaf);
    while (/+nodeStack.front.node[].walkLength < tree.minChildrenPerNode && +/nodeStack.length > 1)
    {
        if (nodeStack.front.node[].walkLength == 1
            && nodeStack.front.node.children[0].type == ReferenceType.Types.nonLeaf)
        {
            auto loneNode = &(nodeStack.front.node.children[0].node());
            nodeStack.front.node.children[] = loneNode.children[];
            dispose(tree.nodeAllocator, loneNode);
        }
        else if (nodeStack.front.node[].walkLength < tree.minChildrenPerNode)
        {
            RTree.ReferenceType sentencedNode = nodeStack.front;
            foreach (child; nodeStack.front.node[])
                orphanStack.pushFront(child);
            nodeStack.front.node.eraseNode;
            nodeStack.popFront;
            auto killNIndex = nodeStack.front.node[].countUntil!(n => n == sentencedNode);
            require(killNIndex != size_t.max);
            removeEntryFromNode(nodeStack.front.node, killNIndex);
            dispose(tree.nodeAllocator, &(sentencedNode.node()));
        }
        else
            nodeStack.popFront;
    }
    if (nodeStack.front.node[].walkLength == 1
        && nodeStack.front.node.children[0].type == ReferenceType.Types.nonLeaf)
    {
        auto loneNode = &(nodeStack.front.node.children[0].node());
        nodeStack.front.node.children[] = loneNode.children[];
        dispose(tree.nodeAllocator, loneNode);
    }
}

/**
Removes an matching element from the specified tree.
Equivalence is defined by the `==` operator for `ElementType`. Only one element is removed at a time, if more than
one element matches the given one, the first one found is removed, others stay in the tree.
May invalidate pointers to elements.

Asserts:
    Whether element is actually in tree.

Params:
    tree = the tree to operate on
    element = an element equivalent to the one to be removed
*/
void remove(RTree, ElementType)(ref RTree tree, auto ref ElementType element)
    if (is(ElementType == RTree.ElementType))
{
    import std.stdio;
    alias ReferenceType = RTree.ReferenceType;
    alias BoxType = RTree.BoxType;
    immutable searchBox = RTree.getBox(element);
    auto fr = tree.findEntry(element);
    Stack!ReferenceType orphanStack;
    scope(exit)
    {
        orphanStack.destroy;
        fr.nodeStack.destroy;
    }
    require(fr.index != size_t.max, "element not found in tree");
    removeEntryFromNode(fr.nodeStack.front.leaf, fr.index);

    if (fr.nodeStack.front.leaf.length < tree.minChildrenPerNode)
    {
        import std.algorithm.searching : countUntil;
        import std.range : walkLength;
        RTree.LeafType* orphanElementsNode = &(fr.nodeStack.front.leaf());
        fr.nodeStack.popFront;
        size_t killIndex = fr.nodeStack.front.node[].countUntil!(n => n == ReferenceType(*orphanElementsNode));
        require(killIndex != size_t.max);
        removeEntryFromNode(fr.nodeStack.front.node, killIndex);

        tree.pruneEmpty(fr.nodeStack, orphanStack);


        if (!fr.nodeStack.front.node[].empty)
            tree.updateBoxes(fr.nodeStack);
        else
            fr.nodeStack.front.node.box = BoxType.init;

        while (!orphanStack.empty)
        {
        /+if (gfile.isOpen)
        {
            gfile.rewind;
            tree.drawTree(nullSink, gwriter);
        }+/
            tree.insert(orphanStack.front);
            orphanStack.popFront;
        }

        import std.range;
        foreach (i, ref e; (*orphanElementsNode)[])
        {
            /+import std.range;
            import std.stdio;
            import std.format;
            auto file = File(format!"trees/g%06s-%04s.dot"(cnt++, i), "w");
            auto w = file.lockingTextWriter;
            tree.drawTree(nullSink, w);
            file.close;+/
            tree.insert(e);

        }
        (*orphanElementsNode).eraseNode;
        dispose(tree.nodeAllocator, orphanElementsNode);
    }
    else
    {
        import std.algorithm.iteration : map, fold;
        auto oldBox = fr.nodeStack.front.leaf.box;

        if (fr.nodeStack.front.leaf.length > 0)
            fr.nodeStack.front.leaf.box = fr.nodeStack.front.leaf[]
                .map!((ref n) => RTree.getBox(n))
                .fold!((a, b) => a.expand(b));
        /+if (oldBox == fr.nodeStack.front.leaf.box) // boxes won't shrink any further, terminate early
            return;
        +/fr.nodeStack.popFront;
        tree.updateBoxes(fr.nodeStack);
     }
}
import std.range;
import std.stdio;
File gfile;
typeof(File.lockingTextWriter()) gwriter;
size_t cnt;

private auto splitFull(RTree, N)(ref RTree tree, ref N node)
    if (is(N == RTree.NodeType)
        || is(N == RTree.LeafType))
{
    alias ReferenceType = RTree.ReferenceType;
    alias dimensionCount = RTree.dimensionCount;
    alias maxChildrenPerNode = RTree.maxChildrenPerNode;
    alias minChildrenPerNode = RTree.minChildrenPerNode;
    alias ManagementType = RTree.ManagementType;
    alias BoxType = RTree.BoxType;
    alias NodeType = RTree.NodeType;

    static if (is(N == RTree.NodeType))
    {
        import std.algorithm.searching : all;
        alias ChildType = ReferenceType;
        require(node[].all!(n => !n.isNull));
    }
    else static if (is(N == RTree.LeafType))
    {
        alias ChildType = RTree.ElementType;
        require(node.length == node.childCount);
    }

    import std.conv : to;
    import std.range : walkLength;
    import std.algorithm.mutation : copy;
    import std.algorithm.sorting : sort;
    ChildType[maxChildrenPerNode][dimensionCount * 2] axes;
    foreach (dimension; 0 .. dimensionCount)
    {
        import std.algorithm.mutation : copy;
        import std.algorithm.iteration : map;
        //import std.range;

        node[].copy(axes[dimension][]);
        // note that .min and .max are members of Box, not free function calls
        axes[dimension][]
            .sort!((a, b) => RTree.getBox(a).min[dimension] < RTree.getBox(b).min[dimension]);
    }
    foreach (dimension; 0 .. dimensionCount)
    {
        // it's probable that sorting max results in a similar order as min does
        axes[dimension][].copy(axes[dimension + dimensionCount][]);
        axes[dimension + dimensionCount][]
            .sort!((a, b) => RTree.getBox(a).max[dimension] < RTree.getBox(b).max[dimension]);
    }

    ChildType[] bestGroupA;
    ChildType[] bestGroupB;
    ManagementType bestPerimeterCost;
    BoxType bestBoxA;
    BoxType bestBoxB;

    foreach (dimension; 0 .. dimensionCount * 2)
    {
        require((maxChildrenPerNode - 2 * minChildrenPerNode + 2) > 0);
        //foreach (k; 0 .. maxEntriesPerPage - 2 * minEntriesPerPage + 2)
        foreach (k; 0 .. maxChildrenPerNode - minChildrenPerNode * 2 + 1)
        {
            import std.range : take, drop;
            import std.algorithm.iteration : map, fold, sum, filter;
            ChildType[] groupA = axes[dimension][].take(minChildrenPerNode + k);
            ChildType[] groupB = axes[dimension][].drop(minChildrenPerNode + k);
            auto boxA = groupA[]
                .map!(n => RTree.getBox(n))
                .fold!((a, b) => a.expand(b));
            auto boxB = groupB[]
                .map!(n => RTree.getBox(n))
                .fold!((a, b) => a.expand(b));
            immutable perimeterA = boxA.size.v[].sum ^^ 2;
            immutable perimeterB = boxB.size.v[].sum ^^ 2;
            immutable perimeterCost = perimeterA + perimeterB;
            if (bestPerimeterCost > perimeterCost || dimension == 0)
            {
                bestGroupA = groupA;
                bestGroupB = groupB;
                bestPerimeterCost = perimeterCost;
                bestBoxA = boxA;
                bestBoxB = boxB;
            }
        }
    }

    require(bestGroupA.length + bestGroupB.length == tree.maxChildrenPerNode);

    // put selections into newly allocated nodes
    auto newNodeA = make!N(tree.nodeAllocator);
    auto newNodeB = make!N(tree.nodeAllocator);

    bestGroupA[].copy(newNodeA.children[]);
    newNodeA.box = bestBoxA;
    bestGroupB[].copy(newNodeB.children[]);
    newNodeB.box = bestBoxB;
    static if (is(N == RTree.LeafType))
    {
        newNodeA.length = bestGroupA.length;
        newNodeB.length = bestGroupB.length;
    }
    else
    {
        require((*newNodeA)[].walkLength + (*newNodeB)[].walkLength == tree.maxChildrenPerNode);
    }
    foreach (ref e; node[])
    {
        import std.algorithm.searching : canFind;
        require((*newNodeA)[].canFind(e)
               || (*newNodeB)[].canFind(e));
    }
    foreach (ref e; (*newNodeA)[])
    {
        require(newNodeA.box.contains(RTree.getBox(e)));
    }
    foreach (ref e; (*newNodeB)[])
    {
        require(newNodeB.box.contains(RTree.getBox(e)));
    }

    // destroy original node as long as it's not the root
    // TODO: see if direct reuse is sensible
    node.eraseNode;
    static if (is(N == NodeType))
    {
        if (&node !is tree.rootPtr)
        {
            dispose(tree.nodeAllocator, &node);
        }
    }
    else
    {
        dispose(tree.nodeAllocator, &node);
    }

    import std.typecons : tuple;
    auto result = tuple(newNodeA, newNodeB);
    return result;
}

private auto findEntry(RTree, T)(ref RTree tree, ref T entry)
{
    return findEntry!false(tree, entry);
}

import std.typecons : Tuple;
private Tuple!(Stack!(RTree.ReferenceType), "nodeStack", size_t, "index")
        findEntry(bool exhaustive, RTree, T)(ref RTree tree, ref T entry)
    if (is(T == RTree.ElementType)
        || is(T == RTree.LeafType)
        || is(T == RTree.NodeType))
{
    import std.typecons : Tuple, tuple;
    immutable(RTree.BoxType) searchBox = RTree.getBox(entry);
    alias ReferenceType = RTree.ReferenceType;
    alias ReturnType = Tuple!(Stack!ReferenceType, "nodeStack", size_t, "index");
    auto arrStack = Stack!(ReferenceType[])(8);
    scope(exit)
        arrStack.destroy;
    static if (is(T == RTree.LeafType) || is(T == RTree.NodeType) || is(T == RTree.ReferenceType))
    {
        if (tree.root == ReferenceType(entry))
        {
            return ReturnType(nodeStack, 0);
        }
    }
    arrStack.pushFront(tree.rootPtr.children);

    void exhaustiveCheck()
    {
        import std.stdio;
        import std.range : enumerate;
        // check if entry is *really* not in tree
        auto res = findEntry!true(tree, entry);
        scope(exit)
            res.nodeStack.destroy;
        if (res.index != size_t.max)
        {
            stderr.writeln("malformed tree:");
            RTree.BoxType prevBox;
            foreach (i, el; res.nodeStack.enumerate)
            {
                bool valid = true;
                if (i > 0)
                {
                    valid = el.box.contains(prevBox);
                    stderr.writef!"is %scontained by "(valid ? "" : "not ");
                }
                stderr.writef!"%s -> %s"(el.type, el.box);
                if (!valid)
                {
                    stderr.writef!" ([%s] [%s])"(
                        prevBox.min - el.box.min,
                        el.box.max - prevBox.max);
                }
                stderr.writeln;
                prevBox = el.box;
            }
            require(0);
        }

        stderr.writeln("really not in tree");
    }

    while (true)
    {
        if (arrStack.empty) // not found
        {
            if (!exhaustive)
                exhaustiveCheck;
            return ReturnType(Stack!ReferenceType(), size_t.max);
        }
        if (arrStack.front.empty || arrStack.front.front.isNull)
        {
            arrStack.popFront;
            if (arrStack.empty) // not found
            {
                if (!exhaustive)
                    exhaustiveCheck;
                return ReturnType(Stack!ReferenceType(), size_t.max);
            }
            arrStack.front.popFront;
            continue;
        }

        if (arrStack.front.front.type == ReferenceType.Types.nonLeaf)
        {
            static if (is(T == RTree.NodeType) || is(T == RTree.ReferenceType))
            {
                if (arrStack.front.front == ReferenceType(entry)) // found entry;
                    break;
            }
            if (arrStack.front.front.node.box.contains(RTree.getBox(entry)) || exhaustive)
            {
                foreach (e; arrStack.front.front.node[])
                    require(arrStack.front.front.node.box.contains(e.box));
                arrStack.pushFront(arrStack.front.front.node.children);
            }
            else
                arrStack.front.popFront;
            continue;
        }
        else if (arrStack.front.front.type == ReferenceType.Types.leaf)
        {
            static if (is(T == RTree.LeafType) || is(T == RTree.ReferenceType))
            {
                if (arrStack.front.front == ReferenceType(entry)) // found entry
                    break;
            }
            else static if (is(T == RTree.ElementType))
            {
                import std.range : enumerate;
                //scan elements
                foreach (i, ref e; arrStack.front.front.leaf[].enumerate)
                {
                    if (e == entry) // found entry
                    {
                        auto result = ReturnType(Stack!ReferenceType(arrStack.length), i);
                        result.nodeStack.pushFront(ReferenceType(*tree.rootPtr));
                        while (!arrStack.empty)
                        {
                            result.nodeStack.pushFront(arrStack.back.front);
                            arrStack.popBack;
                        }
                        return result;
                    }
                }
            }
            arrStack.front.popFront;
            continue;
        }
        // construct result
        auto result = ReturnType(Stack!ReferenceType(arrStack.length),
                                 tree.maxChildrenPerNode - arrStack.front.length);
        result.nodeStack.pushFront(ReferenceType(*tree.rootPtr));
        while (arrStack.length <= 1)
        {
            result.nodeStack.pushFront(arrStack.back.front);
            arrStack.popBack;
        }
        return result;
    }
}
import std.stdio;

enum Color : ubyte
{
    green = 0,
    blue = 1
}

unittest
{
    import std.string;
    import std.format;
    import std.file;
    import std.algorithm;
    import std.stdio;
    import std.array;
    import std.math;
    import std.range;
    import std.path;
    import std.conv;
    import std.typecons;
    Mt19937 gen;
    gen.seed(3);
    alias BoxType = Box!(float, 2);
    auto nodes = File("views/vertdata").byLine.map!((a){double x; double y;
            a.formattedRead!"%f, %f"(y, x);
            return vec2!float(cast(float)(x),cast(float)(y));}).array;
    stderr.writeln("loaded nodes");
    alias ElementType = Tuple!(Vector!(float, 2), "data", Color, "color");
    auto pnnn = nodes.enumerate.map!(n => ElementType(n.value, Color.blue)).cycle.take(50_000).array;
    static auto calcElementBounds(ElementType n)
    {
        return BoxType(n.data.x,
                       n.data.y,
                       n.data.x.nextUp,// + 0.001,
                       n.data.y.nextUp// + 0.001
                       );
    }
    RTree!(typeof(pnnn.front), calcElementBounds, 2, 8, 4, float) tree;
    tree.initialize;    

    dirEntries("trees/", SpanMode.shallow, false).each!(std.file.remove);
    byte[ElementType] elems;
    import std.random;
    import std.datetime;
    import core.thread;
    import std.datetime;

    File file = File("samples", "w");
    auto writer = file.lockingTextWriter;

    ulong[] samples = new ulong[pnnn.length];

    import core.memory;
    auto ttime = MonoTime.currTime + 20.msecs;
    foreach (i, add; pnnn)
    {
        auto start = MonoTime.currTime.ticks;
        tree.insert(add);
        auto end = MonoTime.currTime.ticks;
        samples[i] += end - start;
        //writer.formattedWrite!"%s,%s,\n"(i, (end - start).ticksToNSecs);
        //assert((end - start).ticksToNSecs < 400000);

        if (MonoTime.currTime >= ttime)
        {
            ttime += 20.msecs;
            writefln!"a%s of %s (%s %%)"(i, pnnn.length, cast(float)(i)/(pnnn.length) * 100.0f);
        }
    }

    enum c = vec2!float(9.2, 54.0);

    static struct Rad
    {
        float r = float.infinity;
        size_t boxCnt;
    }

    static struct CloserElement
    {
        enum vec2!float coor = c;

        static bool opCall(ref ElementType arg, ref Rad rad)
        {
            immutable vec2!float coordinate = typeof(tree).getBox(arg).min;
            float newRad = coordinate.distanceTo(coor);
            if (newRad <= rad.r)
            {
                writefln!":::%s"(newRad);
                rad.r = newRad;
                return true;
            }
            else
                return false;
        }
    }

    static struct TouchesCircle
    {
        static bool opCall(Box!(float, 2) box, ref Rad rad)
        {
            box.max += vec2!float(rad.r, rad.r);
            box.min -= vec2!float(rad.r, rad.r);
            rad.boxCnt += !box.contains(c);
            return box.contains(c);
        }
    }

    auto matches = RTreeRange!(typeof(tree), false, TouchesCircle, CloserElement)(tree);
    //matches.each!((n, a){n.color = Color.green; writeln(cnt++);});
    foreach (a, b; matches)
    {
        a.color = Color.green;
        writefln!"%s %s %s"(a, b, cnt++);
    }
    auto ff = File("trees/map.asy", "w");
    auto ww = ff.lockingTextWriter;
    tree.drawTree(ww, nullSink);
    ff.close;
    ttime = MonoTime.currTime + 20.msecs;
    foreach (i, rem; pnnn)
    {
        auto start = MonoTime.currTime.ticks;
        //tree.remove(rem);
        auto end = MonoTime.currTime.ticks;
        //writer.formattedWrite!"%s,,%s\n"(i, (end - start).ticksToNSecs);
        if (MonoTime.currTime >= ttime)
        {
            ttime += 20.msecs;
            writefln!"r%s of %s (%s %%)"(i, pnnn.length, cast(float)(i)/(pnnn.length) * 100.0f);
        }
    }
    foreach (i, s; samples)
    {
        writer.formattedWrite!"%s,%s\n"(i, s.ticksToNSecs);
    }
    file.close;

    tree.destroy;
}



