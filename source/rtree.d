module rtree;

version(LittleEndian)
{}
else
{
    static assert(0, "support for non-little endian platforms has not been implemented yet");
}

class AllocationFailure : Exception
{
    import std.exception;
    mixin basicExceptionCtors;
}

//import dshould;
import gfm.math;
import stack_container;
import std.traits;
import std.experimental.allocator.common;
import std.experimental.allocator.building_blocks.allocator_list;
import std.experimental.allocator.building_blocks.bitmapped_block;
import std.experimental.allocator.mallocator;
import std.experimental.allocator;

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
struct Reference(NodeType_, LeafType_)
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
        assert((_refType & 0b1) == Types.nonLeaf);
        assert(_raw - Types.nonLeaf !is null);
        return *cast(NodeType*)(cast(void*)_nodePtr - Types.nonLeaf);
    }
    ref LeafType leaf() @property
    {
        assert((_refType & 0b1) == Types.leaf);
        assert(_raw - Types.leaf !is null);
        return *cast(LeafType*)(cast(void*)_leafPtr - Types.leaf);
    }
    Types type() @property
    {
        return cast(Types)(_refType & 1);
    }
    ref NodeType node(ref NodeType node) @property
    {
        assert((cast(size_t)&node & 0b1) == 0, "Address not aligned or garbage!");
        _nodePtr = cast(NodeType*)(cast(void*)&node + Types.nonLeaf);
        return node;
    }
    ref LeafType leaf(ref LeafType leaf) @property
    {
        assert((cast(size_t)&leaf & 0b1) == 0, "Address not aligned or garbage!");
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
        import std.algorithm.searching : until;
        return children[].until!(n => n.isNull);
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

    size_t elementCount;
    //import std.experimental.allocator.building_blocks.free_tree;
    //FreeTree!Mallocator pageAllocator;
    //alias pageAllocator = stackAllocator;
    void initialize()
    {
        import std.exception;
        assert(rootPtr is null);
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

    BoxType getBox(T)(ref T entry)
        if (is(T == NodeType)
            || is(T == LeafType)
            || is(T == ReferenceType))
    {
        return entry.box;
    }

    static if (ParameterStorageClassTuple!calcElementBounds[0] == ParameterStorageClass.ref_)
    {
        BoxType getBox(T)(ref T entry)
            if (is(T == ElementType))
        {
            mixin(_getBox_body);
        }
    }
    else
    {
        BoxType getBox(T)(T entry)
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
        assert(result.min[].all!(n => !n.isNaN) && result.max[].all!(n => !n.isNaN));
        return result;
    };
}

size_t drawTree(RTree, W)(ref RTree tree, ref W w, ref W w2)
{
    import std.format;
    import std.range;
    import std.algorithm;
    import std.typecons;
    import std.stdio;
    alias NodeType = RTree.NodeType;
    alias LeafType = RTree.LeafType;
    alias ReferenceType = RTree.ReferenceType;
    //w.formattedWrite!`settings.outformat="pdf";`;
    //w.formattedWrite!"\nunitsize(10cm);\n";
    //w2.formattedWrite!`digraph tree { graph [fontname="osifont", layout="twopi", overlap=true]%s`("\n");
    //w2.formattedWrite!`node [fontname="osifont", shape="circle", fixedsize=false]%s`("\n");
    //w2.formattedWrite!`edge [fontname="osifont"]%s`("\n");
    alias Ve = Tuple!(ReferenceType, "node", size_t, "skip");
    auto vs = Stack!Ve(8);
    scope(exit)
        vs.destroy;
    size_t itemCount;
    //writeln((*tree.rootPtr)[]);
    vs.pushFront(tuple!("node", "skip")(ReferenceType(*tree.rootPtr), size_t.max));
    {
        auto rb = tree.rootPtr.box;
        //w.formattedWrite!"draw(box((%s, %s), (%s, %s)), hsv(284, 1.0, 1.0)+linewidth(2mm));\n"
        //        (rb.min[0], rb.min[1], rb.max[0], rb.max[1]);
        //w2.formattedWrite!`"N%s"[color=violet]%s`(tree.rootPtr, "\n");
    }
    //w.formattedWrite!"draw(box((%s, %s), (%s, %s)), hsv(0.0, 1.0, %s)+linewidth(1mm));\n"(entryBox.min.x,
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
                    //    w2.formattedWrite!`"N%s" [color=red]%s`(&(a.node()), "\n");
                    //    nstring = format!"N%s"(&(a.node()));
                    }
                    else
                    {
                    //    w2.formattedWrite!`"L%s" [color=blue]%s`(&(a.leaf()), "\n");
                    //    nstring = format!"L%s"(&(a.leaf()));
                    }
                    //w2.formattedWrite!`"N%s" -> "%s"%s`(&(vs.front.node.node()), nstring, "\n");
                }
                foreach (b; vs.front.node.node[].map!((ref n) => tuple(n.box, n.type)))
                {
                    assert(vs.front.node.box.contains(b[0]),
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
            assert(vs.front.skip == size_t.max);
            foreach (ref a, b; lockstep(vs.front.node.leaf[],
                                    vs.front.node.leaf[].map!((ref n) => tree.getBox(n))))
            {
                //w2.formattedWrite!`"E%s" [color = green]%s`(&a, "\n");
                //w2.formattedWrite!`"L%s" -> "E%s"%s`(&(vs.front.node.leaf()), &a, "\n");
                assert(vs.front.node.box.contains(b));
               /+ w.formattedWrite!"draw(box((%s, %s), (%s, %s)), hsv(120, 1.0, 0.5)+linewidth(1mm));\n"
                    (b.min[0], b.min[1], b.max[0], b.max[1]);
                +/itemCount += 1;
            }
            vs.popFront;
        }
    }
    //w2.formattedWrite!"}\n";
    return itemCount;
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
    assert(index != size_t.max);
    import std.algorithm.mutation : stdremove = remove, SwapStrategy;

    static if (isInstanceOf!(Leaf, NodeType))
    {
        node.elements[].stdremove!(SwapStrategy.stable)(index);
        node.elements[$ - 1] = typeof(node.elements[0]).init;
        assert(node.length > 0 && node.length <= node.childCount);
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
        assert(entryCount < node.childCount);
        node.elements[entryCount] = entry;
        assert(node.length >= 0 && node.length < node.childCount);
        node.length += 1;
        return entryCount;
    }
    else static if (isInstanceOf!(Node, NodeType))
    {
        import std.range : chain, walkLength;
        entryCount = node[].walkLength;
        assert(entryCount < node.childCount);
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
            assert(0);
    }
    else
    {
        tree.elementCount += 1;
        //static if (is(R == RTree.ElementType))
            //writef!"inserting Element, ";
        //else
            //writef!"inserting %s %s, "(R.stringof, &datum);
        alias ReferenceType = tree.ReferenceType;
        alias NodeType = tree.NodeType;
        alias LeafType = tree.LeafType;
        alias BoxType = tree.BoxType;
        alias ElementType = tree.ElementType;
        auto datumBox = tree.getBox(datum);

        static if (is(B == typeof(null)))
            auto subTree = tree.chooseSubTree!(R)(datumBox);
        else
            auto subTree = preSubTree;
        scope(exit)
            subTree.destroy;

        assert(&(subTree.back.node()) is tree.rootPtr);
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

                    if (!orphanStack.empty)
                    {
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
                            assert(0);
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
                    assert(deadNodeIndex != size_t.max);
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
                                .map!((ref n) => tree.getBox(n))
                                .fold!((a, b) => a.expand(b));
                            assert(newNodes[0].box.contains(datumBox));
                        }
                        else
                        {
                            (*newNodes[1]).addEntryToNode(datum);
                            newNodes[1].box = (*newNodes[1])[]
                                .map!((ref n) => tree.getBox(n))
                                .fold!((a, b) => a.expand(b));
                            assert(newNodes[1].box.contains(datumBox));
                        }
                    }

                    insert(tree, *newNodes[1], originalSubTreeLength, orphanStack);
                    return;
                }
            }
            else
                assert(0, "dead end 2");
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
                            assert(0);
                        return;
                    }
                    else
                        orphanStack.destroy;
                }
                else if (subTree.length < level) // reinsertion
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

                        while (!subTree.empty)
                        {
                            auto oldBox = subTree.front.node.box;
                            subTree.front.box = subTree.front.node[]
                                .map!(n => n.box)
                                .fold!((a, b) => a.expand(b));
                            if (subTree.front.box == oldBox) // boxes wouldn't change any more, terminate early
                                break;
                            subTree.popFront;
                        }
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
                        assert(deadNodeIndex != size_t.max);
                        subTree.front.node.removeEntryFromNode(deadNodeIndex);

                        while (!subTree.empty)
                        {
                            auto oldBox = subTree.front.node.box;
                            subTree.front.box = subTree.front.node[]
                                .map!(n => n.box)
                                .fold!((a, b) => a.expand(b))(BoxType.init);
                            if (subTree.front.box == oldBox) // boxes wouldn't shrink any further, terminate early
                                break;
                            subTree.popFront;
                        }
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
            assert(0, "dead end 3");
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

void remove(RTree, ElementType)(ref RTree tree, auto ref ElementType element)
    if (is(ElementType == RTree.ElementType))
{
    import std.stdio;
    alias ReferenceType = RTree.ReferenceType;
    immutable searchBox = tree.getBox(element);
    auto fr = tree.findEntry(element);
    Stack!ReferenceType orphanStack;
    scope(exit)
    {
        orphanStack.destroy;
        fr.nodeStack.destroy;
    }
    assert(fr.index != size_t.max, "element not found in tree");
    removeEntryFromNode(fr.nodeStack.front.leaf, fr.index);

    if (fr.nodeStack.front.leaf.length < tree.minChildrenPerNode && false)
    {
        import std.algorithm.searching : countUntil;
        ReferenceType deadLeaf = fr.nodeStack.front; // we'll reinsert the contained elements later
        fr.nodeStack.popFront;
        removeEntryFromNode(fr.nodeStack.front.node, fr.nodeStack.front.node[].countUntil!(n => n == deadLeaf));

        bool collapse = true;
        while (!fr.nodeStack.empty)
        {
            if (fr.nodeStack.front.node[].walkLength < tree.minChildrenPerNode
                && collapse
                && &(fr.nodeStack.front.node()) != tree.rootPtr && false)
            {
                ReferenceType deadNode = fr.nodeStack.front;
                foreach (r; fr.nodeStack.front.node[])
                    orphanStack.pushFront(r);
                fr.nodeStack.front.node.eraseNode;
                fr.nodeStack.popFront;
                removeEntryFromNode(
                    fr.nodeStack.front.node,
                    fr.nodeStack.front.node[].countUntil!(n => n == deadNode));
                dispose(tree.nodeAllocator, &(deadNode.node()));
            }
            else
            {
                import std.algorithm.iteration : map, fold;
                collapse = false;
                //import std.stdio;
                //stderr.writefln!"%s %s"(fr.nodeStack.front, fr.nodeStack.front.node);
                foreach (e; fr.nodeStack.front.node[])
                {
                    assert(fr.nodeStack.front.node.box.contains(tree.getBox(e)));
                }
/+                fr.nodeStack.front.node.box = fr.nodeStack.front.node[]
                    .map!((ref n) => tree.getBox(n))
                    .fold!((a, b) => a.expand(b))(RTree.BoxType.init);
                foreach (e; fr.nodeStack.front.node[])
                {
                    assert(fr.nodeStack.front.node.box.contains(tree.getBox(e)));
                }
+/            }
            fr.nodeStack.popFront;
        }
        while (!orphanStack.empty)
        {
            // TODO: see if sorting orphans is useful
            tree.insert(orphanStack.back);
            orphanStack.popBack;
        }
        foreach (ref e; deadLeaf.leaf[])
        {
            tree.insert(e);
        }
        deadLeaf.leaf.eraseNode;
        dispose(tree.nodeAllocator, &(deadLeaf.leaf()));
    }
    else
    {
        import std.algorithm.iteration : map, fold;
        auto oldBox = fr.nodeStack.front.leaf.box;
        /+fr.nodeStack.front.leaf.box = fr.nodeStack.front.leaf[]
            .map!((ref n) => tree.getBox(n))
            .fold!((a, b) => a.expand(b));
        +//+if (oldBox == fr.nodeStack.front.leaf.box) // boxes won't shrink any further, terminate early
            return;
        +/fr.nodeStack.popFront;

        while (!fr.nodeStack.empty)
        {
            /+oldBox = fr.nodeStack.front.node.box;
            fr.nodeStack.front.node.box = fr.nodeStack.front.node[]
                .map!((ref n) => tree.getBox(n))
                .fold!((a, b) => a.expand(b));
            /+if (oldBox == fr.nodeStack.front.node.box) // boxes won't shrink any further, terminate early
                break;
        +/+/
            fr.nodeStack.popFront;
        }
    }
}

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
        assert(node[].all!(n => !n.isNull));
    }
    else static if (is(N == RTree.LeafType))
    {
        alias ChildType = RTree.ElementType;
        assert(node.length == node.childCount);
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
            .sort!((a, b) => tree.getBox(a).min[dimension] < tree.getBox(b).min[dimension]);
    }
    foreach (dimension; 0 .. dimensionCount)
    {
        // it's probable that sorting max results in a similar order as min does
        axes[dimension][].copy(axes[dimension + dimensionCount][]);
        axes[dimension + dimensionCount][]
            .sort!((a, b) => tree.getBox(a).max[dimension] < tree.getBox(b).max[dimension]);
    }

    ChildType[] bestGroupA;
    ChildType[] bestGroupB;
    ManagementType bestPerimeterCost;
    BoxType bestBoxA;
    BoxType bestBoxB;

    foreach (dimension; 0 .. dimensionCount * 2)
    {
        assert((maxChildrenPerNode - 2 * minChildrenPerNode + 2) > 0);
        //foreach (k; 0 .. maxEntriesPerPage - 2 * minEntriesPerPage + 2)
        foreach (k; 0 .. maxChildrenPerNode - minChildrenPerNode * 2 + 1)
        {
            import std.range : take, drop;
            import std.algorithm.iteration : map, fold, sum, filter;
            ChildType[] groupA = axes[dimension][].take(minChildrenPerNode + k);
            ChildType[] groupB = axes[dimension][].drop(minChildrenPerNode + k);
            auto boxA = groupA[]
                .map!(n => tree.getBox(n))
                .fold!((a, b) => a.expand(b));
            auto boxB = groupB[]
                .map!(n => tree.getBox(n))
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

    assert(bestGroupA.length + bestGroupB.length == tree.maxChildrenPerNode);

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
        assert((*newNodeA)[].walkLength + (*newNodeB)[].walkLength == tree.maxChildrenPerNode);
    }
    foreach (ref e; node[])
    {
        import std.algorithm.searching : canFind;
        assert((*newNodeA)[].canFind(e)
               || (*newNodeB)[].canFind(e));
    }
    foreach (ref e; (*newNodeA)[])
    {
        assert(newNodeA.box.contains(tree.getBox(e)));
    }
    foreach (ref e; (*newNodeB)[])
    {
        assert(newNodeB.box.contains(tree.getBox(e)));
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
    if (is(T == RTree.ElementType)
        || is(T == RTree.LeafType)
        || is(T == RTree.NodeType))
{
    import std.typecons : Tuple, tuple;
    immutable(RTree.BoxType) searchBox = tree.getBox(entry);
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

    while (true)
    {
        if (arrStack.empty) // not found
        {
            return ReturnType(Stack!ReferenceType(), size_t.max);
        }
        if (arrStack.front.empty || arrStack.front.front.isNull)
        {
            arrStack.popFront;
            if (arrStack.empty)
                return ReturnType(Stack!ReferenceType(), size_t.max);
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
            if (arrStack.front.front.node.box.contains(tree.getBox(entry)))
            {
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
    alias BoxType = Box!(float, 2);
    auto nodes = File("views/vertdata").byLine.map!((a){double x; double y;
            a.formattedRead!"%f, %f"(y, x);
            return vec2d(x,y);}).array;
    stderr.writeln("loaded nodes");
    alias ElementType = Tuple!(Vector!(double, 2), "data");
    auto pnnn = nodes.enumerate.map!(n => ElementType(n.value)).cycle.take(1_000_000).array;
    alias calcElementBounds =
        (ElementType n){return BoxType(n.data.x,
                           n.data.y,
                           (cast(float)n.data.x).nextUp,// + 0.001,
                           (cast(float)n.data.y).nextUp// + 0.001
                           );};
    RTree!(typeof(pnnn.front), calcElementBounds, 2, 8, 2, float) tree;
    tree.initialize;

    dirEntries("trees/", SpanMode.shallow, false).each!(std.file.remove);
    byte[ElementType] elems;
    import std.random;
    import std.datetime;
    
    //pnnn.randomShuffle;
    auto start = MonoTime.currTime;
    writefln!"starting inserting";
    foreach (i, ref node; pnnn)
    {
        //assert(node !in ptrs);
        //ptrs[node] = 1;

        //assert(node in ptrs);
        //foreach (ref e; tree[])
        //{
        //    assert(&e in ptrs, (&e).to!string ~ " not found in " ~ ptrs.byKey.to!string);
        //}
        if (i % (pnnn.length/20) == 0)
            writefln!"%s %% of %s"(cast(float)i/pnnn.length * 100.0f, pnnn.length);
        tree.insert(node);
        elems[node] = 0;
        //stderr.writefln!"%s: added %s"(i, node);
        //writeln("pageAllocaator:");
        //tree.pageAllocator.reportStatistics(stdout);
        //writeln("stackAllocator:");
        //stackAllocator.reportStatistics(stdout);
     /+   auto file = File(format!"trees/tree%08s.asy"(i++), "w");
        auto writer = file.lockingTextWriter;
        /+Pfmt = (n){return (*n)[].map!(a => polygonBase[a])
         .map!(a => tuple(a.x, a.y))
         .format!"%((%(%s,%s%)) -- %|%)cycle";};
         +///writefln(pFmt(&tris[8]));
        tree.drawTree(writer);
        file.close;
    +/
    }
    auto end = MonoTime.currTime;
    stderr.writefln!"needed %s for insertion, %s per insertion"(end - start, (end - start) / pnnn.length);
    auto file = File(format!"trees/tree_final.asy", "w");
    auto file2 = File(format!"trees/tree_final.dot", "w");
    auto writer = file.lockingTextWriter;
    auto writer2 = file2.lockingTextWriter;
    scope(exit)
    {
        file.close;
        file2.close;
    }
    import core.thread;
    import std.datetime;


    start = MonoTime.currTime;
    foreach (i, n; pnnn)
    {
        if (i % (pnnn.length/20) == 0)
            writefln!"%s %% of %s"(cast(float)i/pnnn.length * 100.0f, pnnn.length);
        auto res = tree.findEntry(n);
        assert(res.index != size_t.max);
        res.nodeStack.destroy;
    }
    end = MonoTime.currTime;
    stderr.writefln!"needed %s for finding, %s per search"(end - start, (end - start) / pnnn.length);
    /+foreach (ii, n; tree[].enumerate)
    {
        writefln!"%s: %s"(ii, n);
    }+/
    start = MonoTime.currTime;
    tree.drawTree(writer, writer2);
    auto ttime = MonoTime.currTime + 500.msecs;
    foreach (i, n; pnnn)
    {
        if (MonoTime.currTime >= ttime || true)
        {
            ttime += 500.msecs;
            writefln!"%s of %s (%s %%)"(i, pnnn.length, cast(float)i/pnnn.length * 100.0f);
        }
        assert(n in elems);
        elems.remove(n);
        if (i >= 999_900)
        {
            file.rewind;
            file2.rewind;
            tree.drawTree(nullSink, nullSink);
        }
        tree.remove(n);
        //stderr.writefln!"%s: removed %s"(i--, n);
        /+foreach (_e; ptrs.byKey)
        {
            ElementType* e = cast(ElementType*)_e;
            writefln!"element %s"(e);
            auto findResult = tree.findEntry(e).map!((ref x) => *x.page);
            writefln!"%(%s\n%)"(findResult.pageStack);
            assert(!findResult.pageStack.empty);
            findResult.pageStack.destroy;
        }+/

        //stderr.writeln("removed ", n, " from ", tree[].map!((ref x) => &x));
    }
    end = MonoTime.currTime;
    stderr.writefln!"needed %s for removal, %s per removal"(end - start, (end - start) / pnnn.length);
    tree.destroy;
}
