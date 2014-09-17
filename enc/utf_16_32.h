#include "regenc.h"
/* dummy for unsupported, statefull encoding */
#define ENC_DUMMY_UNICODE(name) ENC_REPLICATE(name, name "BE")
ENC_DUMMY_UNICODE("UTF-16");
ENC_DUMMY_UNICODE("UTF-32");
