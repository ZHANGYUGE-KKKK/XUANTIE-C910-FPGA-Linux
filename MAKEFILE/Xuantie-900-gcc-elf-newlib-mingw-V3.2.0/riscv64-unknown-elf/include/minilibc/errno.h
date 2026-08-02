/*
 * Copyright (C) 2024 Alibaba Group Holding Limited
 */

#ifndef _MINILIBC_ERRNO_H_
#define _MINILIBC_ERRNO_H_

#ifdef __cplusplus
extern "C" {
#endif

#ifndef __error_t_defined
typedef int error_t;
#define __error_t_defined 1
#endif

extern int errno;

/* original minilibc errno */
// #define	EBADF 9		/* Bad file number */
// #define	ECHILD 10	/* No children */
// #define	EAGAIN 11	/* No more processes */
// #define	ENOMEM 12	/* Not enough space */
// #define	EINVAL 22	/* Invalid argument */
// #define	ENFILE 23	/* Too many open files in system */
// #define EDOM   33       /* Math arg out of domain of func */
// #define ERANGE 34       /* Math result not representable */
// #define ENOSYS 88	/* Function not implemented */
// #define ENOTSUP 134		/* Not supported */
// #define EILSEQ 138      /* Illegal byte sequence.  */

#define	EPERM 1		/* Not owner */
#define	ENOENT 2	/* No such file or directory */
#define	ESRCH 3		/* No such process */
#define	EINTR 4		/* Interrupted system call */
#define	EIO 5		/* I/O error */
#define	ENXIO 6		/* No such device or address */
#define	E2BIG 7		/* Arg list too long */
#define	ENOEXEC 8	/* Exec format error */
#define	EBADF 9		/* Bad file number */
#define	ECHILD 10	/* No children */
#define	EAGAIN 11	/* No more processes */
#define	ENOMEM 12	/* Not enough space */
#define	EACCES 13	/* Permission denied */
#define	EFAULT 14	/* Bad address */
#ifdef __LINUX_ERRNO_EXTENSIONS__
#define	ENOTBLK 15	/* Block device required */
#endif
#define	EBUSY 16	/* Device or resource busy */
#define	EEXIST 17	/* File exists */
#define	EXDEV 18	/* Cross-device link */
#define	ENODEV 19	/* No such device */
#define	ENOTDIR 20	/* Not a directory */
#define	EISDIR 21	/* Is a directory */
#define	EINVAL 22	/* Invalid argument */
#define	ENFILE 23	/* Too many open files in system */
#define	EMFILE 24	/* File descriptor value too large */
#define	ENOTTY 25	/* Not a character device */
#define	ETXTBSY 26	/* Text file busy */
#define	EFBIG 27	/* File too large */
#define	ENOSPC 28	/* No space left on device */
#define	ESPIPE 29	/* Illegal seek */
#define	EROFS 30	/* Read-only file system */
#define	EMLINK 31	/* Too many links */
#define	EPIPE 32	/* Broken pipe */
#define	EDOM 33		/* Mathematics argument out of domain of function */
#define	ERANGE 34	/* Result too large */
#define	ENOMSG 35	/* No message of desired type */
#define	EIDRM 36	/* Identifier removed */

#define	EDEADLK 45	/* Deadlock */
#define	ENOLCK 46	/* No lock */

#define ENOSTR 60	/* Not a stream */
#define ENODATA 61	/* No data (for no delay io) */
#define ETIME 62	/* Stream ioctl timeout */
#define ENOSR 63	/* No stream resources */

#define ENOLINK 67	/* Virtual circuit is gone */

#define EPROTO 71	/* Protocol error */
#define	EMULTIHOP 74	/* Multihop attempted */

#define EBADMSG 77	/* Bad message */
#define EFTYPE 79	/* Inappropriate file type or format */

#define ENOSYS 88	/* Function not implemented */

#define ENOTEMPTY 90	/* Directory not empty */
#define ENAMETOOLONG 91	/* File or path name too long */
#define ELOOP 92	/* Too many symbolic links */
#define EOPNOTSUPP 95	/* Operation not supported on socket */
#define EPFNOSUPPORT 96 /* Protocol family not supported */
#define ECONNRESET 104  /* Connection reset by peer */
#define ENOBUFS 105	/* No buffer space available */
#define EAFNOSUPPORT 106 /* Address family not supported by protocol family */
#define EPROTOTYPE 107	/* Protocol wrong type for socket */
#define ENOTSOCK 108	/* Socket operation on non-socket */
#define ENOPROTOOPT 109	/* Protocol not available */

#define ECONNREFUSED 111	/* Connection refused */
#define EADDRINUSE 112		/* Address already in use */
#define ECONNABORTED 113	/* Software caused connection abort */
#define ENETUNREACH 114		/* Network is unreachable */
#define ENETDOWN 115		/* Network interface is not configured */
#define ETIMEDOUT 116		/* Connection timed out */
#define EHOSTDOWN 117		/* Host is down */
#define EHOSTUNREACH 118	/* Host is unreachable */
#define EINPROGRESS 119		/* Connection already in progress */
#define EALREADY 120		/* Socket already connected */
#define EDESTADDRREQ 121	/* Destination address required */
#define EMSGSIZE 122		/* Message too long */
#define EPROTONOSUPPORT 123	/* Unknown protocol */

#define EADDRNOTAVAIL 125	/* Address not available */
#define ENETRESET 126		/* Connection aborted by network */
#define EISCONN 127		/* Socket is already connected */
#define ENOTCONN 128		/* Socket is not connected */
#define ETOOMANYREFS 129

#define ENOTSUP 134		/* Not supported */
#define EILSEQ 138      /* Illegal byte sequence.  */

/* Since the functions of Annex K are not completely implemented,
   the compiler donot define the __STDC_WANT_LIB_EXT1__.  */
//#if (!defined(__STDC_WANT_LIB_EXT1__) || (__STDC_WANT_LIB_EXT1__ != 0))

#ifndef ESNULLP
#define ESNULLP         ( 400 )       /* null ptr                    */
#endif

#ifndef ESZEROL
#define ESZEROL         ( 401 )       /* length is zero              */
#endif

#ifndef ESLEMIN
#define ESLEMIN         ( 402 )       /* length is below min         */
#endif

#ifndef ESLEMAX
#define ESLEMAX         ( 403 )       /* length exceeds RSIZE_MAX    */
#endif

#ifndef ESOVRLP
#define ESOVRLP         ( 404 )       /* overlap undefined           */
#endif

#ifndef ESEMPTY
#define ESEMPTY         ( 405 )       /* empty string                */
#endif

#ifndef ESNOSPC
#define ESNOSPC         ( 406 )       /* not enough space for s2     */
#endif

#ifndef ESUNTERM
#define ESUNTERM        ( 407 )       /* unterminated string         */
#endif

#ifndef ESNODIFF
#define ESNODIFF        ( 408 )       /* no difference               */
#endif

#ifndef ESNOTFND
#define ESNOTFND        ( 409 )       /* not found                   */
#endif

#ifndef ESLEWRNG
#define ESLEWRNG        ( 410 )       /* wrong size                */
#endif

#ifndef ESLAST
#define ESLAST ESLEWRNG
#endif

#ifndef UNKNOWNERR
#define UNKNOWNERR       ( -1 )        /* Unknown error            */
#endif

/* EOK may or may not be defined in errno.h */
#ifndef EOK
#define EOK             ( 0 )
#endif

#ifdef __cplusplus
}
#endif

#endif /* _MINILIBC_ERRNO_H_ */