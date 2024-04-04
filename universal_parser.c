#include <alloca.h>
#include <string.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>

/* Dependency */
#include "internal/parse.h"
#include "node.h"
#include "id.h"

#include "internal/compilers.h"
#include "ruby/backward/2/inttypes.h"
#include "probes.h"

#define LIKELY(x) RB_LIKELY(x)
#define UNLIKELY(x) RB_UNLIKELY(x)
#ifndef TRUE
# define TRUE    1
#endif

#ifndef FALSE
# define FALSE   0
#endif
#define numberof(array) ((int)(sizeof(array) / sizeof((array)[0])))
#define rb_strlen_lit(str) (sizeof(str "") - 1)
#undef FIXNUM_MAX
#define FIXNUM_MAX (LONG_MAX / 2)
#undef RSTRING_GETMEM
#define RSTRING_GETMEM(str, ptrvar, lenvar) \
    ((ptrvar) = RSTRING_PTR(str),           \
     (lenvar) = RSTRING_LEN(str))

/* parser_st */
#define st_table parser_st_table
#define st_data_t parser_st_data_t
#define st_hash_type parser_st_hash_type
#define ST_CONTINUE ST2_CONTINUE
#define ST_STOP ST2_STOP
#define ST_DELETE ST2_DELETE
#define ST_CHECK ST2_CHECK
#define ST_REPLACE ST2_REPLACE
#undef st_init_numtable
#define st_init_numtable rb_parser_st_init_numtable
#undef st_free_table
#define st_free_table rb_parser_st_free_table
#undef st_init_table_with_size
#define st_init_table_with_size rb_parser_st_init_table_with_size
#undef st_insert
#define st_insert rb_parser_st_insert
#undef st_foreach
#define st_foreach rb_parser_st_foreach
#undef st_delete
#define st_delete rb_parser_st_delete
#undef st_is_member
#define st_is_member parser_st_is_member
#undef st_init_table
#define st_init_table rb_parser_st_init_table
#undef st_lookup
#define st_lookup rb_parser_st_lookup

#define rb_encoding void

#undef xmalloc
#define xmalloc p->config->malloc
#undef xcalloc
#define xcalloc p->config->calloc
#undef xrealloc
#define xrealloc p->config->realloc
#undef ALLOC_N
#define ALLOC_N(type,n)  ((type *)p->config->alloc_n((n), sizeof(type)))
#undef ALLOC
#define ALLOC(type)      ((type *)p->config->alloc(sizeof(type)))
#undef xfree
#define xfree p->config->free
#undef ALLOCA_N
// alloca(rbimpl_size_mul_or_raise(x, y));
#define ALLOCA_N(type,n) ((type *)alloca(sizeof(type) * (n)))
#undef REALLOC_N
#define REALLOC_N(var,type,n) ((var) = (type *)p->config->realloc_n((void *)var, n, sizeof(type)))
#undef ZALLOC
#define ZALLOC(type) ((type *)p->config->zalloc(sizeof(type)))
#undef MEMMOVE
#define MEMMOVE(p1,p2,type,n) (p->config->rb_memmove((p1), (p2), sizeof(type), (n)))
#undef MEMCPY
#define MEMCPY(p1,p2,type,n) (p->config->nonempty_memcpy((p1), (p2), sizeof(type), (n)))

#define compile_callback         p->config->compile_callback
#define reg_named_capture_assign p->config->reg_named_capture_assign

#define rb_obj_freeze p->config->obj_freeze
#define rb_obj_hide p->config->obj_hide
#undef OBJ_FREEZE_RAW
#define OBJ_FREEZE_RAW p->config->obj_freeze_raw

#undef FIXNUM_P
#define FIXNUM_P p->config->fixnum_p
#undef SYMBOL_P
#define SYMBOL_P p->config->symbol_p

#define rb_attr_get p->config->attr_get

#define rb_ary_new           p->config->ary_new
#define rb_ary_push          p->config->ary_push
#undef rb_ary_new_from_args
#define rb_ary_new_from_args p->config->ary_new_from_args
#define rb_ary_unshift       p->config->ary_unshift
#undef rb_ary_new2
#define rb_ary_new2          p->config->ary_new2
#define rb_ary_clear         p->config->ary_clear
#define rb_ary_modify        p->config->ary_modify
#undef RARRAY_LEN
#define RARRAY_LEN           p->config->array_len
#define RARRAY_AREF          p->config->array_aref

#define rb_make_temporary_id     p->config->make_temporary_id
#define is_local_id              p->config->is_local_id
#define is_attrset_id            p->config->is_attrset_id
#define is_global_name_punct     p->config->is_global_name_punct
#define id_type                  p->config->id_type
#define rb_id_attrset            p->config->id_attrset
#undef rb_intern
#define rb_intern                p->config->intern
#define rb_intern2               p->config->intern2
#define rb_intern3               p->config->intern3
#define rb_intern_str            p->config->intern_str
#define is_notop_id              p->config->is_notop_id
#define rb_enc_symname_type      p->config->enc_symname_type
#define rb_id2name               p->config->id2name
#define rb_id2str                p->config->id2str
#undef ID2SYM
#define ID2SYM                   p->config->id2sym
#undef SYM2ID
#define SYM2ID                   p->config->sym2id

#define rb_str_catf                       p->config->str_catf
#undef rb_str_cat_cstr
#define rb_str_cat_cstr                   p->config->str_cat_cstr
#define rb_str_subseq                     p->config->str_subseq
#define rb_str_new_frozen                 p->config->str_new_frozen
#define rb_str_buf_new                    p->config->str_buf_new
#undef rb_str_buf_cat
#define rb_str_buf_cat                    p->config->str_buf_cat
#define rb_str_modify                     p->config->str_modify
#define rb_str_set_len                    p->config->str_set_len
#define rb_str_cat                        p->config->str_cat
#define rb_str_resize                     p->config->str_resize
#undef rb_str_new
#define rb_str_new                        p->config->str_new
#undef rb_str_new_cstr
#define rb_str_new_cstr                   p->config->str_new_cstr
#define rb_str_to_interned_str            p->config->str_to_interned_str
#define is_ascii_string                   p->config->is_ascii_string
#define rb_enc_str_new                    p->config->enc_str_new
#define rb_enc_str_buf_cat                p->config->enc_str_buf_cat
#define rb_str_buf_append                 p->config->str_buf_append
#define rb_str_vcatf                      p->config->str_vcatf
#undef StringValueCStr
#define StringValueCStr(v)                p->config->string_value_cstr(&(v))
#define rb_sprintf                        p->config->rb_sprintf
#undef RSTRING_PTR
#define RSTRING_PTR                       p->config->rstring_ptr
#undef RSTRING_END
#define RSTRING_END                       p->config->rstring_end
#undef RSTRING_LEN
#define RSTRING_LEN                       p->config->rstring_len
#define rb_filesystem_str_new_cstr        p->config->filesystem_str_new_cstr
#define rb_obj_as_string                  p->config->obj_as_string

#define rb_hash_clear     p->config->hash_clear
#define rb_hash_new       p->config->hash_new
#define rb_hash_aset      p->config->hash_aset
#define rb_hash_lookup    p->config->hash_lookup
#define rb_ident_hash_new p->config->ident_hash_new

#undef NUM2INT
#define NUM2INT             p->config->num2int
#undef INT2NUM
#define INT2NUM             p->config->int2num

#define rb_stderr_tty_p    p->config->stderr_tty_p
#define rb_write_error_str p->config->write_error_str
#define rb_default_rs      p->config->default_rs()
#define rb_io_write        p->config->io_write
#define rb_io_flush        p->config->io_flush
#define rb_io_puts         p->config->io_puts
#define rb_io_gets_internal p->config->io_gets_internal

#define rb_ractor_stdout   p->config->debug_output_stdout
#define rb_ractor_stderr   p->config->debug_output_stderr

#define rb_is_usascii_enc       p->config->is_usascii_enc
#define rb_enc_isalnum          p->config->enc_isalnum
#define rb_enc_precise_mbclen   p->config->enc_precise_mbclen
#define MBCLEN_CHARFOUND_P      p->config->mbclen_charfound_p
#define MBCLEN_CHARFOUND_LEN    p->config->mbclen_charfound_len
#define rb_enc_name             p->config->enc_name
#define rb_enc_prev_char        p->config->enc_prev_char
#define rb_enc_get              p->config->enc_get
#define rb_enc_asciicompat      p->config->enc_asciicompat
#define rb_utf8_encoding        p->config->utf8_encoding
#define rb_enc_associate        p->config->enc_associate
#define rb_ascii8bit_encoding   p->config->ascii8bit_encoding
#define rb_enc_codelen          p->config->enc_codelen
#define rb_enc_mbcput           p->config->enc_mbcput
#define rb_enc_find_index       p->config->enc_find_index
#define rb_enc_from_index       p->config->enc_from_index
#define rb_enc_associate_index  p->config->enc_associate_index
#define rb_enc_isspace          p->config->enc_isspace
#define ENC_CODERANGE_7BIT      p->config->enc_coderange_7bit
#define ENC_CODERANGE_UNKNOWN   p->config->enc_coderange_unknown
#define rb_enc_compatible       p->config->enc_compatible
#define rb_enc_from_encoding    p->config->enc_from_encoding
#define ENCODING_IS_ASCII8BIT   p->config->encoding_is_ascii8bit
#define rb_usascii_encoding     p->config->usascii_encoding

#define rb_local_defined          p->config->local_defined
#define rb_dvar_defined           p->config->dvar_defined

#define rb_syntax_error_append p->config->syntax_error_append
#define rb_raise p->config->raise
#define syntax_error_new p->config->syntax_error_new

#define rb_errinfo p->config->errinfo
#define rb_set_errinfo p->config->set_errinfo
#define rb_exc_raise p->config->exc_raise
#define rb_make_exception p->config->make_exception

#define ruby_sized_xfree p->config->sized_xfree
#define SIZED_REALLOC_N(v, T, m, n) ((v) = (T *)p->config->sized_realloc_n((void *)(v), (m), sizeof(T), (n)))
#undef RB_OBJ_WRITE
#define RB_OBJ_WRITE(old, slot, young) p->config->obj_write((VALUE)(old), (VALUE *)(slot), (VALUE)(young))
#undef RB_OBJ_WRITTEN
#define RB_OBJ_WRITTEN(old, oldv, young) p->config->obj_written((VALUE)(old), (VALUE)(oldv), (VALUE)(young))
#undef RB_GC_GUARD
#define RB_GC_GUARD p->config->gc_guard
#define rb_gc_mark p->config->gc_mark

#define rb_reg_compile          p->config->reg_compile
#define rb_reg_check_preprocess p->config->reg_check_preprocess
#define rb_memcicmp p->config->memcicmp

#define rb_compile_warn    p->config->compile_warn
#define rb_compile_warning p->config->compile_warning
#define rb_bug             p->config->bug
#define rb_fatal           p->config->fatal
#undef ruby_verbose
#define ruby_verbose       p->config->verbose()
#undef errno
#define errno              (*p->config->errno_ptr())

#define rb_make_backtrace p->config->make_backtrace

#define ruby_scan_hex    p->config->scan_hex
#define ruby_scan_oct    p->config->scan_oct
#define ruby_scan_digits p->config->scan_digits
#define strtod           p->config->strtod

#undef RBOOL
#define RBOOL p->config->rbool
#undef UNDEF_P
#define UNDEF_P p->config->undef_p
#undef RTEST
#define RTEST p->config->rtest
#undef NIL_P
#define NIL_P p->config->nil_p
#undef Qnil
#define Qnil  p->config->qnil
#undef Qtrue
#define Qtrue p->config->qtrue
#undef Qfalse
#define Qfalse p->config->qfalse
#undef Qundef
#define Qundef p->config->qundef
#define rb_eArgError p->config->eArgError()
#define rb_mRubyVMFrozenCore p->config->mRubyVMFrozenCore()
#undef rb_long2int
#define rb_long2int p->config->long2int
#define rb_enc_mbminlen p->config->enc_mbminlen
#define rb_enc_isascii p->config->enc_isascii
#define rb_enc_mbc_to_codepoint p->config->enc_mbc_to_codepoint

#define rb_node_case_when_optimizable_literal p->config->node_case_when_optimizable_literal

#undef st_init_table_with_size
#define st_init_table_with_size rb_parser_st_init_table_with_size

#define rb_ast_new() \
    rb_ast_new(p->config)
