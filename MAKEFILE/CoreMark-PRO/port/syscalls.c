/* Newlib hooks: DDR heap and UART only; no semihosting or filesystem. */
#include "board.h"
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <malloc.h>
extern char __heap_start[], __heap_end[];
static char *heap_cursor;
/* Newlib provides memalign/free but not the POSIX API used by MITH. */
int posix_memalign(void **result, size_t alignment, size_t size) {
    if (alignment < sizeof(void *) || alignment % sizeof(void *) ||
        (alignment & (alignment - 1))) return EINVAL;
    void *memory = memalign(alignment, size);
    if (!memory) return ENOMEM;
    *result = memory;
    return 0;
}
void *_sbrk(ptrdiff_t increment) {
    if (!heap_cursor) heap_cursor = __heap_start;
    char *old = heap_cursor;
    if ((increment >= 0 && (size_t)increment > (size_t)(__heap_end - old)) ||
        (increment < 0 && increment < __heap_start - old)) {
        errno = ENOMEM;
        return (void *)-1;
    }
    heap_cursor += increment;
    return old;
}
int _write(int fd, const void *buffer, size_t length) {
    if (fd != 1 && fd != 2) { errno = EBADF; return -1; }
    const char *p = buffer;
    for (size_t i = 0; i < length; ++i) board_putc(p[i]);
    return (int)length;
}
int _read(int fd, void *buffer, size_t length) {
    (void)fd; (void)buffer; (void)length; errno = ENOSYS; return -1;
}
int _fstat(int fd, struct stat *st) {
    if (fd < 0 || fd > 2) { errno = EBADF; return -1; }
    st->st_mode = S_IFCHR; st->st_blksize = 0; return 0;
}
int _isatty(int fd) { return fd >= 0 && fd <= 2; }
int _close(int fd) { (void)fd; errno = EBADF; return -1; }
off_t _lseek(int fd, off_t offset, int whence) {
    (void)fd; (void)offset; (void)whence; errno = ESPIPE; return -1;
}
int _open(const char *name, int flags, ...) {
    (void)name; (void)flags; errno = ENOENT; return -1;
}
int _getpid(void) { return 1; }
int _kill(int pid, int sig) { (void)pid; (void)sig; errno = EINVAL; return -1; }
void _exit(int code) { board_exit(code); }
