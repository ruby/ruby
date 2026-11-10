#include "ruby/internal/config.h"

#include "stack.h"

#include <stdlib.h>

#if defined(_WIN32)
# include <windows.h>
#elif defined(HAVE_SYS_MMAN_H)
# include <sys/mman.h>
#endif

#if !defined(MAP_ANONYMOUS) && defined(MAP_ANON)
# define MAP_ANONYMOUS MAP_ANON
#endif

int
coroutine_stack_allocate(struct coroutine_stack *stack, size_t size)
{
#if defined(_WIN32)
    stack->base = VirtualAlloc(NULL, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
#elif defined(HAVE_MMAP) && defined(MAP_ANONYMOUS)
    stack->base = mmap(NULL, size, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (stack->base == MAP_FAILED) stack->base = NULL;
#else
    stack->base = malloc(size);
#endif

    stack->size = stack->base == NULL ? 0 : size;
    return stack->base == NULL ? -1 : 0;
}

void
coroutine_stack_free(struct coroutine_stack *stack)
{
    if (stack->base == NULL) return;

#if defined(_WIN32)
    VirtualFree(stack->base, 0, MEM_RELEASE);
#elif defined(HAVE_MMAP) && defined(MAP_ANONYMOUS)
    munmap(stack->base, stack->size);
#else
    free(stack->base);
#endif

    stack->base = NULL;
    stack->size = 0;
}
