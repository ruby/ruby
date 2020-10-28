#include "ruby.h"

#ifdef __cplusplus
extern "C" {
#endif

void Init_class_id_under_autoload_spec(void) {
  rb_define_class_id_under(rb_cObject, rb_intern("ClassIdUnderAutoload"), rb_cObject);
}

#ifdef __cplusplus
}
#endif
