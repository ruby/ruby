/************************************************

  dln.c -

  $Author$
  $Date$
  created at: Tue Jan 18 17:05:06 JST 1994

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#include "config.h"
#include "defines.h"
#include "dln.h"

char *dln_argv0;

#ifdef _AIX
#pragma alloca
#endif

#if defined(HAVE_ALLOCA_H) && !defined(__GNUC__)
#include <alloca.h>
#endif

#ifdef HAVE_STRING_H
# include <string.h>
#else
# include <strings.h>
#endif

void *xmalloc();
void *xcalloc();
void *xrealloc();

#include <stdio.h>
#ifndef NT
# ifndef USE_CWGUSI
#  include <sys/file.h>
# endif
#else
#include "missing/file.h"
#endif
#include <sys/types.h>
#include <sys/stat.h>

#ifdef HAVE_SYS_PARAM_H
# include <sys/param.h>
#else
# define MAXPATHLEN 1024
#endif

#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif

#ifndef NT
char *strdup();
char *getenv();
#endif

#ifdef __MACOS__
# include <TextUtils.h>
# include <CodeFragments.h>
# include <Aliases.h>
#endif

#ifdef __BEOS__
# include <image.h>
#endif

int eaccess();

#if defined(HAVE_DLOPEN) && !defined(USE_DLN_A_OUT) && !defined(__CYGWIN32__)
/* dynamic load with dlopen() */
# define USE_DLN_DLOPEN
#endif

#ifndef FUNCNAME_PATTERN
# if defined(__hp9000s300) || defined(__NetBSD__) || defined(__BORLANDC__) || defined(__FreeBSD__) || defined(NeXT) || defined(__WATCOMC__)
#  define FUNCNAME_PATTERN "_Init_%.200s"
# else
#  define FUNCNAME_PATTERN "Init_%.200s"
# endif
#endif

static void
init_funcname(buf, file)
    char *buf, *file;
{
    char *p, *slash;

    /* Load the file as an object one */
    for (p = file, slash = p-1; *p; p++) /* Find position of last '/' */
#ifdef __MACOS__
	if (*p == ':') slash = p;
#else
	if (*p == '/') slash = p;
#endif

    sprintf(buf, FUNCNAME_PATTERN, slash + 1);
    for (p = buf; *p; p++) {         /* Delete suffix it it exists */
	if (*p == '.') {
	    *p = '\0'; break;
	}
    }
}

#ifdef USE_DLN_A_OUT

#ifndef LIBC_NAME
# define LIBC_NAME "libc.a"
#endif

#ifndef DLN_DEFAULT_LIB_PATH
#  define DLN_DEFAULT_LIB_PATH "/lib:/usr/lib:/usr/local/lib:."
#endif

#include <errno.h>

static int dln_errno;

#define DLN_ENOEXEC	ENOEXEC	/* Exec format error */
#define DLN_ECONFL	201	/* Symbol name conflict */
#define DLN_ENOINIT	202	/* No inititalizer given */
#define DLN_EUNDEF	203	/* Undefine symbol remains */
#define DLN_ENOTLIB	204	/* Not a library file */
#define DLN_EBADLIB	205	/* Malformed library file */
#define DLN_EINIT	206	/* Not initialized */

static int dln_init_p = 0;

#include "st.h"
#include <ar.h>
#include <a.out.h>
#ifndef N_COMM
# define N_COMM 0x12
#endif
#ifndef N_MAGIC
# define N_MAGIC(x) (x).a_magic
#endif

#define INVALID_OBJECT(h) (N_MAGIC(h) != OMAGIC)

static st_table *sym_tbl;
static st_table *undef_tbl;

static int load_lib();

static int
load_header(fd, hdrp, disp)
    int fd;
    struct exec *hdrp;
    long disp;
{
    int size;

    lseek(fd, disp, 0);
    size = read(fd, hdrp, sizeof(struct exec));
    if (size == -1) {
	dln_errno = errno;
	return -1;
    }
    if (size != sizeof(struct exec) || N_BADMAG(*hdrp)) {
	dln_errno = DLN_ENOEXEC;
	return -1;
    }
    return 0;
}

#if defined(sequent)
#define RELOC_SYMBOL(r)			((r)->r_symbolnum)
#define RELOC_MEMORY_SUB_P(r)		((r)->r_bsr)
#define RELOC_PCREL_P(r)		((r)->r_pcrel || (r)->r_bsr)
#define RELOC_TARGET_SIZE(r)		((r)->r_length)
#endif

/* Default macros */
#ifndef RELOC_ADDRESS
#define RELOC_ADDRESS(r)		((r)->r_address)
#define RELOC_EXTERN_P(r)		((r)->r_extern)
#define RELOC_SYMBOL(r)			((r)->r_symbolnum)
#define RELOC_MEMORY_SUB_P(r)		0
#define RELOC_PCREL_P(r)		((r)->r_pcrel)
#define RELOC_TARGET_SIZE(r)		((r)->r_length)
#endif

#if defined(sun) && defined(sparc)
/* Sparc (Sun 4) macros */
#  undef relocation_info
#  define relocation_info reloc_info_sparc
#  define R_RIGHTSHIFT(r)	(reloc_r_rightshift[(r)->r_type])
#  define R_BITSIZE(r) 		(reloc_r_bitsize[(r)->r_type])
#  define R_LENGTH(r)		(reloc_r_length[(r)->r_type])
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
#endif

#if defined(sequent)
#define R_SYMBOL(r)		((r)->r_symbolnum)
#define R_MEMORY_SUB(r)		((r)->r_bsr)
#define R_PCREL(r)		((r)->r_pcrel || (r)->r_bsr)
#define R_LENGTH(r)		((r)->r_length)
#endif

#ifndef R_SYMBOL
#  define R_SYMBOL(r) 		((r)->r_symbolnum)
#  define R_MEMORY_SUB(r)	0
#  define R_PCREL(r)  		((r)->r_pcrel)
#  define R_LENGTH(r) 		((r)->r_length)
#endif

static struct relocation_info *
load_reloc(fd, hdrp, disp)
     int fd;
     struct exec *hdrp;
     long disp;
{
    struct relocation_info *reloc;
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
load_sym(fd, hdrp, disp)
    int fd;
    struct exec *hdrp;
    long disp;
{
    struct nlist * buffer;
    struct nlist * sym;
    struct nlist * end;
    long displ;
    int size;

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
sym_hash(hdrp, syms)
    struct exec *hdrp;
    struct nlist *syms;
{
    st_table *tbl;
    struct nlist *sym = syms;
    struct nlist *end = syms + (hdrp->a_syms / sizeof(struct nlist));

    tbl = st_init_strtable();
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

static int
dln_init(prog)
    char *prog;
{
    char *file;
    int fd;
    struct exec hdr;
    struct nlist *syms;

    if (dln_init_p == 1) return 0;

    file = dln_find_exe(prog, NULL);
    if (file == NULL || (fd = open(file, O_RDONLY)) < 0) {
	dln_errno = errno;
	return -1;
    }

    if (load_header(fd, &hdr, 0) == -1) return -1;
    syms = load_sym(fd, &hdr, 0);
    if (syms == NULL) {
	close(fd);
	return -1;
    }
    sym_tbl = sym_hash(&hdr, syms);
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

	return dln_init(buf);
    }
    dln_init_p = 1;
    undef_tbl = st_init_strtable();
    close(fd);
    return 0;

  err_noexec:
    close(fd);
    dln_errno = DLN_ENOEXEC;
    return -1;
}

static long
load_text_data(fd, hdrp, bss, disp)
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
	memset(addr +  hdrp->a_text + hdrp->a_data, 0, hdrp->a_bss);
    }
    else if (bss > 0) {
	memset(addr +  hdrp->a_text + hdrp->a_data, 0, bss);
    }

    return (long)addr;
}

static int
undef_print(key, value)
    char *key, *value;
{
    fprintf(stderr, "  %s\n", key);
    return ST_CONTINUE;
}

static void
dln_print_undef()
{
    fprintf(stderr, " Undefined symbols:\n");
    st_foreach(undef_tbl, undef_print, NULL);
}

static void
dln_undefined()
{
    if (undef_tbl->num_entries > 0) {
	fprintf(stderr, "dln: Calling undefined function\n");
	dln_print_undef();
	rb_exit(1);
    }
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
	reloc_tbl = st_init_numtable();
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
    mask = (1 << R_BITSIZE(&(undef->reloc))) - 1;
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
	if (R_MEMORY_SUB(&(undef->reloc)))
	    *address = datum - *address;
	else *address = undef->u.c + datum;
	break;
      case 1:		/* word */
	if (R_MEMORY_SUB(&(undef->reloc)))
	    *(short*)address = datum - *(short*)address;
	else *(short*)address = undef->u.s + datum;
	break;
      case 2:		/* long */
	if (R_MEMORY_SUB(&(undef->reloc)))
	    *(long*)address = datum - *(long*)address;
	else *(long*)address = undef->u.l + datum;
	break;
    }
#endif
    free(undef->name);
    free(undef);
    return ST_DELETE;
}

static void
unlink_undef(name, value)
    char *name;
    long value;
{
    struct reloc_arg arg;

    arg.name = name;
    arg.value = value;
    st_foreach(reloc_tbl, reloc_undef, &arg);
}

#ifdef N_INDR
struct indr_data {
    char *name0, *name1;
};

static int
reloc_repl(no, undef, data)
    int no;
    struct undef *undef;
    struct indr_data *data;
{
    if (strcmp(data->name0, undef->name) == 0) {
	free(undef->name);
	undef->name = strdup(data->name1);
    }
    return ST_CONTINUE;
}
#endif

static int
load_1(fd, disp, need_init)
    int fd;
    long disp;
    char *need_init;
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
    char buf[256];

    if (load_header(fd, &hdr, disp) == -1) return -1;
    if (INVALID_OBJECT(hdr)) {
	dln_errno = DLN_ENOEXEC;
	return -1;
    }
    reloc = load_reloc(fd, &hdr, disp);
    if (reloc == NULL) return -1;
    syms = load_sym(fd, &hdr, disp);
    if (syms == NULL) return -1;

    sym = syms;
    end = syms + (hdr.a_syms / sizeof(struct nlist));
    while (sym < end) {
	struct nlist *old_sym;
	int value = sym->n_value;

#ifdef N_INDR
	if (sym->n_type == (N_INDR | N_EXT)) {
	    char *key = sym->n_un.n_name;

	    if (st_lookup(sym_tbl, sym[1].n_un.n_name, &old_sym)) {
		if (st_delete(undef_tbl, &key, NULL)) {
		    unlink_undef(key, old_sym->n_value);
		    free(key);
		}
	    }
	    else {
		struct indr_data data;

		data.name0 = sym->n_un.n_name;
		data.name1 = sym[1].n_un.n_name;
		st_foreach(reloc_tbl, reloc_repl, &data);

		st_insert(undef_tbl, strdup(sym[1].n_un.n_name), NULL);
		if (st_delete(undef_tbl, &key, NULL)) {
		    free(key);
		}
	    }
	    sym += 2;
	    continue;
	}
#endif
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

    block = load_text_data(fd, &hdr, hdr.a_bss + new_common, disp);
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
	    break;

	  case N_TEXT:
	  case N_DATA:
	    sym->n_value += block;
	    break;
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
		switch (R_SYMBOL(rel)) { 
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
	    mask = (1 << R_BITSIZE(rel)) - 1;
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
	int len;
	char **libs_to_be_linked = 0;

	if (undef_tbl->num_entries > 0) {
	    if (load_lib(libc) == -1) goto err_exit;
	}

	init_funcname(buf, need_init);
	len = strlen(buf);

	for (sym = syms; sym<end; sym++) {
	    char *name = sym->n_un.n_name;
	    if (name[0] == '_' && sym->n_value >= block) {
		if (strcmp(name+1, "libs_to_be_linked") == 0) {
		    libs_to_be_linked = (char**)sym->n_value;
		}
		else if (strcmp(name+1, buf) == 0) {
		    init_p = 1;
		    ((int (*)())sym->n_value)();
		}
	    }
	}
	if (libs_to_be_linked && undef_tbl->num_entries > 0) {
	    while (*libs_to_be_linked) {
		load_lib(*libs_to_be_linked);
		libs_to_be_linked++;
	    }
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
	    if (load_lib(libc) == -1) goto err_exit;
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
    if (block) free((char*)block);
    return -1;
}

static int target_offset;
static int
search_undef(key, value, lib_tbl)
    char *key;
    int value;
    st_table *lib_tbl;
{
    int offset;

    if (st_lookup(lib_tbl, key, &offset) == 0) return ST_CONTINUE;
    target_offset = offset;
    return ST_STOP;
}

struct symdef {
    int str_index;
    int lib_offset;
};

char *dln_library_path = DLN_DEFAULT_LIB_PATH;

static int
load_lib(lib)
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

    if (lib[0] == '-' && lib[1] == 'l') {
	char *p = alloca(strlen(lib) + 4);
	sprintf(p, "lib%s.a", lib+2);
	lib = p;
    }

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
    if (size == -1) goto syserr;

    if (size != SARMAG) {
	dln_errno = DLN_ENOTLIB;
	goto badlib;
    }
    size = read(fd, &ahdr, sizeof(ahdr));
    if (size == -1) goto syserr;
    if (size != sizeof(ahdr) || sscanf(ahdr.ar_size, "%d", &size) != 1) {
	goto badlib;
    }

    if (strncmp(ahdr.ar_name, "__.SYMDEF", 9) == 0) {
	/* make hash table from __.SYMDEF */

	lib_tbl = st_init_strtable();
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
	    if (load_1(fd, target_offset, 0) == -1) {
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
		if (load_header(fd, &hdr, offset) == -1)
		    goto badlib;
		syms = load_sym(fd, &hdr, offset);
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
		    if (load_1(fd, offset, 0) == -1) {
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

static int
load(file)
    char *file;
{
    int fd;
    int result;

    if (dln_init_p == 0) {
	if (dln_init(dln_argv0) == -1) return -1;
    }
    result = strlen(file);
    if (file[result-1] == 'a') {
	return load_lib(file);
    }

    fd = open(file, O_RDONLY);
    if (fd == -1) {
	dln_errno = errno;
	return -1;
    }
    result = load_1(fd, 0, file);
    close(fd);

    return result;
}

void*
dln_sym(name)
    char *name;
{
    struct nlist *sym;

    if (st_lookup(sym_tbl, name, &sym))
	return (void*)sym->n_value;
    return NULL;
}

#endif /* USE_DLN_A_OUT */

#ifdef USE_DLN_DLOPEN
# ifdef __NetBSD__
#  include <nlist.h>
#  include <link.h>
# else
#  include <dlfcn.h>
# endif
#endif

#ifdef hpux
#include <errno.h>
#include "dl.h"
#endif

#ifdef _AIX
#include <ctype.h>	/* for isdigit()	*/
#include <errno.h>	/* for global errno	*/
#include <sys/ldr.h>
#endif

#ifdef NeXT
#if NS_TARGET_MAJOR < 4
#include <mach-o/rld.h>
#else
#include <mach-o/dyld.h>
#endif
#endif

#ifdef _WIN32
#include <windows.h>
#endif

static char *
dln_strerror()
{
#ifdef USE_DLN_A_OUT
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
#endif

#ifdef USE_DLN_DLOPEN
    return (char*)dlerror();
#endif

#ifdef _WIN32
    static char message[1024];
    FormatMessage(
	FORMAT_MESSAGE_FROM_SYSTEM,
	NULL,
	GetLastError(),
	MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US),
	message,
	sizeof message,
	NULL);

    return message;
#endif
}


#ifdef _AIX
static void
aix_loaderror(char *pathname)
{
    char *message[8], errbuf[1024];
    int i,j;

    struct errtab { 
	int errno;
	char *errstr;
    } load_errtab[] = {
	{L_ERROR_TOOMANY,	"too many errors, rest skipped."},
	{L_ERROR_NOLIB,		"can't load library:"},
	{L_ERROR_UNDEF,		"can't find symbol in library:"},
	{L_ERROR_RLDBAD,
	     "RLD index out of range or bad relocation type:"},
	{L_ERROR_FORMAT,	"not a valid, executable xcoff file:"},
	{L_ERROR_MEMBER,
	     "file not an archive or does not contain requested member:"},
	{L_ERROR_TYPE,		"symbol table mismatch:"},
	{L_ERROR_ALIGN,		"text allignment in file is wrong."},
	{L_ERROR_SYSTEM,	"System error:"},
	{L_ERROR_ERRNO,		NULL}
    };

#define LOAD_ERRTAB_LEN	(sizeof(load_errtab)/sizeof(load_errtab[0]))
#define ERRBUF_APPEND(s) strncat(errbuf, s, sizeof(errbuf)-strlen(errbuf)-1)

    sprintf(errbuf, "load failed - %.200s ", pathname);

    if (!loadquery(1, &message[0], sizeof(message))) 
	ERRBUF_APPEND(strerror(errno));
    for(i = 0; message[i] && *message[i]; i++) {
	int nerr = atoi(message[i]);
	for (j=0; j<LOAD_ERRTAB_LEN ; j++) {
	    if (nerr == load_errtab[i].errno && load_errtab[i].errstr)
		ERRBUF_APPEND(load_errtab[i].errstr);
	}
	while (isdigit(*message[i])) message[i]++ ; 
	ERRBUF_APPEND(message[i]);
	ERRBUF_APPEND("\n");
    }
    errbuf[strlen(errbuf)-1] = '\0';	/* trim off last newline */
    LoadError(errbuf);
    return;
}
#endif

void
dln_load(file)
    char *file;
{
#ifdef _WIN32
    HINSTANCE handle;
    char winfile[255];
    void (*init_fct)();
    char buf[MAXPATHLEN];

    /* Load the file as an object one */
    init_funcname(buf, file);

#ifdef __CYGWIN32__
    cygwin32_conv_to_win32_path(file, winfile);
#else
    strcpy(winfile, file);
#endif

    /* Load file */
    if ((handle =
	LoadLibraryExA(winfile, NULL, LOAD_WITH_ALTERED_SEARCH_PATH)) == NULL) {
        printf("LoadLibraryExA\n");
	goto failed;
    }

#ifdef __CYGWIN32__
    init_fct = (void(*)())GetProcAddress(handle, "impure_setup");

    if (init_fct)
	init_fct(_impure_ptr);
#endif

    if ((init_fct = (void(*)())GetProcAddress(handle, buf)) == NULL) {
        printf("GetProcAddress %s\n", buf);
	goto failed;
    }
    /* Call the init code */
    (*init_fct)();
    return;
#else
#ifdef USE_DLN_A_OUT
    if (load(file) == -1) {
	goto failed;
    }
    return;
#else

    char buf[MAXPATHLEN];
    /* Load the file as an object one */
    init_funcname(buf, file);

#ifdef USE_DLN_DLOPEN
#define DLN_DEFINED
    {
	void *handle;
	void (*init_fct)();

# ifndef RTLD_LAZY
#  define RTLD_LAZY 1
# endif
# ifndef RTLD_GLOBAL
#  define RTLD_GLOBAL 0
# endif

	/* Load file */
	if ((handle = dlopen(file, RTLD_LAZY|RTLD_GLOBAL)) == NULL) {
	    goto failed;
	}

	if ((init_fct = (void(*)())dlsym(handle, buf)) == NULL) {
	    goto failed;
	}
	/* Call the init code */
	(*init_fct)();
	return;
    }
#endif /* USE_DLN_DLOPEN */

#ifdef hpux
#define DLN_DEFINED
    {
	shl_t lib = NULL;
	int flags;
	void (*init_fct)();

	flags = BIND_DEFERRED;
	lib = shl_load(file, flags, 0);
	if (lib == NULL) {
	    extern int errno;
	    LoadError("%s - %s", strerror(errno), file);
	}
	shl_findsym(&lib, buf, TYPE_PROCEDURE, (void*)&init_fct);
	if (init_fct == NULL) {
	    shl_findsym(&lib, buf, TYPE_UNDEFINED, (void*)&init_fct);
	    if (init_fct == NULL) {
		errno = ENOSYM;
		LoadError("%s - %s", strerror(ENOSYM), file);
	    }
	}
	(*init_fct)();
	return;
    }
#endif /* hpux */

#ifdef _AIX
#define DLN_DEFINED
    {
	void (*init_fct)();

	init_fct = (void(*)())load(file, 1, 0);
	if (init_fct == NULL) {
	    aix_loaderror(file);
	}
	(*init_fct)();
	return;
    }
#endif /* _AIX */

#ifdef NeXT
#define DLN_DEFINED
/*----------------------------------------------------
   By SHIROYAMA Takayuki Psi@fortune.nest.or.jp
 
   Special Thanks...
    Yu tomoak-i@is.aist-nara.ac.jp,
    Mi hisho@tasihara.nest.or.jp,
    and... Miss ARAI Akino(^^;)
 ----------------------------------------------------*/
#if NS_TARGET_MAJOR < 4 /* NeXTSTEP rld functions */
    {
	unsigned long init_address;
	char *object_files[2] = {NULL, NULL};

	void (*init_fct)();
	
	object_files[0] = file;
	
	/* Load object file, if return value ==0 ,  load failed*/
	if(rld_load(NULL, NULL, object_files, NULL) == 0) {
	    LoadError("Failed to load %.200s", file);
	}

	/* lookup the initial function */
	if(rld_lookup(NULL, buf, &init_address) == 0) {
	    LoadError("Failed to lookup Init function %.200s",file);
	}

	 /* Cannot call *init_address directory, so copy this value to
	    funtion pointer */

	init_fct = (void(*)())init_address;
	(*init_fct)();
	return ;
    }
#else/* OPENSTEP dyld functions */
	{
	int dyld_result ;
	NSObjectFileImage obj_file ; /* handle, but not use it */
	/* "file" is module file name .
	   "buf" is initial function name with "_" . */

	void (*init_fct)();


    dyld_result = NSCreateObjectFileImageFromFile( file, &obj_file );

    if (dyld_result != NSObjectFileImageSuccess)
    {
	    LoadError("Failed to load %.200s", file);
    }

    NSLinkModule(obj_file, file, TRUE);


	/* lookup the initial function */
	 /*NSIsSymbolNameDefined require function name without "_" */
    if( NSIsSymbolNameDefined( buf + 1 ) )
    {
	    LoadError("Failed to lookup Init function %.200s",file);
	}

	/* NSLookupAndBindSymbol require function name with "_" !! */

	init_fct = NSAddressOfSymbol( NSLookupAndBindSymbol( buf ) );
	(*init_fct)();


	return ;
    }
#endif /* rld or dyld */
#endif

#ifdef __BEOS__
# define DLN_DEFINED
    {
      status_t err_stat;  /* BeOS error status code */
      image_id img_id;    /* extention module unique id */
      void (*init_fct)(); /* initialize function for extention module */

      /* load extention module */
      img_id = load_add_on(file);
      if (img_id <= 0) {
	LoadError("Failed to load %.200s", file);
      }
      
      /* find symbol for module initialize function. */
	  /* The Be Book KernelKit Images section described to use
		 B_SYMBOL_TYPE_TEXT for symbol of function, not
		 B_SYMBOL_TYPE_CODE. Why ? */
	  /* strcat(init_fct_symname, "__Fv"); */  /* parameter nothing. */
	  /* "__Fv" dont need! The Be Book Bug ? */
      err_stat = get_image_symbol(img_id, buf,
				  B_SYMBOL_TYPE_TEXT, &init_fct);

      if (err_stat != B_NO_ERROR) {
	    char real_name[1024];
	    strcpy(real_name, buf);
	    strcat(real_name, "__Fv");
        err_stat = get_image_symbol(img_id, real_name,
				  B_SYMBOL_TYPE_TEXT, &init_fct);
      }

      if ((B_BAD_IMAGE_ID == err_stat) || (B_BAD_INDEX == err_stat)) {
	unload_add_on(img_id);
	LoadError("Failed to lookup Init function %.200s", file);
      }
      else if (B_NO_ERROR != err_stat) {
	char errmsg[] = "Internal of BeOS version. %.200s (symbol_name = %s)";
	unload_add_on(img_id);
	LoadError(errmsg, strerror(err_stat), buf);
      }

      /* call module initialize function. */
      (*init_fct)();
      return;
    }
#endif /* __BEOS__*/

#ifdef __MACOS__
# define DLN_DEFINED
    {
      OSErr err;
      FSSpec libspec;
      CFragConnectionID connID;
      Ptr mainAddr;
      char errMessage[1024];
      Boolean isfolder, didsomething;
      Str63 fragname;
      Ptr symAddr;
      CFragSymbolClass class;
      void (*init_fct)();
      char fullpath[MAXPATHLEN];
      extern LoadError();

      strcpy(fullpath, file);

      /* resolve any aliases to find the real file */
      c2pstr(fullpath);
      (void)FSMakeFSSpec(0, 0, fullpath, &libspec);
      err = ResolveAliasFile(&libspec, 1, &isfolder, &didsomething);
      if ( err ) {
	LoadError("Unresolved Alias - %s", file);
      }

      /* Load the fragment (or return the connID if it is already loaded */
      fragname[0] = 0;
      err = GetDiskFragment(&libspec, 0, 0, fragname, 
			    kLoadCFrag, &connID, &mainAddr,
			    errMessage);
      if ( err ) {
	p2cstr(errMessage);
	LoadError("%s - %s",errMessage , file);
      }

      /* Locate the address of the correct init function */
      c2pstr(buf);
      err = FindSymbol(connID, buf, &symAddr, &class);
      if ( err ) {
	LoadError("Unresolved symbols - %s" , file);
      }
	
      init_fct = (void (*)())symAddr;
      (*init_fct)();
      return;
    }
#endif /* __MACOS__ */

#ifndef DLN_DEFINED
    rb_notimplement("dynamic link not supported");
#endif

#endif /* USE_DLN_A_OUT */
#endif
#if !defined(_AIX) && !defined(NeXT)
  failed:
    LoadError("%s - %s", dln_strerror(), file);
#endif
}

static char *dln_find_1();

char *
dln_find_exe(fname, path)
    char *fname;
    char *path;
{
#if defined(__human68k__)
    if (!path)
	path = getenv("path");
    if (!path)
	path = "/usr/local/bin;/usr/ucb;/usr/bin;/bin;.";
#else
    if (!path) path = getenv("PATH");
    if (!path) path = "/usr/local/bin:/usr/ucb:/usr/bin:/bin:.";
#endif
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

#if defined(__CYGWIN32__)
char *
conv_to_posix_path(win32, posix)
    char *win32;
    char *posix;
{
    char *first = win32;
    char *p = win32;
    char *dst = posix;

    for (p = win32; *p; p++)
	if (*p == ';') {
	    *p = 0;
	    cygwin32_conv_to_posix_path(first, posix);
	    posix += strlen(posix);
	    *posix++ = ':';
	    first = p + 1;
	    *p = ';';
	}
    cygwin32_conv_to_posix_path(first, posix);
    return dst;
}
#endif

static char fbuf[MAXPATHLEN];

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

#if defined(__CYGWIN32__)
    char rubypath[MAXPATHLEN];
    conv_to_posix_path(path, rubypath);
    path = rubypath;
#endif
#ifndef __MACOS__
    if (fname[0] == '/') return fname;
    if (strncmp("./", fname, 2) == 0 || strncmp("../", fname, 3) == 0)
      return fname;
    if (exe_flag && strchr(fname, '/')) return fname;
#if defined(MSDOS) || defined(NT) || defined(__human68k__)
    if (fname[0] == '\\') return fname;
    if (strlen(fname) > 2 && fname[1] == ':') return fname;
    if (strncmp(".\\", fname, 2) == 0 || strncmp("..\\", fname, 3) == 0)
      return fname;
    if (exe_flag && strchr(fname, '\\')) return fname;
#endif
#endif /* __MACOS__ */

    for (dp = path;; dp = ++ep) {
	register int l;
	int i;
	int fspace;

	/* extract a component */
#if !defined(MSDOS)  && !defined(NT) && !defined(__human68k__) && !defined(__MACOS__)
	ep = strchr(dp, ':');
#else
	ep = strchr(dp, ';');
#endif
	if (ep == NULL)
	    ep = dp+strlen(dp);

	/* find the length of that component */
	l = ep - dp;
	bp = fbuf;
	fspace = sizeof fbuf - 2;
	if (l > 0) {
	    /*
	    **	If the length of the component is zero length,
	    **	start from the current directory.  If the
	    **	component begins with "~", start from the
	    **	user's $HOME environment variable.  Otherwise
	    **	take the path literally.
	    */

	    if (*dp == '~' && (l == 1 ||
#if defined(MSDOS) || defined(NT) || defined(__human68k__)
			       dp[1] == '\\' || 
#endif
			       dp[1] == '/')) {
		char *home;

		home = getenv("HOME");
		if (home != NULL) {
		    i = strlen(home);
		    if ((fspace -= i) < 0)
			goto toolong;
		    memcpy(bp, home, i);
		    bp += i;
		}
		dp++;
		l--;
	    }
	    if (l > 0) {
		if ((fspace -= l) < 0)
		    goto toolong;
		memcpy(bp, dp, l);
		bp += l;
	    }

	    /* add a "/" between directory and filename */
	    if (ep[-1] != '/')
#ifdef __MACOS__
		*bp++ = ':';
#else
		*bp++ = '/';
#endif
	}

	/* now append the file name */
	i = strlen(fname);
	if ((fspace -= i) < 0) {
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
	    if (eaccess(fbuf, X_OK) == 0) return fbuf;
	}
#if defined(MSDOS) || defined(NT) || defined(__human68k__)
	if (exe_flag) {
	    static const char *extension[] = {
#if defined(MSDOS)
		".com", ".exe", ".bat",
#if defined(DJGPP)
		".btm", ".sh", ".ksh", ".pl", ".sed",
#endif
#else
		".r", ".R", ".x", ".X", ".bat", ".BAT",
#endif
		(char *) NULL
	    };
	    int j;

	    for (j = 0; extension[j]; j++) {
		if (fspace < strlen(extension[j])) {
		    fprintf(stderr, "openpath: pathname too long (ignored)\n");
		    fprintf(stderr, "\tDirectory \"%.*s\"\n", (int) (bp - fbuf), fbuf);
		    fprintf(stderr, "\tFile \"%s%s\"\n", fname, extension[j]);
		    continue;
		}
		strcpy(bp + i, extension[j]);
		if (stat(fbuf, &st) == 0)
		    return fbuf;
	    }
	}
#endif /* MSDOS or NT or __human68k__ */
	/* if not, and no other alternatives, life is bleak */
	if (*ep == '\0') {
	    return NULL;
	}

	/* otherwise try the next component in the search path */
    }
}
