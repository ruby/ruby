/***************************************************************
  signal.c
***************************************************************/

#include <windows.h>
#include "signal.h"

/* lazy replacement... (^^; */
int raise(int sig)
{
	return 0;
}

//#ifdef _WIN32_WCE
//#ifdef _WIN32_WCE_EMULATION
//void (* signal(int sig, void (*func)))
//{
//	return sig;
//}
//#else
void (* signal(int sig, void (__cdecl *func)(int)))(int)
{
	return sig;
}
//#endif
//#endif
