
#ifndef VARARGS_H
#define VARARGS_H 1

#ifdef  __cplusplus
extern "C" {
#endif

#ifndef _VA_LIST_DEFINED
typedef char *va_list;
#define _VA_LIST_DEFINED
#endif

//#ifdef MIPS
#define va_alist __va_alist, __va_alist2, __va_alist3, __va_alist4
#define va_dcl int __va_alist, __va_alist2, __va_alist3, __va_alist4;
#define va_start(list) list = (char *) &__va_alist
#define va_end(list)
#define va_arg(list, mode) ((mode *)(list =\
 (char *) ((((int)list + (__builtin_alignof(mode)<=4?3:7)) &\
 (__builtin_alignof(mode)<=4?-4:-8))+sizeof(mode))))[-1]
#else
#define _INTSIZEOF(n)    ( (sizeof(n) + sizeof(int) - 1) & ~(sizeof(int) - 1) )
#define va_dcl va_list va_alist;
#define va_start(ap) ap = (va_list)&va_alist
#define va_arg(ap,t) ( *(t *)((ap += _INTSIZEOF(t)) - _INTSIZEOF(t)) )
#define va_end(ap) ap = (va_list)0
//#endif

#ifdef  __cplusplus
}
#endif

#endif
