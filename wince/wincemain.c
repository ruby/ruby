#include <windows.h>
#include <stdio.h>
#include "wince.h"

extern int main(int, char**, char**);


int WINAPI
WinMain(HINSTANCE current, HINSTANCE prev, LPWSTR wcmd, int showcmd)
{
	/* wchar_t -> char */
	wce_SetCommandLine(wcmd);

	wce_SetCurrentDir();

	/* main. */
    return main(0, NULL, NULL);
}

