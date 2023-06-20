#include "yarp/extension.h"

void ruby_init_ext(const char *name, void (*init)(void));

void
Init_YARP() {
    ruby_init_ext("yarp.so", Init_yarp);
}
