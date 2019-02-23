module stack_container;
import std.experimental.allocator;
import std.experimental.allocator.building_blocks.stats_collector;
import std.experimental.allocator.building_blocks.fallback_allocator;
import std.experimental.allocator.mallocator;
import std.experimental.allocator.building_blocks.bitmapped_block;
import std.experimental.allocator.building_blocks.allocator_list;
import std.experimental.allocator.gc_allocator;

class AllocationFailure : Exception
{
    import std.exception;
    mixin basicExceptionCtors;
}

FallbackAllocator!(AllocatorList!((n => BitmappedBlock!(1024,
                                                     platformAlignment,
                                                     Mallocator,
                                                     Yes.multiblock)(1_024_000)),
                                  Mallocator),
                                  Mallocator) stackAllocator;


struct Stack(T)
{
    import std.experimental.allocator;
    import std.exception;

    T[] entryStore;
    T[] entries;

    this(size_t size)
    {
        entryStore = makeArray!T(stackAllocator, size);
        enforce(entryStore !is null, new AllocationFailure("Stack construction failed due to allocation failure"));
    }
    ref T opIndex(size_t i)
    {
        return entries[i];
    }
    size_t opDollar()
    {
        return entries.length;
    }
    typeof(this) reap()
    {
        typeof(this) result = this;
        entryStore = null;
        entries = null;
        return result;
    }
    typeof(this) dup()
    {
        typeof(this) result;
        if (entries.length > 0)
        {
            T[] newStore = makeArray!T(stackAllocator, entries.length);
            enforce(newStore !is null, new AllocationFailure("Stack duplication failed due to allocation failure"));
            newStore[] = entries[];
            result.entryStore = newStore;
            result.entries = newStore;
        }
        return result;
    }
    typeof(this) save()
    {
        return this;
    }
    void destroy()
    {
        import std.algorithm.mutation : fill;
        entryStore.fill(T.init);
        if (entryStore !is null)
            dispose(stackAllocator, entryStore.ptr);
    }
    void clear()
    {
        import std.algorithm.mutation : fill;
        entries.fill(T.init);
        entries = null;
    }
    ref T front() @property
    {
        assert(!this.empty, "attempted to get front of empty stack");
        return entries[$ - 1];
    }
    void popFront()
    {
        assert(!this.empty, "attempted to popFront of empty stack");
        entries[$ - 1] = T.init;
        entries = entries[0 .. $ - 1];
    }
    ref T back() @property
    {
        assert(!this.empty, "attempted to get back of empty stack");
        return entries[0];
    }
    void popBack()
    {
        assert(!this.empty, "attempted to popBack of empty stack");
        entries[0] = T.init;
        entries = entries[1 .. $];
    }
    void pushFront(T value)
    {
        import std.conv;
        assert (entries is null
                || entries is null && entryStore is null
                || entries.ptr >= entryStore.ptr
                && entries.ptr + entries.length <= entryStore.ptr + entryStore.length);

        if (entryStore is null)
        {
            T[] newStore = makeArray!T(stackAllocator, 8);
            enforce(newStore !is null, new AllocationFailure("Stack expansion failed due to allocation failure"));
            entryStore = newStore;
        }
        if (entries.length != 0
            && &entryStore[$ - 1] == &entries[$ - 1]) // no space left for insertion
        {
            if (entryStore.ptr != entries.ptr) // entries can be moved to front of entryStore
            {
                import std.algorithm.mutation : copy, fill;
                entries.copy(entryStore);
                entryStore[entries.length .. $].fill(T.init);
            }
            else // otherwise allocate new space
            {
                import std.algorithm.comparison : max;
                enforce(expandArray(stackAllocator, entryStore, max(entryStore.length, 8)),
                        new AllocationFailure("Stack expansion failed due to allocation failure"));
            }
        }
        entries = entryStore[0 .. entries.length + 1];
        entries[$ - 1] = value;
    }
    bool empty() const
    {
        return entries.empty;
    }
    size_t length() const
    {
        return entries.length;
    }
}
