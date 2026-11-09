#ifndef PRISM_INTERNAL_ASSERT_H
#define PRISM_INTERNAL_ASSERT_H

/**
 * Assertion macro for prism. By default, it uses the standard C assert. A
 * consumer can define PRISM_ASSERT before building prism to handle assertions
 * differently.
 */
#ifndef PRISM_ASSERT
#include <assert.h>
#define PRISM_ASSERT(expr_) assert(expr_)
#endif

#endif
