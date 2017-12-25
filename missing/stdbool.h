/*
 * missing/stdbool.h: Quick alternative of C99 stdbool.h
 */

#ifndef _MISSING_STDBOOL_H_
#define _MISSING_STDBOOL_H_

#ifndef __cplusplus

#define bool _Bool
#define true 1
#define false 0

#ifndef HAVE__BOOL /* AC_HEADER_STDBOOL in configure.ac */
typedef int _Bool;
#endif /* HAVE__BOOL */

#endif /* __cplusplus */

#endif /* _MISSING_STDBOOL_H_ */
