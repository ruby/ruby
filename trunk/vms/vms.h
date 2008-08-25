#ifndef __FAST_SETJMP
#define __FAST_SETJMP	/* use decc$setjmp/decc$longjmp */
#endif

extern int isinf(double);
extern int isnan(double);
extern int flock(int fd, int oper);

extern int vsnprintf();
extern int snprintf();

#define LONG_LONG long long
#define SIZEOF_LONG_LONG sizeof(long long)
