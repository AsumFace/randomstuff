module fuse;

import core.sys.posix.sys.types : off_t;
import core.sys.posix.sys.stat;
import core.sys.posix.sys.statvfs;
import core.sys.posix.fcntl : flock_t = flock;
import core.sys.posix.time : timespec;
import core.sys.posix.sys.uio : iovec;
import std.meta;

alias c_string = const(char)*;

// port of fuse_opt.h

struct fuse_opt
{
    const(char)* templ;

    ulong offset;

    int value;
}

alias fuse_opt_key(templ, key) = AliasSeq!(templ, -1u, key);

alias fuse_opt_end = AliasSeq!(null, 0, 0);

struct fuse_args
{
    int argc;

    char** argv;

    int allocated;
}

alias fuse_args_init(argc, argv) = AliasSeq!(arc, argv, 0);

enum FUSE_OPT_KEY_OPT = -1;

enum FUSE_OPT_KEY_NONOPT = -2;

enum FUSE_OPT_KEY_KEEP = -3;

enum FUSE_OPT_KEY_DISCARD = -4;

alias fuse_opt_proc_t = int function(void* data, c_string arg, int key, fuse_args* outargs);

int fuse_opt_parse(fuse_args* args, void* data, const(fuse_opt)* opts, fuse_opt_proc_t proc);

int fuse_opt_add_opt(char** opts, c_string opt);

int fuse_opt_add_opt_escaped(char** opts, c_string opt);

int fuse_opt_add_arg(fuse_args* args, c_string arg);

int fuse_opt_insert_arg(fuse_args* args, int pos, c_string arg);

void fuse_opt_free_args(fuse_args* args);

int fuse_opt_match(const(fuse_opt)* opts, c_string opt);

// port of fuse_common.h

struct fuse_file_info
{
    import std.bitmanip;
    int flags;
    mixin(bitfields!(
    uint, "writepage", 1,
    uint, "direct_io", 1,
    uint, "keep_cache", 1,
    uint, "flush", 1,
    uint, "nonseekable", 1,
    uint, "flock_release", 1,
    uint, "cache_readdir", 1,
    uint, "", 32-7));
    uint _padding; // due to bitfield size bug in libfuse
    ulong fh;
    ulong lock_owner;
    uint poll_events;
}

struct fuse_loop_config
{
    int clone_fd;
    uint max_idle_threads;
}

struct fuse_conn_info
{
    uint proto_major;
    uint proto_minor;
    uint max_write;
    uint max_read;
    uint max_readahead;
    uint capable;
    uint want;
    uint max_background;
    uint congestion_threshold;
    uint time_gran;
    uint[22] reserved;
}

struct fuse_pollhandle;
struct fuse_conn_info_opts;

fuse_conn_info_opts* fuse_parse_conn_info_opts(fuse_args* args);

void fuse_apply_conn_info_opts(fuse_conn_info_opts* opts, fuse_conn_info* conn);

int fuse_daemonize(int foreground);
int fuse_version();

c_string fuse_pkgversion;

void fuse_pollhandle_destroy(fuse_pollhandle* ph);

enum fuse_buf_flags
{
    FUSE_BUF_IS_FD = 1 << 1,
    FUSE_BUF_FD_SEEK = 1 << 2,
    FUSE_BUF_FD_RETRY = 1 << 3
}

enum fuse_buf_copy_flags
{
    FUSE_BUF_NO_SPLICE = (1 << 1),
    FUSE_BUF_FORCE_SPLICE = (1 << 2),
    FUSE_BUF_SPLICE_MOVE = (1 << 3),
    FUSE_BUF_SPLICE_NONBLOCK = (1 << 4),
}

struct fuse_buf
{
    size_t size;
    fuse_buf_flags flags;
    void* mem;
    int fd;
    off_t pos;
}

struct fuse_bufvec
{
    size_t count;
    size_t idx;
    size_t off;
    fuse_buf[1] buf;
}

auto fuse_bufvec_init(size_t size)
{
    fuse_bufvec result;
    with (result)
    {
        count = 1;
        idx = 0;
        off = 0;
        buf[0] = fuse_buf(size, cast(fuse_buf_flags)0, null, -1, 0);
    }
}

size_t fuse_buf_size(const(fuse_bufvec)* bufv);

ptrdiff_t fuse_buf_copy(fuse_bufvec* dst, fuse_bufvec* src, fuse_buf_copy_flags flags);

int fuse_set_signal_handlers(fuse_session* se);

void fuse_remove_signal_handlers(fuse_session* se);

// port of fuse.h

struct fuse_t;

enum fuse_readdir_flags
{
    FUSE_READDIR_PLUS = (1 << 0)
}

enum fuse_fill_dir_flags
{
    FUSE_FILL_DIR_PLUS = (1 << 1)
}

alias fuse_fill_dir_t = int function(void* buf, c_string name, const(stat_t)* stbuf, off_t off, fuse_fill_dir_flags flags);

struct fuse_config
{
    int set_gid;
    uint gid;

    int set_uid;
    uint uid;

    int set_mode;
    uint umask;

    double entry_timeout;
    double negative_timeout;
    double attr_timeout;
    int intr;
    int intr_signal;
    int remember;
    int hard_remove;
    int use_ino;
    int readdir_ino;
    int direct_io;
    int kernel_cache;
    int auto_cache;
    int ac_attr_timeout_set;
    double ac_attr_timeout;
    int nullpath_ok;

    int show_help;
    ubyte* modules;
    int debug_;
}


struct fuse_operations
{
    extern(C):
    int function(c_string, stat_t*, fuse_file_info* fi) getattr;
    int function(c_string, char*, size_t) readlink;
    int function(c_string, mode_t, dev_t) mknod;
    int function(c_string, mode_t) mkdir;
    int function(c_string) unlink;
    int function(c_string) rmdir;
    int function(c_string, c_string) symlink;
    int function(c_string, c_string, uint flags) rename;
    int function(c_string, c_string) link;
    int function(c_string, mode_t, fuse_file_info* fi) chmod;
    int function(c_string, uid_t, gid_t, fuse_file_info* fi) chown;
    int function(c_string, off_t, fuse_file_info* fi) truncate;
    int function(c_string, fuse_file_info*) open;
    int function(c_string, char*, size_t, off_t, fuse_file_info*) read;
    int function(c_string, c_string, size_t, off_t, fuse_file_info*) write;
    int function(c_string, statvfs_t*) statfs;
    int function(c_string, fuse_file_info*) flush;
    int function(c_string, fuse_file_info*) release;
    int function(c_string, int, fuse_file_info*) fsync;
    int function(c_string, c_string, c_string, size_t, int) setxattr;
    int function(c_string, c_string, char*, size_t) getxattr;
    int function(c_string, char*, size_t) listxattr;
    int function(c_string, c_string) removexattr;
    int function(c_string, fuse_file_info*) opendir;
    int function(c_string, void*, fuse_fill_dir_t, off_t, fuse_file_info*, fuse_readdir_flags) readdir;
    int function(c_string, fuse_file_info*) releasedir;
    int function(c_string, int, fuse_file_info*) fsyncdir;
    void* function(fuse_conn_info* conn, fuse_config* cfg) init;
    void function(void* private_data) destroy;
    int function(c_string, int) access;
    int function(c_string, mode_t, fuse_file_info*) create;
    int function(c_string, fuse_file_info*, int cmd, flock_t*) lock;
    int function(c_string, const(timespec[2]) tv, fuse_file_info* fi) utimens;
    int function(c_string, size_t blocksize, ulong* idx) bmap;
    int function(c_string, uint cmd, void* arg, fuse_file_info*, uint flags, void* data) ioctl;
    int function(c_string, fuse_file_info*, fuse_pollhandle* ph, uint *reventsp) poll;
    int function(c_string, fuse_bufvec* buf, off_t off, fuse_file_info*) write_buf;
    int function(c_string, fuse_bufvec** bufp, size_t size, off_t off, fuse_file_info*) read_buf;
    int function(c_string, fuse_file_info*, int op) flock;
    int function(c_string, int, off_t, off_t, fuse_file_info*) fallocate;
    ptrdiff_t function(c_stringpath_in, fuse_file_info* fi_in, off_t offset_in, c_string path_out,
        fuse_file_info* fi_out, off_t offset_out, size_t size, int flags) copy_file_range;
}

struct fuse_context
{
    fuse_t* fuse;
    uid_t uid;
    gid_t gid;
    pid_t pid;
    void* private_data;
    mode_t umask;
}

auto fuse_main(A, B, C, D)(A argc, B argv, C op, D private_data)
{
    fuse_main_real(argc, argv, op, (*(op)).sizeof, private_data);
}

void fuse_lib_help(fuse_args *args);

version(FUSE_USE_VERSION_30)
{
    alias fuse_new_30 = fuse_new;
}
fuse_t *fuse_new(fuse_args* args, const(fuse_operations)* op, size_t op_size, void* private_data);
int fuse_mount(fuse_t *f, c_string mountpoint);

void fuse_unmount(fuse_t* f);
void fuse_destroy(fuse_t* f);
int fuse_loop(fuse_t* f);
void fuse_exit(fuse_t* f);

// #if FUSE_USE_VERSION < 32
// int fuse_loop_mt_31(struct fuse *f, int clone_fd);
// #define fuse_loop_mt(f, clone_fd) fuse_loop_mt_31(f, clone_fd)
int fuse_loop_mt(fuse_t* f, fuse_loop_config* config);

fuse_context* fuse_get_context();

int fuse_getgroups(int size, gid_t* list);

int fuse_interrupted();

int fuse_invalidate_path(fuse_t* f, c_string path);

int fuse_main_real(int argc, char** argv, const(fuse_operations)* op, size_t op_size, void* private_data);

int fuse_start_cleanup_thread(fuse_t* fuse);

void fuse_stop_cleanup_thread(fuse_t* fuse);

int fuse_clean_cache(fuse_t* fuse);


struct fuse_fs;

int fuse_fs_getattr(fuse_fs* fs, c_string path, stat_t* buf, fuse_file_info* fi);
int fuse_fs_rename(fuse_fs* fs, c_string oldpath, c_string newpath, uint flags);
int fuse_fs_unlink(fuse_fs* fs, c_string path);
int fuse_fs_rmdir(fuse_fs* fs, c_string path);
int fuse_fs_symlink(fuse_fs* fs, c_string linkname, c_string path);
int fuse_fs_link(fuse_fs* fs, c_string oldpath, c_string newpath);
int fuse_fs_release(fuse_fs* fs,  c_string path, fuse_file_info* fi);
int fuse_fs_open(fuse_fs* fs, c_string path, fuse_file_info* fi);
int fuse_fs_read(fuse_fs* fs, c_string path, char* buf, size_t size, off_t off, fuse_file_info* fi);
int fuse_fs_read_buf(fuse_fs* fs, c_string path, fuse_bufvec** bufp, size_t size, off_t off, fuse_file_info* fi);
int fuse_fs_write(fuse_fs* fs, c_string path, c_string buf, size_t size, off_t off, fuse_file_info* fi);
int fuse_fs_write_buf(fuse_fs* fs, c_string path, fuse_bufvec* buf, off_t off, fuse_file_info* fi);
int fuse_fs_fsync(fuse_fs* fs, c_string path, int datasync, fuse_file_info* fi);
int fuse_fs_flush(fuse_fs* fs, c_string path, fuse_file_info* fi);
int fuse_fs_statfs(fuse_fs* fs, c_string path, statvfs_t* buf);
int fuse_fs_opendir(fuse_fs* fs, c_string path, fuse_file_info* fi);
int fuse_fs_readdir(fuse_fs* fs, c_string path, void* buf, fuse_fill_dir_t filler, off_t off, fuse_file_info* fi, fuse_readdir_flags flags);
int fuse_fs_fsyncdir(fuse_fs* fs, c_string path, int datasync, fuse_file_info* fi);
int fuse_fs_releasedir(fuse_fs* fs, c_string path, fuse_file_info* fi);
int fuse_fs_create(fuse_fs* fs, c_string path, mode_t mode, fuse_file_info* fi);
int fuse_fs_lock(fuse_fs* fs, c_string path, fuse_file_info* fi, int cmd, flock_t* lock);
int fuse_fs_flock(fuse_fs* fs, c_string path, fuse_file_info *fi, int op);
int fuse_fs_chmod(fuse_fs* fs, c_string path, mode_t mode, fuse_file_info* fi);
int fuse_fs_chown(fuse_fs* fs, c_string path, uid_t uid, gid_t gid, fuse_file_info* fi);
int fuse_fs_truncate(fuse_fs* fs, c_string path, off_t size, fuse_file_info* fi);
int fuse_fs_utimens(fuse_fs* fs, c_string path, const(timespec[2]) tv, fuse_file_info* fi);
int fuse_fs_access(fuse_fs* fs, c_string path, int mask);
int fuse_fs_readlink(fuse_fs* fs, c_string path, char* buf, size_t len);
int fuse_fs_mknod(fuse_fs* fs, c_string path, mode_t mode, dev_t rdev);
int fuse_fs_mkdir(fuse_fs* fs, c_string path, mode_t mode);
int fuse_fs_setxattr(fuse_fs* fs, c_string path, c_string name, c_string value, size_t size, int flags);
int fuse_fs_getxattr(fuse_fs* fs, c_string path, c_string name, char* value, size_t size);
int fuse_fs_listxattr(fuse_fs* fs, c_string path, char* list, size_t size);
int fuse_fs_removexattr(fuse_fs* fs, c_string path, c_string name);
int fuse_fs_bmap(fuse_fs* fs, c_string path, size_t blocksize, ulong* idx);
int fuse_fs_ioctl(fuse_fs* fs, c_string path, uint cmd, void* arg, fuse_file_info* fi, uint flags, void* data);
int fuse_fs_poll(fuse_fs* fs, c_string path, fuse_file_info* fi, fuse_pollhandle* ph, uint* reventsp);
int fuse_fs_fallocate(fuse_fs* fs, c_string path, int mode, off_t offset, off_t length, fuse_file_info* fi);
ptrdiff_t fuse_fs_copy_file_range(fuse_fs* fs, c_string path_in, fuse_file_info* fi_in, off_t off_in, c_string path_out, fuse_file_info* fi_out, off_t off_out, size_t len, int flags);
void fuse_fs_init(fuse_fs* fs, fuse_conn_info* conn, fuse_config* cfg);
void fuse_fs_destroy(fuse_fs* fs);

int fuse_notify_poll(fuse_pollhandle* ph);

fuse_fs* fuse_fs_new(const(fuse_operations)* op, size_t op_size, void* private_data);

alias fuse_module_factory_t = fuse_fs* function(fuse_args*, fuse_fs**);

mixin template fuse_register_module(string name, alias factory)
{
    mixin("fuse_module_factory_t fuse_module_%s_factory = factory;");
}

fuse_session* fuse_get_session(fuse_t* f);

int fuse_open_channel(c_string mountpoint, c_string options);

// port of fuse_lowlevel.h

alias fuse_ino_t = ulong;

struct fuse_req;
alias fuse_req_t = fuse_req*;

struct fuse_session
{
    fuse_ino_t ino;
    ulong generation;
    stat_t attr;
    double attr_timeout;
    double entry_timeout;
}

struct fuse_entry_param
{
    fuse_ino_t ino;
    ulong generation;
    stat_t attr;
    double attr_timeout;
    double entry_timeout;
}

struct fuse_ctx
{
    uid_t uid;
    gid_t gid;
    pid_t pid;
    mode_t umask;
}

struct fuse_forget_data
{
    fuse_ino_t ino;
    ulong nlookup;
}

struct fuse_lowlevel_opts
{
    void function(void* userdata, fuse_conn_info* conn) init;
    void function(void* userdata) destroy;
    void function(fuse_req_t req, fuse_ino_t parent, c_string name) lookup;
    void function(fuse_req_t req, fuse_ino_t ino, ulong nlookup) forget;
    void function(fuse_req_t req, fuse_ino_t ino, fuse_file_info* fi) getattr;
    void function(fuse_req_t req, fuse_ino_t ino, stat_t* attr, int to_set, fuse_file_info* fi) setattr;
    void function(fuse_req_t req, fuse_ino_t ino) readlink;
    void function(fuse_req_t req, fuse_ino_t parent, c_string name, mode_t, dev_t rdev) mknod;
    void function(fuse_req_t req, fuse_ino_t parent, c_string name, mode_t mode) mkdir;
    void function(fuse_req_t req, fuse_ino_t parent, c_string name) unlink;
    void function(fuse_req_t req, fuse_ino_t parent, c_string name) rmdir;
    void function(fuse_req_t req, c_string link, fuse_ino_t parent, c_string name) symlink;
    void function(fuse_req_t req, fuse_ino_t parent, c_string name, fuse_ino_t newparent, c_string newname, uint flags) rename;
    void function(fuse_req_t req, fuse_ino_t ino, fuse_ino_t newparent, c_string newname) link;
    void function(fuse_req_t req, fuse_ino_t ino, fuse_file_info* fi) open;
    void function(fuse_req_t req, fuse_ino_t ino, size_t size, off_t off, fuse_file_info* fi) read;
    void function(fuse_req_t req, fuse_ino_t ino, c_string buf, size_t size, off_t off, fuse_file_info* fi) write;
    void function(fuse_req_t req, fuse_ino_t ino, fuse_file_info* fi) flush;
    void function(fuse_req_t req, fuse_ino_t ino, fuse_file_info* fi) release;
    void function(fuse_req_t req, fuse_ino_t ino, int datasync, fuse_file_info* fi) fsync;
    void function(fuse_req_t req, fuse_ino_t ino, fuse_file_info* fi) opendir;
    void function(fuse_req_t req, fuse_ino_t ino, size_t size, off_t off, fuse_file_info* fi) readdir;
    void function(fuse_req_t req, fuse_ino_t ino, fuse_file_info* fi) releasedir;
    void function(fuse_req_t req, fuse_ino_t ino, int datasync, fuse_file_info* fi) fsyncdir;
    void function(fuse_req_t req, fuse_ino_t ino) statfs;
    void function(fuse_req_t req, fuse_ino_t ino, c_string name, c_string value, size_t size, int flags) setxattr;
    void function(fuse_req_t req, fuse_ino_t ino, c_string name, size_t size) getxattr;
    void function(fuse_req_t req, fuse_ino_t ino, size_t size) listxattr;
    void function(fuse_req_t req, fuse_ino_t ino, c_string name) removexattr;
    void function(fuse_req_t req, fuse_ino_t ino, int mask) access;
    void function(fuse_req_t req, fuse_ino_t parent, c_string name, mode_t mode, fuse_file_info* fi) create;
    void function(fuse_req_t req, fuse_ino_t ino, fuse_file_info* fi, flock_t* lock) getlk;
    void function(fuse_req_t req, fuse_ino_t ino, fuse_file_info* fi, flock_t* lock, int sleep) setlk;
    void function(fuse_req_t req, fuse_ino_t ino, size_t blocksize, ulong idx) bmap;
    void function(fuse_req_t req, fuse_ino_t ino, uint cmd, void* arg, fuse_file_info* fi, uint flags, const(void)* in_buf, size_t in_bufsz, size_t out_bufzs) ioctl;
    void function(fuse_req_t req, fuse_ino_t ino, fuse_file_info* fi, fuse_pollhandle* ph) poll;
    void function(fuse_req_t req, fuse_ino_t ino, fuse_bufvec* bufv, off_t off, fuse_file_info* fi) write_buf;
    void function(fuse_req_t req, void* cookie, fuse_ino_t ino, off_t offset, fuse_bufvec* bufv) retrieve_reply;
    void function(fuse_req_t req, size_t count, fuse_forget_data* forgets) forget_multi;
    void function(fuse_req_t req, fuse_ino_t ino, fuse_file_info* fi, int op) flock;
    void function(fuse_req_t req, fuse_ino_t ino, int mode, off_t offset, off_t length, fuse_file_info* fi) fallocate;
    void function(fuse_req_t req, fuse_ino_t ino_in, off_t off_in, fuse_file_info* fi_in, fuse_ino_t ino_out, off_t off_out, fuse_file_info* fi_out, size_t len, int flags) copy_file_range;
}

int fuse_reply_err(fuse_req_t req, int err);
void fuse_reply_none(fuse_req_t req);
int fuse_reply_entry(fuse_req_t req, const(fuse_entry_param)* e);
int fuse_reply_create(fuse_req_t req, const(fuse_entry_param)* e, const(fuse_file_info)* fi);
int fuse_reply_attr(fuse_req_t req, const(stat_t)* attr, double attr_timeout);
int fuse_reply_readlink(fuse_req_t req, c_string link);
int fuse_reply_open(fuse_req_t req, const(fuse_file_info)* fi);
int fuse_reply_write(fuse_req_t req, size_t count);
int fuse_reply_buf(fuse_req_t req, c_string buf, size_t size);
int fuse_reply_data(fuse_req_t req, fuse_bufvec* bufv, fuse_buf_copy_flags flags);
int fuse_reply_iov(fuse_req_t req, const(iovec)* iov, int count);
int fuse_reply_statfs(fuse_req_t req, const(statvfs_t)* stbuf);
int fuse_reply_xattr(fuse_req_t req, size_t count);
int fuse_reply_lock(fuse_req_t req, const(flock_t)* lock);
int fuse_reply_bmap(fuse_req_t req, ulong idx);
size_t fuse_add_direntry(fuse_req_t req, char* buf, size_t bufsize, c_string name, const(stat_t)* stbuf, off_t off);
size_t fuse_add_direntry_plus(fuse_req_t req, char* buf, size_t bufsize, c_string name, const(fuse_entry_param)* e, off_t off);
int fuse_reply_ioctl_retry(fuse_req_t req, const(iovec)* in_iov, size_t in_count, const(iovec)* out_iov, size_t out_count);
int fuse_reply_ioctl(fuse_req_t req, int result, const(void)* buf, size_t size);
int fuse_reply_ioctl_iov(fuse_req_t req, int result, const(iovec)* iov, int count);
int fuse_reply_poll(fuse_req_t req, uint revents);
int fuse_lowlevel_notify_poll(fuse_pollhandle* ph);
int fuse_lowlevel_notify_inval_inode(fuse_session* se, fuse_ino_t ino, off_t off, off_t len);
int fuse_lowlevel_notify_inval_entry(fuse_session* se, fuse_ino_t parent, c_string name, size_t namelen);
int fuse_lowlevel_notify_delete(fuse_session* se, fuse_ino_t parent, fuse_ino_t child, c_string name, size_t namelen);
int fuse_lowlevel_notify_store(fuse_session* se, fuse_ino_t ino, off_t offset, fuse_bufvec* bufv, fuse_buf_copy_flags flags);
int fuse_lowlevel_notify_retrieve(fuse_session* se, fuse_ino_t ino, size_t size, off_t offset, void* cookie);
void* fuse_req_userdata(fuse_req_t req);
const(fuse_ctx)* fuse_req_ctx(fuse_req_t req);
int fuse_req_getgroups(fuse_req_t req, int size, gid_t* list);
alias fuse_interrupt_func_t = void function(fuse_req_t req, void* data);
void fuse_req_interrupt_func(fuse_req_t req, fuse_interrupt_func_t func, void* data);
int fuse_req_interrupted(fuse_req_t req);
void fuse_lowlevel_version();
void fuse_lowlevel_help();
void fuse_cmdline_help();

struct fuse_cmdline_opts
{
    int singlethread;
    int foreground;
    int _debug;
    int nodefault_subtype;
    char* mountpoint;
    int show_version;
    int show_help;
    int clone_fd;
    uint max_idle_threads;
}

int fuse_parse_cmdline(fuse_args* args, fuse_cmdline_opts* opts);
fuse_session* function(fuse_args* args, const(fuse_lowlevel_opts)* op, size_t op_size, void* userdata) fuse_session_new;
int fuse_session_mount(fuse_session* se, c_string mountpoint);
int fuse_session_loop(fuse_session* se);
//#if FUSE_USE_VERSION < 32
int fuse_session_loop_mt_31(fuse_session* se, int clone_fd);
alias fuse_session_loop_mt = fuse_session_loop_mt_31;
//#else
//int fuse_session_loop_mt(struct fuse_session *se, struct fuse_loop_config *config);
//#endif
void fuse_session_exit(fuse_session* se);
void fuse_session_reset(fuse_session* se);
int fuse_session_exited(fuse_session* se);
void fuse_session_unmount(fuse_session* se);
void fuse_session_destroy(fuse_session* se);
int fuse_session_fd(fuse_session* se);
void fuse_session_process_buf(fuse_session* se, const(fuse_buf)* buf);
int fuse_session_receive_buf(fuse_session* se, fuse_buf* buf);
