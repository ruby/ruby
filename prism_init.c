#include "prism/extension.h"

void ruby_init_ext(const char *name, void (*init)(void));

void
Init_Prism(void)
{
    ruby_init_ext("prism/prism.so", Init_prism);
}
