/* 
 *    Copyright (c) 1991, Larry Wall
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 */

void *xmalloc ();
void *xcalloc ();
void *xrealloc ();
#define ALLOC_N(type,n) (type*)xmalloc(sizeof(type)*(n))
#define ALLOC(type) (type*)xmalloc(sizeof(type))
#define REALLOC_N(var,type,n) (var)=(type*)xrealloc((char*)(var),sizeof(type)*(n))

#ifndef NT
extern char **environ;
#endif
extern char **origenviron;

#ifndef NT
char *strdup();
#endif

#ifdef USE_WIN32_RTL_ENV
#include <stdlib.h>
#endif

static int
envix(nam)
char *nam;
{
    register int i, len = strlen(nam);

    for (i = 0; environ[i]; i++) {
	if (memcmp(environ[i],nam,len) == 0 && environ[i][len] == '=')
	    break;			/* memcmp must come first to avoid */
    }					/* potential SEGV's */
    return i;
}

#ifndef WIN32
void
setenv(nam,val, n)
char *nam, *val;
int n;
{
    register int i=envix(nam);		/* where does it go? */

    if (environ == origenviron) {	/* need we copy environment? */
	int j;
	int max;
	char **tmpenv;

	/*SUPPRESS 530*/
	for (max = i; environ[max]; max++) ;
	tmpenv = ALLOC_N(char*, max+2);
	for (j=0; j<max; j++)		/* copy environment */
	    tmpenv[j] = strdup(environ[j]);
	tmpenv[max] = 0;
	environ = tmpenv;		/* tell exec where it is now */
    }
    if (!val) {
	while (environ[i]) {
	    environ[i] = environ[i+1];
	    i++;
	}
	return;
    }
    if (!environ[i]) {			/* does not exist yet */
	REALLOC_N(environ, char*, i+2);	/* just expand it a bit */
	environ[i+1] = 0;	/* make sure it's null terminated */
    }
    else {
	free(environ[i]);
    }
    environ[i] = ALLOC_N(char, strlen(nam) + strlen(val) + 2);
#ifndef MSDOS
    (void)sprintf(environ[i],"%s=%s",nam,val);/* all that work just for this */
#else
    /* MS-DOS requires environment variable names to be in uppercase */
    /* [Tom Dinger, 27 August 1990: Well, it doesn't _require_ it, but
     * some utilities and applications may break because they only look
     * for upper case strings. (Fixed strupr() bug here.)]
     */
    strcpy(environ[i],nam); strupr(environ[i]);
    (void)sprintf(environ[i] + strlen(nam),"=%s",val);
#endif /* MSDOS */
}
#else /* if WIN32 */
int
setenv(nam,val, n)
char *nam, *val;
int n;
{
#ifdef USE_WIN32_RTL_ENV

    register char *envstr;
    STRLEN namlen = strlen(nam);
    STRLEN vallen;
    char *oldstr = environ[envix(nam)];

    /* putenv() has totally broken semantics in both the Borland
     * and Microsoft CRTLs.  They either store the passed pointer in
     * the environment without making a copy, or make a copy and don't
     * free it. And on top of that, they dont free() old entries that
     * are being replaced/deleted.  This means the caller must
     * free any old entries somehow, or we end up with a memory
     * leak every time setenv() is called.  One might think
     * one could directly manipulate environ[], like the UNIX code
     * above, but direct changes to environ are not allowed when
     * calling putenv(), since the RTLs maintain an internal
     * *copy* of environ[]. Bad, bad, *bad* stink.
     * GSAR 97-06-07
     */

    if (!val) {
	if (!oldstr)
	    return;
	val = "";
	vallen = 0;
    }
    else
	vallen = strlen(val);
    envstr = ALLOC_N(char, namelen + vallen + 3);
    (void)sprintf(envstr,"%s=%s",nam,val);
    (void)putenv(envstr);
    if (oldstr)
	free(oldstr);
#ifdef _MSC_VER
    free(envstr);		/* MSVCRT leaks without this */
#endif

#else /* !USE_WIN32_RTL_ENV */

    /* The sane way to deal with the environment.
     * Has these advantages over putenv() & co.:
     *  * enables us to store a truly empty value in the
     *    environment (like in UNIX).
     *  * we don't have to deal with RTL globals, bugs and leaks.
     *  * Much faster.
     * Why you may want to enable USE_WIN32_RTL_ENV:
     *  * environ[] and RTL functions will not reflect changes,
     *    which might be an issue if extensions want to access
     *    the env. via RTL.  This cuts both ways, since RTL will
     *    not see changes made by extensions that call the Win32
     *    functions directly, either.
     * GSAR 97-06-07
     */
    SetEnvironmentVariable(nam,val);

#endif
    return 1;
}

#endif /* WIN32 */
