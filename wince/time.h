#ifndef _TIME_WINCE_H
#define _TIME_WINCE_H 1

#include <winbase.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

extern int daylight;
extern int _timezone, timezone;
extern char *tzname[2];

#if 0
#define _DAY_SEC           (24L * 60L * 60L)    /* secs in a day */
#define _YEAR_SEC          (365L * _DAY_SEC)    /* secs in a year */
#define _FOUR_YEAR_SEC     (1461L * _DAY_SEC)   /* secs in a 4 year interval */
#define _DEC_SEC           315532800L           /* secs in 1970-1979 */
#define _BASE_YEAR         70L                  /* 1970 is the base year */
#define _BASE_DOW          4                    /* 01-01-70 was a Thursday */
#define _LEAP_YEAR_ADJUST  17L                  /* Leap years 1900 - 1970 */
#define _MAX_YEAR          138L                 /* 2038 is the max year */
#endif

#ifndef _TM_DEFINED
struct tm {
  int tm_sec;     /* seconds after the minute - [0,59] */
  int tm_min;     /* minutes after the hour - [0,59] */
  int tm_hour;    /* hours since midnight - [0,23] */
  int tm_mday;    /* day of the month - [1,31] */
  int tm_mon;     /* months since January - [0,11] */
  int tm_year;    /* years since 1900 */
  int tm_wday;    /* days since Sunday - [0,6] */
  int tm_yday;    /* days since January 1 - [0,365] */
  int tm_isdst;   /* daylight savings time flag */
};
#define _TM_DEFINED
#endif


typedef struct {
		int  yr;        // year of interest
		int  yd;        // day of year 
		long ms;        // milli-seconds in the day 
} transitionTime;

time_t mktime(struct tm* pt);
time_t time( time_t *timer );
struct tm *localtime(const time_t *ptime);
struct tm *gmtime(const time_t *tod);
char* ctime( const time_t *t );
char* asctime(const struct tm *tptr);
void tzset();
int clock(void);
time_t wce_FILETIME2time_t(const FILETIME* pf);


#ifdef __cplusplus
};
#endif

#endif
