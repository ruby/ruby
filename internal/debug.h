#ifndef INTERNAL_DEBUG_H /* -*- C -*- */
#define INTERNAL_DEBUG_H
/**
 * @file
 * @brief      Internal header for debugging.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

/* MRI debug support */
void rb_obj_info_dump(VALUE obj);
void rb_obj_info_dump_loc(VALUE obj, const char *file, int line, const char *func);
void ruby_debug_breakpoint(void);

// show obj data structure without any side-effect
#define rp(obj) rb_obj_info_dump_loc((VALUE)(obj), __FILE__, __LINE__, __func__)

// same as rp, but add message header
#define rp_m(msg, obj) do { \
    fprintf(stderr, "%s", (msg)); \
    rb_obj_info_dump((VALUE)obj); \
} while (0)

// `ruby_debug_breakpoint()` does nothing,
// but breakpoint is set in run.gdb, so `make gdb` can stop here.
#define bp() ruby_debug_breakpoint()

/* debug.c */
PRINTF_ARGS(void ruby_debug_printf(const char*, ...), 1, 2);

#endif /* INTERNAL_DEBUG_H */
