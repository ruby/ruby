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

int mblen(const char *mbstr, size_t count)
{
	const char *p = mbstr;
	size_t i;
	int    n=0;

	for( i=0; i<count; i++ )
	{
		if( *p=='\0' ) break;
		if( IsDBCSLeadByteEx( CP_ACP, *p ) )
			n+=2;
		else
			n+=1;
	}

	return n;
}
