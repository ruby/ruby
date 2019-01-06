/*
 * missing/stdbool.h: Quick alternative of C99 stdbool.h
 */

#ifndef _MISSING_STDBOOL_H_
#define _MISSING_STDBOOL_H_

#ifndef __bool_true_false_are_defined
# ifndef __cplusplus
#  undef bool
#  undef false
#  undef true
#  define bool signed char
#  define false 0
#  define true 1
#  define __bool_true_false_are_defined 1
# endif
#endif

#endif /* _MISSING_STDBOOL_H_ */
