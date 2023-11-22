#include "prism/util/pm_state_stack.h"

/**
 * Pushes a value onto the stack.
 */
void
pm_state_stack_push(pm_state_stack_t *stack, bool value) {
    *stack = (*stack << 1) | (value & 1);
}

/**
 * Pops a value off the stack.
 */
void
pm_state_stack_pop(pm_state_stack_t *stack) {
    *stack >>= 1;
}

/**
 * Returns the value at the top of the stack.
 */
bool
pm_state_stack_p(pm_state_stack_t *stack) {
    return *stack & 1;
}
