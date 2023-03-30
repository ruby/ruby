#include "yp_state_stack.h"

// Initializes the state stack to an empty stack.
void
yp_state_stack_init(yp_state_stack_t *stack) {
  *stack = 0;
}

// Pushes a value onto the stack.
void
yp_state_stack_push(yp_state_stack_t *stack, bool value) {
  *stack = (*stack << 1) | (value & 1);
}

// Pops a value off the stack.
void
yp_state_stack_pop(yp_state_stack_t *stack) {
  *stack >>= 1;
}

// Returns the value at the top of the stack.
bool
yp_state_stack_p(yp_state_stack_t *stack) {
  return *stack & 1;
}
