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
			n+=2, p+=2;
		else
			n+=1, p+=1;
	}

	return n;
}

void *bsearch( const void *key, const void *base,
			   size_t num, size_t width,
			   int ( __cdecl *compare )(const void *, const void *))
{
	size_t i;
	const void* p = base;
	const char* px;

	for( i=0; i<num; i++ )
	{
		if( 0==compare( key, p ) )
			return (void*)p;
		px = (const char*)p; px+=width; p=(const void*)px;
	}
	return NULL;
}

