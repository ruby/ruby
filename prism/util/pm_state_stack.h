#ifndef YP_STATE_STACK_H
#define YP_STATE_STACK_H

#include "yarp/defines.h"

#include <stdbool.h>
#include <stdint.h>

// A struct that represents a stack of bools.
typedef uint32_t yp_state_stack_t;

// Initializes the state stack to an empty stack.
#define YP_STATE_STACK_EMPTY ((yp_state_stack_t) 0)

// Pushes a value onto the stack.
void yp_state_stack_push(yp_state_stack_t *stack, bool value);

// Pops a value off the stack.
void yp_state_stack_pop(yp_state_stack_t *stack);

// Returns the value at the top of the stack.
bool yp_state_stack_p(yp_state_stack_t *stack);

#endif
