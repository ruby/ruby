#include <windows.h>
#include <tchar.h>
#include "assert.h"


void assert( int expression )
{
	if( expression==0 )
		exit(2);
}

