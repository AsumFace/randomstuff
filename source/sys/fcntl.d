module sys.fcntl;
// missing from core.sys.posix.fcntl;

enum O_DIRECT = 0x4000;
enum O_LARGEFILE = 0x8000;
enum O_DIRECTORY = 0x10000;
enum O_NOFOLLOW = 0x20000;
enum O_NOATIME = 0x40000;
enum O_CLOEXEC = 0x80000;
enum O_PATH = 0x200000;
enum O_TMPFILE = 0x400000 | O_DIRECTORY;
import core.sys.posix.fcntl : O_CREAT, O_NONBLOCK;
enum O_TMPFILE_MASK = O_TMPFILE | O_CREAT;

enum O_NDELAY = O_NONBLOCK;

enum F_SETSIG = 1;
enum F_GETSIG = 1;
