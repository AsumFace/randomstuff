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


import gfm.math;
import stack_container;

enum RefTypes : ubyte
{
    page = 0b0,
    element = 0b1
}

struct Reference(PageType, ElementType)
{
    private union
    {
        void* _raw;
        PageType* _pagePtr;
        ElementType* _elementPtr;
        RefTypes _refType;
    }
    ElementType* elementPtr() @property
    {
        assert((_refType & 0b1) == RefTypes.element);
        assert(_raw - RefTypes.element !is null);
        return cast(ElementType*)(cast(void*)_elementPtr - RefTypes.element);
    }
    PageType* pagePtr() @property
    {
        assert((_refType & 0b1) == RefTypes.page);
        assert(_raw - RefTypes.page !is null);
        return cast(PageType*)(cast(void*)_pagePtr - RefTypes.page);
    }
    RefTypes type() @property
    {
        return cast(RefTypes)(_refType & 1);
    }
    ElementType* elementPtr(ElementType* ptr) @property
    {
        _elementPtr = cast(ElementType*)(cast(void*)ptr + RefTypes.element);
        return ptr;
    }
    PageType* pagePtr(PageType* ptr) @property
    {
        _pagePtr = cast(PageType*)(cast(void*)ptr + RefTypes.page);
        return ptr;
    }
    bool isNull()
    {
        return _raw is null || (_raw - 1) is null;
    }
    void erase()
    {
        _raw = null;
    }
    this(PageType* ptr)
    {
        pagePtr(ptr);
    }
    this(ElementType* ptr)
    {
        elementPtr(ptr);
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
/+struct Reference(PageType, ElementType)
{
    private union
    {
        void* _raw;
        PageType* _pagePtr;
        ElementType* _elementPtr;
    }
    RefTypes ttt;
    ElementType* elementPtr() @property
    {
        assert(ttt == RefTypes.element);
        assert(_raw !is null);
        return _elementPtr;
    }
    PageType* pagePtr() @property
    {
        assert(ttt == RefTypes.page);
        assert(_raw !is null);
        return _pagePtr;
    }
    RefTypes type() @property
    {
        return ttt;
    }
    ElementType* elementPtr(ElementType* ptr) @property
    {
        _elementPtr = ptr;
        ttt = RefTypes.element;
        return ptr;
    }
    PageType* pagePtr(PageType* ptr) @property
    {
        _pagePtr = ptr;
        ttt = RefTypes.page;
        return ptr;
    }
    bool isNull()
    {
        return _raw is null;
    }
    void erase()
    {
        _raw = null;
    }
    this(PageType* ptr)
    {
        pagePtr(ptr);
    }
    this(ElementType* ptr)
    {
        elementPtr(ptr);
    }
    this(typeof(this) reference)
    {
        _raw = reference._raw;
        ttt = reference.ttt;
    }
    void toString(W)(ref W w)
    {
        import std.format;
        if (isNull)
            w.formattedWrite!"null";
        else
            w.formattedWrite!"%s@%s"(type, _raw);
    }
}+/

struct Page(_ElementType, uint maxRefs, BoxType)
{
    import std.bitmanip;
    private alias ElementType = _ElementType;
    private alias PageType = typeof(this);
    BoxType box = BoxType(0, 0, 0, 0);
    import std.meta;
    Reference!(PageType, ElementType)[maxRefs] _refs;
    void toString(W)(ref W w)
    {
        import std.format;
        w.formattedWrite!"<%s, %s; %s, %s>[%(%s, %)]"(box.min.x, box.min.y, box.max.x, box.max.y, _refs);
    }
}

enum SearchModes
{
    all,
    includesPoint,
    excludesPoint,
    includesBox,
    excludesBox,
    intersectsBox
}
struct RTreeRange(RTree, SearchModes searchMode, bool matchPages)
{
    alias PageType = RTree.PageType;
    alias ElementType = RTree.ElementType;
    alias BoxType = RTree.BoxType;
    alias dimensionCount = RTree.dimensionCount;
    alias entriesPerPage = RTree.maxEntriesPerPage;
    import std.typecons : tuple, Tuple;
    Stack!(Tuple!(PageType*, "page", size_t, "skip")) visitationStack;
    RTree* tree;
    static if (searchMode != SearchModes.all)
    {
        BoxType delegate(ElementType*) calcElementBounds;
        BoxType getBox(T.ReferenceType reference)
        {
            BoxType result;
            if (reference.type == RefTypes.page)
                result = reference.pagePtr.box;
            else
                result = calcElementBounds(reference.elementPtr);
            assert(result.min[].all!(n => !n.isNaN) && result.max[].all!(n => !n.isNaN));
            return result;
        }
    }
    static if (searchMode == SearchModes.all)
    {
        this(ref RTree tree)
        {
            this.tree = &tree;
            visitationStack = Stack!(Tuple!(PageType*, "page", size_t, "skip"))(8);
            visitationStack.pushFront(tuple!("page", "skip")(tree.rootPageReference.pagePtr, 0uL));
            popFront;
        }
    }
    else static if (searchMode == SearchModes.includesPoint
                    || searchMode == SearchModes.excludesPoint)
    {
        BoxType.bound_t searchPoint;
        //TODO: support search of multiple points in one go
        this(ref RTree tree, BoxType.bound_t searchPoint)
        {
            this.tree = &tree;
            this.searchPoint = searchPoint;
            this.calcElementBounds = tree.calcElementBounds;
            visitationStack = Stack!(Tuple!(PageType*, "page", size_t, "skip"))(8);
            visitationStack.pushFront(tuple!("page", "skip")(tree.rootPageReference.pagePtr, 0uL));
            popFront;
        }
    }
    else static if (searchMode == SearchModes.includesBox
                    || searchMode == SearchModes.excludesBox
                    || searchMode == SearchModes.intersectsBox)
    {
        BoxType searchBox;
        //TODO: support search of multiple boxes in one go
        this(ref RTree tree, BoxType searchBox)
        {
            this.tree = &tree;
            this.searchBox = searchBox;
            this.calcElementBounds = tree.calcElementBounds;
            visitationStack = Stack!(Tuple!(PageType*, "page", size_t, "skip"))(8);
            visitationStack.pushTop(tuple!("page", "skip")(tree.rootPageReference.pagePtr, 0uL));
            popFront;
        }
    }

    static if (matchPages == false)
    {
        ref ElementType front()
        {
            assert(!this.empty, "attempted to get front of an empty range!");
            assert((visitationStack.front.skip - 1) <= (size_t.max / 2));
            return *(visitationStack.front.page._refs[visitationStack.front.skip - 1].elementPtr);
        }
    }
    else
    {
        T.ReferenceType front()
        {
            assert(!this.empty, "attempted to get front of an empty range!");
            assert((visitationStack.front.skip - 1) <= (size_t.max / 2));
            if (visitationStack.front.skip == 0)
                return T.ReferenceType(visitationStack.front.page);
            else
                return visitationStack.front.page._refs[visitationStack.front.skip - 1];
        }
    }
    void popFront()
    {
        assert(!visitationStack.empty, "attempted to popFront an empty range!");
        while (!visitationStack.empty)
        {
            if (visitationStack.front.skip >= entriesPerPage)
            {
                visitationStack.popFront;
                continue;
            }
            auto activeEntry = visitationStack.front.page._refs[visitationStack.front.skip];
            //stderr.writefln!"skip: %s, activeEntry: %s, vs.length: %s"(visitationStack.top.skip, activeEntry, visitationStack.length);
            if (activeEntry.isNull)
            {
                visitationStack.popFront;
            }
            else
            {
                visitationStack.front.skip += 1;
                static if (searchMode == SearchModes.includesBox)
                {
                    if (!tree.getBox(activeEntry).contains(searchBox))
                        continue;
                }
                else static if (searchMode == SearchModes.excludesBox)
                {
                    if (tree.getBox(activeEntry).intersects(searchBox))
                        continue;
                }
                else static if (searchMode == SearchModes.intersectsBox)
                {
                    if (!tree.getBox(activeEntry).intersects(searchBox))
                        continue;
                }
                else static if (searchMode == SearchModes.includesPoint)
                {
                    if (tree.getBox(activeEntry).contains(searchPoint))
                        continue;
                }
                else static if (searchMode == SearchModes.excludesPoint)
                {
                    if (!tree.getBox(activeEntry).contains(searchpoint))
                        continue;
                }

                if (activeEntry.type == RefTypes.element)
                {
                    //stderr.writefln!"activeEntry: %s, em: %s"(activeEntry, this.empty);
                    return;
                }
                else if (activeEntry.type == RefTypes.page)
                {
                    visitationStack.pushFront(tuple!("page", "skip")(activeEntry.pagePtr, 0uL));
                    static if (matchPages)
                    {
                        if (visitationStack.top.skip == 1)
                        {
                            visitationStack.top.skip -= 1;
                            return;
                        }
                    }
                }
            }
        }
    }
    bool empty()
    {
        //stderr.writefln!"%s: %s"(__LINE__, visitationStack.empty);
        return visitationStack.empty;
    }

    this(this)
    {
        visitationStack = visitationStack;
    }

    void destroy()
    {
        visitationStack.destroy;
    }
    
    typeof(this) save()
    {
        auto result = this;
        return result;
    }
}

struct RTree(_ElementType, alias BFun, uint _dimensionCount, uint _maxEntriesPerPage = 16, uint _minEntriesPerPage = 6, _ManagementType = float)
{
    alias ElementType = _ElementType;
    alias BoxType = Box!(ManagementType, dimensionCount);
    alias dimensionCount = _dimensionCount;
    alias ManagementType = _ManagementType;
    alias maxEntriesPerPage = _maxEntriesPerPage;
    alias minEntriesPerPage = _minEntriesPerPage;
    static assert(minEntriesPerPage <= (maxEntriesPerPage / 2),
                   "minEntriesPerPage must not be larger than half of maxEntriesPerPage");
    //BoxType delegate(ElementType*) calcElementBounds;
    import std.traits;
    static assert(isCallable!BFun);
    static assert(is(ReturnType!BFun == BoxType));
    static assert(is(Parameters!BFun[0] == ElementType*));
    alias calcElementBounds = BFun;    alias PageType = Page!(ElementType, maxEntriesPerPage, BoxType);
    alias ReferenceType = Reference!(PageType, ElementType);
    ReferenceType rootPageReference;
    import std.experimental.allocator.common;
    static if (PageType.sizeof % platformAlignment != 0)
        pragma(msg, "INFO: page size ", PageType.sizeof,
                    " will be padded by ", platformAlignment - PageType.sizeof % platformAlignment,
                    " bytes to match the platform alignment ", platformAlignment);
    import std.experimental.allocator.building_blocks.allocator_list;
    import std.experimental.allocator.building_blocks.bitmapped_block;
    import std.experimental.allocator.mallocator;
    import std.experimental.allocator;
    AllocatorList!((n => BitmappedBlock!(PageType.sizeof + PageType.sizeof % platformAlignment,
                                         platformAlignment,
                                         Mallocator,
                                         No.multiblock)(128_000)),
                   Mallocator) pageAllocator;
    
    //import std.experimental.allocator.building_blocks.free_tree;
    //FreeTree!Mallocator pageAllocator;
    //alias pageAllocator = stackAllocator;
    void initialize()
    {
        import std.exception;
        auto newRef = make!PageType(pageAllocator);
        enforce(newRef !is null, new AllocationFailure("Initialization of RTree failed due to allocation failure"));
        rootPageReference = ReferenceType(newRef);
    }

    void destroy()
    {
        auto pageStack = Stack!(PageType*)(8);
        scope(exit)
            pageStack.destroy;
        pageStack.pushFront(rootPageReference.pagePtr);
        while (!pageStack.empty)
        {
            auto pageRefs = pageStack.front.filterRefs!(filterModes.page);
            if (!pageRefs.empty)
            {
                pageStack.pushFront(pageRefs.front.value.pagePtr);
                continue;
            }
            auto killPage = pageStack.front;
            pageStack.popFront;
            dispose(pageAllocator, killPage);
            if (!pageStack.empty) // false if only the root page is left
            {
                import std.algorithm.searching : countUntil;
                pageStack.front.removeEntryFromPage(pageStack.front._refs[].countUntil!(n => n == ReferenceType(killPage)));
            }
        }
    }

    RTreeRange!(typeof(this), SearchModes.all, false) opSlice()
    {
        return typeof(return)(this);
    }

    BoxType getBox(ReferenceType reference)
    {
        import std.algorithm;
        import std.math;
        BoxType result;
        if (reference.type == RefTypes.page)
            result = reference.pagePtr.box;
        else
            result = calcElementBounds(reference.elementPtr);
        assert(result.min[].all!(n => !n.isNaN) && result.max[].all!(n => !n.isNaN));
        return result;
    }
}

private void drawTree(RTree, W)(ref RTree tree, ref W w)
{
    import std.format;
    import std.range;
    import std.algorithm;
    import std.typecons;
    import std.stdio;
    alias PageType = tree.PageType;
    alias ReferenceType = tree.ReferenceType;
    w.formattedWrite!`settings.outformat="pdf";`;
    w.formattedWrite!"\nunitsize(100cm);\n";
    auto visitationStack = Stack!(Tuple!(PageType*, "page", size_t, "skip"))(8);
    scope(exit)
        visitationStack.destroy;
    visitationStack.pushFront(tuple!("page", "skip")(tree.rootPageReference.pagePtr, 0uL));

    while (!visitationStack.empty)
    {
        if (visitationStack.front.skip >= tree.maxEntriesPerPage)
        {
            visitationStack.popFront;
            continue;
        }
        auto activeEntry = visitationStack.front.page._refs[visitationStack.front.skip];
        if (activeEntry.isNull)
        {
            visitationStack.popFront;
        }
        else
        {
            visitationStack.front.skip += 1;
            if (activeEntry.type == RefTypes.page)
            {
                //writefln!"level: %s entries: %s"(visitationStack.length, activeEntry.pagePtr._refs[]
                //                                 .until!(n => n.isNull).walkLength);
                auto entryBox = tree.getBox(ReferenceType(activeEntry.pagePtr));
                w.formattedWrite!"draw(box((%s, %s), (%s, %s)), hsv(0.0, 1.0, %s)+linewidth(1mm));\n"(entryBox.min.x,
                                                                                        entryBox.min.y,
                                                                                        entryBox.max.x,
                                                                                        entryBox.max.y,
                                                                                        visitationStack.length/100.0);
                visitationStack.pushFront(tuple!("page", "skip")(activeEntry.pagePtr, 0uL));
            }
            else if (activeEntry.type == RefTypes.element)
            {
                auto entryBox = tree.getBox(ReferenceType(activeEntry.elementPtr));
                w.formattedWrite!"draw(box((%s, %s), (%s, %s)), blue);\n"(entryBox.min.x,
                                                                          entryBox.min.y,
                                                                          entryBox.max.x,
                                                                          entryBox.max.y);
            }
        }
    }
}

private auto removeEntryFromPage(PageType)(PageType* page, size_t index)
{
    assert(page !is null);
    assert(index != size_t.max);
    import std.conv : to;
    assert(!page._refs[index].isNull, "attempted to remove element " ~ index.to!string ~ " from " ~ (*page).to!string);
    alias ReferenceType = Reference!(PageType, PageType.ElementType);
    ReferenceType result = page._refs[index];
    import std.algorithm.mutation : stdremove = remove, SwapStrategy;
    page._refs[].stdremove!(SwapStrategy.stable)(index);
    page._refs[$ - 1].erase;
    assert(page !is null);
    return result;
}

private size_t addEntryToPage(PageType, ElementType)(PageType* page, Reference!(PageType, ElementType) entry)
    if (is(ElementType == PageType.ElementType))
{
    import std.algorithm.searching;
    assert(page !is null);
    import std.stdio;
    //stderr.writef!"inserting %s at "(entry);
    size_t entryCount = page._refs[].countUntil!(n => n.isNull);
    import std.conv : to;
    assert(entryCount < page._refs.length, "attempted to insert into full page: " ~ (*page).to!string);
    page._refs[entryCount] = entry;
    auto newEntryCount = page._refs[].countUntil!(n => n.isNull);
    if (newEntryCount == -1)
        newEntryCount = entryCount + 1;
    //stderr.writefln!"%s"(newEntryCount - 1);
    assert(entryCount + 1 == newEntryCount);
    return newEntryCount;
}

private enum filterModes
{
    valid,
    element,
    page
}

private auto filterRefs(filterModes mode, PageType)(PageType* page)
{
    import std.algorithm.searching;
    import std.algorithm.iteration : filter;
    import std.range;
    static if (mode == filterModes.valid)
        return page._refs[].until!(n => n.isNull).enumerate;
    else static if (mode == filterModes.element)
        return page._refs[].until!(n => n.isNull).enumerate.filter!(n => n.value.type == RefTypes.element);
    else static if (mode == filterModes.page)
        return page._refs[].until!(n => n.isNull).enumerate.filter!(n => n.value.type == RefTypes.page);
    else
        static assert(0);
}

void insert(RTree, R)(ref RTree tree, R _reference, size_t level = size_t.max)
    if (is(R == RTree.ReferenceType)
        || is(R == RTree.ElementType*)
        || is(R == RTree.PageType*))
{
    alias ReferenceType = tree.ReferenceType;
    alias PageType = tree.PageType;
    alias BoxType = tree.BoxType;
    alias ElementType = tree.ElementType;
    ReferenceType reference = ReferenceType(_reference);
    auto subTree = tree.chooseSubTree(tree.getBox(reference));
    PageType* activePage = subTree.front.pagePtr;
    import std.algorithm.searching : all, countUntil, maxElement;
    import std.algorithm.iteration : filter, sum, map, fold;
    import std.range : walkLength;
    bool overflow = activePage._refs[].filter!(n => !n.isNull).walkLength == tree.maxEntriesPerPage;
    /+if (overflow && subTree.length < level)
    {
        import std.math : abs;

        // computes manhattan distance of centers
//        alias mapFun = a => (activePage.box.center - tree.getBox(ReferenceType(a)).center).v[].map!abs.sum;
        tree.ManagementType mapFun(T)(T a)
        {
            import std.range;
            import std.algorithm;
            //return (activePage.box.center - tree.getBox(ReferenceType(a)).center).v[].map!abs.sum;
            auto c = activePage.box.center;
            auto b = tree.getBox(ReferenceType(a));
            tree.BoxType.bound_t[4] vertices = [b.min, b.min + b.size.x, b.min+b.size.y, b.max];
            return vertices[].map!(n => (c - n).v[].map!abs.sum).maxElement;
        }

        
        import std.range : enumerate;
        auto worstElement = activePage._refs[].enumerate.maxElement!(n => mapFun(n.value));
        ReferenceType orphan;
        if (mapFun(reference) < mapFun(worstElement.value))
        {
            orphan = worstElement.value;
            activePage._refs[worstElement.index] = reference;
        
            while (!subTree.empty) // calculate new bounds
            {
                activePage = subTree.front.pagePtr;
                auto newBox = subTree.front.pagePtr
                    .filterRefs!(filterModes.valid)
                    .map!(n => tree.getBox(n.value))
                    .fold!((a, b) => a.expand(b))(BoxType(0, 0, 0, 0));
                if (activePage.box == newBox)
                    break; // outer boxes won't change, early termination
                activePage.box = newBox;
                subTree.popFront;
            }
            subTree.destroy;
            tree.insert(orphan, subTree.length);
            return;
        }
    }+/
    while (true)
    {
        if (activePage._refs[].filter!(n => !n.isNull).walkLength == tree.maxEntriesPerPage) // overflow
        {
            tree.splitFull(activePage);
            //activePage.addEntryToPage(reference);
            auto newSubTree = tree.chooseSubTree(tree.getBox(reference), activePage);
            while (!newSubTree.empty)
            {
                subTree.pushFront(newSubTree.back);
                newSubTree.popBack;
            }
            newSubTree.destroy;
            activePage = subTree.front.pagePtr;
            continue;
            //tree.insert(reference);
        }
        else
        {
            activePage.addEntryToPage(reference);
            break;
        }
    }
    while (!subTree.empty) // apply the new bounds calculated by chooseSubTree
    {
        subTree.front.pagePtr.box = subTree.front.box;
        subTree.popFront;
    }
    subTree.destroy;
}

private auto chooseSubTree(RTree, BoxType)(ref RTree tree, BoxType searchBox)
    if (is(BoxType == tree.BoxType))
{
    return chooseSubTree(tree, searchBox, tree.rootPageReference.pagePtr);
}
private auto chooseSubTree(RTree, BoxType, PageType)(ref RTree tree, BoxType searchBox, PageType* begin)
    if (is(BoxType == tree.BoxType)
        && is(PageType == tree.PageType))
{
    import std.typecons : Tuple, tuple;
    alias BoxType = tree.BoxType;
    alias ManagementType = tree.ManagementType;
    alias ReferenceType = tree.ReferenceType;
    Stack!(Tuple!(PageType*, "pagePtr", BoxType, "box")) result;
    assert(begin !is null);
    PageType* activeRef = begin;
    result.pushFront(tuple!("pagePtr", "box")(activeRef, activeRef.box.expand(searchBox)));
    while (true)
    {
        auto validRefs = activeRef.filterRefs!(filterModes.valid);
        auto pageRefs = activeRef.filterRefs!(filterModes.page);
        Tuple!(PageType*, "reference",
               ManagementType, "overlapCost",
               ManagementType, "volumeCost",
               ManagementType, "volume",
               BoxType, "newPageBox") bestMatch;

        import std.traits : isFloatingPoint;
        static if (isFloatingPoint!ManagementType)
        {
            bestMatch.overlapCost = ManagementType.infinity;
            bestMatch.volumeCost = ManagementType.infinity;
            bestMatch.volume = ManagementType.infinity;
        }
        else
        {
            bestMatch.overlapCost = ManagementType.max;
            bestMatch.volumeCost = ManagementType.max;
            bestMatch.volume = ManagementType.max;
        }
        import std.range : walkLength;
        if (!pageRefs.empty
            && validRefs.walkLength >= tree.maxEntriesPerPage)
        {
            /+import std.algorithm.searching : minElement;
            import std.algorithm.iteration : map, sum;
            import std.math : abs;
            alias mapFun = a => (searchBox.center - tree.getBox(a.value).center).v[].map!abs.sum;
            bestMatch.reference = pageRefs.minElement!mapFun.value.pagePtr;
            bestMatch.newPageBox = tree.getBox(ReferenceType(bestMatch.reference)).expand(searchBox);
            +/
            foreach (i, reference; pageRefs)
            {
                auto pageBox = tree.getBox(reference);
                auto newPageBox = pageBox.expand(searchBox);
                auto volume = pageBox.volume;
                ManagementType overlapCost = 0;
                foreach (ii, reference2; pageRefs) // determining the cost cas O(n²) complexity and can be optimized by heuristics
                {
                    if (reference2 == reference)
                        continue;
                    auto pageBox2 = reference2.pagePtr.box;
                    auto intersectionBox = pageBox.intersection(pageBox2);
                    auto newIntersectionBox = newPageBox.intersection(pageBox2);
                    overlapCost += newIntersectionBox.volume - intersectionBox.volume;
                }
                auto volumeCost = newPageBox.volume - volume;
                if (overlapCost < bestMatch.overlapCost
                    || overlapCost == bestMatch.overlapCost
                    //&& volumeCost < bestMatch.volumeCost
                    //|| overlapCost == bestMatch.overlapCost
                    //&& volumeCost == bestMatch.volumeCost
                    //&& volume < newPageBox.volume
                    )
                {
                    bestMatch.reference = reference.pagePtr;
                    bestMatch.overlapCost = overlapCost;
                    //bestMatch.volumeCost = volumeCost;
                    //bestMatch.volume = volume;
                    bestMatch.newPageBox = newPageBox;
                }
            }
            result.pushFront(tuple!("pagePtr", "box")(bestMatch.reference, bestMatch.newPageBox));
            activeRef = bestMatch.reference;
        }
        else
        {
            assert(!result.empty);
            return result;
        }
    }
}

void remove(RTree, ElementType)(ref RTree tree, ElementType* elementPtr)
    if (is(ElementType == RTree.ElementType))
{
    alias ReferenceType = tree.ReferenceType;
    alias PageType = tree.PageType;
    alias BoxType = tree.BoxType;
    auto findResult = tree.findEntry(elementPtr);
    scope(exit)
        findResult.pageStack.destroy;
    if (findResult.index == size_t.max) // element not found
        assert(0);

    removeEntryFromPage(findResult.pageStack.front, findResult.index);

    auto orphans = Stack!ReferenceType(8);
    scope(exit)
        orphans.destroy;
    while (!findResult.pageStack.empty)
    {
        import std.range : walkLength;
        PageType* activePage = findResult.pageStack.front;
        assert(activePage !is null);
        if (findResult.pageStack.length >= 2
            && activePage.filterRefs!(filterModes.valid).walkLength < tree.minEntriesPerPage)
            // page underflow, orphan all entries except when it's the root page
        {
            import std.algorithm.iteration : each;
            import std.algorithm.mutation : fill;
            import std.algorithm.searching : countUntil;
            activePage.filterRefs!(filterModes.valid).each!(n => orphans.pushFront(n.value));
            activePage._refs[].fill(ReferenceType.init);
            findResult.pageStack.popFront;
            auto index = findResult.pageStack.front._refs[].countUntil!(n => n == ReferenceType(activePage));
            assert(index != -1);

            // remove page reference and deallocate page
            removeEntryFromPage(findResult.pageStack.front, index);
            import std.experimental.allocator;
            dispose(tree.pageAllocator, activePage);

            // try to cheaply reinsert into tree
            import std.algorithm.comparison : min;
            size_t freeSlots = tree.maxEntriesPerPage - findResult.pageStack.front.filterRefs!(filterModes.valid).walkLength;
            foreach (_; 0 .. min(freeSlots, orphans.length))
            {
                findResult.pageStack.front.addEntryToPage(orphans.back);
                orphans.popBack;
            }
        }
        else
        {
            import std.algorithm.iteration : map, fold;
            auto newBox = findResult.pageStack.front
                .filterRefs!(filterModes.valid)
                .map!(n => tree.getBox(n.value))
                .fold!((a, b) => a.expand(b))(BoxType(0, 0, 0, 0));
            if (activePage.box == newBox)
                break; // outer boxes won't change, early termination
            activePage.box = newBox;
        }
    }
    // expensively reinsert orphans into tree
    while (!orphans.empty)
    {
        tree.insert(orphans.back); // iterating from back *might* be faster than front, so we'll do that
        orphans.popBack;
    }
}

private void splitFull(RTree, PageType)(ref RTree tree, PageType* pagePtr)
    if (is(PageType == RTree.PageType))
{
    alias ReferenceType = tree.ReferenceType;
    alias dimensionCount = tree.dimensionCount;
    alias maxEntriesPerPage = tree.maxEntriesPerPage;
    alias minEntriesPerPage = tree.minEntriesPerPage;
    alias ManagementType = tree.ManagementType;
    alias BoxType = tree.BoxType;
    ReferenceType[maxEntriesPerPage][dimensionCount * 2] axesBase;
    ReferenceType[][dimensionCount * 2] axes;
    auto validRefs = pagePtr.filterRefs!(filterModes.valid);
    import std.conv : to;
    import std.range : walkLength;
    assert(pagePtr.filterRefs!(filterModes.valid).walkLength == tree.maxEntriesPerPage,
        "attempted to split a page with "
        ~ pagePtr.filterRefs!(filterModes.valid).walkLength.to!string
        ~ "/" ~ tree.maxEntriesPerPage.to!string ~ " entries");

    foreach (dimension; 0 .. dimensionCount * 2)
    {
        import std.algorithm.mutation : copy;
        import std.algorithm.sorting : sort;
        import std.algorithm.iteration : map;
        import std.range;
        auto remainder = validRefs.map!"a.value".copy(axesBase[dimension][]).length;
        axes[dimension] = axesBase[dimension][0 .. axesBase[dimension].length - remainder];
        if (dimension < dimensionCount)
            axes[dimension].sort!((a, b) => tree.getBox(a).min[dimension % dimensionCount]
                                            < tree.getBox(b).min[dimension % dimensionCount]);
        else
            axes[dimension].sort!((a, b) => tree.getBox(a).max[dimension % dimensionCount]
                                            < tree.getBox(b).max[dimension % dimensionCount]);
    }
    import std.typecons : Tuple;
    Tuple!(ReferenceType[], "groupA",
           ReferenceType[], "groupB",
           ManagementType, "perimeterCost",
           BoxType, "boxA",
           BoxType, "boxB") bestSplit;

    import std.traits : isFloatingPoint;
    static if (isFloatingPoint!ManagementType)
    {
        bestSplit.perimeterCost = ManagementType.infinity;
    }
    else
    {
        bestSplit.perimeterCost = ManagementType.max;
    }

    foreach (dimension; 0 .. dimensionCount * 2)
    {
        assert((maxEntriesPerPage - 2 * minEntriesPerPage + 2) > 0);
        //foreach (k; 0 .. maxEntriesPerPage - 2 * minEntriesPerPage + 2)
        foreach (k; 0 .. maxEntriesPerPage - minEntriesPerPage * 2 + 1)
        {
            import std.range : take, drop;
            import std.algorithm.iteration : map, fold, sum, filter;
            ReferenceType[] groupA = axes[dimension].take(minEntriesPerPage + k);
            ReferenceType[] groupB = axes[dimension].drop(minEntriesPerPage + k);
            auto boxA = groupA.filter!(n => n.type == RefTypes.element)
                .map!(n => tree.getBox(n))
                .fold!((a, b) => a.expand(b))(BoxType(0, 0, 0, 0));
            auto boxB = groupB.filter!(n => n.type == RefTypes.element)
                .map!(n => tree.getBox(n))
                .fold!((a, b) => a.expand(b))(BoxType(0, 0, 0, 0));
            auto perimeterA = boxA.size.v[].sum ^^ 2;
            auto perimeterB = boxB.size.v[].sum ^^ 2;
            auto perimeterCost = perimeterA + perimeterB;
            if (bestSplit.perimeterCost > perimeterCost)
            {
                bestSplit.groupA = groupA;
                bestSplit.groupB = groupB;
                bestSplit.perimeterCost = perimeterCost;
                bestSplit.boxA = boxA;
                bestSplit.boxB = boxB;
            }
        }
        import std.range : empty;
        import std.experimental.allocator;
        assert(!bestSplit.groupA.empty && !bestSplit.groupB.empty);
        auto pageA = ReferenceType(make!PageType(tree.pageAllocator));
        auto pageB = ReferenceType(make!PageType(tree.pageAllocator));
        import std.exception : enforce;
        enforce(pageA.pagePtr !is null, new AllocationFailure("Page split failed due to allocation failure!"));
        enforce(pageB.pagePtr !is null, new AllocationFailure("Page split failed due to allocation failure!"));
        import std.range : lockstep;
        foreach (ref target, entry; lockstep(pageA.pagePtr._refs[], bestSplit.groupA)) // populate new pages
        {
            target = entry;
        }
        pageA.pagePtr.box = bestSplit.boxA;
        foreach (ref target, entry; lockstep(pageB.pagePtr._refs[], bestSplit.groupB))
        {
            target = entry;
        }
        pageB.pagePtr.box = bestSplit.boxB;
        import std.algorithm.mutation : fill;
        pagePtr._refs[].fill(ReferenceType.init); // erase double references
        pagePtr._refs[0] = pageA; // reference our new pages
        pagePtr._refs[1] = pageB;
        // no boxes need to be recalculated at this point
       
        //move child pages higher up for better space utilization
        foreach (index, page; pageA.pagePtr.filterRefs!(filterModes.page))
        {
            pagePtr.addEntryToPage(pageA.pagePtr.removeEntryFromPage(index));
        }
        foreach (index, page; pageB.pagePtr.filterRefs!(filterModes.page))
        {
            pagePtr.addEntryToPage(pageB.pagePtr.removeEntryFromPage(index));
        }
        if (pageA.pagePtr.filterRefs!(filterModes.valid).walkLength < minEntriesPerPage
            || pageB.pagePtr.filterRefs!(filterModes.valid).walkLength < minEntriesPerPage) // underflow
        {
            import std.algorithm.iteration : map, fold;
            auto orphans = Stack!ReferenceType(8);
            if (pageA.pagePtr.filterRefs!(filterModes.valid).walkLength < minEntriesPerPage)
            {
                foreach (index, entry; pageA.pagePtr.filterRefs!(filterModes.valid))
                    orphans.pushFront(pageA.pagePtr.removeEntryFromPage(index));
                pageA.pagePtr.box = pageA.pagePtr.filterRefs!(filterModes.valid)
                                    .map!(n => tree.getBox(n.value))
                                    .fold!((a, b) => a.expand(b))(BoxType(0, 0, 0, 0));
            }
            if (pageB.pagePtr.filterRefs!(filterModes.valid).walkLength < minEntriesPerPage)
            {
                foreach (index, entry; pageB.pagePtr.filterRefs!(filterModes.valid))
                    orphans.pushFront(pageB.pagePtr.removeEntryFromPage(index));
                pageB.pagePtr.box = pageB.pagePtr.filterRefs!(filterModes.valid)
                                    .map!(n => tree.getBox(n.value))
                                    .fold!((a, b) => a.expand(b))(BoxType(0, 0, 0, 0));
            }
            while (!orphans.empty)
            {
                tree.insert(orphans.back);
                orphans.popBack;
            }
            orphans.destroy;
        }
    }
}

private auto findEntry(RTree, T)(ref RTree tree, T reference)
    if (is(T == RTree.ReferenceType)
        || is(T == RTree.ElementType*)
        || is(T == RTree.PageType*))
{
    RTree.BoxType searchBox = tree.getBox(RTree.ReferenceType(reference));
    auto indexStack = Stack!size_t(8);
    indexStack.pushFront(size_t.max);
    auto pageStack = Stack!(RTree.PageType*)(8);
    scope(exit)
        indexStack.destroy;
    static if (is(T == RTree.PageType*) || is(T == RTree.ReferenceType))
    {
        if (tree.rootPageReference == RTree.ReferenceType(reference))
        {
            return tuple!("pageStack", "index")(pageStack, cast(size_t)0);
        }
    }
    pageStack.pushFront(tree.rootPageReference.pagePtr);
    RTree.PageType* activePage() @property
    {
        return pageStack.front;
    }

    import std.typecons : Tuple, tuple;
    while (true)
    {
        if (indexStack.empty) // not found
        {
            return tuple!("pageStack", "index")(pageStack, size_t.max);
        }
        if (indexStack.front == size_t.max) // scan elements upon first visit
        {
            foreach (index, entry; activePage.filterRefs!(filterModes.valid))
            {
                if (entry == RTree.ReferenceType(reference))
                {
                    return tuple!("pageStack", "index")(pageStack, cast(size_t)index);
                }
            }
            indexStack.front += 1;
        }

        if (indexStack.front >= tree.maxEntriesPerPage
            || activePage._refs[indexStack.front].isNull)
        {
            indexStack.popFront;
            pageStack.popFront;
            continue;
        }
        else if (activePage._refs[indexStack.front].type == RefTypes.page
                 && activePage._refs[indexStack.front].pagePtr.box.contains(searchBox))
        {

            auto newPagePtr = activePage._refs[indexStack.front].pagePtr;
            indexStack.front += 1;
            pageStack.pushFront(newPagePtr);
            indexStack.pushFront(size_t.max);
            assert(*activePage == *newPagePtr);
            continue;
        }
        indexStack.front += 1;
    }
}
unittest
{
    // testing the low level insertion function
    import std.algorithm;
    import std.stdio;
    
    int[] data = [7, 6, 5, 4, 3, 9, 8];
    Box!(float, 2)[] boxes;
    auto tree = RTree!(int, (int* n) => boxes[*n], 2, 5, 1, float)();
    alias PageType = tree.PageType;
    alias BoxType = tree.BoxType;
    alias ElementType = tree.ElementType;
    alias ReferenceType = tree.ReferenceType;
    boxes = [BoxType(-84.0f, -60.0f, 90.0f, 77.0f), // outer box
             BoxType(-67.0f, 10.0f, -10.0f, 66.0f), // upper left box
             BoxType(27.0f, -53.0f, 82.0f, -12.0f), // lower right box
             BoxType(-55.0f, 36.0f, -41.0f, 51.0f), // upper left element
             BoxType(-29.0f, 39.0f, -17.0f, 52.0f), // upper center element
             BoxType(-38.0f, 12.0f, -26.0f, 22.0f), // center left element
             BoxType(-17.0f, 2.0f, 0.0f, 18.0f), // center element
             BoxType(50.0f, 40.0f, 62.0f, 52.0f), // upper right element
             BoxType(45.0f, -33.0f, 57.0f, -27.0f), // center right element
             BoxType(64.0f, -43.0f, 75.0f, -31.0f)]; // lower right element

    tree.initialize;

    tree.rootPageReference.pagePtr.box = boxes[0];
    tree.rootPageReference.pagePtr.addEntryToPage(ReferenceType(&data[0]));
    tree.rootPageReference.pagePtr.addEntryToPage(ReferenceType(&data[1]));
    tree.rootPageReference.pagePtr.addEntryToPage(ReferenceType(&data[2]));

    import std.experimental.allocator;
    PageType* newPage = make!PageType(tree.pageAllocator);
    newPage.box = boxes[1];
    tree.rootPageReference.pagePtr.addEntryToPage(ReferenceType(newPage));
    newPage.addEntryToPage(ReferenceType(&data[3]));
    newPage.addEntryToPage(ReferenceType(&data[4]));
    //writefln!"newPage: %s"(*newPage);

    newPage = make!PageType(tree.pageAllocator);
    newPage.box = boxes[2];
    tree.rootPageReference.pagePtr.addEntryToPage(ReferenceType(newPage));
    newPage.addEntryToPage(ReferenceType(&data[5]));
    newPage.addEntryToPage(ReferenceType(&data[6]));

    import std.stdio;

    // testing the entry locating function
    foreach (ref d; data)
    {
        auto entryPath = tree.findEntry(&d);
        writefln!"searching for %s: %s->%s"(tree.ReferenceType(&d), entryPath.pageStack, entryPath.index);
        assert(entryPath.index != size_t.max);
        entryPath.pageStack.destroy;
    }

    // testing the split function
    writefln!"performing split of root page";
    tree.splitFull(tree.rootPageReference.pagePtr);

    // testing the entry locating function and checking split
    foreach (ref d; data)
    {
        auto entryPath = tree.findEntry(&d);
        writefln!"searching for %s: %s->%s"(tree.ReferenceType(&d), entryPath.pageStack, entryPath.index);
        assert(entryPath.index != size_t.max);
        entryPath.pageStack.destroy;
    }

    writefln!"removing %s from tree"(ReferenceType(&data[5]));
    tree.remove(&data[5]);

    foreach (ref d; data)
    {
        auto entryPath = tree.findEntry(&d);
        writefln!"searching for %s: %s->%s"(tree.ReferenceType(&d), entryPath.pageStack, entryPath.index);
        if (&d == &data[5])
            assert(entryPath.pageStack.empty && entryPath.index == size_t.max);
        else
            assert(entryPath.index != size_t.max);
        entryPath.pageStack.destroy;
    }

    writefln!"removing all elements";
    tree.remove(&data[0]);
    tree.remove(&data[1]);
    tree.remove(&data[2]);
    tree.remove(&data[3]);
    tree.remove(&data[4]);
    tree.remove(&data[6]);

    foreach (ref d; data)
    {
        auto entryPath = tree.findEntry(&d);
        writefln!"searching for %s: %s->%s"(tree.ReferenceType(&d), entryPath.pageStack, entryPath.index);
        assert(entryPath.pageStack.empty && entryPath.index == size_t.max);
        entryPath.pageStack.destroy;
    }

    writefln!"inserting all elements";
    foreach (ref d; data)
    {
        tree.insert(&d);
    }
    foreach (ref d; data)
    {
        auto entryPath = tree.findEntry(&d);
        writefln!"searching for %s: %s->%s"(tree.ReferenceType(&d), entryPath.pageStack, entryPath.index);
        assert(entryPath.index != size_t.max);
        entryPath.pageStack.destroy;
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
    alias BoxType = Box!(float, 2);
    auto nodes = File("views/vertdata").byLine.map!((a){double x; double y;
            a.formattedRead!"%f, %f"(y, x);
            return vec2d(x,y);}).array;
    auto nodePtrs = nodes.map!((ref n) => &n);
    stderr.writeln("loaded nodes");
    alias calcElementBounds =
        (Vector!(double, 2)* n){return BoxType(n.x,
                           n.y,
                           (cast(float)n.x).nextUp,// + 0.001,
                           (cast(float)n.y).nextUp// + 0.001
                           );};
    RTree!(Vector!(double, 2), calcElementBounds, 2, 8, 2) tree;
    tree.initialize;

    dirEntries("trees/", SpanMode.shallow, false).each!(std.file.remove);
    size_t i;
    alias ElementType = typeof(tree).ElementType;
    //byte[ElementType*] ptrs;
    import std.random;
    import std.datetime;
    auto pnnn = nodePtrs.take(1_000_000).array;
    pnnn.randomShuffle;
    auto start = MonoTime.currTime;
    foreach (ref node; pnnn)
    {
        //assert(node !in ptrs);
        //ptrs[node] = 1;

        //assert(node in ptrs);
        //foreach (ref e; tree[])
        //{
        //    assert(&e in ptrs, (&e).to!string ~ " not found in " ~ ptrs.byKey.to!string);
        //}
        i++;
        tree.insert(node);
        //stderr.writefln!"%s: added %s"(i, node);
        //writeln("pageAllocator:");
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
    auto writer = file.lockingTextWriter;
    tree.drawTree(writer);
    file.close;
    import core.thread;
    import std.datetime;


    start = MonoTime.currTime;
    foreach (n; pnnn)
    {
        tree.findEntry(n);
    }
    end = MonoTime.currTime;
    stderr.writefln!"needed %s for finding, %s per search"(end - start, (end - start) / pnnn.length);
    /+foreach (ii, n; tree[].enumerate)
    {
        writefln!"%s: %s"(ii, n);
    }+/
    start = MonoTime.currTime;
    foreach (ref n; pnnn)
    {
        //assert(n in ptrs);
        //ptrs.remove(n);
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
