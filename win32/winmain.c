#include <stdio.h>
#include <windows.h>

extern int main(int, char **);

int WINAPI
WinMain(HINSTANCE current, HINSTANCE prev, LPSTR cmdline, int showcmd)
{
    return main(0, NULL);
}
