/* 
 *    Copyright (c) 1991, Larry Wall
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 */

#include "ruby.h"

#ifndef NT
extern char **environ;
#endif
extern char **origenviron;

#ifndef NT
char *strdup();
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

void
setenv(nam,val)
char *nam, *val;
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
