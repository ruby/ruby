#ifndef SYS_TIMEB_H
#define SYS_TIMEB_H 1

#include <sys/types.h>

struct _timeb {
	time_t time;
	unsigned short millitm;
	short timezone;
	short dstflag;
};

#define timeb _timeb

#ifdef __cplusplus
extern "C" {
#endif

int ftime(struct timeb *tp);

#ifdef __cplusplus
};
#endif


#endif
