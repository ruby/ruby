#ifndef PRISM_STATE_STACK_H
#define PRISM_STATE_STACK_H

#include "prism/defines.h"

#include <stdbool.h>
#include <stdint.h>

/**
 * A struct that represents a stack of boolean values.
 */
typedef uint32_t pm_state_stack_t;

/**
 * Initializes the state stack to an empty stack.
 */
#define PM_STATE_STACK_EMPTY ((pm_state_stack_t) 0)

/**
 * Pushes a value onto the stack.
 *
 * @param stack The stack to push the value onto.
 * @param value The value to push onto the stack.
 */
void pm_state_stack_push(pm_state_stack_t *stack, bool value);

/**
 * Pops a value off the stack.
 *
 * @param stack The stack to pop the value off of.
 */
void pm_state_stack_pop(pm_state_stack_t *stack);

/**
 * Returns the value at the top of the stack.
 *
 * @param stack The stack to get the value from.
 */
bool pm_state_stack_p(pm_state_stack_t *stack);

#endif
