/+--------------------Copyright Notice------------------------+\
|      Copyright:                                              |
|  - AsumFace (asumface@gmail.com) 2019                        |
|  Distributed under the Boost Software License, Version 1.0.  |
|  See accompanying file Boost1_0 or copy at                   |
|      https://www.boost.org/LICENSE_1_0.txt                   |
\+------------------------------------------------------------+/


/++
This module is intended to implement a minimal filesystem with transparent compression but no permanent storage
  capability. Although libfuse says that all functions are optional, this filesystem, as of now, does not appear
  to work usefully at all.
+/


module zefs;
import zstdc;
import fuse;
import std.string : fromStringz;
import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import rtree;
import cgfm.math.box;
import core.stdc.errno;
import std.stdio : File;
import stack_container;
import std.exception : assumeWontThrow;
import required;
import std.stdio;
import core.sync.rwmutex;

struct mapping
{
    invariant(_offset % zpage_size == 0);
    ulong offset() const nothrow
    { return _offset; }
    ulong offset(ulong val) nothrow
    { return _offset = val; }
    ulong handle;
    private ulong _offset;
    ulong blob_offset;
    ulong blob_length;
}

enum zpage_size = 1024UL ^^ 2 * 2; // 2 MiB | 512 x 4 KiB pages

struct z_cache
{
    mapping descriptor;
    ubyte[] data;
}

Box!(ulong, 2) mapping_to_box(mapping n) nothrow
{
    return Box!(ulong, 2)(
        n.offset, n.offset + zpage_size,
        n.blob_offset, n.blob_offset + n.blob_length);
}

struct zefs_state
{
    ulong handle_counter = 0;
    ZSTD_DCtx* dctx;
    ZSTD_CCtx* cctx;
    ulong origin = ulong.max;
    ulong fh;
    bool dirty;
    ubyte[] uncompressed_buffer;
    ubyte[] compressed_buffer;
    RTree!(mapping, mapping_to_box) zpage_tree;
    File store;
    ReadWriteMutex mut;
}

const(fuse_operations) oper = {
    init : &zefs_init,
    destroy : &zefs_destroy,
    open : &zefs_open,
    release : &zefs_release,
    read : &zefs_read,
    write : &zefs_write
};

zefs_state* state(fuse_context* context) nothrow
{
    return cast(zefs_state*)(context.private_data);
}

nothrow:
extern(C):
void* zefs_init(fuse_conn_info* conn, fuse_config* cfg)
{
    assumeWontThrow(stderr.writeln(__FUNCTION__));
    import std.exception;
    cfg.entry_timeout = 0;
    cfg.negative_timeout = 0;
    cfg.attr_timeout = 0;

    zefs_state* result = Mallocator.instance.make!zefs_state;
    result.uncompressed_buffer = Mallocator.instance.makeArray!ubyte(zpage_size);
    result.compressed_buffer = Mallocator.instance.makeArray!ubyte(ZSTD_compressBound(zpage_size));
    result.dctx = ZSTD_createDCtx();
    result.cctx = ZSTD_createCCtx();
    if (result.uncompressed_buffer is null
        || result.compressed_buffer is null
        || result.cctx is null
        || result.dctx is null)
        assert(0);
    assumeWontThrow(result.zpage_tree.initialize);
    assumeWontThrow(result.store = File(".ZEFS_STORE", "w"));
    assumeWontThrow(result.mut = new ReadWriteMutex());
    return result;
}

void zefs_destroy(void* _state)
{
    assumeWontThrow(stderr.writeln(__FUNCTION__));
    zefs_state* state = cast(zefs_state*)_state;
    assumeWontThrow({
    synchronized (state.mut.writer)
    {
        import std.file;
        import std.exception;
        Mallocator.instance.dispose(state.uncompressed_buffer);
        Mallocator.instance.dispose(state.compressed_buffer);
        ZSTD_freeDCtx(state.dctx);
        ZSTD_freeCCtx(state.cctx);
        state.zpage_tree.destroy;
        state.store.close;
        remove(".ZEFS_STORE");
        Mallocator.instance.dispose(state);
    }
    }());
}

int zefs_open(c_string path, fuse_file_info* fi)
{
    assumeWontThrow(stderr.writeln(__FUNCTION__));
    auto context = fuse_get_context();
    assumeWontThrow({
    synchronized (context.state.mut.writer)
        fi.fh = context.state.handle_counter++;
    }());
    return 0;
}

int zefs_release(c_string path, fuse_file_info* fi)
{
    assumeWontThrow(stderr.writeln(__FUNCTION__));
    auto context = fuse_get_context();
    Stack!(context.state.zpage_tree.ElementType) elems;
    match_all_boxes mab;
    match_all_elements mae;
    assumeWontThrow({
    synchronized (context.state.mut.writer)
    {
        foreach (e; RTreeRange!(typeof(context.state.zpage_tree),
            true, match_all_boxes,
            match_all_elements)(context.state.zpage_tree, mab, mae))
        {
            if (e.handle == fi.fh)
                elems.pushFront(e);
        }

        foreach (e; elems[])
        {
            auto success = assumeWontThrow(context.state.zpage_tree.remove(e));
            assert(success);
        }
    }
    }());
    elems.destroy;
    return 0;
}

int zefs_fallocate(c_string path, int mode, off_t offset, off_t length, fuse_file_info* fi)
{
    assumeWontThrow(stderr.writeln(__FUNCTION__));
    if (offset < 0 || length <= 0)
        return -EINVAL;
    return 0;
}

struct shouldEnter
{
    ulong begin;
    bool opCall(typeof(zefs_state.zpage_tree).BoxType box)
    {
        if (begin >= box.min.x && begin < box.max.x)
            return true;
        if (begin + zpage_size >= box.min.x && begin + zpage_size < box.max.x)
            return true;
        return false;
    }
}
struct isEntry
{
    ulong handle;
    ulong begin;
    bool opCall(ref typeof(zefs_state.zpage_tree).ElementType arg)
    {
        return arg.handle == handle && arg.offset == begin;
    }
}

struct touches
{
    ulong begin;
    ulong length;
    bool opCall(typeof(zefs_state.zpage_tree).BoxType box)
    {
        if (begin > box.min.y && begin <= box.max.y)
            return true;
        if (begin + length > box.min.y && begin + length <= box.max.y)
            return true;
        if (begin <= box.min.y && begin + length >= box.max.y)
            return true;
        return false;
    }
}

struct match_all_boxes
{
    bool opCall(typeof(zefs_state.zpage_tree).BoxType arg)
    {
        return true;
    }
}

struct match_all_elements
{
    bool opCall(ref typeof(zefs_state.zpage_tree).ElementType arg)
    {
        return true;
    }
}

struct match
{
    ulong begin;
    ulong length;
    bool opCall(ref typeof(zefs_state.zpage_tree).ElementType arg)
    {
        touches t;
        t.begin = begin;
        t.length = length;
        auto box = typeof(zefs_state.zpage_tree).getBounds(arg);
        return t(box);
    }
}

extern(D) mapping find_free_region(zefs_state* context, ulong size)
    in(context !is null)
    out(r; r.blob_length == size)
{
    struct blob_region // basically `mapping` without the junk that we don't need here
    {
        this(mapping arg) nothrow
        {
            this.blob_offset = arg.blob_offset;
            this.blob_length = arg.blob_length;
        }
        ulong blob_offset = 0;
        ulong blob_length = 0;
    }
    Stack!blob_region map_stack;
    map_stack.pushFront(blob_region()); // this is needed so we can find the space before the first mapping

    scope(exit)
        map_stack.destroy;

    mapping result;
    result.blob_length = size;
    ulong addr;
    ulong len = zpage_size; // tuning parameter; not critical for correctness, can be pretty much anything
    import core.stdc.stdio : SEEK_END;
    assumeWontThrow(context.store.seek(0, SEEK_END));
    ulong give_up_threshold;
    assumeWontThrow(give_up_threshold = context.store.tell); // the only simple way to get the current file size?



    while (true)
    {
        if (addr >= give_up_threshold)
        {
            result.blob_offset = give_up_threshold;
            return result;
        }
        touches tou = {addr, len};
        match mat = {addr, len};
        RTreeRange!(typeof(context.zpage_tree), true, touches, match) findings;
        assumeWontThrow(findings = typeof(findings)(context.zpage_tree, tou, mat));
        assumeWontThrow(
        {
        foreach (f; findings)
            map_stack.pushFront(blob_region(f));
        }());
        import std.algorithm : sort;
        map_stack[].sort!((blob_region a, blob_region b) => a.blob_offset < b.blob_offset);
        while (map_stack.length > 1)
        {
            blob_region a = map_stack[0];
            blob_region b = map_stack[1];
            ulong space = b.blob_offset - (a.blob_offset + a.blob_length);

             // we might have a single duplicate if a mapping is matched in two separate queries
            if (a != b && space >= size)
            {
                result.blob_offset = a.blob_offset + a.blob_length;
                return result;
            }
            else
            {
                map_stack.popBack;
                continue;
            }
        }
        addr += len;
    }
}

extern(D) void commit_dirty_page(zefs_state* context)
    in(context !is null)
    in(context.dirty == true)
    out(;context.dirty == false)
{
    assert(context.compressed_buffer.length == ZSTD_compressBound(zpage_size));
    assert(context.uncompressed_buffer.length == zpage_size);
    size_t written = ZSTD_compressCCtx(context.cctx,
        context.compressed_buffer.ptr, context.compressed_buffer.length,
        context.uncompressed_buffer.ptr, zpage_size,
        20);
    if (ZSTD_isError(written))
        assert(0, ZSTD_getErrorName(written).fromStringz);
    shouldEnter sho = {context.origin};
    isEntry ise = {context.fh, context.origin};
    RTreeRange!(typeof(context.zpage_tree), true, shouldEnter, isEntry) findings;
    assumeWontThrow(findings = typeof(findings)(context.zpage_tree, sho, ise));
    if (!findings.empty)
    {
        ref mapping existing_mapping() { return findings.front; }
        size_t existing_space = existing_mapping.blob_length;
        assumeWontThrow(
        {
        if (existing_space == written)
        {
            context.store.seek(existing_mapping.blob_offset);
            context.store.rawWrite(context.compressed_buffer[0 .. written]);
        }
        else if (existing_space > written)
        {
            /+ reinserting the mapping into the tree could be done but i think that's mostly
                only detrimental to performance +/
            //context.zpage_tree.remove(existing_mapping);
            existing_mapping.blob_length = written;
            context.store.seek(existing_mapping.blob_offset);
            context.store.rawWrite(context.compressed_buffer[0 .. written]);
            //context.zpage_tree.insert(existing_mapping);
        }
        else if (existing_space < written)
        {
            context.zpage_tree.remove(existing_mapping);
            auto new_mapping = find_free_region(context, written);
            new_mapping.offset = existing_mapping.offset;
            new_mapping.handle = existing_mapping.handle;
            context.zpage_tree.insert(new_mapping);
            context.store.seek(new_mapping.blob_offset);
            context.store.rawWrite(context.compressed_buffer[0 .. written]);
        }
        else
            unreachable;
        }());
    }
    assert(assumeWontThrow({if(findings.empty) return true; else findings.popFront; return findings.empty;}()));
}


extern(D) void load_zpage(zefs_state* context, ulong begin, ulong fh)
    in(context !is null)
    in(begin % zpage_size == 0)
    out(;context.fh == fh)
    out(;context.origin == begin)
{
    import std.algorithm : fill;
    shouldEnter sho = {begin};
    isEntry ise = {fh, begin};
    RTreeRange!(typeof(context.zpage_tree), true, shouldEnter, isEntry) findings;
    assumeWontThrow(findings = typeof(findings)(context.zpage_tree, sho, ise));

    if (context.dirty)
        commit_dirty_page(context);
    if (!findings.empty)
    {
        assert(context.uncompressed_buffer.length == zpage_size);
        import core.stdc.stdio : SEEK_SET;
        assumeWontThrow(context.store.seek(findings.front.blob_offset, SEEK_SET));
        assert(findings.front.blob_length <= ZSTD_compressBound(zpage_size));
        assumeWontThrow(context.store.rawRead(context.compressed_buffer.ptr[0 .. findings.front.blob_length]));
        auto status = ZSTD_decompressDCtx(context.dctx,
            context.uncompressed_buffer.ptr, context.uncompressed_buffer.length,
            context.compressed_buffer.ptr, context.compressed_buffer.length);
        if (ZSTD_isError(status))
            assert(0, ZSTD_getErrorName(status).fromStringz);
    }
    else
        context.uncompressed_buffer[].fill(cast(ubyte)0);
    context.origin = begin;
    context.fh = fh;
    assert(assumeWontThrow({if(findings.empty) return true; else findings.popFront; return findings.empty;}()));
}

int zefs_read(c_string path, ubyte* dst, size_t offset, off_t length, fuse_file_info* fi)
{
    assumeWontThrow(stderr.writeln(__FUNCTION__));
    import std.range : iota;
    auto context = fuse_get_context();
    auto aligned_begin_offset = offset - offset % zpage_size;
    auto page_begins = iota(aligned_begin_offset, alignSize(offset + length, zpage_size));

    ulong bytes_left = 0;
    bool first = true;
    assumeWontThrow({
    synchronized (context.state.mut.writer)
    foreach (begin; page_begins)
    {
        if (begin != context.state.origin || fi.fh != context.state.fh)
        {
            load_zpage(context.state, begin, fi.fh);
        }

        ulong start;
        if (first)
            start = offset - aligned_begin_offset;
        else
            start = 0;

        import std.algorithm : min;
        ulong end = min(start + bytes_left, zpage_size);

        dst[length - bytes_left .. length - bytes_left + (end - start)] = context.state.uncompressed_buffer[start .. end];
        bytes_left -= end - start;
        if (first) first = false;
    }
    }());
    assert(bytes_left == 0);
    return 0;
}


int zefs_write(c_string path, const(ubyte)* src, size_t offset, off_t length, fuse_file_info* fi)
{
    assumeWontThrow(stderr.writeln(__FUNCTION__));
    import std.range : iota;
    auto context = fuse_get_context();
    auto aligned_begin_offset = offset - offset % zpage_size;
    auto page_begins = iota(aligned_begin_offset, alignSize(offset + length, zpage_size));

    ulong bytes_left = 0;
    bool first = true;
    assumeWontThrow({
    synchronized (context.state.mut.writer)
    foreach (begin; page_begins)
    {
        if (begin != context.state.origin || fi.fh != context.state.fh)
        {
            load_zpage(context.state, begin, fi.fh);
        }

        ulong start;
        if (first)
            start = offset - aligned_begin_offset;
        else
            start = 0;

        import std.algorithm : min;
        ulong end = min(start + bytes_left, zpage_size);

        context.state.uncompressed_buffer[start .. end] = src[length - bytes_left .. length - bytes_left + (end - start)];
        context.state.dirty = true;
        context.state.origin = begin;
        context.state.fh = fi.fh;
        bytes_left -= end - start;
        if (first) first = false;
    }
    }());
    assert(bytes_left == 0);
    return 0;
}

import std.math : isPowerOf2;
extern(D) private ulong alignSize(ulong size, ulong alignment)
    in(alignment.isPowerOf2, "alignment must be a power of two")
    out(r; r % alignment == 0)
{
    return size + (alignment - (size % alignment)) % alignment;
}
