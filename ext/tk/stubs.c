int ruby_tcltk_stubs();

#if defined USE_TCL_STUBS && defined USE_TK_STUBS
#include "ruby.h"

#if defined _WIN32 || defined __CYGWIN__
# include "util.h"
# include <windows.h>
  typedef HINSTANCE DL_HANDLE;
# define DL_OPEN LoadLibrary
# define DL_SYM GetProcAddress
# define TCL_INDEX 4
# define TK_INDEX 3
# define TCL_NAME "tcl89%s"
# define TK_NAME "tk89%s"
# undef DLEXT
# define DLEXT ".dll"
#elif defined HAVE_DLOPEN
# include <dlfcn.h>
  typedef void *DL_HANDLE;
# define DL_OPEN(file) dlopen(file, RTLD_LAZY|RTLD_GLOBAL)
# define DL_SYM dlsym
# define TCL_INDEX 8
# define TK_INDEX 7
# define TCL_NAME "libtcl8.9%s"
# define TK_NAME "libtk8.9%s"
#endif

#include <tcl.h>
#include <tk.h>

int
ruby_tcltk_stubs()
{
    DL_HANDLE tcl_dll;
    DL_HANDLE tk_dll;
    void (*p_Tcl_FindExecutable)(const char *);
    Tcl_Interp *(*p_Tcl_CreateInterp)();
    int (*p_Tk_Init)(Tcl_Interp *);
    Tcl_Interp *tcl_ip;
    int n;
    char *ruby_tcl_dll = 0;
    char *ruby_tk_dll = 0;
    char tcl_name[20];
    char tk_name[20];

    ruby_tcl_dll = getenv("RUBY_TCL_DLL");
#if defined _WIN32
    if (ruby_tcl_dll) ruby_tcl_dll = ruby_strdup(ruby_tcl_dll);
#endif
    ruby_tk_dll = getenv("RUBY_TK_DLL");
    if (ruby_tcl_dll && ruby_tk_dll) {
        tcl_dll = (DL_HANDLE)DL_OPEN(ruby_tcl_dll);
        tk_dll = (DL_HANDLE)DL_OPEN(ruby_tk_dll);
    } else {
        snprintf(tcl_name, sizeof tcl_name, TCL_NAME, DLEXT);
        snprintf(tk_name, sizeof tk_name, TK_NAME, DLEXT);
        /* examine from 8.9 to 8.1 */
        for (n = '9'; n > '0'; n--) {
            tcl_name[TCL_INDEX] = n;
            tk_name[TK_INDEX] = n;
            tcl_dll = (DL_HANDLE)DL_OPEN(tcl_name);
            tk_dll = (DL_HANDLE)DL_OPEN(tk_name);
            if (tcl_dll && tk_dll)
                break;
        }
    }

#if defined _WIN32
    if (ruby_tcl_dll) ruby_xfree(ruby_tcl_dll);
#endif

    if (!tcl_dll || !tk_dll)
        return -1;

    p_Tcl_FindExecutable = (void (*)(const char *))DL_SYM(tcl_dll, "Tcl_FindExecutable");
    if (!p_Tcl_FindExecutable)
        return -7;

    p_Tcl_FindExecutable("ruby");

    p_Tcl_CreateInterp = (Tcl_Interp *(*)())DL_SYM(tcl_dll, "Tcl_CreateInterp");
    if (!p_Tcl_CreateInterp)
        return -2;

    tcl_ip = (*p_Tcl_CreateInterp)();
    if (!tcl_ip)
        return -3;

    p_Tk_Init = (int (*)(Tcl_Interp *))DL_SYM(tk_dll, "Tk_Init");
    if (!p_Tk_Init)
        return -4;
    (*p_Tk_Init)(tcl_ip);

    if (!Tcl_InitStubs(tcl_ip, "8.1", 0))
        return -5;
    if (!Tk_InitStubs(tcl_ip, "8.1", 0))
        return -6;

    Tcl_DeleteInterp(tcl_ip);

    return 0;
}
#endif
