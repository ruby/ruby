/***************************************************************
  stdlib.c
***************************************************************/

#include <windows.h>

char **environ;
extern char * rb_w32_getenv(const char *);

/* getenv should replace with rb_w32_getenv. */
char *getenv(const char *env)
{
	return rb_w32_getenv(env);
}

char *_fullpath(char *absPath, const char *relPath, 
				size_t maxLength)
{
	strcpy( absPath, relPath );
	return absPath;
}

