#include "config.h"

#if !HAVE_SELECT
#include "x68/select.c"
#endif
#if MISSING__DTOS18
#include "x68/_dtos18.c"
#endif
#if MISSING_FCONVERT
#include "x68/_round.c"
#include "x68/fconvert.c"
#endif
