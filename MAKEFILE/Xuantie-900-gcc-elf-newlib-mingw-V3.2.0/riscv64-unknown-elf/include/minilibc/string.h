/*
 * string.h
 *
 * Definitions for memory and string functions.
 */

#ifndef _MINILIBC_STRING_H_
#define _MINILIBC_STRING_H_

#include "ansidef.h"

#define __need_size_t
#define __need_NULL
#include <stddef.h>

#include "errno.h"

/* RSIZE_MAX defines the highest number that a value of type rsize_t may contain.

   Functions that have a parameter of rsize_t will report a runtime
   constraint violation if its value exceeds RSIZE_MAX.  */
#define RSIZE_MAX (SIZE_MAX >> 1)


/* rsize_t is a type for communicating realistic object sizes.
   Often, large object sizes are the result of an integer overflow. To
   detect these overflow conditions at runtime, the type rsize_t
   restricts the maximum allowed object size. It does not allow
   large positive numbers.  rsize_t is an unsigned type. It's maximum
   value is given by the macro RSIZE_MAX.  */
typedef size_t rsize_t;

/* errno_t is the type for communicating error values.
   It may contain all of the values that might be found in errno.  */
typedef int errno_t;

_BEGIN_STD_C

/*  Copying functions */
extern void * memcpy( void *, const void *, size_t );
extern void * memmove( void *, const void *, size_t );
extern char * strcpy( char *, const char * );
extern char * strncpy( char *, const char *, size_t );

/*  Concatenation functions */
extern char * strcat( char *, const char * );
extern char * strncat( char *, const char *, size_t );

/*  Comparison functions */
extern int memcmp( const void *, const void *, size_t );
extern int strcmp( const char *, const char * );
extern int strcoll( const char *, const char * );
extern int strncmp( const char *, const char *, size_t );
extern size_t strxfrm( char *, const char *, size_t );

/*  Search functions */
extern void * memchr( const void *, int,  size_t );
extern char * strchr( const char *, int );
extern size_t strcspn( const char *, const char * );
extern char * strpbrk( const char *, const char * );
extern char * strrchr( const char *, int );
extern size_t strspn( const char *, const char * );
extern char * strstr( const char *, const char * );
extern char * strtok( char *, const char * );

/*  Miscellaneous functions */
extern void * memset(void * buffer, int c, size_t count);
extern char * strerror(int errnum);
extern size_t strlen( const char * );

/* optimize for size */
extern void * memcpy_size( void *, const void *, size_t );
extern void * memmove_size( void *, const void *, size_t );
extern void * memset_size(void * buffer, int c, size_t count);
extern char * strcpy_size( char *, const char * );
extern int strcmp_size( const char *, const char * );
extern size_t strlen_size( const char * );

extern errno_t memcpy_s(void *__restrict dest, rsize_t dmax,
                        const void *__restrict src, rsize_t slen);
extern errno_t memmove_s(void *dest, rsize_t dmax, const void *src,
                         rsize_t slen);
extern errno_t memcmp_s(const void *dest, rsize_t dmax, const void *src,
                        rsize_t slen, int *diff);
extern errno_t memset_s(void *dest, rsize_t dmax, int value, rsize_t n);

_END_STD_C

#endif /* _MINILIBC_STRING_H_ */
