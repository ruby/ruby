/************************************************

  util.c -

  $Author$
  $Date$
  created at: Fri Mar 10 17:22:34 JST 1995

  Copyright (C) 1993-1999 Yukihiro Matsumoto

************************************************/

#include <stdio.h>

#ifdef NT
#include "missing/file.h"
#endif

#define RUBY_NO_INLINE
#include "ruby.h"

#ifdef USE_CWGUSI
extern char* mktemp(char*);
#endif

VALUE
rb_class_of(obj)
    VALUE obj;
{
    if (FIXNUM_P(obj)) return rb_cFixnum;
    if (obj == Qnil) return rb_cNilClass;
    if (obj == Qfalse) return rb_cFalseClass;
    if (obj == Qtrue) return rb_cTrueClass;

    return RBASIC(obj)->klass;
}

int
rb_type(obj)
    VALUE obj;
{
    if (FIXNUM_P(obj)) return T_FIXNUM;
    if (obj == Qnil) return T_NIL;
    if (obj == Qfalse) return T_FALSE;
    if (obj == Qtrue) return T_TRUE;

    return BUILTIN_TYPE(obj);
}

int
rb_special_const_p(obj)
    VALUE obj;
{
    if (FIXNUM_P(obj)) return Qtrue;
    if (obj == Qnil) return Qtrue;
    if (obj == Qfalse) return Qtrue;
    if (obj == Qtrue) return Qtrue;

    return Qfalse;
}

int
rb_test_false_or_nil(v)
    VALUE v;
{
    return (v != Qnil) && (v != Qfalse);
}

#include "util.h"
#ifndef HAVE_STRING_H
char *strchr _((char*,char));
#endif

unsigned long
scan_oct(start, len, retlen)
const char *start;
int len;
int *retlen;
{
    register const char *s = start;
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
const char *start;
int len;
int *retlen;
{
    static char hexdigit[] = "0123456789abcdef0123456789ABCDEFx";
    register const char *s = start;
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
#if defined(HAVE_FCNTL)
#include <fcntl.h>
#endif

#ifndef S_ISDIR
#   define S_ISDIR(m) ((m & S_IFMT) == S_IFDIR)
#endif

#ifdef NT
#include "missing/file.h"
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
ruby_add_suffix(str, suffix)
    VALUE str;
    char *suffix;
{
    int baselen;
    int extlen = strlen(suffix);
    char *s, *t, *p;
    int slen;
    char buf[1024];

    if (RSTRING(str)->len > 1000)
        rb_fatal("Cannot do inplace edit on long filename (%d characters)",
		 RSTRING(str)->len);

#if defined(DJGPP) || defined(__CYGWIN32__) || defined(NT)
    /* Style 0 */
    slen = RSTRING(str)->len;
    rb_str_cat(str, suffix, extlen);
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
    rb_str_resize(str, strlen(buf));
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
/* Copyright (C) 1995 DJ Delorie, see COPYING.DJ for details */
#include <libc/stubs.h>
#include <stdio.h>		/* For FILENAME_MAX */
#include <errno.h>		/* For errno */
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

/* mm.c */

static int mmkind, mmsize, high, low;

#define A ((int*)a)
#define B ((int*)b)
#define C ((int*)c)
#define D ((int*)d)

static void mmprepare(base, size) void *base; int size;
{
#ifdef DEBUG
 if (sizeof(int) != 4) die("sizeof(int) != 4");
 if (size <= 0) die("mmsize <= 0");
#endif

 if (((long)base & (4-1)) == 0 && ((long)base & (4-1)) == 0)
   if (size >= 16) mmkind = 1;
   else            mmkind = 0;
 else              mmkind = -1;
 
 mmsize = size;
 high = (size & (-16));
 low  = (size & 0x0C );
}

static void mmswap(a, b) register char *a, *b;
{
 register int s;
 if (a == b) return;
 if (mmkind >= 0) {
   if (mmkind > 0) {
     register char *t = a + high;
     do {
       s = A[0]; A[0] = B[0]; B[0] = s;
       s = A[1]; A[1] = B[1]; B[1] = s;
       s = A[2]; A[2] = B[2]; B[2] = s;
       s = A[3]; A[3] = B[3]; B[3] = s;  a += 16; b += 16;
     } while (a < t);
   }
   if (low != 0) { s = A[0]; A[0] = B[0]; B[0] = s;
     if (low >= 8) { s = A[1]; A[1] = B[1]; B[1] = s;
       if (low == 12) {s = A[2]; A[2] = B[2]; B[2] = s;}}}
 }else{
   register char *t = a + mmsize;
   do {s = *a; *a++ = *b; *b++ = s;} while (a < t);
 }
}

static void mmswapblock(a, b, size) register char *a, *b; int size;
{
 register int s;
 if (mmkind >= 0) {
   register char *t = a + (size & (-16)); register int  lo = (size & 0x0C);
   if (size >= 16) {
     do {
       s = A[0]; A[0] = B[0]; B[0] = s;
       s = A[1]; A[1] = B[1]; B[1] = s;
       s = A[2]; A[2] = B[2]; B[2] = s;
       s = A[3]; A[3] = B[3]; B[3] = s;  a += 16; b += 16;
     }while (a < t);
   }
   if (lo != 0) { s = A[0]; A[0] = B[0]; B[0] = s;
     if (lo >= 8) { s = A[1]; A[1] = B[1]; B[1] = s;
       if (lo == 12) {s = A[2]; A[2] = B[2]; B[2] = s;}}}
 }else{
   register char *t = a + size;
   do {s = *a; *a++ = *b; *b++ = s;} while (a < t);
 }
}

static void mmrot3(a, b, c) register char *a, *b, *c;
{
 register int s;
 if (mmkind >= 0) {
   if (mmkind > 0) {
     register char *t = a + high;
     do {
       s = A[0]; A[0] = B[0]; B[0] = C[0]; C[0] = s;
       s = A[1]; A[1] = B[1]; B[1] = C[1]; C[1] = s;
       s = A[2]; A[2] = B[2]; B[2] = C[2]; C[2] = s;
       s = A[3]; A[3] = B[3]; B[3] = C[3]; C[3] = s; a += 16; b += 16; c += 16;
     }while (a < t);
   }
   if (low != 0) { s = A[0]; A[0] = B[0]; B[0] = C[0]; C[0] = s;
     if (low >= 8) { s = A[1]; A[1] = B[1]; B[1] = C[1]; C[1] = s;
       if (low == 12) {s = A[2]; A[2] = B[2]; B[2] = C[2]; C[2] = s;}}}
 }else{
   register char *t = a + mmsize;
   do {s = *a; *a++ = *b; *b++ = *c; *c++ = s;} while (a < t);
 }
}

/* qs6.c */
/*****************************************************/
/*                                                   */
/*          qs6   (Quick sort function)              */
/*                                                   */
/* by  Tomoyuki Kawamura              1995.4.21      */
/* kawamura@tokuyama.ac.jp                           */
/*****************************************************/

typedef struct { char *LL, *RR; } stack_node; /* Stack structure for L,l,R,r */
#define PUSH(ll,rr) {top->LL = (ll); top->RR = (rr); ++top;}  /* Push L,l,R,r */
#define POP(ll,rr)  {--top; ll = top->LL; rr = top->RR;}      /* Pop L,l,R,r */

#define med3(a,b,c) ((*cmp)(a,b)<0 ?                                   \
                       ((*cmp)(b,c)<0 ? b : ((*cmp)(a,c)<0 ? c : a)) : \
                       ((*cmp)(b,c)>0 ? b : ((*cmp)(a,c)<0 ? a : c)) )

void ruby_qsort (base, nel, size, cmp) void* base; int nel; int size; int (*cmp)();
{
 register char *l, *r, *m;          	/* l,r:left,right group   m:median point */
 register int  t, eq_l, eq_r;       	/* eq_l: all items in left group are equal to S */
 char *L = base;                    	/* left end of curren region */
 char *R = (char*)base + size*(nel-1); 	/* right end of current region */
 int  chklim = 63;                      /* threshold of ordering element check */
 stack_node stack[32], *top = stack;    /* 32 is enough for 32bit CPU */

 if (nel <= 1) return;        /* need not to sort */
 mmprepare( base, size );
 goto start;
  
 nxt:
 if (stack == top) return;    /* return if stack is empty */
 POP(L,R);
   
 for (;;) {
   start:
   if (L + size == R) {if ((*cmp)(L,R) > 0) mmswap(L,R); goto nxt;}/* 2 elements */
   
   l = L; r = R;
   t = (r - l + size) / size;  /* number of elements */
   m = l + size * (t >> 1);    /* calculate median value */
   
   if (t >= 60) {
     register char *m1;
     register char *m3;
     if (t >= 200) {
       t = size*(t>>3); /* number of bytes in splitting 8 */
       {
       register char *p1 = l  + t;
       register char *p2 = p1 + t;
       register char *p3 = p2 + t;
       m1 = med3( p1, p2, p3 );
       p1 = m  + t;
       p2 = p1 + t;
       p3 = p2 + t;
       m3 = med3( p1, p2, p3 );
       }
     }else{
       t = size*(t>>2); /* number of bytes in splitting 4 */
       m1 = l + t;
       m3 = m + t;
     }
     m = med3( m1, m, m3 );
   }
   
   if ((t = (*cmp)(l,m)) < 0) {                             /*3-5-?*/
     if ((t = (*cmp)(m,r)) < 0) {                           /*3-5-7*/
       if (chklim && nel >= chklim) {   /* check if already ascending order */
         char *p;
         chklim = 0;
         for (p=l; p<r; p+=size) if ((*cmp)(p,p+size) > 0) goto fail;
         goto nxt;
       }
       fail: goto loopA;                                    /*3-5-7*/
     }
     if (t > 0) {
       if ((*cmp)(l,r) <= 0) {mmswap(m,r); goto loopA;}     /*3-5-4*/
       mmrot3(r,m,l); goto loopA;                           /*3-5-2*/
     }
     goto loopB;                                            /*3-5-5*/
   }
   
   if (t > 0) {                                             /*7-5-?*/
     if ((t = (*cmp)(m,r)) > 0) {                           /*7-5-3*/
       if (chklim && nel >= chklim) {   /* check if already ascending order */
         char *p;
         chklim = 0;
         for (p=l; p<r; p+=size) if ((*cmp)(p,p+size) < 0) goto fail2;
         while (l<r) {mmswap(l,r); l+=size; r-=size;}  /* reverse region */
         goto nxt;
       }
       fail2: mmswap(l,r); goto loopA;                      /*7-5-3*/
     }
     if (t < 0) {
       if ((*cmp)(l,r) <= 0) {mmswap(l,m); goto loopB;}     /*7-5-8*/
       mmrot3(l,m,r); goto loopA;                           /*7-5-6*/
     }
     mmswap(l,r); goto loopA;                               /*7-5-5*/
   }
    
   if ((t = (*cmp)(m,r)) < 0)  {goto loopA;}                /*5-5-7*/
   if (t > 0) {mmswap(l,r); goto loopB;}                    /*5-5-3*/
   
   /* deteming splitting type in case 5-5-5 */              /*5-5-5*/
   for (;;) {
     if ((l += size) == r)      goto nxt;                   /*5-5-5*/
     if (l == m) continue;
     if ((t = (*cmp)(l,m)) > 0) {mmswap(l,r); l = L; goto loopA;}  /*575-5*/
     if (t < 0)                 {mmswap(L,l); l = L; goto loopB;}  /*535-5*/
   }
   
   loopA: eq_l = 1; eq_r = 1;  /* splitting type A */ /* left <= median < right */
   for (;;) {
     for (;;) {
       if ((l += size) == r)
         {l -= size; if (l != m) mmswap(m,l); l -= size; goto fin;}
       if (l == m) continue;
       if ((t = (*cmp)(l,m)) > 0) {eq_r = 0; break;}
       if (t < 0) eq_l = 0;
     }
     for (;;) {
       if (l == (r -= size))
         {l -= size; if (l != m) mmswap(m,l); l -= size; goto fin;}
       if (r == m) {m = l; break;}
       if ((t = (*cmp)(r,m)) < 0) {eq_l = 0; break;}
       if (t == 0) break;
     }
     mmswap(l,r);    /* swap left and right */
   }
   
   loopB: eq_l = 1; eq_r = 1;  /* splitting type B */ /* left < median <= right */
   for (;;) {
     for (;;) {
       if (l == (r -= size))
         {r += size; if (r != m) mmswap(r,m); r += size; goto fin;}
       if (r == m) continue;
       if ((t = (*cmp)(r,m)) < 0) {eq_l = 0; break;}
       if (t > 0) eq_r = 0;
     }
     for (;;) {
       if ((l += size) == r)
         {r += size; if (r != m) mmswap(r,m); r += size; goto fin;}
       if (l == m) {m = r; break;}
       if ((t = (*cmp)(l,m)) > 0) {eq_r = 0; break;}
       if (t == 0) break;
     }
     mmswap(l,r);    /* swap left and right */
   }
   
   fin:
   if (eq_l == 0)                         /* need to sort left side */
     if (eq_r == 0)                       /* need to sort right side */
       if (l-L < R-r) {PUSH(r,R); R = l;} /* sort left side first */
       else           {PUSH(L,l); L = r;} /* sort right side first */
     else R = l;                          /* need to sort left side only */
   else if (eq_r == 0) L = r;             /* need to sort right side only */
   else goto nxt;                         /* need not to sort both sides */
 }
}

