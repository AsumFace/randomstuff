module sys.userfaultfd;

private extern(C) long syscall(long number, ...);
extern(C) int userfaultfd(int flags)
{
    return cast(int)syscall(323, flags); // userfaultfd
}

enum ulong UFFD_API = 0xAA;
enum UFFD_API_FEATURES =
    UFFD_FEATURE_EVENT_FORK
    | UFFD_FEATURE_EVENT_REMAP
    | UFFD_FEATURE_EVENT_REMOVE
    | UFFD_FEATURE_EVENT_UNMAP
    | UFFD_FEATURE_MISSING_HUGETLBFS
    | UFFD_FEATURE_MISSING_SHMEM
    | UFFD_FEATURE_SIGBUS
    | UFFD_FEATURE_THREAD_ID;

enum UFFD_API_IOCTLS =
    1UL << _UFFDIO_REGISTER
    | 1UL << _UFFDIO_UNREGISTER
    | 1UL << _UFFDIO_API;

enum UFFD_API_RANGE_IOCTLS =
    1UL << _UFFDIO_WAKE
    | 1UL << _UFFDIO_COPY
    | 1UL << _UFFDIO_ZEROPAGE;

enum UFFD_API_RANGE_IOCTLS_BASIC =
    1UL << _UFFDIO_WAKE
    | 1UL << _UFFDIO_COPY;

enum _UFFDIO_REGISTER = 0x00;
enum _UFFDIO_UNREGISTER = 0x01;
enum _UFFDIO_WAKE = 0x02;
enum _UFFDIO_COPY = 0x03;
enum _UFFDIO_ZEROPAGE = 0x04;
enum _UFFDIO_API = 0x3f;

enum UFFDIO = 0xAA;

import core.sys.posix.sys.ioctl;
enum UFFDIO_API = cast(uint)_IOWR!uffdio_api(UFFDIO, _UFFDIO_API);
enum UFFDIO_REGISTER = cast(uint)_IOWR!uffdio_register(UFFDIO, _UFFDIO_REGISTER);
enum UFFDIO_UNREGISTER = cast(uint)_IOR!uffdio_range(UFFDIO, _UFFDIO_UNREGISTER);
enum UFFDIO_WAKE = cast(uint)_IOR!uffdio_range(UFFDIO, _UFFDIO_WAKE);
enum UFFDIO_COPY = cast(uint)_IOWR!uffdio_copy(UFFDIO, _UFFDIO_COPY);
enum UFFDIO_ZEROPAGE = cast(uint)_IOWR!uffdio_zeropage(UFFDIO, _UFFDIO_ZEROPAGE);

align(ulong.alignof) struct uffd_msg
{
    align(1):
    ubyte event;

    ubyte reserved1;
    ushort reserved2;
    uint reserved3;

    union Arg
    {
        struct Pagefault
        {
            ulong flags;
            ulong address;
            union Feat
            {
                uint ptid;
            }
            Feat feat;
        }
        Pagefault pagefault;

        struct Fork
        {
            uint ufd;
        }
        Fork fork;

        struct Remap
        {
            ulong from;
            ulong to;
            ulong len;
        }
        Remap remap;

        struct Remove
        {
            ulong start;
            ulong end;
        }
        Remove remove;

        struct Reserved
        {
            ulong    reserved1;
            ulong    reserved2;
            ulong    reserved3;
        }
        Reserved reserved;
    }
    Arg arg;
}

enum UFFD_EVENT_PAGEFAULT = 0x12;
enum UFFD_EVENT_FORK = 0x13;
enum UFFD_EVENT_REMAP = 0x14;
enum UFFD_EVENT_REMOVE = 0x15;
enum UFFD_EVENT_UNMAP = 0x16;

enum UFFD_PAGEFAULT_FLAG_WRITE = 1 << 0;
enum UFFD_PAGEFAULT_FLAG_WP = 1 << 1;

struct uffdio_api
{
    ulong api;
    ulong features;
    ulong ioctls;
}

enum UFFD_FEATURE_PAGEFAULT_FLAG_WP = 1 << 0;
enum UFFD_FEATURE_EVENT_FORK = 1 << 1;
enum UFFD_FEATURE_EVENT_REMAP = 1 << 2;
enum UFFD_FEATURE_EVENT_REMOVE = 1 << 3;
enum UFFD_FEATURE_MISSING_HUGETLBFS = 1 << 4;
enum UFFD_FEATURE_MISSING_SHMEM = 1 << 5;
enum UFFD_FEATURE_EVENT_UNMAP = 1 << 6;
enum UFFD_FEATURE_SIGBUS = 1 << 7;
enum UFFD_FEATURE_THREAD_ID = 1 << 8;

struct uffdio_range
{
    ulong start;
    ulong len;
}

struct uffdio_register
{
    uffdio_range range;
    ulong mode;
    ulong ioctls;
}

enum UFFDIO_REGISTER_MODE_MISSING = 1 << 0;
enum UFFDIO_REGISTER_MODE_WP = 1 << 1;

struct uffdio_copy
{
    ulong dst;
    ulong src;
    ulong len;
    ulong mode;
    long copy;
}

enum UFFDIO_COPY_MODE_DONTWAKE = 1 << 0;

struct uffdio_zeropage
{
    uffdio_range range;
    ulong mode;
    long zeropage;
}

enum UFFDIO_ZEROPAGE_MODE_DONTWAKE = 1 << 0;
