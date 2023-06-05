#ifndef COROUTINE_UNIVERSAL_CONTEXT_H
#define COROUTINE_UNIVERSAL_CONTEXT_H 1

#if 0
#elif defined __x86_64__
# include "coroutine/amd64/Context.h"
#elif defined __i386__
# include "coroutine/x86/Context.h"
#elif defined __ppc__
# include "coroutine/ppc/Context.h"
#elif defined __ppc64__ && defined(WORDS_BIGENDIAN)
# include "coroutine/ppc64/Context.h"
#elif defined __ppc64__ && !defined(WORDS_BIGENDIAN)
# include "coroutine/ppc64le/Context.h"
#elif defined __arm64__
# include "coroutine/arm64/Context.h"
#else
# error "Unsupported CPU"
#endif

#endif /* COROUTINE_UNIVERSAL_CONTEXT_H */
