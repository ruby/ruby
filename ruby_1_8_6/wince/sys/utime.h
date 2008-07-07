#ifndef SYS_UTIME_H
#define SYS_UTIME_H 1

#include <time.h>

struct utimbuf 
{
  time_t actime;
  time_t modtime;
};

#define _utimbuf utimbuf


#ifdef __cplusplus
extern "C" {
#endif

int utime(const char *f, struct utimbuf *t);

#ifdef __cplusplus
};
#endif

//#define utime _utime

#endif
