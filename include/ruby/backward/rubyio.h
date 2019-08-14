#if   defined __GNUC__
#warning use "ruby/io.h" instead of "rubyio.h"
#elif defined _MSC_VER
#pragma message("warning: use \"ruby/io.h\" instead of \"rubyio.h\"")
#endif
#include "ruby/io.h"
