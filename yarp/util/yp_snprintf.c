#include "yarp/defines.h"

#ifndef HAVE_SNPRINTF
// In case snprintf isn't present on the system, we provide our own that simply
// forwards to the less-safe sprintf.
int
yp_snprintf(char *dest, YP_ATTRIBUTE_UNUSED size_t size, const char *format, ...) {
    va_list args;
    va_start(args, format);
    int result = vsprintf(dest, format, args);
    va_end(args);
    return result;
}
#endif
