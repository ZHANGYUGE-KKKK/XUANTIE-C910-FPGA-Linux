/*
 * stdio.h.
 *
 * Copyright (C): 2012 Hangzhou C-SKY Microsystem Co.,LTD.
 * Author: Junshan Hu (junshan_hu@c-sky.com)
 * Contrbutior: Junshan Hu
 * Date: 2012-05-03
 */
#ifndef _MINILIBC_STDIO_H_
#define _MINILIBC_STDIO_H_

#include "ansidef.h"

#define __need_size_t
#define __need_NULL
#include <stddef.h>
#include <stdarg.h>

#ifndef NULL
#define NULL 0
#endif

#define EOF (-1)

/*
 *  A type capable of specifying uniquely every file position - ISO C
 *   standard chap 7.9.1
 */
typedef signed long fpos_t;

/* FILE is just cast to an address here. */
struct __stdio_file;
typedef struct __stdio_file FILE;

#define BUFSIZ 1024

#define FOPEN_MAX 20

#define FILENAME_MAX 1024

#define L_tmpnam FILENAME_MAX

#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2

#define TMP_MAX 26

#define _IOFBF  0               /* setvbuf should set fully buffered */
#define _IOLBF  1               /* setvbuf should set line buffered */
#define _IONBF  2               /* setvbuf should set unbuffered */

/*
 * Default file streams for input/output. These only need to be
 * expressions, not l-values - ISO C standard chap. 7.9.1
 */
extern FILE *stdin, *stdout, *stderr;

#define	__SLBF	0x0001		/* line buffered */
#define	__SNBF	0x0002		/* unbuffered */
#define	__SRD	0x0004		/* OK to read */
#define	__SWR	0x0008		/* OK to write */
	/* RD and WR are never simultaneously asserted */
#define	__SRW	0x0010		/* open for reading & writing */
#define	__SEOF	0x0020		/* found EOF */
#define	__SERR	0x0040		/* found error */
#define	__SMBF	0x0080		/* _buf is from malloc */
#define	__SAPP	0x0100		/* fdopen()ed in append mode - so must  write to end */
#define	__SSTR	0x0200		/* this is an sprintf/snprintf string */
#define	__SOPT	0x0400		/* do fseek() optimisation */
#define	__SNPT	0x0800		/* do not do fseek() optimisation */
#define	__SOFF	0x1000		/* set iff _offset is in fact correct */
#define	__SORD	0x2000		/* true => stream orientation (byte/wide) decided */
#if defined(__CYGWIN__)
#  define __SCLE  0x4000        /* convert line endings CR/LF <-> NL */
#endif
#define	__SL64	0x8000		/* is 64-bit offset large file */


#define	__sfeof(p)           ((int)(((p)->flags & __SEOF) != 0))
#define __sfileno(p)         ((p)->fd)

#ifdef __cplusplus
extern "C"{
#endif

extern int remove(const char *filename);
extern int rename(const char *oldname, const char *newname);
extern FILE *tmpfile(void);
extern char *tmpnam(char *sptr);
extern FILE *fopen(const char *filename, const char *type);
extern FILE *freopen(const char *filename, const char *type, FILE *fp);
extern int fflush(FILE *stream);
extern int fclose(FILE *stream);
extern void setbuf(FILE *stream, char *buf);
extern int setvbuf(FILE  *stream, char *buf, int type, size_t size);
extern int printf(const char *format, ...);
extern int fprintf(FILE *stream, const char *format, ...);
extern int sprintf(char *string, const char *format, ...);
extern int fnprintf(FILE *str,size_t size, const char *format,...);
extern int scanf(const char *format, ...);
extern int fscanf(FILE *stream, const char *format, ...);
extern int sscanf(const char *str, const char *format, ...);
extern int vfscanf(FILE * stream, const char * format, va_list arg_ptr);
extern int vscanf( const char * format, va_list ap);
extern int vsscanf(const char * str, const char * format, va_list arg_ptr);
extern int vprintf(const char *, va_list);
extern int vsprintf( char * str, const char * format, va_list arg_ptr);
extern int vsnprintf(char * str, size_t length, const char * format, va_list arg_ptr);
extern int vfprintf(FILE *stream, const char *format, va_list ap);
extern int snprintf(char *str, size_t size, const char *format, ...); 
extern int fgetc(FILE *stream);
extern char *fgets(char *string,int n, FILE *stream);
extern char *gets(char *s);
extern int fputc(int ch, FILE *stream);
extern int fputs(const char *string, FILE *stream);
extern int getc(FILE *stream);
extern int putc(int c, FILE *stream);
extern int putchar(int ch);
extern int puts(const char *string);
extern int ungetc(int c, FILE *stream);
extern size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
extern size_t fwrite(const void *ptr, size_t size, size_t nitems, FILE *stream);
extern int fseek(FILE *stream, long offset, int fromwhere);
extern long ftell(FILE *stream);
extern void rewind(FILE *stream);
extern int fgetpos(FILE *stream, fpos_t *fileops);
extern int fsetpos(FILE *stream, const fpos_t *pos);
extern void clearerr(FILE *stream);
extern int feof(FILE *stream);
extern int ferror(FILE *stream);
extern void perror(const char *string);

extern int __dtostr(double d,char *buf,unsigned int maxlen,unsigned int prec,unsigned int prec2);
extern int __lltostr(char *s, int size, unsigned long long i, int base, char UpCase);
extern int __ltostr(char *s, unsigned int size, unsigned long i, unsigned int base, int UpCase);

/* there is no function achieve */
extern int getchar (void);
extern FILE *fdopen (int __fd, __const char *__modes);
extern int fileno (FILE *__stream);
#ifdef __cplusplus
}
#endif

#endif  /* _MINILIBC_STDIO_H_ */

