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
#if defined(USE_FLONUM)
# /* Take that. */
#elif SIZEOF_VALUE >= SIZEOF_DOUBLE
# define USE_FLONUM 1
#else
# define USE_FLONUM 0
#endif

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

#define rb_encoding void

#undef T_FLOAT
#define T_FLOAT    0x04
#undef T_REGEXP
#define T_REGEXP   0x06
#undef T_HASH
#define T_HASH     0x08
#undef T_BIGNUM
#define T_BIGNUM   0x0a
#undef T_COMPLEX
#define T_COMPLEX  0x0e
#undef T_RATIONAL
#define T_RATIONAL 0x0f

#ifndef INTERNAL_IMEMO_H
struct rb_imemo_tmpbuf_struct {
    VALUE flags;
    VALUE reserved;
    VALUE *ptr; /* malloc'ed buffer */
    struct rb_imemo_tmpbuf_struct *next; /* next imemo */
    size_t cnt; /* buffer size in VALUE */
};
#endif

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

#define new_strterm p->config->new_strterm
#define strterm_is_heredoc p->config->strterm_is_heredoc
#define rb_imemo_tmpbuf_auto_free_pointer p->config->tmpbuf_auto_free_pointer
#define rb_imemo_tmpbuf_set_ptr p->config->tmpbuf_set_ptr
#define rb_imemo_tmpbuf_parser_heap p->config->tmpbuf_parser_heap

#define compile_callback         p->config->compile_callback
#define reg_named_capture_assign p->config->reg_named_capture_assign
#define script_lines_defined     p->config->script_lines_defined
#define script_lines_get         p->config->script_lines_get

#define rb_obj_freeze p->config->obj_freeze
#define rb_obj_hide p->config->obj_hide
#undef RB_OBJ_FROZEN
#define RB_OBJ_FROZEN p->config->obj_frozen
#undef RB_TYPE_P
#define RB_TYPE_P p->config->type_p
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
#define rb_ary_pop           p->config->ary_pop
#define rb_ary_last          p->config->ary_last
#define rb_ary_unshift       p->config->ary_unshift
#undef rb_ary_new2
#define rb_ary_new2          p->config->ary_new2
#define rb_ary_entry         p->config->ary_entry
#define rb_ary_join          p->config->ary_join
#define rb_ary_reverse       p->config->ary_reverse
#define rb_ary_clear         p->config->ary_clear
#undef RARRAY_LEN
#define RARRAY_LEN           p->config->array_len
#define RARRAY_AREF          p->config->array_aref

#undef rb_sym_intern_ascii_cstr
#define rb_sym_intern_ascii_cstr p->config->sym_intern_ascii_cstr
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
#define rb_str_intern            p->config->str_intern
#define rb_id2name               p->config->id2name
#define rb_id2str                p->config->id2str
#define rb_id2sym                p->config->id2sym
#undef ID2SYM
#define ID2SYM                   p->config->id2sym
#undef SYM2ID
#define SYM2ID                   p->config->sym2id

#define rb_str_catf                       p->config->str_catf
#undef rb_str_cat_cstr
#define rb_str_cat_cstr                   p->config->str_cat_cstr
#define rb_str_subseq                     p->config->str_subseq
#define rb_str_dup                        p->config->str_dup
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
#define rb_fstring                        p->config->fstring
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

#undef INT2FIX
#define INT2FIX  p->config->int2fix
#undef LONG2FIX
#define LONG2FIX p->config->int2fix

#define bignum_negate p->config->bignum_negate
#define rb_big_norm   p->config->big_norm
#define rb_cstr_to_inum p->config->cstr_to_inum

#define rb_float_new   p->config->float_new
#undef RFLOAT_VALUE
#define RFLOAT_VALUE   p->config->float_value
#undef DBL2NUM
#define DBL2NUM p->config->float_new

#undef NUM2INT
#define NUM2INT             p->config->num2int
#define rb_int_positive_pow p->config->int_positive_pow
#undef INT2NUM
#define INT2NUM             p->config->int2num
#undef FIX2LONG
#define FIX2LONG            p->config->fix2long

#define rb_rational_new  p->config->rational_new
#undef rb_rational_raw1
#define rb_rational_raw1 p->config->rational_raw1
#define rational_set_num p->config->rational_set_num
#define rational_get_num p->config->rational_get_num

#define rb_complex_raw    p->config->complex_raw
#define rcomplex_set_real p->config->rcomplex_set_real
#define rcomplex_set_imag p->config->rcomplex_set_imag
#define rcomplex_get_real p->config->rcomplex_get_real
#define rcomplex_get_imag p->config->rcomplex_get_imag

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
#define rb_enc_name             p->config->enc_name
#define rb_enc_prev_char        p->config->enc_prev_char
#define rb_enc_get              p->config->enc_get
#define rb_enc_asciicompat      p->config->enc_asciicompat
#define rb_utf8_encoding        p->config->utf8_encoding
#define rb_enc_associate        p->config->enc_associate
#define rb_ascii8bit_encoding   p->config->ascii8bit_encoding
#define rb_enc_codelen          p->config->enc_codelen
#define rb_enc_mbcput           p->config->enc_mbcput
#define rb_char_to_option_kcode p->config->char_to_option_kcode
#define rb_ascii8bit_encindex   p->config->ascii8bit_encindex
#define rb_enc_find_index       p->config->enc_find_index
#define rb_enc_from_index       p->config->enc_from_index
#define rb_enc_associate_index  p->config->enc_associate_index
#define rb_enc_isspace          p->config->enc_isspace
#define ENC_CODERANGE_7BIT      p->config->enc_coderange_7bit
#define ENC_CODERANGE_UNKNOWN   p->config->enc_coderange_unknown
#define rb_enc_compatible       p->config->enc_compatible
#define rb_enc_from_encoding    p->config->enc_from_encoding
#define ENCODING_GET            p->config->encoding_get
#define ENCODING_SET            p->config->encoding_set
#define ENCODING_IS_ASCII8BIT   p->config->encoding_is_ascii8bit
#define rb_usascii_encoding     p->config->usascii_encoding

#define rb_ractor_make_shareable p->config->ractor_make_shareable

#define ruby_vm_keep_script_lines p->config->vm_keep_script_lines()
#define rb_local_defined          p->config->local_defined
#define rb_dvar_defined           p->config->dvar_defined

#define literal_cmp  p->config->literal_cmp
#define literal_hash p->config->literal_hash

#define rb_builtin_class_name p->config->builtin_class_name
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
#define rb_gc_register_mark_object p->config->gc_register_mark_object
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
#undef FLONUM_P
#define FLONUM_P p->config->flonum_p
#undef Qnil
#define Qnil  p->config->qnil
#undef Qtrue
#define Qtrue p->config->qtrue
#undef Qfalse
#define Qfalse p->config->qfalse
#undef Qundef
#define Qundef p->config->qundef
#define rb_eArgError p->config->eArgError
#define rb_mRubyVMFrozenCore p->config->mRubyVMFrozenCore
#undef rb_long2int
#define rb_long2int p->config->long2int
#undef SPECIAL_CONST_P
#define SPECIAL_CONST_P p->config->special_const_p
#undef BUILTIN_TYPE
#define BUILTIN_TYPE p->config->builtin_type
#define ruby_snprintf p->config->snprintf

#define rb_node_case_when_optimizable_literal p->config->node_case_when_optimizable_literal

#undef st_init_table_with_size
#define st_init_table_with_size rb_parser_st_init_table_with_size

#define rb_ast_new() \
    rb_ast_new(p->config)
