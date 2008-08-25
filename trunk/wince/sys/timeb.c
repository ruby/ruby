/***************************************************************
  timeb.c
***************************************************************/

#include <windows.h>
#include <time.h>
#include <sys/timeb.h>


int ftime(struct timeb *tp)
{
	SYSTEMTIME s;
	FILETIME   f;

	GetLocalTime(&s);
	SystemTimeToFileTime( &s, &f );

	tp->dstflag  = 0;
	tp->timezone = _timezone/60;
	tp->time     = wce_FILETIME2time_t(&f);
	tp->millitm  = s.wMilliseconds;

	return 0;
}

