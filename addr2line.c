/**********************************************************************

  addr2line.c -

  $Author$

  Copyright (C) 2010 Shinichiro Hamaji

**********************************************************************/

#include "ruby/config.h"
#include "ruby/missing.h"
#include "addr2line.h"

#include <stdio.h>
#include <stdbool.h>
#include <errno.h>

#ifdef USE_ELF

#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#ifdef __OpenBSD__
#include <elf_abi.h>
#else
#include <elf.h>
#endif

/* Make alloca work the best possible way.  */
#ifdef __GNUC__
# ifndef alloca
#  define alloca __builtin_alloca
# endif
#else
# ifdef HAVE_ALLOCA_H
#  include <alloca.h>
# else
#  ifdef _AIX
#pragma alloca
#  else
#   ifndef alloca		/* predefined by HP cc +Olibcalls */
void *alloca();
#   endif
#  endif /* AIX */
# endif	/* HAVE_ALLOCA_H */
#endif /* __GNUC__ */

#ifdef HAVE_DLADDR
# include <dlfcn.h>
#endif

#define DW_LNS_copy                     0x01
#define DW_LNS_advance_pc               0x02
#define DW_LNS_advance_line             0x03
#define DW_LNS_set_file                 0x04
#define DW_LNS_set_column               0x05
#define DW_LNS_negate_stmt              0x06
#define DW_LNS_set_basic_block          0x07
#define DW_LNS_const_add_pc             0x08
#define DW_LNS_fixed_advance_pc         0x09
#define DW_LNS_set_prologue_end         0x0a /* DWARF3 */
#define DW_LNS_set_epilogue_begin       0x0b /* DWARF3 */
#define DW_LNS_set_isa                  0x0c /* DWARF3 */

/* Line number extended opcode name. */
#define DW_LNE_end_sequence             0x01
#define DW_LNE_set_address              0x02
#define DW_LNE_define_file              0x03
#define DW_LNE_set_discriminator        0x04  /* DWARF4 */

#ifndef ElfW
# if SIZEOF_VOIDP == 8
#  define ElfW(x) Elf64##_##x
# else
#  define ElfW(x) Elf32##_##x
# endif
#endif
#ifndef ELF_ST_TYPE
# if SIZEOF_VOIDP == 8
#  define ELF_ST_TYPE ELF64_ST_TYPE
# else
#  define ELF_ST_TYPE ELF32_ST_TYPE
# endif
#endif
#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#ifndef SHF_COMPRESSED /* compatibility with glibc < 2.22 */
#define SHF_COMPRESSED 0
#endif

int kprintf(const char *fmt, ...);

typedef struct {
    const char *dirname;
    const char *filename;
    const char *path; /* object path */
    int line;

    uintptr_t base_addr;
    uintptr_t saddr;
    const char *sname; /* function name */
} line_info_t;
typedef struct obj_info obj_info_t;
struct obj_info {
    const char *path; /* object path */
    int fd;
    void *mapped;
    size_t mapped_size;
    uintptr_t base_addr;
    obj_info_t *next;
};

/* Avoid consuming stack as this module may be used from signal handler */
static char binary_filename[PATH_MAX];

static unsigned long
uleb128(char **p)
{
    unsigned long r = 0;
    int s = 0;
    for (;;) {
	unsigned char b = *(unsigned char *)(*p)++;
	if (b < 0x80) {
	    r += (unsigned long)b << s;
	    break;
	}
	r += (b & 0x7f) << s;
	s += 7;
    }
    return r;
}

static long
sleb128(char **p)
{
    long r = 0;
    int s = 0;
    for (;;) {
	unsigned char b = *(unsigned char *)(*p)++;
	if (b < 0x80) {
	    if (b & 0x40) {
		r -= (0x80 - b) << s;
	    }
	    else {
		r += (b & 0x3f) << s;
	    }
	    break;
	}
	r += (b & 0x7f) << s;
	s += 7;
    }
    return r;
}

static const char *
get_nth_dirname(unsigned long dir, char *p)
{
    if (!dir--) {
	return "";
    }
    while (dir--) {
	while (*p) p++;
	p++;
	if (!*p) {
	    kprintf("Unexpected directory number %lu in %s\n",
		    dir, binary_filename);
	    return "";
	}
    }
    return p;
}

static void
fill_filename(int file, char *include_directories, char *filenames,
	      line_info_t *line)
{
    int i;
    char *p = filenames;
    char *filename;
    unsigned long dir;
    for (i = 1; i <= file; i++) {
	filename = p;
	if (!*p) {
	    /* Need to output binary file name? */
	    kprintf("Unexpected file number %d in %s\n",
		    file, binary_filename);
	    return;
	}
	while (*p) p++;
	p++;
	dir = uleb128(&p);
	/* last modified. */
	uleb128(&p);
	/* size of the file. */
	uleb128(&p);

	if (i == file) {
	    line->filename = filename;
	    line->dirname = get_nth_dirname(dir, include_directories);
	}
    }
}

static void
fill_line(int num_traces, void **traces, uintptr_t addr, int file, int line,
	  char *include_directories, char *filenames,
	  obj_info_t *obj, line_info_t *lines, int offset)
{
    int i;
    addr += obj->base_addr;
    for (i = offset; i < num_traces; i++) {
	uintptr_t a = (uintptr_t)traces[i];
	/* We assume one line code doesn't result >100 bytes of native code.
       We may want more reliable way eventually... */
	if (addr < a && a < addr + 100) {
	    fill_filename(file, include_directories, filenames, &lines[i]);
	    lines[i].line = line;
	}
    }
}

static int
parse_debug_line_cu(int num_traces, void **traces, char **debug_line,
		obj_info_t *obj, line_info_t *lines, int offset)
{
    char *p, *cu_end, *cu_start, *include_directories, *filenames;
    unsigned long unit_length;
    int default_is_stmt, line_base;
    unsigned int header_length, minimum_instruction_length, line_range,
		 opcode_base;
    /* unsigned char *standard_opcode_lengths; */

    /* The registers. */
    unsigned long addr = 0;
    unsigned int file = 1;
    unsigned int line = 1;
    /* unsigned int column = 0; */
    int is_stmt;
    /* int basic_block = 0; */
    /* int end_sequence = 0; */
    /* int prologue_end = 0; */
    /* int epilogue_begin = 0; */
    /* unsigned int isa = 0; */

    p = *debug_line;

    unit_length = *(unsigned int *)p;
    p += sizeof(unsigned int);
    if (unit_length == 0xffffffff) {
	unit_length = *(unsigned long *)p;
	p += sizeof(unsigned long);
    }

    cu_end = p + unit_length;

    /*dwarf_version = *(unsigned short *)p;*/
    p += 2;

    header_length = *(unsigned int *)p;
    p += sizeof(unsigned int);

    cu_start = p + header_length;

    minimum_instruction_length = *(unsigned char *)p;
    p++;

    is_stmt = default_is_stmt = *(unsigned char *)p;
    p++;

    line_base = *(signed char *)p;
    p++;

    line_range = *(unsigned char *)p;
    p++;

    opcode_base = *(unsigned char *)p;
    p++;

    /* standard_opcode_lengths = (unsigned char *)p - 1; */
    p += opcode_base - 1;

    include_directories = p;

    /* temporary measure for compress-debug-sections */
    if (p >= cu_end) return -1;

    /* skip include directories */
    while (*p) {
	p = memchr(p, '\0', cu_end - p);
	if (!p) return -1;
	p++;
    }
    p++;

    filenames = p;

    p = cu_start;

#define FILL_LINE()						    \
    do {							    \
	fill_line(num_traces, traces, addr, file, line,		    \
		  include_directories, filenames,		    \
		  obj, lines, offset);				    \
	/*basic_block = prologue_end = epilogue_begin = 0;*/	    \
    } while (0)

    while (p < cu_end) {
	unsigned long a;
	unsigned char op = *p++;
	switch (op) {
	case DW_LNS_copy:
	    FILL_LINE();
	    break;
	case DW_LNS_advance_pc:
	    a = uleb128(&p);
	    addr += a;
	    break;
	case DW_LNS_advance_line: {
	    long a = sleb128(&p);
	    line += a;
	    break;
	}
	case DW_LNS_set_file:
	    file = (unsigned int)uleb128(&p);
	    break;
	case DW_LNS_set_column:
	    /*column = (unsigned int)*/(void)uleb128(&p);
	    break;
	case DW_LNS_negate_stmt:
	    is_stmt = !is_stmt;
	    break;
	case DW_LNS_set_basic_block:
	    /*basic_block = 1; */
	    break;
	case DW_LNS_const_add_pc:
	    a = ((255 - opcode_base) / line_range) *
		minimum_instruction_length;
	    addr += a;
	    break;
	case DW_LNS_fixed_advance_pc:
	    a = *(unsigned char *)p++;
	    addr += a;
	    break;
	case DW_LNS_set_prologue_end:
	    /* prologue_end = 1; */
	    break;
	case DW_LNS_set_epilogue_begin:
	    /* epilogue_begin = 1; */
	    break;
	case DW_LNS_set_isa:
	    /* isa = (unsigned int)*/(void)uleb128(&p);
	    break;
	case 0:
	    a = *(unsigned char *)p++;
	    op = *p++;
	    switch (op) {
	    case DW_LNE_end_sequence:
		/* end_sequence = 1; */
		FILL_LINE();
		addr = 0;
		file = 1;
		line = 1;
		/* column = 0; */
		is_stmt = default_is_stmt;
		/* end_sequence = 0; */
		/* isa = 0; */
		break;
	    case DW_LNE_set_address:
		addr = *(unsigned long *)p;
		p += sizeof(unsigned long);
		break;
	    case DW_LNE_define_file:
		kprintf("Unsupported operation in %s\n",
			binary_filename);
		break;
	    case DW_LNE_set_discriminator:
		/* TODO:currently ignore */
		uleb128(&p);
		break;
	    default:
		kprintf("Unknown extended opcode: %d in %s\n",
			op, binary_filename);
	    }
	    break;
	default: {
	    unsigned long addr_incr;
	    unsigned long line_incr;
	    a = op - opcode_base;
	    addr_incr = (a / line_range) * minimum_instruction_length;
	    line_incr = line_base + (a % line_range);
	    addr += (unsigned int)addr_incr;
	    line += (unsigned int)line_incr;
	    FILL_LINE();
	}
	}
    }
    *debug_line = p;
    return 0;
}

static int
parse_debug_line(int num_traces, void **traces,
		 char *debug_line, unsigned long size,
		 obj_info_t *obj, line_info_t *lines, int offset)
{
    char *debug_line_end = debug_line + size;
    while (debug_line < debug_line_end) {
	if (parse_debug_line_cu(num_traces, traces, &debug_line, obj, lines, offset))
	    return -1;
    }
    if (debug_line != debug_line_end) {
	kprintf("Unexpected size of .debug_line in %s\n",
		binary_filename);
    }
    return 0;
}

/* read file and fill lines */
static uintptr_t
fill_lines(int num_traces, void **traces, int check_debuglink,
	   obj_info_t **objp, line_info_t *lines, int offset);

static void
append_obj(obj_info_t **objp)
{
    obj_info_t *newobj = calloc(1, sizeof(obj_info_t));
    if (*objp) (*objp)->next = newobj;
    *objp = newobj;
}

static void
follow_debuglink(const char *debuglink, int num_traces, void **traces,
		 obj_info_t **objp, line_info_t *lines, int offset)
{
    /* Ideally we should check 4 paths to follow gnu_debuglink,
       but we handle only one case for now as this format is used
       by some linux distributions. See GDB's info for detail. */
    static const char global_debug_dir[] = "/usr/lib/debug";
    const size_t global_debug_dir_len = sizeof(global_debug_dir) - 1;
    char *p;
    obj_info_t *o1 = *objp, *o2;
    size_t len;

    p = strrchr(binary_filename, '/');
    if (!p) {
	return;
    }
    p[1] = '\0';

    len = strlen(binary_filename);
    if (len >= PATH_MAX - global_debug_dir_len)
	len = PATH_MAX - global_debug_dir_len - 1;
    memmove(binary_filename + global_debug_dir_len, binary_filename, len);
    memcpy(binary_filename, global_debug_dir, global_debug_dir_len);
    len += global_debug_dir_len;
    strlcpy(binary_filename + len, debuglink, PATH_MAX - len);

    append_obj(objp);
    o2 = *objp;
    o2->base_addr = o1->base_addr;
    o2->path = o1->path;
    fill_lines(num_traces, traces, 0, objp, lines, offset);
}

/* read file and fill lines */
static uintptr_t
fill_lines(int num_traces, void **traces, int check_debuglink,
	   obj_info_t **objp, line_info_t *lines, int offset)
{
    int i, j;
    char *shstr;
    char *section_name;
    ElfW(Ehdr) *ehdr;
    ElfW(Shdr) *shdr, *shstr_shdr;
    ElfW(Shdr) *debug_line_shdr = NULL, *gnu_debuglink_shdr = NULL;
    int fd;
    off_t filesize;
    char *file;
    ElfW(Shdr) *symtab_shdr = NULL, *strtab_shdr = NULL;
    ElfW(Shdr) *dynsym_shdr = NULL, *dynstr_shdr = NULL;
    obj_info_t *obj = *objp;
    uintptr_t dladdr_fbase = 0;
    bool compressed_p = false;

    fd = open(binary_filename, O_RDONLY);
    if (fd < 0) {
	goto fail;
    }
    filesize = lseek(fd, 0, SEEK_END);
    if (filesize < 0) {
	int e = errno;
	close(fd);
	kprintf("lseek: %s\n", strerror(e));
	goto fail;
    }
#if SIZEOF_OFF_T > SIZEOF_SIZE_T
    if (filesize > (off_t)SIZE_MAX) {
	close(fd);
	kprintf("Too large file %s\n", binary_filename);
	goto fail;
    }
#endif
    lseek(fd, 0, SEEK_SET);
    /* async-signal unsafe */
    file = (char *)mmap(NULL, (size_t)filesize, PROT_READ, MAP_SHARED, fd, 0);
    if (file == MAP_FAILED) {
	int e = errno;
	close(fd);
	kprintf("mmap: %s\n", strerror(e));
	goto fail;
    }

    ehdr = (ElfW(Ehdr) *)file;
    if (memcmp(ehdr->e_ident, "\177ELF", 4) != 0) {
	/*
	 * Huh? Maybe filename was overridden by setproctitle() and
	 * it match non-elf file.
	 */
	close(fd);
	goto fail;
    }

    obj->fd = fd;
    obj->mapped = file;
    obj->mapped_size = (size_t)filesize;

    shdr = (ElfW(Shdr) *)(file + ehdr->e_shoff);

    shstr_shdr = shdr + ehdr->e_shstrndx;
    shstr = file + shstr_shdr->sh_offset;

    for (i = 0; i < ehdr->e_shnum; i++) {
	section_name = shstr + shdr[i].sh_name;
	switch (shdr[i].sh_type) {
	  case SHT_STRTAB:
	    if (!strcmp(section_name, ".strtab")) {
		strtab_shdr = shdr + i;
	    }
	    else if (!strcmp(section_name, ".dynstr")) {
		dynstr_shdr = shdr + i;
	    }
	    break;
	  case SHT_SYMTAB:
	    /* if (!strcmp(section_name, ".symtab")) */
	    symtab_shdr = shdr + i;
	    break;
	  case SHT_DYNSYM:
	    /* if (!strcmp(section_name, ".dynsym")) */
	    dynsym_shdr = shdr + i;
	    break;
	  case SHT_PROGBITS:
	    if (!strcmp(section_name, ".debug_line")) {
		if (shdr[i].sh_flags & SHF_COMPRESSED) {
		    compressed_p = true;
		}
		debug_line_shdr = shdr + i;
	    }
	    else if (!strcmp(section_name, ".gnu_debuglink")) {
		gnu_debuglink_shdr = shdr + i;
	    }
	    break;
	}
    }

    if (offset == -1) {
	/* main executable */
	offset = 0;
	if (dynsym_shdr && dynstr_shdr) {
	    char *strtab = file + dynstr_shdr->sh_offset;
	    ElfW(Sym) *symtab = (ElfW(Sym) *)(file + dynsym_shdr->sh_offset);
	    int symtab_count = (int)(dynsym_shdr->sh_size / sizeof(ElfW(Sym)));
	    for (j = 0; j < symtab_count; j++) {
		ElfW(Sym) *sym = &symtab[j];
		Dl_info info;
		void *h, *s;
		if (ELF_ST_TYPE(sym->st_info) != STT_FUNC || sym->st_size <= 0) continue;
		h = dlopen(NULL, RTLD_NOW|RTLD_LOCAL);
		if (!h) continue;
		s = dlsym(h, strtab + sym->st_name);
		if (!s) continue;
		if (dladdr(s, &info)) {
		    dladdr_fbase = (uintptr_t)info.dli_fbase;
		    break;
		}
	    }
	    if (ehdr->e_type == ET_EXEC) {
		obj->base_addr = 0;
	    }
	    else {
		/* PIE (position-independent executable) */
		obj->base_addr = dladdr_fbase;
	    }
	}
    }

    if (!symtab_shdr) {
	symtab_shdr = dynsym_shdr;
	strtab_shdr = dynstr_shdr;
    }

    if (symtab_shdr && strtab_shdr) {
	char *strtab = file + strtab_shdr->sh_offset;
	ElfW(Sym) *symtab = (ElfW(Sym) *)(file + symtab_shdr->sh_offset);
	int symtab_count = (int)(symtab_shdr->sh_size / sizeof(ElfW(Sym)));
	for (j = 0; j < symtab_count; j++) {
	    ElfW(Sym) *sym = &symtab[j];
	    uintptr_t saddr = (uintptr_t)sym->st_value + obj->base_addr;
	    if (ELF_ST_TYPE(sym->st_info) != STT_FUNC || sym->st_size <= 0) continue;
	    for (i = offset; i < num_traces; i++) {
		uintptr_t d = (uintptr_t)traces[i] - saddr;
		if (lines[i].line > 0 || d <= 0 || d > (uintptr_t)sym->st_size)
		    continue;
		/* fill symbol name and addr from .symtab */
		lines[i].sname = strtab + sym->st_name;
		lines[i].saddr = saddr;
		lines[i].path  = obj->path;
		lines[i].base_addr = obj->base_addr;
	    }
	}
    }

    if (!debug_line_shdr) {
	/* This file doesn't have .debug_line section,
	   let's check .gnu_debuglink section instead. */
	if (gnu_debuglink_shdr && check_debuglink) {
	    follow_debuglink(file + gnu_debuglink_shdr->sh_offset,
			     num_traces, traces,
			     objp, lines, offset);
	}
	goto finish;
    }

    if (!compressed_p &&
	    parse_debug_line(num_traces, traces,
			 file + debug_line_shdr->sh_offset,
			 debug_line_shdr->sh_size,
			 obj, lines, offset))
	goto fail;
finish:
    return dladdr_fbase;
fail:
    return (uintptr_t)-1;
}

#define HAVE_MAIN_EXE_PATH
#if defined(__FreeBSD__)
# include <sys/sysctl.h>
#endif
/* ssize_t main_exe_path(void)
 *
 * store the path of the main executable to `binary_filename`,
 * and returns strlen(binary_filename).
 * it is NUL terminated.
 */
#if defined(__linux__)
static ssize_t
main_exe_path(void)
{
# define PROC_SELF_EXE "/proc/self/exe"
    ssize_t len = readlink(PROC_SELF_EXE, binary_filename, PATH_MAX);
    binary_filename[len] = 0;
    return len;
}
#elif defined(__FreeBSD__)
static ssize_t
main_exe_path(void)
{
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PATHNAME, -1};
    size_t len = PATH_MAX;
    int err = sysctl(mib, 4, binary_filename, &len, NULL, 0);
    if (err) {
	kprintf("Can't get the path of ruby");
	return -1;
    }
    len--; /* sysctl sets strlen+1 */
    return len;
}
#else
#undef HAVE_MAIN_EXE_PATH
#endif

void
rb_dump_backtrace_with_lines(int num_traces, void **traces)
{
    int i;
    /* async-signal unsafe */
    line_info_t *lines = (line_info_t *)calloc(num_traces, sizeof(line_info_t));
    obj_info_t *obj = NULL;
    /* 2 is NULL + main executable */
    void **dladdr_fbases = (void **)calloc(num_traces+2, sizeof(void *));
#ifdef HAVE_MAIN_EXE_PATH
    char *main_path = NULL; /* used on printing backtrace */
    ssize_t len;
    if ((len = main_exe_path()) > 0) {
	main_path = (char *)alloca(len + 1);
	if (main_path) {
	    uintptr_t addr;
	    memcpy(main_path, binary_filename, len+1);
	    append_obj(&obj);
	    obj->path = main_path;
	    addr = fill_lines(num_traces, traces, 1, &obj, lines, -1);
	    if (addr != (uintptr_t)-1) {
		dladdr_fbases[0] = (void *)addr;
	    }
	}
    }
#endif

    /* fill source lines by reading dwarf */
    for (i = 0; i < num_traces; i++) {
	Dl_info info;
	if (lines[i].line) continue;
	if (dladdr(traces[i], &info)) {
	    const char *path;
	    void **p;

	    /* skip symbols which is in already checked objects */
	    /* if the binary is strip-ed, this may effect */
	    for (p=dladdr_fbases; *p; p++) {
		if (*p == info.dli_fbase) {
		    lines[i].path = info.dli_fname;
		    lines[i].sname = info.dli_sname;
		    goto next_line;
		}
	    }
	    *p = info.dli_fbase;

	    append_obj(&obj);
	    obj->base_addr = (uintptr_t)info.dli_fbase;
	    path = info.dli_fname;
	    obj->path = path;
	    lines[i].path = path;
	    strlcpy(binary_filename, path, PATH_MAX);
	    if (fill_lines(num_traces, traces, 1, &obj, lines, i) == (uintptr_t)-1)
		break;
	}
next_line:
	continue;
    }

    /* output */
    for (i = 0; i < num_traces; i++) {
	line_info_t *line = &lines[i];
	uintptr_t addr = (uintptr_t)traces[i];
	uintptr_t d = addr - line->saddr;
	if (!line->path) {
	    kprintf("[0x%lx]\n", addr);
	}
	else if (!line->saddr || !line->sname) {
	    kprintf("%s(0x%lx) [0x%lx]\n", line->path, addr-line->base_addr, addr);
	}
	else if (line->line <= 0) {
	    kprintf("%s(%s+0x%lx) [0x%lx]\n", line->path, line->sname,
		    d, addr);
	}
	else if (!line->filename) {
	    kprintf("%s(%s+0x%lx) [0x%lx] ???:%d\n", line->path, line->sname,
		    d, addr, line->line);
	}
	else if (line->dirname && line->dirname[0]) {
	    kprintf("%s(%s+0x%lx) [0x%lx] %s/%s:%d\n", line->path, line->sname,
		    d, addr, line->dirname, line->filename, line->line);
	}
	else {
	    kprintf("%s(%s+0x%lx) [0x%lx] %s:%d\n", line->path, line->sname,
		    d, addr, line->filename, line->line);
	}
	/* FreeBSD's backtrace may show _start and so on */
	if (line->sname && strcmp("main", line->sname) == 0)
	    break;
    }

    /* free */
    while (obj) {
	obj_info_t *o = obj;
	obj = o->next;
	if (o->fd) {
	    munmap(o->mapped, o->mapped_size);
	    close(o->fd);
	}
	free(o);
    }
    free(lines);
    free(dladdr_fbases);
}

/* From FreeBSD's lib/libstand/printf.c */
/*-
 * Copyright (c) 1986, 1988, 1991, 1993
 *	The Regents of the University of California.  All rights reserved.
 * (c) UNIX System Laboratories, Inc.
 * All or some portions of this file are derived from material licensed
 * to the University of California by American Telephone and Telegraph
 * Co. or Unix System Laboratories, Inc. and are reproduced herein with
 * the permission of UNIX System Laboratories, Inc.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *	@(#)subr_prf.c	8.3 (Berkeley) 1/21/94
 */

#include <stdarg.h>
#define MAXNBUF (sizeof(intmax_t) * CHAR_BIT + 1)
static inline int toupper(int c) { return ('A' <= c && c <= 'Z') ? (c&0x5f) : c; }
#define    hex2ascii(hex)  (hex2ascii_data[hex])
char const hex2ascii_data[] = "0123456789abcdefghijklmnopqrstuvwxyz";
static inline int imax(int a, int b) { return (a > b ? a : b); }
static int kvprintf(char const *fmt, void (*func)(int), void *arg, int radix, va_list ap);

static void putce(int c)
{
    char s[1];
    ssize_t ret;

    s[0] = (char)c;
    ret = write(2, s, 1);
    (void)ret;
}

int
kprintf(const char *fmt, ...)
{
	va_list ap;
	int retval;

	va_start(ap, fmt);
	retval = kvprintf(fmt, putce, NULL, 10, ap);
	va_end(ap);
	return retval;
}

/*
 * Put a NUL-terminated ASCII number (base <= 36) in a buffer in reverse
 * order; return an optional length and a pointer to the last character
 * written in the buffer (i.e., the first character of the string).
 * The buffer pointed to by `nbuf' must have length >= MAXNBUF.
 */
static char *
ksprintn(char *nbuf, uintmax_t num, int base, int *lenp, int upper)
{
	char *p, c;

	p = nbuf;
	*p = '\0';
	do {
		c = hex2ascii(num % base);
		*++p = upper ? toupper(c) : c;
	} while (num /= base);
	if (lenp)
		*lenp = (int)(p - nbuf);
	return (p);
}

/*
 * Scaled down version of printf(3).
 *
 * Two additional formats:
 *
 * The format %b is supported to decode error registers.
 * Its usage is:
 *
 *	printf("reg=%b\n", regval, "<base><arg>*");
 *
 * where <base> is the output base expressed as a control character, e.g.
 * \10 gives octal; \20 gives hex.  Each arg is a sequence of characters,
 * the first of which gives the bit number to be inspected (origin 1), and
 * the next characters (up to a control character, i.e. a character <= 32),
 * give the name of the register.  Thus:
 *
 *	kvprintf("reg=%b\n", 3, "\10\2BITTWO\1BITONE\n");
 *
 * would produce output:
 *
 *	reg=3<BITTWO,BITONE>
 *
 * XXX:  %D  -- Hexdump, takes pointer and separator string:
 *		("%6D", ptr, ":")   -> XX:XX:XX:XX:XX:XX
 *		("%*D", len, ptr, " " -> XX XX XX XX ...
 */
static int
kvprintf(char const *fmt, void (*func)(int), void *arg, int radix, va_list ap)
{
#define PCHAR(c) {int cc=(c); if (func) (*func)(cc); else *d++ = cc; retval++; }
	char nbuf[MAXNBUF];
	char *d;
	const char *p, *percent, *q;
	unsigned char *up;
	int ch, n;
	uintmax_t num;
	int base, lflag, qflag, tmp, width, ladjust, sharpflag, neg, sign, dot;
	int cflag, hflag, jflag, tflag, zflag;
	int dwidth, upper;
	char padc;
	int stop = 0, retval = 0;

	num = 0;
	if (!func)
		d = (char *) arg;
	else
		d = NULL;

	if (fmt == NULL)
		fmt = "(fmt null)\n";

	if (radix < 2 || radix > 36)
		radix = 10;

	for (;;) {
		padc = ' ';
		width = 0;
		while ((ch = (unsigned char)*fmt++) != '%' || stop) {
			if (ch == '\0')
				return (retval);
			PCHAR(ch);
		}
		percent = fmt - 1;
		qflag = 0; lflag = 0; ladjust = 0; sharpflag = 0; neg = 0;
		sign = 0; dot = 0; dwidth = 0; upper = 0;
		cflag = 0; hflag = 0; jflag = 0; tflag = 0; zflag = 0;
reswitch:	switch (ch = (unsigned char)*fmt++) {
		case '.':
			dot = 1;
			goto reswitch;
		case '#':
			sharpflag = 1;
			goto reswitch;
		case '+':
			sign = 1;
			goto reswitch;
		case '-':
			ladjust = 1;
			goto reswitch;
		case '%':
			PCHAR(ch);
			break;
		case '*':
			if (!dot) {
				width = va_arg(ap, int);
				if (width < 0) {
					ladjust = !ladjust;
					width = -width;
				}
			} else {
				dwidth = va_arg(ap, int);
			}
			goto reswitch;
		case '0':
			if (!dot) {
				padc = '0';
				goto reswitch;
			}
		case '1': case '2': case '3': case '4':
		case '5': case '6': case '7': case '8': case '9':
				for (n = 0;; ++fmt) {
					n = n * 10 + ch - '0';
					ch = *fmt;
					if (ch < '0' || ch > '9')
						break;
				}
			if (dot)
				dwidth = n;
			else
				width = n;
			goto reswitch;
		case 'b':
			num = (unsigned int)va_arg(ap, int);
			p = va_arg(ap, char *);
			for (q = ksprintn(nbuf, num, *p++, NULL, 0); *q;)
				PCHAR(*q--);

			if (num == 0)
				break;

			for (tmp = 0; *p;) {
				n = *p++;
				if (num & (1 << (n - 1))) {
					PCHAR(tmp ? ',' : '<');
					for (; (n = *p) > ' '; ++p)
						PCHAR(n);
					tmp = 1;
				} else
					for (; *p > ' '; ++p)
						continue;
			}
			if (tmp)
				PCHAR('>');
			break;
		case 'c':
			PCHAR(va_arg(ap, int));
			break;
		case 'D':
			up = va_arg(ap, unsigned char *);
			p = va_arg(ap, char *);
			if (!width)
				width = 16;
			while(width--) {
				PCHAR(hex2ascii(*up >> 4));
				PCHAR(hex2ascii(*up & 0x0f));
				up++;
				if (width)
					for (q=p;*q;q++)
						PCHAR(*q);
			}
			break;
		case 'd':
		case 'i':
			base = 10;
			sign = 1;
			goto handle_sign;
		case 'h':
			if (hflag) {
				hflag = 0;
				cflag = 1;
			} else
				hflag = 1;
			goto reswitch;
		case 'j':
			jflag = 1;
			goto reswitch;
		case 'l':
			if (lflag) {
				lflag = 0;
				qflag = 1;
			} else
				lflag = 1;
			goto reswitch;
		case 'n':
			if (jflag)
				*(va_arg(ap, intmax_t *)) = retval;
			else if (qflag)
				*(va_arg(ap, int64_t *)) = retval;
			else if (lflag)
				*(va_arg(ap, long *)) = retval;
			else if (zflag)
				*(va_arg(ap, size_t *)) = retval;
			else if (hflag)
				*(va_arg(ap, short *)) = retval;
			else if (cflag)
				*(va_arg(ap, char *)) = retval;
			else
				*(va_arg(ap, int *)) = retval;
			break;
		case 'o':
			base = 8;
			goto handle_nosign;
		case 'p':
			base = 16;
			sharpflag = (width == 0);
			sign = 0;
			num = (uintptr_t)va_arg(ap, void *);
			goto number;
		case 'q':
			qflag = 1;
			goto reswitch;
		case 'r':
			base = radix;
			if (sign)
				goto handle_sign;
			goto handle_nosign;
		case 's':
			p = va_arg(ap, char *);
			if (p == NULL)
				p = "(null)";
			if (!dot)
				n = (int)strlen (p);
			else
				for (n = 0; n < dwidth && p[n]; n++)
					continue;

			width -= n;

			if (!ladjust && width > 0)
				while (width--)
					PCHAR(padc);
			while (n--)
				PCHAR(*p++);
			if (ladjust && width > 0)
				while (width--)
					PCHAR(padc);
			break;
		case 't':
			tflag = 1;
			goto reswitch;
		case 'u':
			base = 10;
			goto handle_nosign;
		case 'X':
			upper = 1;
		case 'x':
			base = 16;
			goto handle_nosign;
		case 'y':
			base = 16;
			sign = 1;
			goto handle_sign;
		case 'z':
			zflag = 1;
			goto reswitch;
handle_nosign:
			sign = 0;
			if (jflag)
				num = va_arg(ap, uintmax_t);
			else if (qflag)
				num = va_arg(ap, uint64_t);
			else if (tflag)
				num = va_arg(ap, ptrdiff_t);
			else if (lflag)
				num = va_arg(ap, unsigned long);
			else if (zflag)
				num = va_arg(ap, size_t);
			else if (hflag)
				num = (unsigned short)va_arg(ap, int);
			else if (cflag)
				num = (unsigned char)va_arg(ap, int);
			else
				num = va_arg(ap, unsigned int);
			goto number;
handle_sign:
			if (jflag)
				num = va_arg(ap, intmax_t);
			else if (qflag)
				num = va_arg(ap, int64_t);
			else if (tflag)
				num = va_arg(ap, ptrdiff_t);
			else if (lflag)
				num = va_arg(ap, long);
			else if (zflag)
				num = va_arg(ap, ssize_t);
			else if (hflag)
				num = (short)va_arg(ap, int);
			else if (cflag)
				num = (char)va_arg(ap, int);
			else
				num = va_arg(ap, int);
number:
			if (sign && (intmax_t)num < 0) {
				neg = 1;
				num = -(intmax_t)num;
			}
			p = ksprintn(nbuf, num, base, &n, upper);
			tmp = 0;
			if (sharpflag && num != 0) {
				if (base == 8)
					tmp++;
				else if (base == 16)
					tmp += 2;
			}
			if (neg)
				tmp++;

			if (!ladjust && padc == '0')
				dwidth = width - tmp;
			width -= tmp + imax(dwidth, n);
			dwidth -= n;
			if (!ladjust)
				while (width-- > 0)
					PCHAR(' ');
			if (neg)
				PCHAR('-');
			if (sharpflag && num != 0) {
				if (base == 8) {
					PCHAR('0');
				} else if (base == 16) {
					PCHAR('0');
					PCHAR('x');
				}
			}
			while (dwidth-- > 0)
				PCHAR('0');

			while (*p)
				PCHAR(*p--);

			if (ladjust)
				while (width-- > 0)
					PCHAR(' ');

			break;
		default:
			while (percent < fmt)
				PCHAR(*percent++);
			/*
			 * Since we ignore an formatting argument it is no
			 * longer safe to obey the remaining formatting
			 * arguments as the arguments will no longer match
			 * the format specs.
			 */
			stop = 1;
			break;
		}
	}
#undef PCHAR
}
#else /* defined(USE_ELF) */
#error not supported
#endif
