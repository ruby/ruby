/************************************************

  util.c -

  $Author$
  $Date$
  created at: Fri Mar 10 17:22:34 JST 1995

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#define RUBY_NO_INLINE
#include "ruby.h"

int
rb_type(obj)
    VALUE obj;
{
    if (FIXNUM_P(obj)) return T_FIXNUM;
    if (obj == Qnil) return T_NIL;
    if (obj == FALSE) return T_FALSE;
    if (obj == TRUE) return T_TRUE;

    return BUILTIN_TYPE(obj);
}

int
rb_special_const_p(obj)
    VALUE obj;
{
    if (FIXNUM_P(obj)) return TRUE;
    if (obj == Qnil) return TRUE;
    if (obj == FALSE) return TRUE;
    if (obj == TRUE) return TRUE;

    return FALSE;
}

int
rb_test_false_or_nil(v)
    VALUE v;
{
    return (v != Qnil) && (v != FALSE);
}

#include "util.h"
#ifndef HAVE_STRING_H
char *strchr();
#endif

unsigned long
scan_oct(start, len, retlen)
char *start;
int len;
int *retlen;
{
    register char *s = start;
    register unsigned long retval = 0;

    while (len-- && *s >= '0' && *s <= '7') {
	retval <<= 3;
	retval |= *s++ - '0';
    }
    *retlen = s - start;
    return retval;
}

unsigned long
scan_hex(start, len, retlen)
char *start;
int len;
int *retlen;
{
    static char hexdigit[] = "0123456789abcdef0123456789ABCDEFx";
    register char *s = start;
    register unsigned long retval = 0;
    char *tmp;

    while (len-- && *s && (tmp = strchr(hexdigit, *s))) {
	retval <<= 4;
	retval |= (tmp - hexdigit) & 15;
	s++;
    }
    *retlen = s - start;
    return retval;
}

#include <sys/types.h>
#include <sys/stat.h>
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifndef S_ISDIR
#   define S_ISDIR(m) ((m & S_IFMT) == S_IFDIR)
#endif

static char *
check_dir(dir)
    char *dir;
{
    struct stat st;

    if (dir == NULL) return NULL;
    if (stat(dir, &st) < 0) return NULL;
    if (!S_ISDIR(st.st_mode)) return NULL;
    if (eaccess(dir, W_OK) < 0) return NULL;
    return dir;
}

char *
ruby_mktemp()
{
    char *dir;
    char *buf;

    dir = check_dir(getenv("TMP"));
    if (!dir) dir = check_dir(getenv("TMPDIR"));
    if (!dir) dir = "/tmp";

    buf = ALLOC_N(char,strlen(dir)+10);
    sprintf(buf, "%s/rbXXXXXX", dir);
    dir = mktemp(buf);
    if (dir == NULL) free(buf);

    return dir;
}

#if defined(MSDOS) || defined(__CYGWIN32__) || defined(NT)
#include <fcntl.h>
/*
 *  Copyright (c) 1993, Intergraph Corporation
 *
 *  You may distribute under the terms of either the GNU General Public
 *  License or the Artistic License, as specified in the perl README file.
 *
 *  Various Unix compatibility functions and NT specific functions.
 *
 *  Some of this code was derived from the MSDOS port(s) and the OS/2 port.
 *
 */


/*
 * Suffix appending for in-place editing under MS-DOS and OS/2 (and now NT!).
 *
 * Here are the rules:
 *
 * Style 0:  Append the suffix exactly as standard perl would do it.
 *           If the filesystem groks it, use it.  (HPFS will always
 *           grok it.  So will NTFS. FAT will rarely accept it.)
 *
 * Style 1:  The suffix begins with a '.'.  The extension is replaced.
 *           If the name matches the original name, use the fallback method.
 *
 * Style 2:  The suffix is a single character, not a '.'.  Try to add the 
 *           suffix to the following places, using the first one that works.
 *               [1] Append to extension.  
 *               [2] Append to filename, 
 *               [3] Replace end of extension, 
 *               [4] Replace end of filename.
 *           If the name matches the original name, use the fallback method.
 *
 * Style 3:  Any other case:  Ignore the suffix completely and use the
 *           fallback method.
 *
 * Fallback method:  Change the extension to ".$$$".  If that matches the
 *           original name, then change the extension to ".~~~".
 *
 * If filename is more than 1000 characters long, we die a horrible
 * death.  Sorry.
 *
 * The filename restriction is a cheat so that we can use buf[] to store
 * assorted temporary goo.
 *
 * Examples, assuming style 0 failed.
 *
 * suffix = ".bak" (style 1)
 *                foo.bar => foo.bak
 *                foo.bak => foo.$$$	(fallback)
 *                foo.$$$ => foo.~~~	(fallback)
 *                makefile => makefile.bak
 *
 * suffix = "~" (style 2)
 *                foo.c => foo.c~
 *                foo.c~ => foo.c~~
 *                foo.c~~ => foo~.c~~
 *                foo~.c~~ => foo~~.c~~
 *                foo~~~~~.c~~ => foo~~~~~.$$$ (fallback)
 *
 *                foo.pas => foo~.pas
 *                makefile => makefile.~
 *                longname.fil => longname.fi~
 *                longname.fi~ => longnam~.fi~
 *                longnam~.fi~ => longnam~.$$$
 *                
 */


static int valid_filename(char *s);

static char suffix1[] = ".$$$";
static char suffix2[] = ".~~~";

#define ext (&buf[1000])

#define strEQ(s1,s2) (strcmp(s1,s2) == 0)

void
add_suffix(VALUE str, char *suffix)
{
    int baselen;
    int extlen = strlen(suffix);
    char *s, *t, *p;
    int slen;
    char buf[1024];

    if (RSTRING(str)->len > 1000)
        Fatal("Cannot do inplace edit on long filename (%d characters)", RSTRING(str)->len);

#if defined(DJGPP) || defined(__CYGWIN32__) || defined(NT)
    /* Style 0 */
    slen = RSTRING(str)->len;
    str_cat(str, suffix, extlen);
#if defined(DJGPP)
    if (_USE_LFN) return;
#else
    if (valid_filename(RSTRING(str)->ptr)) return;
#endif

    /* Fooey, style 0 failed.  Fix str before continuing. */
    RSTRING(str)->ptr[RSTRING(str)->len = slen] = '\0';
#endif

    slen = extlen;
    t = buf; baselen = 0; s = RSTRING(str)->ptr;
    while ( (*t = *s) && *s != '.') {
	baselen++;
	if (*s == '\\' || *s == '/') baselen = 0;
 	s++; t++;
    }
    p = t;

    t = ext; extlen = 0;
    while (*t++ = *s++) extlen++;
    if (extlen == 0) { ext[0] = '.'; ext[1] = 0; extlen++; }

    if (*suffix == '.') {        /* Style 1 */
        if (strEQ(ext, suffix)) goto fallback;
	strcpy(p, suffix);
    } else if (suffix[1] == '\0') {  /* Style 2 */
        if (extlen < 4) { 
	    ext[extlen] = *suffix;
	    ext[++extlen] = '\0';
        } else if (baselen < 8) {
   	    *p++ = *suffix;
	} else if (ext[3] != *suffix) {
	    ext[3] = *suffix;
	} else if (buf[7] != *suffix) {
	    buf[7] = *suffix;
	} else goto fallback;
	strcpy(p, ext);
    } else { /* Style 3:  Panic */
fallback:
	(void)memcpy(p, strEQ(ext, suffix1) ? suffix2 : suffix1, 5);
    }
    str_resize(str, strlen(buf));
    memcpy(RSTRING(str)->ptr, buf, RSTRING(str)->len);
}

#if defined(__CYGWIN32__) || defined(NT)
static int 
valid_filename(char *s)
{
    int fd;

    /*
    // if the file exists, then it's a valid filename!
    */

    if (_access(s, 0) == 0) {
	return 1;
    }

    /*
    // It doesn't exist, so see if we can open it.
    */
    
    if ((fd = _open(s, O_CREAT, 0666)) >= 0) {
	_close(fd);
	_unlink (s);	/* don't leave it laying around */
	return 1;
    }
    return 0;
}
#endif
#endif

#ifdef DJGPP
/* Copyright (C) 1996 DJ Delorie, see COPYING.DJ for details */
/* Copyright (C) 1995 DJ Delorie, see COPYING.DJ for details */
#include <libc/stubs.h>
#include <stdio.h>		/* For FILENAME_MAX */
#include <errno.h>		/* For errno */
#include <ctype.h>		/* For tolower */
#include <fcntl.h>		/* For LFN stuff */
#include <go32.h>
#include <dpmi.h>		/* For dpmisim */
#include <crt0.h>		/* For crt0 flags */
#include <libc/dosio.h>

static unsigned use_lfn;

static char *__get_current_directory(char *out, int drive_number);

static char *
__get_current_directory(char *out, int drive_number)
{
  __dpmi_regs r;
  char tmpbuf[FILENAME_MAX];

  memset(&r, 0, sizeof(r));
  if(use_lfn)
    r.x.ax = 0x7147;
  else
    r.h.ah = 0x47;
  r.h.dl = drive_number + 1;
  r.x.si = __tb_offset;
  r.x.ds = __tb_segment;
  __dpmi_int(0x21, &r);

  if (r.x.flags & 1)
  {
    errno = r.x.ax;
    return out;
  }
  else
  {
    dosmemget(__tb, sizeof(tmpbuf), tmpbuf);
    strcpy(out+1,tmpbuf);

    /* Root path, don't insert "/", it'll be added later */
    if (*(out + 1) != '\0')
      *out = '/';
    else
      *out = '\0';
    return out + strlen(out);
  }
}

__inline__ static int
is_slash(int c)
{
  return c == '/' || c == '\\';
}

__inline__ static int
is_term(int c)
{
  return c == '/' || c == '\\' || c == '\0';
}

#ifdef SJIS
__inline__ static int
is_sjis1(int c)
{
  return 0x81 <= c && (c <= 0x9f || 0xe0 <= c);
}
#endif

/* Takes as input an arbitrary path.  Fixes up the path by:
   1. Removing consecutive slashes
   2. Removing trailing slashes
   3. Making the path absolute if it wasn't already
   4. Removing "." in the path
   5. Removing ".." entries in the path (and the directory above them)
   6. Adding a drive specification if one wasn't there
   7. Converting all slashes to '/'
 */
void
_fixpath(const char *in, char *out)
{
  int		drive_number;
  const char	*ip = in;
  char		*op = out;
  int		preserve_case = _preserve_fncase();
  char		*name_start;

  use_lfn = _USE_LFN;

  /* Add drive specification to output string */
  if (((*ip >= 'a' && *ip <= 'z') ||
       (*ip >= 'A' && *ip <= 'Z'))
      && (*(ip + 1) == ':'))
  {
    if (*ip >= 'a' && *ip <= 'z')
    {
      drive_number = *ip - 'a';
      *op++ = *ip++;
    }
    else
    {
      drive_number = *ip - 'A';
      if (*ip <= 'Z')
	*op++ = drive_number + 'a';
      else
	*op++ = *ip;
      ++ip;
    }
    *op++ = *ip++;
  }
  else
  {
    __dpmi_regs r;
    r.h.ah = 0x19;
    __dpmi_int(0x21, &r);
    drive_number = r.h.al;
    *op++ = drive_number + (drive_number < 26 ? 'a' : 'A');
    *op++ = ':';
  }

  /* Convert relative path to absolute */
  if (!is_slash(*ip))
    op = __get_current_directory(op, drive_number);

  /* Step through the input path */
  while (*ip)
  {
    /* Skip input slashes */
    if (is_slash(*ip))
    {
      ip++;
      continue;
    }

    /* Skip "." and output nothing */
    if (*ip == '.' && is_term(*(ip + 1)))
    {
      ip++;
      continue;
    }

    /* Skip ".." and remove previous output directory */
    if (*ip == '.' && *(ip + 1) == '.' && is_term(*(ip + 2)))
    {
      ip += 2;
      /* Don't back up over drive spec */
      if (op > out + 2)
	/* This requires "/" to follow drive spec */
	while (!is_slash(*--op));
      continue;
    }

    /* Copy path component from in to out */
    *op++ = '/';
#ifndef SJIS
    while (!is_term(*ip)) *op++ = *ip++;
#else
    while (!is_term(*ip)) {
      if (is_sjis1((unsigned char)*ip))
	*op++ = *ip++;
      *op++ = *ip++;
    }
#endif
  }

  /* If root directory, insert trailing slash */
  if (op == out + 2) *op++ = '/';

  /* Null terminate the output */
  *op = '\0';

  /* switch FOO\BAR to foo/bar, downcase where appropriate */
  for (op = out + 3, name_start = op - 1; *name_start; op++)
  {
    char long_name[FILENAME_MAX], short_name[13];

#ifdef SJIS
    if (is_sjis1((unsigned char)*op)) {
      op++;
      continue;
    }
#endif
    if (*op == '\\')
      *op = '/';
    if (!preserve_case && (*op == '/' || *op == '\0'))
    {
      memcpy(long_name, name_start+1, op - name_start - 1);
      long_name[op - name_start - 1] = '\0';
      if (!strcmp(_lfn_gen_short_fname(long_name, short_name), long_name))
      {
#ifndef SJIS
	while (++name_start < op)
	  if (*name_start >= 'A' && *name_start <= 'Z')
	    *name_start += 'a' - 'A';
#else
	while (++name_start < op) {
	  if (is_sjis1((unsigned char)*name_start))
	    name_start++;
	  else if (*name_start >= 'A' && *name_start <= 'Z')
	    *name_start += 'a' - 'A';
	}
#endif
      }
      else
	name_start = op;
    }
    else if (*op == '\0')
      break;
  }
}

#ifdef TEST

int main (int argc, char *argv[])
{
  char fixed[FILENAME_MAX];
  if (argc > 1)
    {
      _fixpath (argv[1], fixed);
      printf ("You mean %s?\n", fixed);
    }
  return 0;
}

#endif
#endif
