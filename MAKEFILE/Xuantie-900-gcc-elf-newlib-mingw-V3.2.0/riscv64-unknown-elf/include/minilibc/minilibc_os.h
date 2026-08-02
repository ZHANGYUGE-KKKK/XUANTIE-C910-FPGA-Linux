/*
 * minilibc_os.h.
 *
 * Copyright (C): 2012 Hangzhou C-SKY Microsystem Co.,LTD.
 * Author: Linfei Chen (linfei_chen@c-sky.com)
 * Contrbutior: Linfei Chen
 * Date: 2014-06-04
 */
#ifndef _MINILIBC_OS_H_
#define _MINILIBC_OS_H_

#include <features.h>

#ifdef MINILIBC_WITHOUT_CRITICAL_LOCK

#define os_critical_open(lock)
#define os_critical_enter(lock)
#define os_critical_exit(lock)
#define os_critical_close(lock)

#else

extern int os_critical_open(unsigned int *lock);

extern int os_critical_enter(unsigned int *lock);

extern int os_critical_exit(unsigned int *lock);

extern int os_critical_close(unsigned int *lock);

#endif  /* MINILIBC_WITHOUT_CRITICAL_LOCK */

#endif  /* _MINILIBC_OS_H_ */

