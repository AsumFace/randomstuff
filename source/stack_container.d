module stack_container;
import std.experimental.allocator;
import std.experimental.allocator.building_blocks.stats_collector;
import std.experimental.allocator.building_blocks.fallback_allocator;
import std.experimental.allocator.mallocator;
import std.experimental.allocator.building_blocks.bitmapped_block;
import std.experimental.allocator.building_blocks.allocator_list;
import std.experimental.allocator.gc_allocator;
import required;

class AllocationFailure : Exception
{
    import std.exception;
    mixin basicExceptionCtors;
}

/+FallbackAllocator!(AllocatorList!((n => BitmappedBlock!(1024,
                                                     platformAlignment,
                                                     Mallocator,
                                                     Yes.multiblock)(1_024_000)),
                                  Mallocator),
                                  Mallocator) stackAllocator;
+/

alias stackAllocator = Mallocator.instance;

/**
A loosely stack-like data structure using manual memory management.
*/
struct Stack(T)
{
    import std.experimental.allocator;
    import std.exception;

    T[] entryStore;
    T[] entries;

    this(size_t size)
    {
        //if (!__ctfe)
            entryStore = makeArray!T(stackAllocator, size);
        //else
        //    entryStore = new T[size];
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
    /**
    Invalidates `this` and transfers all its resources to `return`.
    Does not invalidate any pointers to elements.
    Does not invalidate dependent copies.
    */
    typeof(this) reap()
    {
        typeof(this) result = this;
        entryStore = null;
        entries = null;
        return result;
    }
    /**
    Creates an independent copy of the `Stack`. Will allocate.
    */
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
    /**
    Creates a dependent copy of the `Stack`.
    */
    typeof(this) save()
    {
        typeof(this) result;
        result.entryStore = null;
        result.entries = entries;
        return result;
    }
    /**
    Destructor.
    Invalidates pointers to elements.
    Invalidates dependent copies.
    */
    void destroy()
    {
        import std.algorithm.mutation : fill;
        entryStore.fill(T.init);
        if (entryStore !is null)
            dispose(stackAllocator, entryStore.ptr);
    }
    /**
    Clears the `Stack` without deallocating resources. Beware of stale pointers to former elements.
    Invalidates dependent copies.
    */
    void clear()
    {
        import std.algorithm.mutation : fill;
        entries.fill(T.init);
        entries = null;
    }
    ref T front() @property
    {
        require(!this.empty, "attempted to get front of empty stack");
        return entries[$ - 1];
    }
    void popFront()
    {
        require(!this.empty, "attempted to popFront of empty stack");
        entries = entries[0 .. $ - 1];
    }
    ref T back() @property
    {
        require(!this.empty, "attempted to get back of empty stack");
        return entries[0];
    }
    void popBack()
    {
        require(!this.empty, "attempted to popBack of empty stack");
        entries = entries[1 .. $];
    }
    /**
    Push a new value onto the `Stack`, allocates as neccessary.
    May invalidate pointers to elements.
    Invalidates dependent copies.
    */
    void pushFront(T value)
    {
        import std.conv;
        require(entries is null
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
                // TODO: try regular allocation if expansion fails
                import std.stdio;
                //stderr.writefln!"%s %s"(entryStore, entries);
                enforce(expandArray(stackAllocator, entryStore, max(entryStore.length * 2, 8)),
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
