#include "yarp/enc/yp_encoding.h"

// The function is shared between all of the encodings that use single bytes to
// represent characters. They don't have need of a dynamic function to determine
// their width.
size_t
yp_encoding_single_char_width(YP_ATTRIBUTE_UNUSED const char *c) {
    return 1;
}
