#ifndef YP_STRPBRK_H
#define YP_STRPBRK_H

#include "yarp/defines.h"

#include <stddef.h>
#include <string.h>

// Here we have rolled our own version of strpbrk. The standard library strpbrk
// has undefined behavior when the source string is not null-terminated. We want
// to support strings that are not null-terminated because yp_parse does not
// have the contract that the string is null-terminated. (This is desirable
// because it means the extension can call yp_parse with the result of a call to
// mmap).
//
// The standard library strpbrk also does not support passing a maximum length
// to search. We want to support this for the reason mentioned above, but we
// also don't want it to stop on null bytes. Ruby actually allows null bytes
// within strings, comments, regular expressions, etc. So we need to be able to
// skip past them.
const char *
yp_strpbrk(const char *source, const char *charset, long length);

#endif
