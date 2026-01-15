#include "parser_st.h"
#include "parser_bits.h"

#ifndef TRUE
# define TRUE    1
#endif

#ifndef FALSE
# define FALSE   0
#endif

#undef NOT_RUBY
#undef RUBY
#undef RUBY_EXPORT

#undef MEMCPY
#define MEMCPY(p1,p2,type,n) nonempty_memcpy((p1), (p2), (sizeof(type) * (n)))
/* The multiplication should not overflow since this macro is used
 * only with the already allocated size. */
static inline void *
nonempty_memcpy(void *dest, const void *src, size_t n)
{
    if (n) {
        return memcpy(dest, src, n);
    }
    else {
        return dest;
    }
}

#include <stdio.h>
#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#endif
#include <string.h>
#include <assert.h>

#ifdef __GNUC__
#define PREFETCH(addr, write_p) __builtin_prefetch(addr, write_p)
#define EXPECT(expr, val) __builtin_expect(expr, val)
#define ATTRIBUTE_UNUSED  __attribute__((unused))
#else
#define PREFETCH(addr, write_p)
#define EXPECT(expr, val) (expr)
#define ATTRIBUTE_UNUSED
#endif


#define st_index_t parser_st_index_t
#define st_hash_t parser_st_hash_t
#define st_data_t parser_st_data_t
#define st_hash_type parser_st_hash_type
#define st_table parser_st_table
#define st_table_entry parser_st_table_entry
#define st_update_callback_func parser_st_update_callback_func
#define st_foreach_check_callback_func parser_st_foreach_check_callback_func
#define st_foreach_callback_func parser_st_foreach_callback_func
#define st_retval parser_st_retval

#define ST_CONTINUE ST2_CONTINUE
#define ST_STOP ST2_STOP
#define ST_DELETE ST2_DELETE
#define ST_CHECK ST2_CHECK
#define ST_REPLACE ST2_REPLACE

#undef st_numcmp
#define st_numcmp rb_parser_st_numcmp
#undef st_numhash
#define st_numhash rb_parser_st_numhash
#undef st_free_table
#define st_free_table rb_parser_st_free_table
#define rb_st_hash_start rb_parser_st_hash_start
#undef st_delete
#define st_delete rb_parser_st_delete
#undef st_foreach
#define st_foreach rb_parser_st_foreach
#undef st_init_numtable
#define st_init_numtable rb_parser_st_init_numtable
#undef st_init_table_with_size
#define st_init_table_with_size rb_parser_st_init_table_with_size
#undef st_init_existing_table_with_size
#define st_init_existing_table_with_size rb_parser_st_init_existing_table_with_size
#undef st_insert
#define st_insert rb_parser_st_insert
#undef st_lookup
#define st_lookup rb_parser_st_lookup

#undef st_table_size
#define st_table_size rb_parser_st_table_size
#undef st_clear
#define st_clear rb_parser_st_clear
#undef st_init_strtable
#define st_init_strtable rb_parser_st_init_strtable
#undef st_init_table
#define st_init_table rb_parser_st_init_table
#undef st_init_strcasetable
#define st_init_strcasetable rb_parser_st_init_strcasetable
#undef st_init_strtable_with_size
#define st_init_strtable_with_size rb_parser_st_init_strtable_with_size
#undef st_init_numtable_with_size
#define st_init_numtable_with_size rb_parser_st_init_numtable_with_size
#undef st_init_strcasetable_with_size
#define st_init_strcasetable_with_size rb_parser_st_init_strcasetable_with_size
#undef st_memsize
#define st_memsize rb_parser_st_memsize
#undef st_get_key
#define st_get_key rb_parser_st_get_key
#undef st_add_direct
#define st_add_direct rb_parser_st_add_direct
#define rb_st_add_direct_with_hash rb_parser_st_add_direct_with_hash
#undef st_insert2
#define st_insert2 rb_parser_st_insert2
#undef st_replace
#define st_replace rb_parser_st_replace
#undef st_copy
#define st_copy rb_parser_st_copy
#undef st_delete_safe
#define st_delete_safe rb_parser_st_delete_safe
#undef st_shift
#define st_shift rb_parser_st_shift
#undef st_cleanup_safe
#define st_cleanup_safe rb_parser_st_cleanup_safe
#undef st_update
#define st_update rb_parser_st_update
#undef st_foreach_with_replace
#define st_foreach_with_replace rb_parser_st_foreach_with_replace
#undef st_foreach_check
#define st_foreach_check rb_parser_st_foreach_check
#undef st_keys
#define st_keys rb_parser_st_keys
#undef st_keys_check
#define st_keys_check rb_parser_st_keys_check
#undef st_values
#define st_values rb_parser_st_values
#undef st_values_check
#define st_values_check rb_parser_st_values_check
#undef st_hash
#define st_hash rb_parser_st_hash
#undef st_hash_uint32
#define st_hash_uint32 rb_parser_st_hash_uint32
#undef st_hash_uint
#define st_hash_uint rb_parser_st_hash_uint
#undef st_hash_end
#define st_hash_end rb_parser_st_hash_end
#undef st_locale_insensitive_strcasecmp
#define st_locale_insensitive_strcasecmp rb_parser_st_locale_insensitive_strcasecmp
#undef st_locale_insensitive_strncasecmp
#define st_locale_insensitive_strncasecmp rb_parser_st_locale_insensitive_strncasecmp

#if defined(__GNUC__) && (__GNUC__ > 4 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 6))
/* GCC warns about unknown sanitizer, which is annoying. */
# undef NO_SANITIZE
# define NO_SANITIZE(x, y) \
    _Pragma("GCC diagnostic push") \
    _Pragma("GCC diagnostic ignored \"-Wattributes\"") \
    __attribute__((__no_sanitize__(x))) y; \
    _Pragma("GCC diagnostic pop") \
    y
#endif

#ifndef NO_SANITIZE
# define NO_SANITIZE(x, y) y
#endif

#include "st.c"
