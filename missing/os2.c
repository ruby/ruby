#include "ruby.h"
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <process.h>
#include <limits.h>
#include <errno.h>

#define INCL_DOS
#include <os2.h>

int
chown(char *path, int owner, int group)
{
	return 0;
}

int
link(char *from, char *to)
{
	return -1;
}

typedef char* CHARP;

int
do_spawn(cmd)
char *cmd;
{
    register char **a;
    register char *s;
    char **argv;
    char *shell, *sw, *cmd2;
    int status;

    if ((shell = getenv("RUBYSHELL")) != NULL && *shell != '\0') {
	s = shell;
	do
	    *s = isupper(*s) ? tolower(*s) : *s;
	while (*++s);
	if (strstr(shell, "cmd") || strstr(shell, "4os2"))
	    sw = "/c";
	else
	    sw = "-c";
    } else if ((shell = getenv("SHELL")) != NULL && *shell != '\0') {
	s = shell;
	do
	    *s = isupper(*s) ? tolower(*s) : *s;
	while (*++s);
	if (strstr(shell, "cmd") || strstr(shell, "4os2"))
	    sw = "/c";
	else
	    sw = "-c";
    } else if ((shell = getenv("COMSPEC")) != NULL && *shell != '\0') {
	s = shell;
	do
	    *s = isupper(*s) ? tolower(*s) : *s;
	while (*++s);
	if (strstr(shell, "cmd") || strstr(shell, "4os2"))
	    sw = "/c";
	else
	    sw = "-c";
    }
    /* see if there are shell metacharacters in it */
    /*SUPPRESS 530*/
    /*    for (s = cmd; *s && isalpha(*s); s++) ;
    if (*s == '=')
    goto doshell; */
    for (s = cmd; *s; s++) {
	if (*sw == '-' && *s != ' ' && 
	    !isalpha(*s) && index("$&*(){}[]'\";\\|?<>~`\n",*s)) {
	    if (*s == '\n' && !s[1]) {
		*s = '\0';
		break;
	    }
	    goto doshell;
	} else if (*sw == '/' && *s != ' ' && 
	    !isalpha(*s) && index("^()<>|&\n",*s)) {
	    if (*s == '\n' && !s[1]) {
		*s = '\0';
		break;
	    }
	  doshell:
	    status = spawnlp(P_WAIT,shell,shell,sw,cmd,(char*)NULL);
	    return status;
	}
    }
    argv = ALLOC_N(CHARP,(strlen(cmd) / 2 + 2));
    cmd2 = ALLOC_N(char, (strlen(cmd) + 1));
    strcpy(cmd2, cmd);
    a = argv;
    for (s = cmd2; *s;) {
	while (*s && isspace(*s)) s++;
	if (*s)
	    *(a++) = s;
	while (*s && !isspace(*s)) s++;
	if (*s)
	    *s++ = '\0';
    }
    *a = NULL;
    if (argv[0]) {
	if ((status = spawnvp(P_WAIT, argv[0], argv)) == -1) {
	    free(argv);
	    free(cmd2);
	    return -1;
	}
    }
    free(cmd2);
    free(argv);
    return status;
}
