/************************************************

  dln.c -

  $Author: matz $
  $Date: 1994/06/17 14:23:49 $
  created at: Tue Jan 18 17:05:06 JST 1994

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include <stdio.h>
#include <sys/param.h>
#include <sys/file.h>
#include "defines.h"
#include "dln.h"
#include <sys/types.h>
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

char *strdup();

extern int errno;
int dln_errno;

static int dln_init_p = 0;

#include <sys/stat.h>

static char fbuf[MAXPATHLEN];
static char *dln_find_1();
char *getenv();
char *index();
int strcmp();

char *
dln_find_exe(fname, path)
    char *fname;
    char *path;
{
    if (!path) path = getenv("PATH");
    if (!path) path = "/usr/local/bin:/usr/ucb:/usr/bin:/bin:.";
    return dln_find_1(fname, path, 1);
}

char *
dln_find_file(fname, path)
    char *fname;
    char *path;
{
    if (!path) path = ".";
    return dln_find_1(fname, path, 0);
}

static char *
dln_find_1(fname, path, exe_flag)
    char *fname;
    char *path;
    int exe_flag;		/* non 0 if looking for executable. */
{
    register char *dp;
    register char *ep;
    register char *bp;
    struct stat st;

    if (fname[0] == '/') return fname;

    for (dp = path;; dp = ++ep)
    {
	register int l;
	int i;
	int fspace;

	/* extract a component */
	ep = index(dp, ':');
	if (ep == NULL)
	    ep = dp+strlen(dp);

	/* find the length of that component */
	l = ep - dp;
	bp = fbuf;
	fspace = sizeof fbuf - 2;
	if (l > 0)
	{
	    /*
	    **	If the length of the component is zero length,
	    **	start from the current directory.  If the
	    **	component begins with "~", start from the
	    **	user's $HOME environment variable.  Otherwise
	    **	take the path literally.
	    */

	    if (*dp == '~' && (l == 1 || dp[1] == '/'))
	    {
		char *home;

		home = getenv("HOME");
		if (home != NULL)
		{
		    i = strlen(home);
		    if ((fspace -= i) < 0)
			goto toolong;
		    memcpy(bp, home, i);
		    bp += i;
		}
		dp++;
		l--;
	    }
	    if (l > 0)
	    {
		if ((fspace -= l) < 0)
		    goto toolong;
		memcpy(bp, dp, l);
		bp += l;
	    }

	    /* add a "/" between directory and filename */
	    if (ep[-1] != '/')
		*bp++ = '/';
	}

	/* now append the file name */
	i = strlen(fname);
	if ((fspace -= i) < 0)
	{
    toolong:
	    fprintf(stderr, "openpath: pathname too long (ignored)\n");
	    *bp = '\0';
	    fprintf(stderr, "\tDirectory \"%s\"\n", fbuf);
	    fprintf(stderr, "\tFile \"%s\"\n", fname);
	    continue;
	}
	memcpy(bp, fname, i + 1);

	if (stat(fbuf, &st) == 0) {
	    if (exe_flag == 0) return fbuf;
	    /* looking for executable */
#ifdef RUBY
	    if (eaccess(fbuf, X_OK) == 0) return fbuf;
#else
	    {
		uid_t uid = getuid();
		gid_t gid = getgid();

		if (uid == st.st_uid &&
		    (st.st_mode & S_IEXEC) ||
		    gid == st.st_gid &&
		    (st.st_mode & (S_IEXEC>>3)) ||
		    st.st_mode & (S_IEXEC>>6)) {
		    return fbuf;
		}
	    }
#endif
	}
	/* if not, and no other alternatives, life is bleak */
	if (*ep == '\0') {
	    dln_errno = DLN_ENOENT;
	    return NULL;
	}

	/* otherwise try the next component in the search path */
    }
}

#ifdef USE_DLN

#include "st.h"
#include <ar.h>
#include <a.out.h>
#ifndef N_COMM
# define N_COMM 0x12
#endif

#define INVALID_OBJECT(h) (N_MAGIC(h) != OMAGIC)

static st_table *sym_tbl;
static st_table *undef_tbl;

static int
dln_load_header(fd, hdrp, disp)
    int fd;
    struct exec *hdrp;
    long disp;
{
    int size;

    lseek(fd, disp, 0);
    size = read(fd, hdrp, sizeof(*hdrp));
    if (size == -1) {
	dln_errno = errno;
	return -1;
    }
    if (size != sizeof(*hdrp) || N_BADMAG(*hdrp)) {
	dln_errno = DLN_ENOEXEC;
	return -1;
    }
    return 0;
}

#if defined(sun) && defined(sparc)
/* Sparc (Sun 4) macros */
#  undef relocation_info
#  define relocation_info reloc_info_sparc
#  define R_RIGHTSHIFT(r) (reloc_r_rightshift[(r)->r_type])
#  define R_BITSIZE(r) (reloc_r_bitsize[(r)->r_type])
#  define R_LENGTH(r) (reloc_r_length[(r)->r_type])
static int reloc_r_rightshift[] = {
  0, 0, 0, 0, 0, 0, 2, 2, 10, 0, 0, 0, 0, 0, 0,
};
static int reloc_r_bitsize[] = {
  8, 16, 32, 8, 16, 32, 30, 22, 22, 22, 13, 10, 32, 32, 16,
};
static int reloc_r_length[] = {
  0, 1, 2, 0, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
};
#  define R_PCREL(r) \
    ((r)->r_type >= RELOC_DISP8 && (r)->r_type <= RELOC_WDISP22)
#  define R_SYMBOL(r) ((r)->r_index)
#else
#  define R_LENGTH(r) ((r)->r_length)
#  define R_PCREL(r)  ((r)->r_pcrel)
#  define R_SYMBOL(r) ((r)->r_symbolnum)
#endif

static struct relocation_info *
dln_load_reloc(fd, hdrp, disp)
     int fd;
     struct exec *hdrp;
     long disp;
{
    struct relocation_info * reloc;
    int size;

    lseek(fd, disp + N_TXTOFF(*hdrp) + hdrp->a_text + hdrp->a_data, 0);
  
    size = hdrp->a_trsize + hdrp->a_drsize;
    reloc = (struct relocation_info*)xmalloc(size);
    if (reloc == NULL) {
	dln_errno = errno;
	return NULL;
    }

    if (read(fd, reloc, size) !=  size) {
	dln_errno = errno;
	free(reloc);
	return NULL;
    }
  
    return reloc;
}

static struct nlist *
dln_load_sym(fd, hdrp, disp)
    int fd;
    struct exec *hdrp;
    long disp;
{
    struct nlist * buffer;
    struct nlist * sym;
    struct nlist * end;
    long displ;
    int size;
    st_table *tbl;

    lseek(fd, N_SYMOFF(*hdrp) + hdrp->a_syms + disp, 0);
    if (read(fd, &size, sizeof(int)) != sizeof(int)) {
	goto err_noexec;
    }

    buffer = (struct nlist*)xmalloc(hdrp->a_syms + size);
    if (buffer == NULL) {
	dln_errno = errno;
	return NULL;
    }

    lseek(fd, disp + N_SYMOFF(*hdrp), 0);
    if (read(fd, buffer, hdrp->a_syms + size) != hdrp->a_syms + size) {
	free(buffer);
	goto err_noexec;
    }

    sym = buffer;
    end = sym + hdrp->a_syms / sizeof(struct nlist);
    displ = (long)buffer + (long)(hdrp->a_syms);

    while (sym < end) {
	sym->n_un.n_name = (char*)sym->n_un.n_strx + displ;
	sym++;
    }
    return buffer;

  err_noexec:
    dln_errno = DLN_ENOEXEC;
    return NULL;
}

static st_table *
dln_sym_hash(hdrp, syms)
    struct exec *hdrp;
    struct nlist *syms;
{
    st_table *tbl;
    struct nlist *sym = syms;
    struct nlist *end = syms + (hdrp->a_syms / sizeof(struct nlist));

    tbl = st_init_table(strcmp, st_strhash);
    if (tbl == NULL) {
	dln_errno = errno;
	return NULL;
    }

    while (sym < end) {
	st_insert(tbl, sym->n_un.n_name, sym);
	sym++;
    }
    return tbl;
}

int
dln_init(prog)
    char *prog;
{
    char *file;
    int fd, size;
    struct exec hdr;
    struct nlist *syms;

    if (dln_init_p == 1) return;

    file = dln_find_exe(prog, NULL);
    if (file == NULL) return -1;
    if ((fd = open(file, O_RDONLY)) < 0) {
	dln_errno = errno;
	return -1;
    }

    if (dln_load_header(fd, &hdr, 0) == -1) return -1;
    syms = dln_load_sym(fd, &hdr, 0);
    if (syms == NULL) {
	close(fd);
	return -1;
    }
    sym_tbl = dln_sym_hash(&hdr, syms);
    if (sym_tbl == NULL) {	/* file may be start with #! */
	char c = '\0';
	char buf[MAXPATHLEN];
	char *p;

	free(syms);
	lseek(fd, 0L, 0);
	if (read(fd, &c, 1) == -1) {
	    dln_errno = errno;
	    return -1;
	}
	if (c != '#') goto err_noexec;
	if (read(fd, &c, 1) == -1) {
	    dln_errno = errno;
	    return -1;
	}
	if (c != '!') goto err_noexec;

	p = buf;
	/* skip forwading spaces */
	while (read(fd, &c, 1) == 1) {
	    if (c == '\n') goto err_noexec;
	    if (c != '\t' && c != ' ') {
		*p++ = c;
		break;
	    }
	}
	/* read in command name */
	while (read(fd, p, 1) == 1) {
	    if (*p == '\n' || *p == '\t' || *p == ' ') break;
	    p++;
	}
	*p = '\0';
	printf("%s\n", buf);

	return dln_init(buf);
    }
    dln_init_p = 1;
    undef_tbl = st_init_table(strcmp, st_strhash);
    close(fd);
    return 0;

  err_noexec:
    close(fd);
    dln_errno = DLN_ENOEXEC;
    return -1;
}

long
dln_load_text_data(fd, hdrp, bss, disp)
    int fd;
    struct exec *hdrp;
    int bss;
    long disp;
{
    int size;
    unsigned char* addr;

    lseek(fd, disp + N_TXTOFF(*hdrp), 0);
    size = hdrp->a_text + hdrp->a_data;

    if (bss == -1) size += hdrp->a_bss;
    else if (bss > 1) size += bss;

    addr = (unsigned char*)xmalloc(size);
    if (addr == NULL) {
	dln_errno = errno;
	return 0;
    }

    if (read(fd, addr, size) !=  size) {
	dln_errno = errno;
	free(addr);
	return 0;
    }

    if (bss == -1) {
	bzero(addr +  hdrp->a_text + hdrp->a_data, hdrp->a_bss);
    }
    else if (bss > 0) {
	bzero(addr +  hdrp->a_text + hdrp->a_data, bss );
    }

    return (long)addr;
}

static int
undef_print(key, value, arg)
    char *key;
{
    fprintf(stderr, "  %s\n", key);
    return ST_CONTINUE;
}

static
dln_undefined()
{
    fprintf(stderr, "dln: Calling undefined function\n");
    fprintf(stderr, " Undefined symbols:\n");
    st_foreach(undef_tbl, undef_print, NULL);
#ifdef RUBY
    rb_exit(1);
#else
    exit(1);
#endif
}

struct undef {
    char *name;
    struct relocation_info reloc;
    long base;
    char *addr;
    union {
	char c;
	short s;
	long l;
    } u;
};

static st_table *reloc_tbl = NULL;
static void
link_undef(name, base, reloc)
    char *name;
    long base;
    struct relocation_info *reloc;
{
    static int u_no = 0;
    struct undef *obj;
    char *addr = (char*)(reloc->r_address + base);

    obj = (struct undef*)xmalloc(sizeof(struct undef));
    obj->name = strdup(name);
    obj->reloc = *reloc;
    obj->base = base;
    switch (R_LENGTH(reloc)) {
      case 0:		/* byte */
	obj->u.c = *addr;
	break;
      case 1:		/* word */
	obj->u.s = *(short*)addr;
	break;
      case 2:		/* long */
	obj->u.l = *(long*)addr;
	break;
    }
    if (reloc_tbl == NULL) {
	reloc_tbl = st_init_table(ST_NUMCMP, ST_NUMHASH);
    }
    st_insert(reloc_tbl, u_no++, obj);
}

struct reloc_arg {
    char *name;
    long value;
};

static int
reloc_undef(no, undef, arg)
    int no;
    struct undef *undef;
    struct reloc_arg *arg;
{
    int datum;
    char *address;
#if defined(sun) && defined(sparc)
    unsigned int mask = 0;
#endif

    if (strcmp(arg->name, undef->name) != 0) return ST_CONTINUE;
    address = (char*)(undef->base + undef->reloc.r_address);
    datum = arg->value;

    if (R_PCREL(&(undef->reloc))) datum -= undef->base;
#if defined(sun) && defined(sparc)
    datum += undef->reloc.r_addend;
    datum >>= R_RIGHTSHIFT(&(undef->reloc));
    mask = 1 << R_BITSIZE(&(undef->reloc)) - 1;
    mask |= mask -1;
    datum &= mask;
    switch (R_LENGTH(&(undef->reloc))) {
      case 0:
	*address = undef->u.c;
	*address &= ~mask;
	*address |= datum;
	break;
      case 1:
	*(short *)address = undef->u.s;
	*(short *)address &= ~mask;
	*(short *)address |= datum;
	break;
      case 2:
	*(long *)address = undef->u.l;
	*(long *)address &= ~mask;
	*(long *)address |= datum;
	break;
    }
#else
    switch (R_LENGTH(&(undef->reloc))) {
      case 0:		/* byte */
	*address = undef->u.c + datum;
	break;
      case 1:		/* word */
	*(short *)address = undef->u.s + datum;
	break;
      case 2:		/* long */
	*(long *)address = undef->u.l + datum;
	break;
    }
#endif
    free(undef->name);
    free(undef);
    return ST_DELETE;
}

static int
unlink_undef(name, value)
    char *name;
    long value;
{
    struct reloc_arg arg;

    arg.name = name;
    arg.value = value;
    st_foreach(reloc_tbl, reloc_undef, &arg);
}

static int dln_load_1(fd, disp, need_init)
    int fd;
    long disp;
    int need_init;
{
    static char *libc = LIBC_NAME;
    struct exec hdr;
    struct relocation_info *reloc = NULL;
    long block = 0;
    long new_common = 0; /* Length of new common */
    struct nlist *syms = NULL;
    struct nlist *sym;
    struct nlist *end;
    int init_p = 0;

    if (dln_load_header(fd, &hdr, disp) == -1) return -1;
    if (INVALID_OBJECT(hdr)) {
	dln_errno = DLN_ENOEXEC;
	return -1;
    }
    reloc = dln_load_reloc(fd, &hdr, disp);
    if (reloc == NULL) return -1;
    syms = dln_load_sym(fd, &hdr, disp);
    if (syms == NULL) return -1;

    sym = syms;
    end = syms + (hdr.a_syms / sizeof(struct nlist));
    while (sym < end) {
	struct nlist *old_sym;
	int value = sym->n_value;

	if (sym->n_type == (N_UNDF | N_EXT)) {
	    if (st_lookup(sym_tbl, sym->n_un.n_name, &old_sym) == 0) {
		old_sym = NULL;
	    }

	    if (value) {
		if (old_sym) {
		    sym->n_type = N_EXT | N_COMM;
		    sym->n_value = old_sym->n_value;
		}
		else {
		    int rnd =
			value >= sizeof(double) ? sizeof(double) - 1
			    : value >= sizeof(long) ? sizeof(long) - 1
				: sizeof(short) - 1;

		    sym->n_type = N_COMM;
		    new_common += rnd;
		    new_common &= ~(long)rnd;
		    sym->n_value = new_common;
		    new_common += value;
		}
	    }
	    else {
		if (old_sym) {
		    sym->n_type = N_EXT | N_COMM;
		    sym->n_value = old_sym->n_value;
		}
		else {
		    sym->n_value = (long)dln_undefined;
		    st_insert(undef_tbl, strdup(sym->n_un.n_name), NULL);
		}
	    }
	}
	sym++;
    }

    block = dln_load_text_data(fd, &hdr, hdr.a_bss + new_common, disp);
    if (block == 0) goto err_exit;

    sym = syms;
    while (sym < end) {
	struct nlist *new_sym;
	char *key;

	switch (sym->n_type) {
	  case N_COMM:
	    sym->n_value += hdr.a_text + hdr.a_data;
	  case N_TEXT|N_EXT:
	  case N_DATA|N_EXT:
	    sym->n_value += block;

	    if (st_lookup(sym_tbl, sym->n_un.n_name, &new_sym) != 0
		&& new_sym->n_value != (long)dln_undefined) {
		dln_errno = DLN_ECONFL;
		goto err_exit;
	    }

	    key = sym->n_un.n_name;
	    if (st_delete(undef_tbl, &key, NULL) != 0) {
		unlink_undef(key, sym->n_value);
		free(key);
	    }

	    new_sym = (struct nlist*)xmalloc(sizeof(struct nlist));
	    *new_sym = *sym;
	    new_sym->n_un.n_name = strdup(sym->n_un.n_name);
	    st_insert(sym_tbl, new_sym->n_un.n_name, new_sym);
	}
	sym++;
    }

    /*
     * First comes the text-relocation
     */
    {
	struct relocation_info * rel = reloc;
	struct relocation_info * rel_beg = reloc + 
	    (hdr.a_trsize/sizeof(struct relocation_info));
	struct relocation_info * rel_end = reloc +
	    (hdr.a_trsize+hdr.a_drsize)/sizeof(struct relocation_info);

	while (rel < rel_end) {
	    char *address = (char*)(rel->r_address + block);
	    long datum = 0;
#if defined(sun) && defined(sparc)
	    unsigned int mask = 0;
#endif

	    if(rel >= rel_beg)
		address += hdr.a_text;

	    if (rel->r_extern) { /* Look it up in symbol-table */
		sym = &(syms[R_SYMBOL(rel)]);
		switch (sym->n_type) {
		  case N_EXT|N_UNDF:
		    link_undef(sym->n_un.n_name, block, rel);
		  case N_EXT|N_COMM:
		  case N_COMM:
		    datum = sym->n_value;
		    break;
		  default:
		    goto err_exit;
		}
	    } /* end.. look it up */
	    else { /* is static */
		switch (R_SYMBOL(rel) & N_TYPE) {
		  case N_TEXT:
		  case N_DATA:
		    datum = block;
		    break;
		  case N_BSS:
		    datum = block +  new_common;
		    break;
		  case N_ABS:
		    break;
		}
	    } /* end .. is static */
	    if (R_PCREL(rel)) datum -= block;

#if defined(sun) && defined(sparc)
	    datum += rel->r_addend;
	    datum >>= R_RIGHTSHIFT(rel);
	    mask = 1 << R_BITSIZE(rel) - 1;
	    mask |= mask -1;
	    datum &= mask;

	    switch (R_LENGTH(rel)) {
	      case 0:
		*address &= ~mask;
		*address |= datum;
		break;
	      case 1:
		*(short *)address &= ~mask;
		*(short *)address |= datum;
		break;
	      case 2:
		*(long *)address &= ~mask;
		*(long *)address |= datum;
		break;
	    }
#else
	    switch (R_LENGTH(rel)) {
	      case 0:		/* byte */
		if (datum < -128 || datum > 127) goto err_exit;
		*address += datum;
		break;
	      case 1:		/* word */
		*(short *)address += datum;
		break;
	      case 2:		/* long */
		*(long *)address += datum;
		break;
	    }
#endif
	    rel++;
	}
    }

    if (need_init) {
	if (undef_tbl->num_entries > 0) {
	    if (dln_load_lib(libc) == -1) goto err_exit;
	}

	sym = syms;
	while (sym < end) {
	    char *name = sym->n_un.n_name;
	    if (name[0] == '_' && sym->n_value >= block
		&& ((bcmp (name, "_Init_", 6) == 0 
		     || bcmp (name, "_init_", 6) == 0) && name[6] != '_')) {
		init_p = 1;
		((int (*)())sym->n_value)();
	    }
	    sym++;
	}
    }
    free(reloc);
    free(syms);
    if (need_init) {
	if (init_p == 0) {
	    dln_errno = DLN_ENOINIT;
	    return -1;
	}
	if (undef_tbl->num_entries > 0) {
	    if (dln_load_lib(libc) == -1) goto err_exit;
	    if (undef_tbl->num_entries > 0) {
		dln_errno = DLN_EUNDEF;
		return -1;
	    }
	}
    }
    return 0;

  err_exit:
    if (syms) free(syms);
    if (reloc) free(reloc);
    if (block) free(block);
    return -1;
}

int
dln_load(file)
    char *file;
{
    int fd;
    int result;

    if (dln_init_p == 0) {
	dln_errno = DLN_ENOINIT;
	return -1;
    }

    fd = open(file, O_RDONLY);
    if (fd == -1) {
	dln_errno = errno;
	return -1;
    }
    result = dln_load_1(fd, 0, 1);
    close(fd);

    return result;
}

struct symdef {
    int str_index;
    int lib_offset;
};

static int target_offset;
static int
search_undef(key, value, lib_tbl)
    char *key;
    int value;
    st_table *lib_tbl;
{
    static char *last = "";
    int offset;

    if (st_lookup(lib_tbl, key, &offset) == 0) return ST_CONTINUE;
    if (strcmp(last, key) != 0) {
	last = key;
	target_offset = offset;
    }
    return ST_STOP;
}

char *dln_library_path = DLN_DEFAULT_PATH;

int
dln_load_lib(lib)
    char *lib;
{
    char *path, *file;
    char armagic[SARMAG];
    int fd, size;
    struct ar_hdr ahdr;
    st_table *lib_tbl = NULL;
    int *data, nsym;
    struct symdef *base;
    char *name_base;

    if (dln_init_p == 0) {
	dln_errno = DLN_ENOINIT;
	return -1;
    }

    if (undef_tbl->num_entries == 0) return 0;
    dln_errno = DLN_EBADLIB;

    /* library search path: */
    /* look for environment variable DLN_LIBRARY_PATH first. */
    /* then variable dln_library_path. */
    /* if path is still NULL, use "." for path. */
    path = getenv("DLN_LIBRARY_PATH");
    if (path == NULL) path = dln_library_path;

    file = dln_find_file(lib, path);
    fd = open(file, O_RDONLY);
    if (fd == -1) goto syserr;
    size = read(fd, armagic, SARMAG);
    if (fd == -1) goto syserr;

    if (size != SARMAG) {
	dln_errno = DLN_ENOTLIB;
	goto badlib;
    }
    size = read(fd, &ahdr, sizeof(ahdr));
    if (size == -1) goto syserr;
    if (size != sizeof(ahdr) || sscanf(ahdr.ar_size, "%d", &size) != 1) {
	goto badlib;
    }

    if (strncmp(ahdr.ar_name, "__.SYMDEF", 9) == 0 && ahdr.ar_name[9] == ' ') {
	/* make hash table from __.SYMDEF */

	lib_tbl = st_init_table(strcmp, st_strhash);
	data = (int*)xmalloc(size);
	if (data == NULL) goto syserr;
	size = read(fd, data, size);
	nsym = *data / sizeof(struct symdef);
	base = (struct symdef*)(data + 1);
	name_base = (char*)(base + nsym) + sizeof(int);
	while (nsym > 0) {
	    char *name = name_base + base->str_index;

	    st_insert(lib_tbl, name, base->lib_offset + sizeof(ahdr));
	    nsym--;
	    base++;
	}
	for (;;) {
	    target_offset = -1;
	    st_foreach(undef_tbl, search_undef, lib_tbl);
	    if (target_offset == -1) break;
	    if (dln_load_1(fd, target_offset, 0) == -1) {
		st_free_table(lib_tbl);
		free(data);
		goto badlib;
	    }
	    if (undef_tbl->num_entries == 0) break;
	}
	free(data);
	st_free_table(lib_tbl);
    }
    else {
	/* linear library, need to scan (FUTURE) */

	for (;;) {
	    int offset = SARMAG;
	    int found = 0;
	    struct exec hdr;
	    struct nlist *syms, *sym, *end;

	    while (undef_tbl->num_entries > 0) {
		found = 0;
		lseek(fd, offset, 0);
		size = read(fd, &ahdr, sizeof(ahdr));
		if (size == -1) goto syserr;
		if (size == 0) break;
		if (size != sizeof(ahdr)
		    || sscanf(ahdr.ar_size, "%d", &size) != 1) {
		    goto badlib;
		}
		offset += sizeof(ahdr);
		if (dln_load_header(fd, &hdr, offset) == -1)
		    goto badlib;
		syms = dln_load_sym(fd, &hdr, offset);
		if (syms == NULL) goto badlib;
		sym = syms;
		end = syms + (hdr.a_syms / sizeof(struct nlist));
		while (sym < end) {
		    if (sym->n_type == N_EXT|N_TEXT
			&& st_lookup(undef_tbl, sym->n_un.n_name, NULL)) {
			break;
		    }
		    sym++;
		}
		if (sym < end) {
		    found++;
		    free(syms);
		    if (dln_load_1(fd, offset, 0) == -1) {
			goto badlib;
		    }
		}
		offset += size;
		if (offset & 1) offset++;
	    }
	    if (found) break;
	}
    }
    close(fd);
    return 0;

  syserr:
    dln_errno = errno;
  badlib:
    if (fd >= 0) close(fd);
    return -1;
}

char *
dln_strerror()
{
    char *strerror();

    switch (dln_errno) {
      case DLN_ECONFL:
	return "Symbol name conflict";
      case DLN_ENOINIT:
	return "No inititalizer given";
      case DLN_EUNDEF:
	return "Unresolved symbols";
      case DLN_ENOTLIB:
	return "Not a library file";
      case DLN_EBADLIB:
	return "Malformed library file";
      case DLN_EINIT:
	return "Not initialized";
      default:
	return strerror(dln_errno);
    }
}

dln_perror(str)
    char *str;
{
    fprintf(stderr, "%s: %s\n", str, dln_strerror());
}

void*
dln_get_sym(name)
    char *name;
{
    struct nlist *sym;

    if (st_lookup(sym_tbl, name, &sym))
	return (void*)sym->n_value;
    return NULL;
}

#ifdef TEST
xmalloc(size)
    int size;
{
    return malloc(size);
}

xcalloc(size, n)
    int size, n;
{
    return calloc(size, n);
}

main(argc, argv)
    int argc;
    char **argv;
{
    if (dln_init(argv[0]) == -1) {
	dln_perror("dln_init");
	exit(1);
    }

    while (argc > 1) {
	printf("obj: %s\n", argv[1]);
	if (dln_load(argv[1]) == -1) {
	    dln_perror("dln_load");
	    exit(1);
	}
	argc--;
	argv++;
    }
    if (dln_load_lib("libdln.a") == -1) {
	dln_perror("dln_init");
	exit(1);
    }

    if (dln_get_sym("_foo"))
	printf("_foo defined\n");
    else
	printf("_foo undefined\n");
}
#endif				/* TEST */

#else				/* USE_DLN */

int
dln_init(file)
    char *file;
{
    return 0;
}

int
dln_load(file)
    char *file;
{
    return 0;
}

int
dln_load_lib(file)
    char *file;
{
    return 0;
}

#endif				/* USE_DLN */
