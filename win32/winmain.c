#include <windows.h>
#include <stdio.h>

extern int wmain(int, WCHAR**);

int WINAPI
WinMain(HINSTANCE current, HINSTANCE prev, LPSTR cmdline, int showcmd)
{
    return wmain(0, NULL);
}
