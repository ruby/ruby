/**********************************************************************

  util.c -

  $Author$
  $Date$
  created at: Fri Mar 10 17:22:34 JST 1995

  Copyright (C) 1993-2000 Yukihiro Matsumoto

**********************************************************************/

#include <stdio.h>

#ifdef NT
#include "missing/file.h"
#endif

#define INLINE_DEFINE
#include "ruby.h"

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
    static char hexdigit[] = "0123456789abcdef0123456789ABCDEF";
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
#if defined(HAVE_FCNTL_H)
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
        rb_fatal("Cannot do inplace edit on long filename (%ld characters)",
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
    while ((*t = *s) && *s != '.') {
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

#if defined __DJGPP__

#include <dpmi.h>

static char dbcs_table[256];

int
make_dbcs_table()
{
    __dpmi_regs r;
    struct {
	unsigned char start;
	unsigned char end;
    } vec;
    int offset;

    memset(&r, 0, sizeof(r));
    r.x.ax = 0x6300;
    __dpmi_int(0x21, &r);
    offset = r.x.ds * 16 + r.x.si;

    for (;;) {
	int i;
	dosmemget(offset, sizeof vec, &vec);
	if (!vec.start && !vec.end)
	    break;
	for (i = vec.start; i <= vec.end; i++)
	    dbcs_table[i] = 1;
	offset += 2;
    }
}

int
mblen(const char *s, size_t n)
{
    static int need_init = 1;
    if (need_init) {
	make_dbcs_table();
	need_init = 0;
    }
    if (s) {
	if (n == 0 || *s == 0)
	    return 0;
	return dbcs_table[(unsigned char)*s] + 1;
    }
    else
	return 1;
}

struct PathList {
    struct PathList *next;
    char *path;
};

struct PathInfo {
    struct PathList *head;
    int count;
};

static void
push_element(const char *path, VALUE vinfo)
{
    struct PathList *p;
    struct PathInfo *info = (struct PathInfo *)vinfo;

    p = ALLOC(struct PathList);
    MEMZERO(p, struct PathList, 1);
    p->path = ruby_strdup(path);
    p->next = info->head;
    info->head = p;
    info->count++;
}

#include <dirent.h>
int __opendir_flags = __OPENDIR_PRESERVE_CASE;

char **
__crt0_glob_function(char *path)
{
    int len = strlen(path);
    int i;
    char **rv;
    char path_buffer[PATH_MAX];
    char *buf = path_buffer;
    char *p;
    struct PathInfo info;
    struct PathList *plist;

    if (PATH_MAX <= len)
	buf = ruby_xmalloc(len + 1);

    strncpy(buf, path, len);
    buf[len] = '\0';

    for (p = buf; *p; p += mblen(p, MB_CUR_MAX))
	if (*p == '\\')
	    *p = '/';

    info.count = 0;
    info.head = 0;

    rb_iglob(buf, push_element, (VALUE)&info);

    if (buf != path_buffer)
	ruby_xfree(buf);

    if (info.count == 0)
	return 0;

    rv = ruby_xmalloc((info.count + 1) * sizeof (char *));

    plist = info.head;
    i = 0;
    while (plist) {
	struct PathList *cur;
	rv[i] = plist->path;
	cur = plist;
	plist = plist->next;
	ruby_xfree(cur);
	i++;
    }
    rv[i] = 0;
    return rv;
}

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
 low  = (size & 0x0c);
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
                       ((*cmp)(b,c)>0 ? b : ((*cmp)(a,c)<0 ? a : c)))

void ruby_qsort (base, nel, size, cmp) void* base; int nel; int size; int (*cmp)();
{
 register char *l, *r, *m;          	/* l,r:left,right group   m:median point */
 register int  t, eq_l, eq_r;       	/* eq_l: all items in left group are equal to S */
 char *L = base;                    	/* left end of curren region */
 char *R = (char*)base + size*(nel-1); 	/* right end of current region */
 int  chklim = 63;                      /* threshold of ordering element check */
 stack_node stack[32], *top = stack;    /* 32 is enough for 32bit CPU */

 if (nel <= 1) return;        /* need not to sort */
 mmprepare(base, size);
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
       m1 = med3(p1, p2, p3);
       p1 = m  + t;
       p2 = p1 + t;
       p3 = p2 + t;
       m3 = med3(p1, p2, p3);
       }
     }else{
       t = size*(t>>2); /* number of bytes in splitting 4 */
       m1 = l + t;
       m3 = m + t;
     }
     m = med3(m1, m, m3);
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

char *
ruby_strdup(str)
    const char *str;
{
    char *tmp;
    int len = strlen(str) + 1;

    tmp = xmalloc(len);
    if (tmp == NULL) return NULL;
    memcpy(tmp, str, len);

    return tmp;
}
