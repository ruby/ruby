/**********************************************************************

  addr2line.c -

  $Author$

  Copyright (C) 2010 Shinichiro Hamaji

**********************************************************************/

#if defined(__clang__)
#pragma clang diagnostic ignored "-Wgnu-empty-initializer"
#pragma clang diagnostic ignored "-Wgcc-compat"
#endif

#include "ruby/internal/config.h"
#include "ruby/defines.h"
#include "ruby/missing.h"
#include "addr2line.h"

#include <stdio.h>
#include <errno.h>

#ifdef HAVE_LIBPROC_H
#include <libproc.h>
#endif

#include "ruby/internal/stdbool.h"

#if defined(USE_ELF) || defined(HAVE_MACH_O_LOADER_H)

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

#ifdef HAVE_MACH_O_LOADER_H
# include <crt_externs.h>
# include <mach-o/fat.h>
# include <mach-o/loader.h>
# include <mach-o/nlist.h>
# include <mach-o/stab.h>
#endif

#ifdef USE_ELF
# ifdef __OpenBSD__
#  include <elf_abi.h>
# else
#  include <elf.h>
# endif

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
#endif

#ifdef SHF_COMPRESSED
# if defined(ELFCOMPRESS_ZLIB) && defined(HAVE_LIBZ)
   /* FreeBSD 11.0 lacks ELFCOMPRESS_ZLIB */
#  include <zlib.h>
#  define SUPPORT_COMPRESSED_DEBUG_LINE
# endif
#else /* compatibility with glibc < 2.22 */
# define SHF_COMPRESSED 0
#endif

#ifndef PATH_MAX
#define PATH_MAX 4096
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

PRINTF_ARGS(static int kprintf(const char *fmt, ...), 1, 2);

typedef struct line_info {
    const char *dirname;
    const char *filename;
    const char *path; /* object path */
    int line;

    uintptr_t base_addr;
    uintptr_t saddr;
    const char *sname; /* function name */

    struct line_info *next;
} line_info_t;

struct dwarf_section {
    char *ptr;
    size_t size;
    uint64_t flags;
};

typedef struct obj_info {
    const char *path; /* object path */
    char *mapped;
    size_t mapped_size;
    void *uncompressed;
    uintptr_t base_addr;
    uintptr_t vmaddr;
    struct dwarf_section debug_abbrev;
    struct dwarf_section debug_info;
    struct dwarf_section debug_line;
    struct dwarf_section debug_ranges;
    struct dwarf_section debug_str;
    struct obj_info *next;
} obj_info_t;

#define DWARF_SECTION_COUNT 5

static struct dwarf_section *
obj_dwarf_section_at(obj_info_t *obj, int n)
{
    struct dwarf_section *ary[] = {
        &obj->debug_abbrev,
        &obj->debug_info,
        &obj->debug_line,
        &obj->debug_ranges,
        &obj->debug_str
    };
    if (n < 0 || DWARF_SECTION_COUNT <= n) {
        abort();
    }
    return ary[n];
}

struct debug_section_definition {
    const char *name;
    struct dwarf_section *dwarf;
};

/* Avoid consuming stack as this module may be used from signal handler */
static char binary_filename[PATH_MAX + 1];

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
fill_filename(int file, char *include_directories, char *filenames, line_info_t *line, obj_info_t *obj)
{
    int i;
    char *p = filenames;
    char *filename;
    unsigned long dir;
    for (i = 1; i <= file; i++) {
	filename = p;
	if (!*p) {
	    /* Need to output binary file name? */
	    kprintf("Unexpected file number %d in %s at %tx\n",
		    file, binary_filename, filenames - obj->mapped);
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
    addr += obj->base_addr - obj->vmaddr;
    for (i = offset; i < num_traces; i++) {
	uintptr_t a = (uintptr_t)traces[i];
	/* We assume one line code doesn't result >100 bytes of native code.
       We may want more reliable way eventually... */
	if (addr < a && a < addr + 100) {
	    fill_filename(file, include_directories, filenames, &lines[i], obj);
	    lines[i].line = line;
	}
    }
}

struct LineNumberProgramHeader {
    uint64_t unit_length;
    uint16_t version;
    uint8_t format; /* 4 or 8 */
    uint64_t header_length;
    uint8_t minimum_instruction_length;
    uint8_t maximum_operations_per_instruction;
    uint8_t default_is_stmt;
    int8_t line_base;
    uint8_t line_range;
    uint8_t opcode_base;
    /* uint8_t standard_opcode_lengths[opcode_base-1]; */
    const char *include_directories;
    const char *filenames;
    const char *cu_start;
    const char *cu_end;
};

static int
parse_debug_line_header(const char **pp, struct LineNumberProgramHeader *header)
{
    const char *p = *pp;
    header->unit_length = *(uint32_t *)p;
    p += sizeof(uint32_t);

    header->format = 4;
    if (header->unit_length == 0xffffffff) {
	header->unit_length = *(uint64_t *)p;
	p += sizeof(uint64_t);
        header->format = 8;
    }

    header->cu_end = p + header->unit_length;

    header->version = *(uint16_t *)p;
    p += sizeof(uint16_t);
    if (header->version > 4) return -1;

    header->header_length = header->format == 4 ? *(uint32_t *)p : *(uint64_t *)p;
    p += header->format;
    header->cu_start = p + header->header_length;

    header->minimum_instruction_length = *(uint8_t *)p++;

    if (header->version >= 4) {
        /* maximum_operations_per_instruction = *(uint8_t *)p; */
        if (*p != 1) return -1; /* For non-VLIW architectures, this field is 1 */
        p++;
    }

    header->default_is_stmt = *(uint8_t *)p++;
    header->line_base = *(int8_t *)p++;
    header->line_range = *(uint8_t *)p++;
    header->opcode_base = *(uint8_t *)p++;
    /* header->standard_opcode_lengths = (uint8_t *)p - 1; */
    p += header->opcode_base - 1;

    header->include_directories = p;

    /* temporary measure for compress-debug-sections */
    if (p >= header->cu_end) return -1;

    /* skip include directories */
    while (*p) {
	p = memchr(p, '\0', header->cu_end - p);
	if (!p) return -1;
	p++;
    }
    p++;

    header->filenames = p;

    *pp = header->cu_start;

    return 0;
}

static int
parse_debug_line_cu(int num_traces, void **traces, char **debug_line,
		obj_info_t *obj, line_info_t *lines, int offset)
{
    const char *p = (const char *)*debug_line;
    struct LineNumberProgramHeader header;

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

    if (parse_debug_line_header(&p, &header))
        return -1;
    is_stmt = header.default_is_stmt;

#define FILL_LINE()						    \
    do {							    \
	fill_line(num_traces, traces, addr, file, line,		    \
                  (char *)header.include_directories,               \
                  (char *)header.filenames,                         \
		  obj, lines, offset);				    \
	/*basic_block = prologue_end = epilogue_begin = 0;*/	    \
    } while (0)

    while (p < header.cu_end) {
	unsigned long a;
	unsigned char op = *p++;
	switch (op) {
	case DW_LNS_copy:
	    FILL_LINE();
	    break;
	case DW_LNS_advance_pc:
	    a = uleb128((char **)&p);
	    addr += a;
	    break;
	case DW_LNS_advance_line: {
	    long a = sleb128((char **)&p);
	    line += a;
	    break;
	}
	case DW_LNS_set_file:
	    file = (unsigned int)uleb128((char **)&p);
	    break;
	case DW_LNS_set_column:
	    /*column = (unsigned int)*/(void)uleb128((char **)&p);
	    break;
	case DW_LNS_negate_stmt:
	    is_stmt = !is_stmt;
	    break;
	case DW_LNS_set_basic_block:
	    /*basic_block = 1; */
	    break;
	case DW_LNS_const_add_pc:
	    a = ((255UL - header.opcode_base) / header.line_range) *
		header.minimum_instruction_length;
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
	    /* isa = (unsigned int)*/(void)uleb128((char **)&p);
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
		is_stmt = header.default_is_stmt;
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
		uleb128((char **)&p);
		break;
	    default:
		kprintf("Unknown extended opcode: %d in %s\n",
			op, binary_filename);
	    }
	    break;
	default: {
            uint8_t adjusted_opcode = op - header.opcode_base;
            uint8_t operation_advance = adjusted_opcode / header.line_range;
            /* NOTE: this code doesn't support VLIW */
            addr += operation_advance * header.minimum_instruction_length;
            line += header.line_base + (adjusted_opcode % header.line_range);
	    FILL_LINE();
	}
	}
    }
    *debug_line = (char *)p;
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

#ifdef USE_ELF
/* Ideally we should check 4 paths to follow gnu_debuglink:
 *
 *   - /usr/lib/debug/.build-id/ab/cdef1234.debug
 *   - /usr/bin/ruby.debug
 *   - /usr/bin/.debug/ruby.debug
 *   - /usr/lib/debug/usr/bin/ruby.debug.
 *
 * but we handle only two cases for now as the two formats are
 * used by some linux distributions.
 *
 * See GDB's info for detail.
 * https://sourceware.org/gdb/onlinedocs/gdb/Separate-Debug-Files.html
 */

// check the path pattern of "/usr/lib/debug/usr/bin/ruby.debug"
static void
follow_debuglink(const char *debuglink, int num_traces, void **traces,
		 obj_info_t **objp, line_info_t *lines, int offset)
{
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

// check the path pattern of "/usr/lib/debug/.build-id/ab/cdef1234.debug"
static void
follow_debuglink_build_id(const char *build_id, size_t build_id_size, int num_traces, void **traces,
                          obj_info_t **objp, line_info_t *lines, int offset)
{
    static const char global_debug_dir[] = "/usr/lib/debug/.build-id/";
    const size_t global_debug_dir_len = sizeof(global_debug_dir) - 1;
    char *p;
    obj_info_t *o1 = *objp, *o2;
    size_t i;

    if (PATH_MAX < global_debug_dir_len + 1 + build_id_size * 2 + 6) return;

    memcpy(binary_filename, global_debug_dir, global_debug_dir_len);
    p = binary_filename + global_debug_dir_len;
    for (i = 0; i < build_id_size; i++) {
        static const char tbl[] = "0123456789abcdef";
        unsigned char n = build_id[i];
        *p++ = tbl[n / 16];
        *p++ = tbl[n % 16];
        if (i == 0) *p++ = '/';
    }
    strcpy(p, ".debug");

    append_obj(objp);
    o2 = *objp;
    o2->base_addr = o1->base_addr;
    o2->path = o1->path;
    fill_lines(num_traces, traces, 0, objp, lines, offset);
}
#endif

enum
{
    DW_TAG_compile_unit = 0x11,
    DW_TAG_inlined_subroutine = 0x1d,
    DW_TAG_subprogram = 0x2e,
};

/* Attributes encodings */
enum
{
    DW_AT_sibling = 0x01,
    DW_AT_location = 0x02,
    DW_AT_name = 0x03,
    /* Reserved 0x04 */
    /* Reserved 0x05 */
    /* Reserved 0x06 */
    /* Reserved 0x07 */
    /* Reserved 0x08 */
    DW_AT_ordering = 0x09,
    /* Reserved 0x0a */
    DW_AT_byte_size = 0x0b,
    /* Reserved 0x0c */
    DW_AT_bit_size = 0x0d,
    /* Reserved 0x0e */
    /* Reserved 0x0f */
    DW_AT_stmt_list = 0x10,
    DW_AT_low_pc = 0x11,
    DW_AT_high_pc = 0x12,
    DW_AT_language = 0x13,
    /* Reserved 0x14 */
    DW_AT_discr = 0x15,
    DW_AT_discr_value = 0x16,
    DW_AT_visibility = 0x17,
    DW_AT_import = 0x18,
    DW_AT_string_length = 0x19,
    DW_AT_common_reference = 0x1a,
    DW_AT_comp_dir = 0x1b,
    DW_AT_const_value = 0x1c,
    DW_AT_containing_type = 0x1d,
    DW_AT_default_value = 0x1e,
    /* Reserved 0x1f */
    DW_AT_inline = 0x20,
    DW_AT_is_optional = 0x21,
    DW_AT_lower_bound = 0x22,
    /* Reserved 0x23 */
    /* Reserved 0x24 */
    DW_AT_producer = 0x25,
    /* Reserved 0x26 */
    DW_AT_prototyped = 0x27,
    /* Reserved 0x28 */
    /* Reserved 0x29 */
    DW_AT_return_addr = 0x2a,
    /* Reserved 0x2b */
    DW_AT_start_scope = 0x2c,
    /* Reserved 0x2d */
    DW_AT_bit_stride = 0x2e,
    DW_AT_upper_bound = 0x2f,
    /* Reserved 0x30 */
    DW_AT_abstract_origin = 0x31,
    DW_AT_accessibility = 0x32,
    DW_AT_address_class = 0x33,
    DW_AT_artificial = 0x34,
    DW_AT_base_types = 0x35,
    DW_AT_calling_convention = 0x36,
    DW_AT_count = 0x37,
    DW_AT_data_member_location = 0x38,
    DW_AT_decl_column = 0x39,
    DW_AT_decl_file = 0x3a,
    DW_AT_decl_line = 0x3b,
    DW_AT_declaration = 0x3c,
    DW_AT_discr_list = 0x3d,
    DW_AT_encoding = 0x3e,
    DW_AT_external = 0x3f,
    DW_AT_frame_base = 0x40,
    DW_AT_friend = 0x41,
    DW_AT_identifier_case = 0x42,
    /* Reserved 0x43 */
    DW_AT_namelist_item = 0x44,
    DW_AT_priority = 0x45,
    DW_AT_segment = 0x46,
    DW_AT_specification = 0x47,
    DW_AT_static_link = 0x48,
    DW_AT_type = 0x49,
    DW_AT_use_location = 0x4a,
    DW_AT_variable_parameter = 0x4b,
    DW_AT_virtuality = 0x4c,
    DW_AT_vtable_elem_location = 0x4d,
    DW_AT_allocated = 0x4e,
    DW_AT_associated = 0x4f,
    DW_AT_data_location = 0x50,
    DW_AT_byte_stride = 0x51,
    DW_AT_entry_pc = 0x52,
    DW_AT_use_UTF8 = 0x53,
    DW_AT_extension = 0x54,
    DW_AT_ranges = 0x55,
    DW_AT_trampoline = 0x56,
    DW_AT_call_column = 0x57,
    DW_AT_call_file = 0x58,
    DW_AT_call_line = 0x59,
    DW_AT_description = 0x5a,
    DW_AT_binary_scale = 0x5b,
    DW_AT_decimal_scale = 0x5c,
    DW_AT_small = 0x5d,
    DW_AT_decimal_sign = 0x5e,
    DW_AT_digit_count = 0x5f,
    DW_AT_picture_string = 0x60,
    DW_AT_mutable = 0x61,
    DW_AT_threads_scaled = 0x62,
    DW_AT_explicit = 0x63,
    DW_AT_object_pointer = 0x64,
    DW_AT_endianity = 0x65,
    DW_AT_elemental = 0x66,
    DW_AT_pure = 0x67,
    DW_AT_recursive = 0x68,
    DW_AT_signature = 0x69,
    DW_AT_main_subprogram = 0x6a,
    DW_AT_data_bit_offset = 0x6b,
    DW_AT_const_expr = 0x6c,
    DW_AT_enum_class = 0x6d,
    DW_AT_linkage_name = 0x6e,
    DW_AT_string_length_bit_size = 0x6f,
    DW_AT_string_length_byte_size = 0x70,
    DW_AT_rank = 0x71,
    DW_AT_str_offsets_base = 0x72,
    DW_AT_addr_base = 0x73,
    DW_AT_rnglists_base = 0x74,
    /* Reserved 0x75 */
    DW_AT_dwo_name = 0x76,
    DW_AT_reference = 0x77,
    DW_AT_rvalue_reference = 0x78,
    DW_AT_macros = 0x79,
    DW_AT_call_all_calls = 0x7a,
    DW_AT_call_all_source_calls = 0x7b,
    DW_AT_call_all_tail_calls = 0x7c,
    DW_AT_call_return_pc = 0x7d,
    DW_AT_call_value = 0x7e,
    DW_AT_call_origin = 0x7f,
    DW_AT_call_parameter = 0x80,
    DW_AT_call_pc = 0x81,
    DW_AT_call_tail_call = 0x82,
    DW_AT_call_target = 0x83,
    DW_AT_call_target_clobbered = 0x84,
    DW_AT_call_data_location = 0x85,
    DW_AT_call_data_value = 0x86,
    DW_AT_noreturn = 0x87,
    DW_AT_alignment = 0x88,
    DW_AT_export_symbols = 0x89,
    DW_AT_deleted = 0x8a,
    DW_AT_defaulted = 0x8b,
    DW_AT_loclists_base = 0x8c,
    DW_AT_lo_user = 0x2000,
    DW_AT_hi_user = 0x3fff
};

/* Attribute form encodings */
enum
{
    DW_FORM_addr = 0x01,
    /* Reserved 0x02 */
    DW_FORM_block2 = 0x03,
    DW_FORM_block4 = 0x04,
    DW_FORM_data2 = 0x05,
    DW_FORM_data4 = 0x06,
    DW_FORM_data8 = 0x07,
    DW_FORM_string = 0x08,
    DW_FORM_block = 0x09,
    DW_FORM_block1 = 0x0a,
    DW_FORM_data1 = 0x0b,
    DW_FORM_flag = 0x0c,
    DW_FORM_sdata = 0x0d,
    DW_FORM_strp = 0x0e,
    DW_FORM_udata = 0x0f,
    DW_FORM_ref_addr = 0x10,
    DW_FORM_ref1 = 0x11,
    DW_FORM_ref2 = 0x12,
    DW_FORM_ref4 = 0x13,
    DW_FORM_ref8 = 0x14,
    DW_FORM_ref_udata = 0x15,
    DW_FORM_indirect = 0x16,
    DW_FORM_sec_offset = 0x17,
    DW_FORM_exprloc = 0x18,
    DW_FORM_flag_present = 0x19,
    DW_FORM_strx = 0x1a,
    DW_FORM_addrx = 0x1b,
    DW_FORM_ref_sup4 = 0x1c,
    DW_FORM_strp_sup = 0x1d,
    DW_FORM_data16 = 0x1e,
    DW_FORM_line_strp = 0x1f,
    DW_FORM_ref_sig8 = 0x20,
    DW_FORM_implicit_const = 0x21,
    DW_FORM_loclistx = 0x22,
    DW_FORM_rnglistx = 0x23,
    DW_FORM_ref_sup8 = 0x24,
    DW_FORM_strx1 = 0x25,
    DW_FORM_strx2 = 0x26,
    DW_FORM_strx3 = 0x27,
    DW_FORM_strx4 = 0x28,
    DW_FORM_addrx1 = 0x29,
    DW_FORM_addrx2 = 0x2a,
    DW_FORM_addrx3 = 0x2b,
    DW_FORM_addrx4 = 0x2c
};

enum {
    VAL_none = 0,
    VAL_cstr = 1,
    VAL_data = 2,
    VAL_uint = 3,
    VAL_int = 4
};

# define ABBREV_TABLE_SIZE 256
typedef struct {
    obj_info_t *obj;
    char *file;
    char *current_cu;
    uint64_t current_low_pc;
    char *debug_line_cu_end;
    char *debug_line_files;
    char *debug_line_directories;
    char *p;
    char *cu_end;
    char *pend;
    char *q0;
    char *q;
    int format; // 4 or 8
    uint8_t address_size;
    int level;
    char *abbrev_table[ABBREV_TABLE_SIZE];
} DebugInfoReader;

typedef struct {
    ptrdiff_t pos;
    int tag;
    int has_children;
} DIE;

typedef struct {
    union {
        char *ptr;
        uint64_t uint64;
        int64_t int64;
    } as;
    uint64_t off;
    uint64_t at;
    uint64_t form;
    size_t size;
    int type;
} DebugInfoValue;

/* TODO: Big Endian */
#define MERGE_2INTS(a,b,sz) (((uint64_t)(b)<<sz)|(a))

static uint16_t
get_uint16(const uint8_t *p)
{
    return (uint16_t)MERGE_2INTS(p[0],p[1],8);
}

static uint32_t
get_uint32(const uint8_t *p)
{
    return (uint32_t)MERGE_2INTS(get_uint16(p),get_uint16(p+2),16);
}

static uint64_t
get_uint64(const uint8_t *p)
{
    return MERGE_2INTS(get_uint32(p),get_uint32(p+4),32);
}

static uint8_t
read_uint8(char **ptr)
{
    const unsigned char *p = (const unsigned char *)*ptr;
    *ptr = (char *)(p + 1);
    return *p;
}

static uint16_t
read_uint16(char **ptr)
{
    const unsigned char *p = (const unsigned char *)*ptr;
    *ptr = (char *)(p + 2);
    return get_uint16(p);
}

static uint32_t
read_uint24(char **ptr)
{
    const unsigned char *p = (const unsigned char *)*ptr;
    *ptr = (char *)(p + 3);
    return (*p << 16) | get_uint16(p+1);
}

static uint32_t
read_uint32(char **ptr)
{
    const unsigned char *p = (const unsigned char *)*ptr;
    *ptr = (char *)(p + 4);
    return get_uint32(p);
}

static uint64_t
read_uint64(char **ptr)
{
    const unsigned char *p = (const unsigned char *)*ptr;
    *ptr = (char *)(p + 8);
    return get_uint64(p);
}

static uintptr_t
read_uintptr(char **ptr)
{
    const unsigned char *p = (const unsigned char *)*ptr;
    *ptr = (char *)(p + SIZEOF_VOIDP);
#if SIZEOF_VOIDP == 8
    return get_uint64(p);
#else
    return get_uint32(p);
#endif
}

static uint64_t
read_uint(DebugInfoReader *reader)
{
    if (reader->format == 4) {
        return read_uint32(&reader->p);
    } else { /* 64 bit */
        return read_uint64(&reader->p);
    }
}

static uint64_t
read_uleb128(DebugInfoReader *reader)
{
    return uleb128(&reader->p);
}

static int64_t
read_sleb128(DebugInfoReader *reader)
{
    return sleb128(&reader->p);
}

static void
debug_info_reader_init(DebugInfoReader *reader, obj_info_t *obj)
{
    reader->file = obj->mapped;
    reader->obj = obj;
    reader->p = obj->debug_info.ptr;
    reader->pend = obj->debug_info.ptr + obj->debug_info.size;
    reader->debug_line_cu_end = obj->debug_line.ptr;
    reader->current_low_pc = 0;
}

static void
di_read_debug_abbrev_cu(DebugInfoReader *reader)
{
    uint64_t prev = 0;
    char *p = reader->q0;
    for (;;) {
        uint64_t abbrev_number = uleb128(&p);
        if (abbrev_number <= prev) break;
        if (abbrev_number < ABBREV_TABLE_SIZE) {
            reader->abbrev_table[abbrev_number] = p;
        }
        prev = abbrev_number;
        uleb128(&p); /* tag */
        p++; /* has_children */
        /* skip content */
        for (;;) {
            uint64_t at = uleb128(&p);
            uint64_t form = uleb128(&p);
            if (!at && !form) break;
        }
    }
}

static int
di_read_debug_line_cu(DebugInfoReader *reader)
{
    const char *p;
    struct LineNumberProgramHeader header;

    p = (const char *)reader->debug_line_cu_end;
    if (parse_debug_line_header(&p, &header))
        return -1;

    reader->debug_line_cu_end = (char *)header.cu_end;
    reader->debug_line_directories = (char *)header.include_directories;
    reader->debug_line_files = (char *)header.filenames;

    return 0;
}

static void
set_uint_value(DebugInfoValue *v, uint64_t n)
{
    v->as.uint64 = n;
    v->type = VAL_uint;
}

static void
set_int_value(DebugInfoValue *v, int64_t n)
{
    v->as.int64 = n;
    v->type = VAL_int;
}

static void
set_cstr_value(DebugInfoValue *v, char *s)
{
    v->as.ptr = s;
    v->off = 0;
    v->type = VAL_cstr;
}

static void
set_cstrp_value(DebugInfoValue *v, char *s, uint64_t off)
{
    v->as.ptr = s;
    v->off = off;
    v->type = VAL_cstr;
}

static void
set_data_value(DebugInfoValue *v, char *s)
{
    v->as.ptr = s;
    v->type = VAL_data;
}

static const char *
get_cstr_value(DebugInfoValue *v)
{
    if (v->as.ptr) {
        return v->as.ptr + v->off;
    } else {
        return NULL;
    }
}

static void
debug_info_reader_read_value(DebugInfoReader *reader, uint64_t form, DebugInfoValue *v)
{
    switch (form) {
      case DW_FORM_addr:
        if (reader->address_size == 4) {
            set_uint_value(v, read_uint32(&reader->p));
        } else if (reader->address_size == 8) {
            set_uint_value(v, read_uint64(&reader->p));
        } else {
            fprintf(stderr,"unknown address_size:%d", reader->address_size);
            abort();
        }
        break;
      case DW_FORM_block2:
        v->size = read_uint16(&reader->p);
        set_data_value(v, reader->p);
        reader->p += v->size;
        break;
      case DW_FORM_block4:
        v->size = read_uint32(&reader->p);
        set_data_value(v, reader->p);
        reader->p += v->size;
        break;
      case DW_FORM_data2:
        set_uint_value(v, read_uint16(&reader->p));
        break;
      case DW_FORM_data4:
        set_uint_value(v, read_uint32(&reader->p));
        break;
      case DW_FORM_data8:
        set_uint_value(v, read_uint64(&reader->p));
        break;
      case DW_FORM_string:
        v->size = strlen(reader->p);
        set_cstr_value(v, reader->p);
        reader->p += v->size + 1;
        break;
      case DW_FORM_block:
        v->size = uleb128(&reader->p);
        set_data_value(v, reader->p);
        reader->p += v->size;
        break;
      case DW_FORM_block1:
        v->size = read_uint8(&reader->p);
        set_data_value(v, reader->p);
        reader->p += v->size;
        break;
      case DW_FORM_data1:
        set_uint_value(v, read_uint8(&reader->p));
        break;
      case DW_FORM_flag:
        set_uint_value(v, read_uint8(&reader->p));
        break;
      case DW_FORM_sdata:
        set_int_value(v, read_sleb128(reader));
        break;
      case DW_FORM_strp:
        set_cstrp_value(v, reader->obj->debug_str.ptr, read_uint(reader));
        break;
      case DW_FORM_udata:
        set_uint_value(v, read_uleb128(reader));
        break;
      case DW_FORM_ref_addr:
        if (reader->address_size == 4) {
            set_uint_value(v, read_uint32(&reader->p));
        } else if (reader->address_size == 8) {
            set_uint_value(v, read_uint64(&reader->p));
        } else {
            fprintf(stderr,"unknown address_size:%d", reader->address_size);
            abort();
        }
        break;
      case DW_FORM_ref1:
        set_uint_value(v, read_uint8(&reader->p));
        break;
      case DW_FORM_ref2:
        set_uint_value(v, read_uint16(&reader->p));
        break;
      case DW_FORM_ref4:
        set_uint_value(v, read_uint32(&reader->p));
        break;
      case DW_FORM_ref8:
        set_uint_value(v, read_uint64(&reader->p));
        break;
      case DW_FORM_ref_udata:
        set_uint_value(v, uleb128(&reader->p));
        break;
      case DW_FORM_indirect:
        /* TODO: read the referred value */
        set_uint_value(v, uleb128(&reader->p));
        break;
      case DW_FORM_sec_offset:
        set_uint_value(v, read_uint(reader)); /* offset */
        /* addrptr: debug_addr */
        /* lineptr: debug_line */
        /* loclist: debug_loclists */
        /* loclistptr: debug_loclists */
        /* macptr: debug_macro */
        /* rnglist: debug_rnglists */
        /* rnglistptr: debug_rnglists */
        /* stroffsetsptr: debug_str_offsets */
        break;
      case DW_FORM_exprloc:
        v->size = (size_t)read_uleb128(reader);
        set_data_value(v, reader->p);
        reader->p += v->size;
        break;
      case DW_FORM_flag_present:
        set_uint_value(v, 1);
        break;
      case DW_FORM_strx:
        set_uint_value(v, uleb128(&reader->p));
        break;
      case DW_FORM_addrx:
        /* TODO: read .debug_addr */
        set_uint_value(v, uleb128(&reader->p));
        break;
      case DW_FORM_ref_sup4:
        set_uint_value(v, read_uint32(&reader->p));
        break;
      case DW_FORM_strp_sup:
        set_uint_value(v, read_uint(reader));
        /* *p = reader->sup_file + reader->sup_str->sh_offset + ret; */
        break;
      case DW_FORM_data16:
        v->size = 16;
        set_data_value(v, reader->p);
        reader->p += v->size;
        break;
      case DW_FORM_line_strp:
        set_uint_value(v, read_uint(reader));
        /* *p = reader->file + reader->line->sh_offset + ret; */
        break;
      case DW_FORM_ref_sig8:
        set_uint_value(v, read_uint64(&reader->p));
        break;
      case DW_FORM_implicit_const:
        set_int_value(v, sleb128(&reader->q));
        break;
      case DW_FORM_loclistx:
        set_uint_value(v, read_uleb128(reader));
        break;
      case DW_FORM_rnglistx:
        set_uint_value(v, read_uleb128(reader));
        break;
      case DW_FORM_ref_sup8:
        set_uint_value(v, read_uint64(&reader->p));
        break;
      case DW_FORM_strx1:
        set_uint_value(v, read_uint8(&reader->p));
        break;
      case DW_FORM_strx2:
        set_uint_value(v, read_uint16(&reader->p));
        break;
      case DW_FORM_strx3:
        set_uint_value(v, read_uint24(&reader->p));
        break;
      case DW_FORM_strx4:
        set_uint_value(v, read_uint32(&reader->p));
        break;
      case DW_FORM_addrx1:
        set_uint_value(v, read_uint8(&reader->p));
        break;
      case DW_FORM_addrx2:
        set_uint_value(v, read_uint16(&reader->p));
        break;
      case DW_FORM_addrx3:
        set_uint_value(v, read_uint24(&reader->p));
        break;
      case DW_FORM_addrx4:
        set_uint_value(v, read_uint32(&reader->p));
        break;
      case 0:
        goto fail;
        break;
    }
    return;

  fail:
    fprintf(stderr, "%d: unsupported form: %#"PRIx64"\n", __LINE__, form);
    exit(1);
}

/* find abbrev in current compilation unit */
static char *
di_find_abbrev(DebugInfoReader *reader, uint64_t abbrev_number)
{
    char *p;
    if (abbrev_number < ABBREV_TABLE_SIZE) {
        return reader->abbrev_table[abbrev_number];
    }
    p = reader->abbrev_table[ABBREV_TABLE_SIZE-1];
    /* skip 255th record */
    uleb128(&p); /* tag */
    p++; /* has_children */
    /* skip content */
    for (;;) {
        uint64_t at = uleb128(&p);
        uint64_t form = uleb128(&p);
        if (!at && !form) break;
    }
    for (uint64_t n = uleb128(&p); abbrev_number != n; n = uleb128(&p)) {
        if (n == 0) {
            fprintf(stderr,"%d: Abbrev Number %"PRId64" not found\n",__LINE__, abbrev_number);
            exit(1);
        }
        uleb128(&p); /* tag */
        p++; /* has_children */
        /* skip content */
        for (;;) {
            uint64_t at = uleb128(&p);
            uint64_t form = uleb128(&p);
            if (!at && !form) break;
        }
    }
    return p;
}

#if 0
static void
hexdump0(const unsigned char *p, size_t n)
{
    size_t i;
    fprintf(stderr, "     0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F\n");
    for (i=0; i < n; i++){
        switch (i & 15) {
          case 0:
            fprintf(stderr, "%02zd: %02X ", i/16, p[i]);
            break;
          case 15:
            fprintf(stderr, "%02X\n", p[i]);
            break;
          default:
            fprintf(stderr, "%02X ", p[i]);
            break;
        }
    }
    if ((i & 15) != 15) {
        fprintf(stderr, "\n");
    }
}
#define hexdump(p,n) hexdump0((const unsigned char *)p, n)

static void
div_inspect(DebugInfoValue *v)
{
    switch (v->type) {
      case VAL_uint:
        fprintf(stderr,"%d: type:%d size:%zx v:%lx\n",__LINE__,v->type,v->size,v->as.uint64);
        break;
      case VAL_int:
        fprintf(stderr,"%d: type:%d size:%zx v:%ld\n",__LINE__,v->type,v->size,(int64_t)v->as.uint64);
        break;
      case VAL_cstr:
        fprintf(stderr,"%d: type:%d size:%zx v:'%s'\n",__LINE__,v->type,v->size,v->as.ptr);
        break;
      case VAL_data:
        fprintf(stderr,"%d: type:%d size:%zx v:\n",__LINE__,v->type,v->size);
        hexdump(v->as.ptr, 16);
        break;
    }
}
#endif

static DIE *
di_read_die(DebugInfoReader *reader, DIE *die)
{
    uint64_t abbrev_number = uleb128(&reader->p);
    if (abbrev_number == 0) {
        reader->level--;
        return NULL;
    }

    reader->q = di_find_abbrev(reader, abbrev_number);

    die->pos = reader->p - reader->obj->debug_info.ptr - 1;
    die->tag = (int)uleb128(&reader->q); /* tag */
    die->has_children = *reader->q++; /* has_children */
    if (die->has_children) {
        reader->level++;
    }
    return die;
}

static DebugInfoValue *
di_read_record(DebugInfoReader *reader, DebugInfoValue *vp)
{
    uint64_t at = uleb128(&reader->q);
    uint64_t form = uleb128(&reader->q);
    if (!at || !form) return NULL;
    vp->at = at;
    vp->form = form;
    debug_info_reader_read_value(reader, form, vp);
    return vp;
}

static void
di_skip_records(DebugInfoReader *reader)
{
    for (;;) {
        DebugInfoValue v = {{}};
        uint64_t at = uleb128(&reader->q);
        uint64_t form = uleb128(&reader->q);
        if (!at || !form) return;
        debug_info_reader_read_value(reader, form, &v);
    }
}

typedef struct {
    uint64_t low_pc;
    uint64_t high_pc;
    uint64_t ranges;
    bool low_pc_set;
    bool high_pc_set;
    bool ranges_set;
} ranges_t;

static void
ranges_set(ranges_t *ptr, DebugInfoValue *v)
{
    switch (v->at) {
      case DW_AT_low_pc:
        ptr->low_pc = v->as.uint64;
        ptr->low_pc_set = true;
        break;
      case DW_AT_high_pc:
        if (v->form == DW_FORM_addr) {
            ptr->high_pc = v->as.uint64;
        }
        else {
            ptr->high_pc = ptr->low_pc + v->as.uint64;
        }
        ptr->high_pc_set = true;
        break;
      case DW_AT_ranges:
        ptr->ranges = v->as.uint64;
        ptr->ranges_set = true;
        break;
    }
}

static uintptr_t
ranges_include(DebugInfoReader *reader, ranges_t *ptr, uint64_t addr)
{
    if (ptr->high_pc_set) {
        if (ptr->ranges_set || !ptr->low_pc_set) {
            exit(1);
        }
        if (ptr->low_pc <= addr && addr <= ptr->high_pc) {
            return (uintptr_t)ptr->low_pc;
        }
    }
    else if (ptr->ranges_set) {
        /* TODO: support base address selection entry */
        char *p = reader->obj->debug_ranges.ptr + ptr->ranges;
        uint64_t base = ptr->low_pc_set ? ptr->low_pc : reader->current_low_pc;
        for (;;) {
            uintptr_t from = read_uintptr(&p);
            uintptr_t to = read_uintptr(&p);
            if (!from && !to) break;
            if (from == UINTPTR_MAX) {
                /* base address selection entry */
                base = to;
            }
            else if (base + from <= addr && addr < base + to) {
                return from;
            }
        }
    }
    else if (ptr->low_pc_set) {
        if (ptr->low_pc == addr) {
            return (uintptr_t)ptr->low_pc;
        }
    }
    return false;
}

#if 0
static void
ranges_inspect(DebugInfoReader *reader, ranges_t *ptr)
{
    if (ptr->high_pc_set) {
        if (ptr->ranges_set || !ptr->low_pc_set) {
            fprintf(stderr,"low_pc_set:%d high_pc_set:%d ranges_set:%d\n",ptr->low_pc_set,ptr->high_pc_set,ptr->ranges_set);
            exit(1);
        }
        fprintf(stderr,"low_pc:%"PRIx64" high_pc:%"PRIx64"\n",ptr->low_pc,ptr->high_pc);
    }
    else if (ptr->ranges_set) {
        char *p = reader->obj->debug_ranges.ptr + ptr->ranges;
        fprintf(stderr,"low_pc:%"PRIx64" ranges:%"PRIx64" %lx ",ptr->low_pc,ptr->ranges, p-reader->obj->mapped);
        for (;;) {
            uintptr_t from = read_uintptr(&p);
            uintptr_t to = read_uintptr(&p);
            if (!from && !to) break;
            fprintf(stderr,"%"PRIx64"-%"PRIx64" ",ptr->low_pc+from,ptr->low_pc+to);
        }
        fprintf(stderr,"\n");
    }
    else if (ptr->low_pc_set) {
        fprintf(stderr,"low_pc:%"PRIx64"\n",ptr->low_pc);
    }
    else {
        fprintf(stderr,"empty\n");
    }
}
#endif

static int
di_read_cu(DebugInfoReader *reader)
{
    uint64_t unit_length;
    uint16_t version;
    uint64_t debug_abbrev_offset;
    reader->format = 4;
    reader->current_cu = reader->p;
    unit_length = read_uint32(&reader->p);
    if (unit_length == 0xffffffff) {
        unit_length = read_uint64(&reader->p);
        reader->format = 8;
    }
    reader->cu_end = reader->p + unit_length;
    version = read_uint16(&reader->p);
    if (version > 5) {
        return -1;
    }
    else if (version == 5) {
        /* unit_type = */ read_uint8(&reader->p);
        reader->address_size = read_uint8(&reader->p);
        debug_abbrev_offset = read_uint(reader);
    }
    else {
        debug_abbrev_offset = read_uint(reader);
        reader->address_size = read_uint8(&reader->p);
    }
    reader->q0 = reader->obj->debug_abbrev.ptr + debug_abbrev_offset;

    reader->level = 0;
    di_read_debug_abbrev_cu(reader);
    if (di_read_debug_line_cu(reader)) return -1;

#if defined(__GNUC__) && !defined(__clang__) && !defined(__INTEL_COMPILER_BUILD_DATE)
    /* Though DWARF specifies "the applicable base address defaults to the base
       address of the compilation unit", but GCC seems to use zero as default */
#else
    do {
        DIE die;

        if (!di_read_die(reader, &die)) continue;

        if (die.tag != DW_TAG_compile_unit) {
            di_skip_records(reader);
            break;
        }

        /* enumerate abbrev */
        for (;;) {
            DebugInfoValue v = {{}};
            if (!di_read_record(reader, &v)) break;
            switch (v.at) {
              case DW_AT_low_pc:
                reader->current_low_pc = v.as.uint64;
                break;
            }
        }
    } while (0);
#endif
    return 0;
}

static void
read_abstract_origin(DebugInfoReader *reader, uint64_t abstract_origin, line_info_t *line)
{
    char *p = reader->p;
    char *q = reader->q;
    int level = reader->level;
    DIE die;

    reader->p = reader->current_cu + abstract_origin;
    if (!di_read_die(reader, &die)) goto finish;

    /* enumerate abbrev */
    for (;;) {
        DebugInfoValue v = {{}};
        if (!di_read_record(reader, &v)) break;
        switch (v.at) {
          case DW_AT_name:
            line->sname = get_cstr_value(&v);
            break;
        }
    }

  finish:
    reader->p = p;
    reader->q = q;
    reader->level = level;
}

static void
debug_info_read(DebugInfoReader *reader, int num_traces, void **traces,
         line_info_t *lines, int offset) {
    while (reader->p < reader->cu_end) {
        DIE die;
        ranges_t ranges = {};
        line_info_t line = {};

        if (!di_read_die(reader, &die)) continue;
        /* fprintf(stderr,"%d:%tx: <%d>\n",__LINE__,die.pos,reader->level,die.tag); */

        if (die.tag != DW_TAG_subprogram && die.tag != DW_TAG_inlined_subroutine) {
          skip_die:
            di_skip_records(reader);
            continue;
        }

        /* enumerate abbrev */
        for (;;) {
            DebugInfoValue v = {{}};
            /* ptrdiff_t pos = reader->p - reader->p0; */
            if (!di_read_record(reader, &v)) break;
            /* fprintf(stderr,"\n%d:%tx: AT:%lx FORM:%lx\n",__LINE__,pos,v.at,v.form); */
            /* div_inspect(&v); */
            switch (v.at) {
              case DW_AT_name:
                line.sname = get_cstr_value(&v);
                break;
              case DW_AT_call_file:
                fill_filename((int)v.as.uint64, reader->debug_line_directories, reader->debug_line_files, &line, reader->obj);
                break;
              case DW_AT_call_line:
                line.line = (int)v.as.uint64;
                break;
              case DW_AT_low_pc:
              case DW_AT_high_pc:
              case DW_AT_ranges:
                ranges_set(&ranges, &v);
                break;
              case DW_AT_declaration:
                goto skip_die;
              case DW_AT_inline:
                /* 1 or 3 */
                break; /* goto skip_die; */
              case DW_AT_abstract_origin:
                read_abstract_origin(reader, v.as.uint64, &line);
                break; /* goto skip_die; */
            }
        }
        /* ranges_inspect(reader, &ranges); */
        /* fprintf(stderr,"%d:%tx: %x ",__LINE__,diepos,die.tag); */
        for (int i=offset; i < num_traces; i++) {
            uintptr_t addr = (uintptr_t)traces[i];
            uintptr_t offset = addr - reader->obj->base_addr + reader->obj->vmaddr;
            uintptr_t saddr = ranges_include(reader, &ranges, offset);
            if (saddr) {
                /* fprintf(stderr, "%d:%tx: %d %lx->%lx %x %s: %s/%s %d %s %s %s\n",__LINE__,die.pos, i,addr,offset, die.tag,line.sname,line.dirname,line.filename,line.line,reader->obj->path,line.sname,lines[i].sname); */
                if (lines[i].sname) {
                    line_info_t *lp = malloc(sizeof(line_info_t));
                    memcpy(lp, &lines[i], sizeof(line_info_t));
                    lines[i].next = lp;
                    lp->dirname = line.dirname;
                    lp->filename = line.filename;
                    lp->line = line.line;
                    lp->saddr = 0;
                }
                lines[i].path = reader->obj->path;
                lines[i].base_addr = line.base_addr;
                lines[i].sname = line.sname;
                lines[i].saddr = saddr + reader->obj->base_addr - reader->obj->vmaddr;
            }
        }
    }
}

#ifdef USE_ELF
static unsigned long
uncompress_debug_section(ElfW(Shdr) *shdr, char *file, char **ptr)
{
#ifdef SUPPORT_COMPRESSED_DEBUG_LINE
    ElfW(Chdr) *chdr = (ElfW(Chdr) *)(file + shdr->sh_offset);
    unsigned long destsize = chdr->ch_size;
    int ret = 0;

    if (chdr->ch_type != ELFCOMPRESS_ZLIB) {
	/* unsupported compression type */
	return 0;
    }

    *ptr = malloc(destsize);
    if (!*ptr) return 0;
    ret = uncompress((Bytef *)*ptr, &destsize,
	    (const Bytef*)chdr + sizeof(ElfW(Chdr)),
            shdr->sh_size - sizeof(ElfW(Chdr)));
    if (ret != Z_OK) goto fail;
    return destsize;

fail:
    free(*ptr);
#endif
    return 0;
}

/* read file and fill lines */
static uintptr_t
fill_lines(int num_traces, void **traces, int check_debuglink,
	   obj_info_t **objp, line_info_t *lines, int offset)
{
    int i, j;
    char *shstr;
    ElfW(Ehdr) *ehdr;
    ElfW(Shdr) *shdr, *shstr_shdr;
    ElfW(Shdr) *gnu_debuglink_shdr = NULL;
    ElfW(Shdr) *note_gnu_build_id = NULL;
    int fd;
    off_t filesize;
    char *file;
    ElfW(Shdr) *symtab_shdr = NULL, *strtab_shdr = NULL;
    ElfW(Shdr) *dynsym_shdr = NULL, *dynstr_shdr = NULL;
    obj_info_t *obj = *objp;
    uintptr_t dladdr_fbase = 0;

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
    close(fd);

    ehdr = (ElfW(Ehdr) *)file;
    if (memcmp(ehdr->e_ident, "\177ELF", 4) != 0) {
	/*
	 * Huh? Maybe filename was overridden by setproctitle() and
	 * it match non-elf file.
	 */
	goto fail;
    }
    obj->mapped = file;
    obj->mapped_size = (size_t)filesize;

    shdr = (ElfW(Shdr) *)(file + ehdr->e_shoff);

    shstr_shdr = shdr + ehdr->e_shstrndx;
    shstr = file + shstr_shdr->sh_offset;

    for (i = 0; i < ehdr->e_shnum; i++) {
        char *section_name = shstr + shdr[i].sh_name;
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
          case SHT_NOTE:
            if (!strcmp(section_name, ".note.gnu.build-id")) {
                note_gnu_build_id = shdr + i;
            }
            break;
	  case SHT_PROGBITS:
	    if (!strcmp(section_name, ".gnu_debuglink")) {
		gnu_debuglink_shdr = shdr + i;
	    }
            else {
                const char *debug_section_names[] = {
                    ".debug_abbrev",
                    ".debug_info",
                    ".debug_line",
                    ".debug_ranges",
                    ".debug_str"
                };

                for (j=0; j < DWARF_SECTION_COUNT; j++) {
                    struct dwarf_section *s = obj_dwarf_section_at(obj, j);

                    if (strcmp(section_name, debug_section_names[j]) != 0)
                        continue;

                    s->ptr = file + shdr[i].sh_offset;
                    s->size = shdr[i].sh_size;
                    s->flags = shdr[i].sh_flags;
                    if (s->flags & SHF_COMPRESSED) {
                        s->size = uncompress_debug_section(&shdr[i], file, &s->ptr);
                        if (!s->size) goto fail;
                    }
                    break;
                }
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
            void *handle = dlopen(NULL, RTLD_NOW|RTLD_LOCAL);
            if (handle) {
                for (j = 0; j < symtab_count; j++) {
                    ElfW(Sym) *sym = &symtab[j];
                    Dl_info info;
                    void *s;
                    if (ELF_ST_TYPE(sym->st_info) != STT_FUNC || sym->st_size == 0) continue;
                    s = dlsym(handle, strtab + sym->st_name);
                    if (s && dladdr(s, &info)) {
                        obj->base_addr = dladdr_fbase;
                        dladdr_fbase = (uintptr_t)info.dli_fbase;
                        break;
                    }
                }
                dlclose(handle);
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

    if (obj->debug_info.ptr && obj->debug_abbrev.ptr) {
        DebugInfoReader reader;
        debug_info_reader_init(&reader, obj);
        i = 0;
        while (reader.p < reader.pend) {
            /* fprintf(stderr, "%d:%tx: CU[%d]\n", __LINE__, reader.p - reader.obj->debug_info.ptr, i++); */
            if (di_read_cu(&reader)) goto use_symtab;
            debug_info_read(&reader, num_traces, traces, lines, offset);
        }
    }
    else {
        /* This file doesn't have dwarf, use symtab or dynsym */
use_symtab:
        if (!symtab_shdr) {
            /* This file doesn't have symtab, use dynsym instead */
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
                if (ELF_ST_TYPE(sym->st_info) != STT_FUNC) continue;
                for (i = offset; i < num_traces; i++) {
                    uintptr_t d = (uintptr_t)traces[i] - saddr;
                    if (lines[i].line > 0 || d > (uintptr_t)sym->st_size)
                        continue;
                    /* fill symbol name and addr from .symtab */
                    if (!lines[i].sname) lines[i].sname = strtab + sym->st_name;
                    lines[i].saddr = saddr;
                    lines[i].path  = obj->path;
                    lines[i].base_addr = obj->base_addr;
                }
            }
        }
    }

    if (!obj->debug_line.ptr) {
	/* This file doesn't have .debug_line section,
	   let's check .gnu_debuglink section instead. */
	if (gnu_debuglink_shdr && check_debuglink) {
	    follow_debuglink(file + gnu_debuglink_shdr->sh_offset,
			     num_traces, traces,
			     objp, lines, offset);
	}
        if (note_gnu_build_id && check_debuglink) {
            ElfW(Nhdr) *nhdr = (ElfW(Nhdr)*) (file + note_gnu_build_id->sh_offset);
            const char *build_id = (char *)(nhdr + 1) + nhdr->n_namesz;
            follow_debuglink_build_id(build_id, nhdr->n_descsz,
			       num_traces, traces,
			       objp, lines, offset);
        }
	goto finish;
    }

    if (parse_debug_line(num_traces, traces,
            obj->debug_line.ptr,
            obj->debug_line.size,
            obj, lines, offset) == -1)
        goto fail;

finish:
    return dladdr_fbase;
fail:
    return (uintptr_t)-1;
}
#else /* Mach-O */
/* read file and fill lines */
static uintptr_t
fill_lines(int num_traces, void **traces, int check_debuglink,
        obj_info_t **objp, line_info_t *lines, int offset)
{
# ifdef __LP64__
#  define LP(x) x##_64
# else
#  define LP(x) x
# endif
    int fd;
    off_t filesize;
    char *file, *p = NULL;
    obj_info_t *obj = *objp;
    struct LP(mach_header) *header;
    uintptr_t dladdr_fbase = 0;

    {
        char *s = binary_filename;
        char *base = strrchr(binary_filename, '/')+1;
        size_t max = PATH_MAX;
        size_t size = strlen(binary_filename);
        size_t basesize = size - (base - binary_filename);
        s += size;
        max -= size;
        p = s;
        size = strlcpy(s, ".dSYM/Contents/Resources/DWARF/", max);
        if (size == 0) goto fail;
        s += size;
        max -= size;
        if (max <= basesize) goto fail;
        memcpy(s, base, basesize);
        s[basesize] = 0;

        fd = open(binary_filename, O_RDONLY);
        if (fd < 0) {
            *p = 0; /* binary_filename becomes original file name */
            fd = open(binary_filename, O_RDONLY);
            if (fd < 0) {
                goto fail;
            }
        }
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
    close(fd);

    obj->mapped = file;
    obj->mapped_size = (size_t)filesize;

    header = (struct LP(mach_header) *)file;
    if (header->magic == LP(MH_MAGIC)) {
        /* non universal binary */
        p = file;
    }
    else if (header->magic == FAT_CIGAM) {
        struct LP(mach_header) *mhp = _NSGetMachExecuteHeader();
        struct fat_header *fat = (struct fat_header *)file;
        char *q = file + sizeof(*fat);
        uint32_t nfat_arch = __builtin_bswap32(fat->nfat_arch);
        /* fprintf(stderr,"%d: fat:%s %d\n",__LINE__, binary_filename,nfat_arch); */
        for (uint32_t i = 0; i < nfat_arch; i++) {
            struct fat_arch *arch = (struct fat_arch *)q;
            cpu_type_t cputype = __builtin_bswap32(arch->cputype);
            cpu_subtype_t cpusubtype = __builtin_bswap32(arch->cpusubtype);
            uint32_t offset = __builtin_bswap32(arch->offset);
            /* fprintf(stderr,"%d: fat %d %x/%x %x/%x\n",__LINE__, i, mhp->cputype,mhp->cpusubtype, cputype,cpusubtype); */
            if (mhp->cputype == cputype &&
                    (cpu_subtype_t)(mhp->cpusubtype & ~CPU_SUBTYPE_MASK) == cpusubtype) {
                p = file + offset;
                file = p;
                header = (struct LP(mach_header) *)p;
                if (header->magic == LP(MH_MAGIC)) {
                    goto found_mach_header;
                }
                break;
            }
            q += sizeof(*arch);
        }
        kprintf("'%s' is not a Mach-O universal binary file!\n",binary_filename);
        close(fd);
        goto fail;
    }
    else {
        kprintf("'%s' is not a "
# ifdef __LP64__
                "64"
# else
                "32"
# endif
                "-bit Mach-O file!\n",binary_filename);
        close(fd);
        goto fail;
    }
found_mach_header:
    p += sizeof(*header);

    for (uint32_t i = 0; i < (uint32_t)header->ncmds; i++) {
        struct load_command *lcmd = (struct load_command *)p;
        switch (lcmd->cmd) {
          case LP(LC_SEGMENT):
            {
                static const char *debug_section_names[] = {
                    "__debug_abbrev",
                    "__debug_info",
                    "__debug_line",
                    "__debug_ranges",
                    "__debug_str"
                };
                struct LP(segment_command) *scmd = (struct LP(segment_command) *)lcmd;
                if (strcmp(scmd->segname, "__TEXT") == 0) {
                    obj->vmaddr = scmd->vmaddr;
                }
                else if (strcmp(scmd->segname, "__DWARF") == 0) {
                    p += sizeof(struct LP(segment_command));
                    for (uint64_t i = 0; i < scmd->nsects; i++) {
                        struct LP(section) *sect = (struct LP(section) *)p;
                        p += sizeof(struct LP(section));
                        for (int j=0; j < DWARF_SECTION_COUNT; j++) {
                            struct dwarf_section *s = obj_dwarf_section_at(obj, j);

                            if (strcmp(sect->sectname, debug_section_names[j]) != 0)
                                continue;

                            s->ptr = file + sect->offset;
                            s->size = sect->size;
                            s->flags = sect->flags;
                            if (s->flags & SHF_COMPRESSED) {
                                goto fail;
                            }
                            break;
                        }
                    }
                }
            }
            break;

          case LC_SYMTAB:
            {
                struct symtab_command *cmd = (struct symtab_command *)lcmd;
                struct LP(nlist) *nl = (struct LP(nlist) *)(file + cmd->symoff);
                char *strtab = file + cmd->stroff, *sname = 0;
                uint32_t j;
                uintptr_t saddr = 0;
                /* kprintf("[%2d]: %x/symtab %p\n", i, cmd->cmd, p); */
                for (j = 0; j < cmd->nsyms; j++) {
                    uintptr_t symsize, d;
                    struct LP(nlist) *e = &nl[j];
                        /* kprintf("[%2d][%4d]: %02x/%x/%x: %s %llx\n", i, j, e->n_type,e->n_sect,e->n_desc,strtab+e->n_un.n_strx,e->n_value); */
                    if (e->n_type != N_FUN) continue;
                    if (e->n_sect) {
                        saddr = (uintptr_t)e->n_value + obj->base_addr - obj->vmaddr;
                        sname = strtab + e->n_un.n_strx;
                        /* kprintf("[%2d][%4d]: %02x/%x/%x: %s %llx\n", i, j, e->n_type,e->n_sect,e->n_desc,strtab+e->n_un.n_strx,e->n_value); */
                        continue;
                    }
                    for (int k = offset; k < num_traces; k++) {
                        d = (uintptr_t)traces[k] - saddr;
                        symsize = e->n_value;
                        /* kprintf("%lx %lx %lx\n",saddr,symsize,traces[k]); */
                        if (lines[k].line > 0 || d > (uintptr_t)symsize)
                            continue;
                        /* fill symbol name and addr from .symtab */
                        if (!lines[k].sname) lines[k].sname = sname;
                        lines[k].saddr = saddr;
                        lines[k].path  = obj->path;
                        lines[k].base_addr = obj->base_addr;
                    }
                }
            }
        }
        p += lcmd->cmdsize;
    }

    if (obj->debug_info.ptr && obj->debug_abbrev.ptr) {
        DebugInfoReader reader;
        debug_info_reader_init(&reader, obj);
        while (reader.p < reader.pend) {
            if (di_read_cu(&reader)) goto fail;
            debug_info_read(&reader, num_traces, traces, lines, offset);
        }
    }

    if (parse_debug_line(num_traces, traces,
            obj->debug_line.ptr,
            obj->debug_line.size,
            obj, lines, offset) == -1)
        goto fail;

    return dladdr_fbase;
fail:
    return (uintptr_t)-1;
}
#endif

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
    if (len < 0) return 0;
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
#elif defined(HAVE_LIBPROC_H)
static ssize_t
main_exe_path(void)
{
    int len = proc_pidpath(getpid(), binary_filename, PATH_MAX);
    if (len == 0) return 0;
    binary_filename[len] = 0;
    return len;
}
#else
#undef HAVE_MAIN_EXE_PATH
#endif

static void
print_line0(line_info_t *line, void *address)
{
    uintptr_t addr = (uintptr_t)address;
    uintptr_t d = addr - line->saddr;
    if (!address) {
        /* inlined */
        if (line->dirname && line->dirname[0]) {
            kprintf("%s(%s) %s/%s:%d\n", line->path, line->sname, line->dirname, line->filename, line->line);
        }
        else {
            kprintf("%s(%s) %s:%d\n", line->path, line->sname, line->filename, line->line);
        }
    }
    else if (!line->path) {
        kprintf("[0x%"PRIxPTR"]\n", addr);
    }
    else if (!line->saddr || !line->sname) {
        kprintf("%s(0x%"PRIxPTR") [0x%"PRIxPTR"]\n", line->path, addr-line->base_addr, addr);
    }
    else if (line->line <= 0) {
        kprintf("%s(%s+0x%"PRIxPTR") [0x%"PRIxPTR"]\n", line->path, line->sname,
                d, addr);
    }
    else if (!line->filename) {
        kprintf("%s(%s+0x%"PRIxPTR") [0x%"PRIxPTR"] ???:%d\n", line->path, line->sname,
                d, addr, line->line);
    }
    else if (line->dirname && line->dirname[0]) {
        kprintf("%s(%s+0x%"PRIxPTR") [0x%"PRIxPTR"] %s/%s:%d\n", line->path, line->sname,
                d, addr, line->dirname, line->filename, line->line);
    }
    else {
        kprintf("%s(%s+0x%"PRIxPTR") [0x%"PRIxPTR"] %s:%d\n", line->path, line->sname,
                d, addr, line->filename, line->line);
    }
}

static void
print_line(line_info_t *line, void *address)
{
    print_line0(line, address);
    if (line->next) {
        print_line(line->next, NULL);
    }
}

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
            lines[i].sname = info.dli_sname;
            lines[i].saddr = (uintptr_t)info.dli_saddr;
	    strlcpy(binary_filename, path, PATH_MAX);
	    if (fill_lines(num_traces, traces, 1, &obj, lines, i) == (uintptr_t)-1)
		break;
	}
next_line:
	continue;
    }

    /* output */
    for (i = 0; i < num_traces; i++) {
        print_line(&lines[i], traces[i]);

	/* FreeBSD's backtrace may show _start and so on */
	if (lines[i].sname && strcmp("main", lines[i].sname) == 0)
	    break;
    }

    /* free */
    while (obj) {
	obj_info_t *o = obj;
        for (i=0; i < DWARF_SECTION_COUNT; i++) {
            struct dwarf_section *s = obj_dwarf_section_at(obj, i);
            if (s->flags & SHF_COMPRESSED) {
                free(s->ptr);
            }
        }
	if (obj->mapped_size) {
	    munmap(obj->mapped, obj->mapped_size);
	}
	obj = o->next;
	free(o);
    }
    for (i = 0; i < num_traces; i++) {
        line_info_t *line = lines[i].next;
        while (line) {
            line_info_t *l = line;
            line = line->next;
            free(l);
        }
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
static const char hex2ascii_data[] = "0123456789abcdefghijklmnopqrstuvwxyz";
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

static int
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
