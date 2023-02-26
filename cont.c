/**********************************************************************

  cont.c -

  $Author$
  created at: Thu May 23 09:03:43 2007

  Copyright (C) 2007 Koichi Sasada

**********************************************************************/

#include "ruby/internal/config.h"

#ifndef _WIN32
#include <unistd.h>
#include <sys/mman.h>
#endif

// On Solaris, madvise() is NOT declared for SUS (XPG4v2) or later,
// but MADV_* macros are defined when __EXTENSIONS__ is defined.
#ifdef NEED_MADVICE_PROTOTYPE_USING_CADDR_T
#include <sys/types.h>
extern int madvise(caddr_t, size_t, int);
#endif

#include COROUTINE_H

#include "eval_intern.h"
#include "gc.h"
#include "internal.h"
#include "internal/cont.h"
#include "internal/error.h"
#include "internal/proc.h"
#include "internal/sanitizers.h"
#include "internal/warnings.h"
#include "ruby/fiber/scheduler.h"
#include "mjit.h"
#include "yjit.h"
#include "vm_core.h"
#include "vm_sync.h"
#include "id_table.h"
#include "ractor_core.h"

static const int DEBUG = 0;

#define RB_PAGE_SIZE (pagesize)
#define RB_PAGE_MASK (~(RB_PAGE_SIZE - 1))
static long pagesize;

static const rb_data_type_t cont_data_type, fiber_data_type;
static VALUE rb_cContinuation;
static VALUE rb_cFiber;
static VALUE rb_eFiberError;
#ifdef RB_EXPERIMENTAL_FIBER_POOL
static VALUE rb_cFiberPool;
#endif

#define CAPTURE_JUST_VALID_VM_STACK 1

// Defined in `coroutine/$arch/Context.h`:
#ifdef COROUTINE_LIMITED_ADDRESS_SPACE
#define FIBER_POOL_ALLOCATION_FREE
#define FIBER_POOL_INITIAL_SIZE 8
#define FIBER_POOL_ALLOCATION_MAXIMUM_SIZE 32
#else
#define FIBER_POOL_INITIAL_SIZE 32
#define FIBER_POOL_ALLOCATION_MAXIMUM_SIZE 1024
#endif
#ifdef RB_EXPERIMENTAL_FIBER_POOL
#define FIBER_POOL_ALLOCATION_FREE
#endif

#define jit_cont_enabled (mjit_enabled || rb_yjit_enabled_p())

enum context_type {
    CONTINUATION_CONTEXT = 0,
    FIBER_CONTEXT = 1
};

struct cont_saved_vm_stack {
    VALUE *ptr;
#ifdef CAPTURE_JUST_VALID_VM_STACK
    size_t slen;  /* length of stack (head of ec->vm_stack) */
    size_t clen;  /* length of control frames (tail of ec->vm_stack) */
#endif
};

struct fiber_pool;

// Represents a single stack.
struct fiber_pool_stack {
    // A pointer to the memory allocation (lowest address) for the stack.
    void * base;

    // The current stack pointer, taking into account the direction of the stack.
    void * current;

    // The size of the stack excluding any guard pages.
    size_t size;

    // The available stack capacity w.r.t. the current stack offset.
    size_t available;

    // The pool this stack should be allocated from.
    struct fiber_pool * pool;

    // If the stack is allocated, the allocation it came from.
    struct fiber_pool_allocation * allocation;
};

// A linked list of vacant (unused) stacks.
// This structure is stored in the first page of a stack if it is not in use.
// @sa fiber_pool_vacancy_pointer
struct fiber_pool_vacancy {
    // Details about the vacant stack:
    struct fiber_pool_stack stack;

    // The vacancy linked list.
#ifdef FIBER_POOL_ALLOCATION_FREE
    struct fiber_pool_vacancy * previous;
#endif
    struct fiber_pool_vacancy * next;
};

// Manages singly linked list of mapped regions of memory which contains 1 more more stack:
//
// base = +-------------------------------+-----------------------+  +
//        |VM Stack       |VM Stack       |                       |  |
//        |               |               |                       |  |
//        |               |               |                       |  |
//        +-------------------------------+                       |  |
//        |Machine Stack  |Machine Stack  |                       |  |
//        |               |               |                       |  |
//        |               |               |                       |  |
//        |               |               | .  .  .  .            |  |  size
//        |               |               |                       |  |
//        |               |               |                       |  |
//        |               |               |                       |  |
//        |               |               |                       |  |
//        |               |               |                       |  |
//        +-------------------------------+                       |  |
//        |Guard Page     |Guard Page     |                       |  |
//        +-------------------------------+-----------------------+  v
//
//        +------------------------------------------------------->
//
//                                  count
//
struct fiber_pool_allocation {
    // A pointer to the memory mapped region.
    void * base;

    // The size of the individual stacks.
    size_t size;

    // The stride of individual stacks (including any guard pages or other accounting details).
    size_t stride;

    // The number of stacks that were allocated.
    size_t count;

#ifdef FIBER_POOL_ALLOCATION_FREE
    // The number of stacks used in this allocation.
    size_t used;
#endif

    struct fiber_pool * pool;

    // The allocation linked list.
#ifdef FIBER_POOL_ALLOCATION_FREE
    struct fiber_pool_allocation * previous;
#endif
    struct fiber_pool_allocation * next;
};

// A fiber pool manages vacant stacks to reduce the overhead of creating fibers.
struct fiber_pool {
    // A singly-linked list of allocations which contain 1 or more stacks each.
    struct fiber_pool_allocation * allocations;

    // Provides O(1) stack "allocation":
    struct fiber_pool_vacancy * vacancies;

    // The size of the stack allocations (excluding any guard page).
    size_t size;

    // The total number of stacks that have been allocated in this pool.
    size_t count;

    // The initial number of stacks to allocate.
    size_t initial_count;

    // Whether to madvise(free) the stack or not:
    int free_stacks;

    // The number of stacks that have been used in this pool.
    size_t used;

    // The amount to allocate for the vm_stack:
    size_t vm_stack_size;
};

// Continuation contexts used by JITs
struct rb_jit_cont {
    rb_execution_context_t *ec; // continuation ec
    struct rb_jit_cont *prev, *next; // used to form lists
};

// Doubly linked list for enumerating all on-stack ISEQs.
static struct rb_jit_cont *first_jit_cont;

typedef struct rb_context_struct {
    enum context_type type;
    int argc;
    int kw_splat;
    VALUE self;
    VALUE value;

    struct cont_saved_vm_stack saved_vm_stack;

    struct {
        VALUE *stack;
        VALUE *stack_src;
        size_t stack_size;
    } machine;
    rb_execution_context_t saved_ec;
    rb_jmpbuf_t jmpbuf;
    rb_ensure_entry_t *ensure_array;
    struct rb_jit_cont *jit_cont; // Continuation contexts for JITs
} rb_context_t;


/*
 * Fiber status:
 *    [Fiber.new] ------> FIBER_CREATED
 *                        | [Fiber#resume]
 *                        v
 *                   +--> FIBER_RESUMED ----+
 *    [Fiber#resume] |    | [Fiber.yield]   |
 *                   |    v                 |
 *                   +-- FIBER_SUSPENDED    | [Terminate]
 *                                          |
 *                       FIBER_TERMINATED <-+
 */
enum fiber_status {
    FIBER_CREATED,
    FIBER_RESUMED,
    FIBER_SUSPENDED,
    FIBER_TERMINATED
};

#define FIBER_CREATED_P(fiber)    ((fiber)->status == FIBER_CREATED)
#define FIBER_RESUMED_P(fiber)    ((fiber)->status == FIBER_RESUMED)
#define FIBER_SUSPENDED_P(fiber)  ((fiber)->status == FIBER_SUSPENDED)
#define FIBER_TERMINATED_P(fiber) ((fiber)->status == FIBER_TERMINATED)
#define FIBER_RUNNABLE_P(fiber)   (FIBER_CREATED_P(fiber) || FIBER_SUSPENDED_P(fiber))

struct rb_fiber_struct {
    rb_context_t cont;
    VALUE first_proc;
    struct rb_fiber_struct *prev;
    struct rb_fiber_struct *resuming_fiber;

    BITFIELD(enum fiber_status, status, 2);
    /* Whether the fiber is allowed to implicitly yield. */
    unsigned int yielding : 1;
    unsigned int blocking : 1;

    struct coroutine_context context;
    struct fiber_pool_stack stack;
};

static struct fiber_pool shared_fiber_pool = {NULL, NULL, 0, 0, 0, 0};

static ID fiber_initialize_keywords[3] = {0};

/*
 * FreeBSD require a first (i.e. addr) argument of mmap(2) is not NULL
 * if MAP_STACK is passed.
 * https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=158755
 */
#if defined(MAP_STACK) && !defined(__FreeBSD__) && !defined(__FreeBSD_kernel__)
#define FIBER_STACK_FLAGS (MAP_PRIVATE | MAP_ANON | MAP_STACK)
#else
#define FIBER_STACK_FLAGS (MAP_PRIVATE | MAP_ANON)
#endif

#define ERRNOMSG strerror(errno)

// Locates the stack vacancy details for the given stack.
inline static struct fiber_pool_vacancy *
fiber_pool_vacancy_pointer(void * base, size_t size)
{
    STACK_GROW_DIR_DETECTION;

    return (struct fiber_pool_vacancy *)(
        (char*)base + STACK_DIR_UPPER(0, size - RB_PAGE_SIZE)
    );
}

#if defined(COROUTINE_SANITIZE_ADDRESS)
// Compute the base pointer for a vacant stack, for the area which can be poisoned.
inline static void *
fiber_pool_stack_poison_base(struct fiber_pool_stack * stack)
{
    STACK_GROW_DIR_DETECTION;

    return (char*)stack->base + STACK_DIR_UPPER(RB_PAGE_SIZE, 0);
}

// Compute the size of the vacant stack, for the area that can be poisoned.
inline static size_t
fiber_pool_stack_poison_size(struct fiber_pool_stack * stack)
{
    return stack->size - RB_PAGE_SIZE;
}
#endif

// Reset the current stack pointer and available size of the given stack.
inline static void
fiber_pool_stack_reset(struct fiber_pool_stack * stack)
{
    STACK_GROW_DIR_DETECTION;

    stack->current = (char*)stack->base + STACK_DIR_UPPER(0, stack->size);
    stack->available = stack->size;
}

// A pointer to the base of the current unused portion of the stack.
inline static void *
fiber_pool_stack_base(struct fiber_pool_stack * stack)
{
    STACK_GROW_DIR_DETECTION;

    VM_ASSERT(stack->current);

    return STACK_DIR_UPPER(stack->current, (char*)stack->current - stack->available);
}

// Allocate some memory from the stack. Used to allocate vm_stack inline with machine stack.
// @sa fiber_initialize_coroutine
inline static void *
fiber_pool_stack_alloca(struct fiber_pool_stack * stack, size_t offset)
{
    STACK_GROW_DIR_DETECTION;

    if (DEBUG) fprintf(stderr, "fiber_pool_stack_alloca(%p): %"PRIuSIZE"/%"PRIuSIZE"\n", (void*)stack, offset, stack->available);
    VM_ASSERT(stack->available >= offset);

    // The pointer to the memory being allocated:
    void * pointer = STACK_DIR_UPPER(stack->current, (char*)stack->current - offset);

    // Move the stack pointer:
    stack->current = STACK_DIR_UPPER((char*)stack->current + offset, (char*)stack->current - offset);
    stack->available -= offset;

    return pointer;
}

// Reset the current stack pointer and available size of the given stack.
inline static void
fiber_pool_vacancy_reset(struct fiber_pool_vacancy * vacancy)
{
    fiber_pool_stack_reset(&vacancy->stack);

    // Consume one page of the stack because it's used for the vacancy list:
    fiber_pool_stack_alloca(&vacancy->stack, RB_PAGE_SIZE);
}

inline static struct fiber_pool_vacancy *
fiber_pool_vacancy_push(struct fiber_pool_vacancy * vacancy, struct fiber_pool_vacancy * head)
{
    vacancy->next = head;

#ifdef FIBER_POOL_ALLOCATION_FREE
    if (head) {
        head->previous = vacancy;
        vacancy->previous = NULL;
    }
#endif

    return vacancy;
}

#ifdef FIBER_POOL_ALLOCATION_FREE
static void
fiber_pool_vacancy_remove(struct fiber_pool_vacancy * vacancy)
{
    if (vacancy->next) {
        vacancy->next->previous = vacancy->previous;
    }

    if (vacancy->previous) {
        vacancy->previous->next = vacancy->next;
    }
    else {
        // It's the head of the list:
        vacancy->stack.pool->vacancies = vacancy->next;
    }
}

inline static struct fiber_pool_vacancy *
fiber_pool_vacancy_pop(struct fiber_pool * pool)
{
    struct fiber_pool_vacancy * vacancy = pool->vacancies;

    if (vacancy) {
        fiber_pool_vacancy_remove(vacancy);
    }

    return vacancy;
}
#else
inline static struct fiber_pool_vacancy *
fiber_pool_vacancy_pop(struct fiber_pool * pool)
{
    struct fiber_pool_vacancy * vacancy = pool->vacancies;

    if (vacancy) {
        pool->vacancies = vacancy->next;
    }

    return vacancy;
}
#endif

// Initialize the vacant stack. The [base, size] allocation should not include the guard page.
// @param base The pointer to the lowest address of the allocated memory.
// @param size The size of the allocated memory.
inline static struct fiber_pool_vacancy *
fiber_pool_vacancy_initialize(struct fiber_pool * fiber_pool, struct fiber_pool_vacancy * vacancies, void * base, size_t size)
{
    struct fiber_pool_vacancy * vacancy = fiber_pool_vacancy_pointer(base, size);

    vacancy->stack.base = base;
    vacancy->stack.size = size;

    fiber_pool_vacancy_reset(vacancy);

    vacancy->stack.pool = fiber_pool;

    return fiber_pool_vacancy_push(vacancy, vacancies);
}

// Allocate a maximum of count stacks, size given by stride.
// @param count the number of stacks to allocate / were allocated.
// @param stride the size of the individual stacks.
// @return [void *] the allocated memory or NULL if allocation failed.
inline static void *
fiber_pool_allocate_memory(size_t * count, size_t stride)
{
    // We use a divide-by-2 strategy to try and allocate memory. We are trying
    // to allocate `count` stacks. In normal situation, this won't fail. But
    // if we ran out of address space, or we are allocating more memory than
    // the system would allow (e.g. overcommit * physical memory + swap), we
    // divide count by two and try again. This condition should only be
    // encountered in edge cases, but we handle it here gracefully.
    while (*count > 1) {
#if defined(_WIN32)
        void * base = VirtualAlloc(0, (*count)*stride, MEM_COMMIT, PAGE_READWRITE);

        if (!base) {
            *count = (*count) >> 1;
        }
        else {
            return base;
        }
#else
        errno = 0;
        void * base = mmap(NULL, (*count)*stride, PROT_READ | PROT_WRITE, FIBER_STACK_FLAGS, -1, 0);

        if (base == MAP_FAILED) {
            // If the allocation fails, count = count / 2, and try again.
            *count = (*count) >> 1;
        }
        else {
#if defined(MADV_FREE_REUSE)
            // On Mac MADV_FREE_REUSE is necessary for the task_info api
            // to keep the accounting accurate as possible when a page is marked as reusable
            // it can possibly not occurring at first call thus re-iterating if necessary.
            while (madvise(base, (*count)*stride, MADV_FREE_REUSE) == -1 && errno == EAGAIN);
#endif
            return base;
        }
#endif
    }

    return NULL;
}

// Given an existing fiber pool, expand it by the specified number of stacks.
// @param count the maximum number of stacks to allocate.
// @return the allocated fiber pool.
// @sa fiber_pool_allocation_free
static struct fiber_pool_allocation *
fiber_pool_expand(struct fiber_pool * fiber_pool, size_t count)
{
    STACK_GROW_DIR_DETECTION;

    size_t size = fiber_pool->size;
    size_t stride = size + RB_PAGE_SIZE;

    // Allocate the memory required for the stacks:
    void * base = fiber_pool_allocate_memory(&count, stride);

    if (base == NULL) {
        rb_raise(rb_eFiberError, "can't alloc machine stack to fiber (%"PRIuSIZE" x %"PRIuSIZE" bytes): %s", count, size, ERRNOMSG);
    }

    struct fiber_pool_vacancy * vacancies = fiber_pool->vacancies;
    struct fiber_pool_allocation * allocation = RB_ALLOC(struct fiber_pool_allocation);

    // Initialize fiber pool allocation:
    allocation->base = base;
    allocation->size = size;
    allocation->stride = stride;
    allocation->count = count;
#ifdef FIBER_POOL_ALLOCATION_FREE
    allocation->used = 0;
#endif
    allocation->pool = fiber_pool;

    if (DEBUG) {
        fprintf(stderr, "fiber_pool_expand(%"PRIuSIZE"): %p, %"PRIuSIZE"/%"PRIuSIZE" x [%"PRIuSIZE":%"PRIuSIZE"]\n",
                count, (void*)fiber_pool, fiber_pool->used, fiber_pool->count, size, fiber_pool->vm_stack_size);
    }

    // Iterate over all stacks, initializing the vacancy list:
    for (size_t i = 0; i < count; i += 1) {
        void * base = (char*)allocation->base + (stride * i);
        void * page = (char*)base + STACK_DIR_UPPER(size, 0);

#if defined(_WIN32)
        DWORD old_protect;

        if (!VirtualProtect(page, RB_PAGE_SIZE, PAGE_READWRITE | PAGE_GUARD, &old_protect)) {
            VirtualFree(allocation->base, 0, MEM_RELEASE);
            rb_raise(rb_eFiberError, "can't set a guard page: %s", ERRNOMSG);
        }
#else
        if (mprotect(page, RB_PAGE_SIZE, PROT_NONE) < 0) {
            munmap(allocation->base, count*stride);
            rb_raise(rb_eFiberError, "can't set a guard page: %s", ERRNOMSG);
        }
#endif

        vacancies = fiber_pool_vacancy_initialize(
            fiber_pool, vacancies,
            (char*)base + STACK_DIR_UPPER(0, RB_PAGE_SIZE),
            size
        );

#ifdef FIBER_POOL_ALLOCATION_FREE
        vacancies->stack.allocation = allocation;
#endif
    }

    // Insert the allocation into the head of the pool:
    allocation->next = fiber_pool->allocations;

#ifdef FIBER_POOL_ALLOCATION_FREE
    if (allocation->next) {
        allocation->next->previous = allocation;
    }

    allocation->previous = NULL;
#endif

    fiber_pool->allocations = allocation;
    fiber_pool->vacancies = vacancies;
    fiber_pool->count += count;

    return allocation;
}

// Initialize the specified fiber pool with the given number of stacks.
// @param vm_stack_size The size of the vm stack to allocate.
static void
fiber_pool_initialize(struct fiber_pool * fiber_pool, size_t size, size_t count, size_t vm_stack_size)
{
    VM_ASSERT(vm_stack_size < size);

    fiber_pool->allocations = NULL;
    fiber_pool->vacancies = NULL;
    fiber_pool->size = ((size / RB_PAGE_SIZE) + 1) * RB_PAGE_SIZE;
    fiber_pool->count = 0;
    fiber_pool->initial_count = count;
    fiber_pool->free_stacks = 1;
    fiber_pool->used = 0;

    fiber_pool->vm_stack_size = vm_stack_size;

    fiber_pool_expand(fiber_pool, count);
}

#ifdef FIBER_POOL_ALLOCATION_FREE
// Free the list of fiber pool allocations.
static void
fiber_pool_allocation_free(struct fiber_pool_allocation * allocation)
{
    STACK_GROW_DIR_DETECTION;

    VM_ASSERT(allocation->used == 0);

    if (DEBUG) fprintf(stderr, "fiber_pool_allocation_free: %p base=%p count=%"PRIuSIZE"\n", (void*)allocation, allocation->base, allocation->count);

    size_t i;
    for (i = 0; i < allocation->count; i += 1) {
        void * base = (char*)allocation->base + (allocation->stride * i) + STACK_DIR_UPPER(0, RB_PAGE_SIZE);

        struct fiber_pool_vacancy * vacancy = fiber_pool_vacancy_pointer(base, allocation->size);

        // Pop the vacant stack off the free list:
        fiber_pool_vacancy_remove(vacancy);
    }

#ifdef _WIN32
    VirtualFree(allocation->base, 0, MEM_RELEASE);
#else
    munmap(allocation->base, allocation->stride * allocation->count);
#endif

    if (allocation->previous) {
        allocation->previous->next = allocation->next;
    }
    else {
        // We are the head of the list, so update the pool:
        allocation->pool->allocations = allocation->next;
    }

    if (allocation->next) {
        allocation->next->previous = allocation->previous;
    }

    allocation->pool->count -= allocation->count;

    ruby_xfree(allocation);
}
#endif

// Acquire a stack from the given fiber pool. If none are available, allocate more.
static struct fiber_pool_stack
fiber_pool_stack_acquire(struct fiber_pool * fiber_pool)
{
    struct fiber_pool_vacancy * vacancy = fiber_pool_vacancy_pop(fiber_pool);

    if (DEBUG) fprintf(stderr, "fiber_pool_stack_acquire: %p used=%"PRIuSIZE"\n", (void*)fiber_pool->vacancies, fiber_pool->used);

    if (!vacancy) {
        const size_t maximum = FIBER_POOL_ALLOCATION_MAXIMUM_SIZE;
        const size_t minimum = fiber_pool->initial_count;

        size_t count = fiber_pool->count;
        if (count > maximum) count = maximum;
        if (count < minimum) count = minimum;

        fiber_pool_expand(fiber_pool, count);

        // The free list should now contain some stacks:
        VM_ASSERT(fiber_pool->vacancies);

        vacancy = fiber_pool_vacancy_pop(fiber_pool);
    }

    VM_ASSERT(vacancy);
    VM_ASSERT(vacancy->stack.base);

#if defined(COROUTINE_SANITIZE_ADDRESS)
    __asan_unpoison_memory_region(fiber_pool_stack_poison_base(&vacancy->stack), fiber_pool_stack_poison_size(&vacancy->stack));
#endif

    // Take the top item from the free list:
    fiber_pool->used += 1;

#ifdef FIBER_POOL_ALLOCATION_FREE
    vacancy->stack.allocation->used += 1;
#endif

    fiber_pool_stack_reset(&vacancy->stack);

    return vacancy->stack;
}

// We advise the operating system that the stack memory pages are no longer being used.
// This introduce some performance overhead but allows system to relaim memory when there is pressure.
static inline void
fiber_pool_stack_free(struct fiber_pool_stack * stack)
{
    void * base = fiber_pool_stack_base(stack);
    size_t size = stack->available;

    // If this is not true, the vacancy information will almost certainly be destroyed:
    VM_ASSERT(size <= (stack->size - RB_PAGE_SIZE));

    if (DEBUG) fprintf(stderr, "fiber_pool_stack_free: %p+%"PRIuSIZE" [base=%p, size=%"PRIuSIZE"]\n", base, size, stack->base, stack->size);

    // The pages being used by the stack can be returned back to the system.
    // That doesn't change the page mapping, but it does allow the system to
    // reclaim the physical memory.
    // Since we no longer care about the data itself, we don't need to page
    // out to disk, since that is costly. Not all systems support that, so
    // we try our best to select the most efficient implementation.
    // In addition, it's actually slightly desirable to not do anything here,
    // but that results in higher memory usage.

#ifdef __wasi__
    // WebAssembly doesn't support madvise, so we just don't do anything.
#elif VM_CHECK_MODE > 0 && defined(MADV_DONTNEED)
    // This immediately discards the pages and the memory is reset to zero.
    madvise(base, size, MADV_DONTNEED);
#elif defined(MADV_FREE_REUSABLE)
    // Darwin / macOS / iOS.
    // Acknowledge the kernel down to the task info api we make this
    // page reusable for future use.
    // As for MADV_FREE_REUSE below we ensure in the rare occasions the task was not
    // completed at the time of the call to re-iterate.
    while (madvise(base, size, MADV_FREE_REUSABLE) == -1 && errno == EAGAIN);
#elif defined(MADV_FREE)
    // Recent Linux.
    madvise(base, size, MADV_FREE);
#elif defined(MADV_DONTNEED)
    // Old Linux.
    madvise(base, size, MADV_DONTNEED);
#elif defined(POSIX_MADV_DONTNEED)
    // Solaris?
    posix_madvise(base, size, POSIX_MADV_DONTNEED);
#elif defined(_WIN32)
    VirtualAlloc(base, size, MEM_RESET, PAGE_READWRITE);
    // Not available in all versions of Windows.
    //DiscardVirtualMemory(base, size);
#endif

#if defined(COROUTINE_SANITIZE_ADDRESS)
    __asan_poison_memory_region(fiber_pool_stack_poison_base(stack), fiber_pool_stack_poison_size(stack));
#endif
}

// Release and return a stack to the vacancy list.
static void
fiber_pool_stack_release(struct fiber_pool_stack * stack)
{
    struct fiber_pool * pool = stack->pool;
    struct fiber_pool_vacancy * vacancy = fiber_pool_vacancy_pointer(stack->base, stack->size);

    if (DEBUG) fprintf(stderr, "fiber_pool_stack_release: %p used=%"PRIuSIZE"\n", stack->base, stack->pool->used);

    // Copy the stack details into the vacancy area:
    vacancy->stack = *stack;
    // After this point, be careful about updating/using state in stack, since it's copied to the vacancy area.

    // Reset the stack pointers and reserve space for the vacancy data:
    fiber_pool_vacancy_reset(vacancy);

    // Push the vacancy into the vancancies list:
    pool->vacancies = fiber_pool_vacancy_push(vacancy, pool->vacancies);
    pool->used -= 1;

#ifdef FIBER_POOL_ALLOCATION_FREE
    struct fiber_pool_allocation * allocation = stack->allocation;

    allocation->used -= 1;

    // Release address space and/or dirty memory:
    if (allocation->used == 0) {
        fiber_pool_allocation_free(allocation);
    }
    else if (stack->pool->free_stacks) {
        fiber_pool_stack_free(&vacancy->stack);
    }
#else
    // This is entirely optional, but clears the dirty flag from the stack
    // memory, so it won't get swapped to disk when there is memory pressure:
    if (stack->pool->free_stacks) {
        fiber_pool_stack_free(&vacancy->stack);
    }
#endif
}

static inline void
ec_switch(rb_thread_t *th, rb_fiber_t *fiber)
{
    rb_execution_context_t *ec = &fiber->cont.saved_ec;
    rb_ractor_set_current_ec(th->ractor, th->ec = ec);
    // ruby_current_execution_context_ptr = th->ec = ec;

    /*
     * timer-thread may set trap interrupt on previous th->ec at any time;
     * ensure we do not delay (or lose) the trap interrupt handling.
     */
    if (th->vm->ractor.main_thread == th &&
        rb_signal_buff_size() > 0) {
        RUBY_VM_SET_TRAP_INTERRUPT(ec);
    }

    VM_ASSERT(ec->fiber_ptr->cont.self == 0 || ec->vm_stack != NULL);
}

static inline void
fiber_restore_thread(rb_thread_t *th, rb_fiber_t *fiber)
{
    ec_switch(th, fiber);
    VM_ASSERT(th->ec->fiber_ptr == fiber);
}

static COROUTINE
fiber_entry(struct coroutine_context * from, struct coroutine_context * to)
{
    rb_fiber_t *fiber = to->argument;

#if defined(COROUTINE_SANITIZE_ADDRESS)
    // Address sanitizer will copy the previous stack base and stack size into
    // the "from" fiber. `coroutine_initialize_main` doesn't generally know the
    // stack bounds (base + size). Therefore, the main fiber `stack_base` and
    // `stack_size` will be NULL/0. It's specifically important in that case to
    // get the (base+size) of the previous fiber and save it, so that later when
    // we return to the main coroutine, we don't supply (NULL, 0) to
    // __sanitizer_start_switch_fiber which royally messes up the internal state
    // of ASAN and causes (sometimes) the following message:
    // "WARNING: ASan is ignoring requested __asan_handle_no_return"
    __sanitizer_finish_switch_fiber(to->fake_stack, (const void**)&from->stack_base, &from->stack_size);
#endif

    rb_thread_t *thread = fiber->cont.saved_ec.thread_ptr;

#ifdef COROUTINE_PTHREAD_CONTEXT
    ruby_thread_set_native(thread);
#endif

    fiber_restore_thread(thread, fiber);

    rb_fiber_start(fiber);

#ifndef COROUTINE_PTHREAD_CONTEXT
    VM_UNREACHABLE(fiber_entry);
#endif
}

// Initialize a fiber's coroutine's machine stack and vm stack.
static VALUE *
fiber_initialize_coroutine(rb_fiber_t *fiber, size_t * vm_stack_size)
{
    struct fiber_pool * fiber_pool = fiber->stack.pool;
    rb_execution_context_t *sec = &fiber->cont.saved_ec;
    void * vm_stack = NULL;

    VM_ASSERT(fiber_pool != NULL);

    fiber->stack = fiber_pool_stack_acquire(fiber_pool);
    vm_stack = fiber_pool_stack_alloca(&fiber->stack, fiber_pool->vm_stack_size);
    *vm_stack_size = fiber_pool->vm_stack_size;

    coroutine_initialize(&fiber->context, fiber_entry, fiber_pool_stack_base(&fiber->stack), fiber->stack.available);

    // The stack for this execution context is the one we allocated:
    sec->machine.stack_start = fiber->stack.current;
    sec->machine.stack_maxsize = fiber->stack.available;

    fiber->context.argument = (void*)fiber;

    return vm_stack;
}

// Release the stack from the fiber, it's execution context, and return it to
// the fiber pool.
static void
fiber_stack_release(rb_fiber_t * fiber)
{
    rb_execution_context_t *ec = &fiber->cont.saved_ec;

    if (DEBUG) fprintf(stderr, "fiber_stack_release: %p, stack.base=%p\n", (void*)fiber, fiber->stack.base);

    // Return the stack back to the fiber pool if it wasn't already:
    if (fiber->stack.base) {
        fiber_pool_stack_release(&fiber->stack);
        fiber->stack.base = NULL;
    }

    // The stack is no longer associated with this execution context:
    rb_ec_clear_vm_stack(ec);
}

static const char *
fiber_status_name(enum fiber_status s)
{
    switch (s) {
      case FIBER_CREATED: return "created";
      case FIBER_RESUMED: return "resumed";
      case FIBER_SUSPENDED: return "suspended";
      case FIBER_TERMINATED: return "terminated";
    }
    VM_UNREACHABLE(fiber_status_name);
    return NULL;
}

static void
fiber_verify(const rb_fiber_t *fiber)
{
#if VM_CHECK_MODE > 0
    VM_ASSERT(fiber->cont.saved_ec.fiber_ptr == fiber);

    switch (fiber->status) {
      case FIBER_RESUMED:
        VM_ASSERT(fiber->cont.saved_ec.vm_stack != NULL);
        break;
      case FIBER_SUSPENDED:
        VM_ASSERT(fiber->cont.saved_ec.vm_stack != NULL);
        break;
      case FIBER_CREATED:
      case FIBER_TERMINATED:
        /* TODO */
        break;
      default:
        VM_UNREACHABLE(fiber_verify);
    }
#endif
}

inline static void
fiber_status_set(rb_fiber_t *fiber, enum fiber_status s)
{
    // if (DEBUG) fprintf(stderr, "fiber: %p, status: %s -> %s\n", (void *)fiber, fiber_status_name(fiber->status), fiber_status_name(s));
    VM_ASSERT(!FIBER_TERMINATED_P(fiber));
    VM_ASSERT(fiber->status != s);
    fiber_verify(fiber);
    fiber->status = s;
}

static rb_context_t *
cont_ptr(VALUE obj)
{
    rb_context_t *cont;

    TypedData_Get_Struct(obj, rb_context_t, &cont_data_type, cont);

    return cont;
}

static rb_fiber_t *
fiber_ptr(VALUE obj)
{
    rb_fiber_t *fiber;

    TypedData_Get_Struct(obj, rb_fiber_t, &fiber_data_type, fiber);
    if (!fiber) rb_raise(rb_eFiberError, "uninitialized fiber");

    return fiber;
}

NOINLINE(static VALUE cont_capture(volatile int *volatile stat));

#define THREAD_MUST_BE_RUNNING(th) do { \
        if (!(th)->ec->tag) rb_raise(rb_eThreadError, "not running thread"); \
    } while (0)

rb_thread_t*
rb_fiber_threadptr(const rb_fiber_t *fiber)
{
    return fiber->cont.saved_ec.thread_ptr;
}

static VALUE
cont_thread_value(const rb_context_t *cont)
{
    return cont->saved_ec.thread_ptr->self;
}

static void
cont_compact(void *ptr)
{
    rb_context_t *cont = ptr;

    if (cont->self) {
        cont->self = rb_gc_location(cont->self);
    }
    cont->value = rb_gc_location(cont->value);
    rb_execution_context_update(&cont->saved_ec);
}

static void
cont_mark(void *ptr)
{
    rb_context_t *cont = ptr;

    RUBY_MARK_ENTER("cont");
    if (cont->self) {
        rb_gc_mark_movable(cont->self);
    }
    rb_gc_mark_movable(cont->value);

    rb_execution_context_mark(&cont->saved_ec);
    rb_gc_mark(cont_thread_value(cont));

    if (cont->saved_vm_stack.ptr) {
#ifdef CAPTURE_JUST_VALID_VM_STACK
        rb_gc_mark_locations(cont->saved_vm_stack.ptr,
                             cont->saved_vm_stack.ptr + cont->saved_vm_stack.slen + cont->saved_vm_stack.clen);
#else
        rb_gc_mark_locations(cont->saved_vm_stack.ptr,
                             cont->saved_vm_stack.ptr, cont->saved_ec.stack_size);
#endif
    }

    if (cont->machine.stack) {
        if (cont->type == CONTINUATION_CONTEXT) {
            /* cont */
            rb_gc_mark_locations(cont->machine.stack,
                                 cont->machine.stack + cont->machine.stack_size);
        }
        else {
            /* fiber */
            const rb_fiber_t *fiber = (rb_fiber_t*)cont;

            if (!FIBER_TERMINATED_P(fiber)) {
                rb_gc_mark_locations(cont->machine.stack,
                                     cont->machine.stack + cont->machine.stack_size);
            }
        }
    }

    RUBY_MARK_LEAVE("cont");
}

#if 0
static int
fiber_is_root_p(const rb_fiber_t *fiber)
{
    return fiber == fiber->cont.saved_ec.thread_ptr->root_fiber;
}
#endif

static void jit_cont_free(struct rb_jit_cont *cont);

static void
cont_free(void *ptr)
{
    rb_context_t *cont = ptr;

    RUBY_FREE_ENTER("cont");

    if (cont->type == CONTINUATION_CONTEXT) {
        ruby_xfree(cont->saved_ec.vm_stack);
        ruby_xfree(cont->ensure_array);
        RUBY_FREE_UNLESS_NULL(cont->machine.stack);
    }
    else {
        rb_fiber_t *fiber = (rb_fiber_t*)cont;
        coroutine_destroy(&fiber->context);
        fiber_stack_release(fiber);
    }

    RUBY_FREE_UNLESS_NULL(cont->saved_vm_stack.ptr);

    if (jit_cont_enabled) {
        VM_ASSERT(cont->jit_cont != NULL);
        jit_cont_free(cont->jit_cont);
    }
    /* free rb_cont_t or rb_fiber_t */
    ruby_xfree(ptr);
    RUBY_FREE_LEAVE("cont");
}

static size_t
cont_memsize(const void *ptr)
{
    const rb_context_t *cont = ptr;
    size_t size = 0;

    size = sizeof(*cont);
    if (cont->saved_vm_stack.ptr) {
#ifdef CAPTURE_JUST_VALID_VM_STACK
        size_t n = (cont->saved_vm_stack.slen + cont->saved_vm_stack.clen);
#else
        size_t n = cont->saved_ec.vm_stack_size;
#endif
        size += n * sizeof(*cont->saved_vm_stack.ptr);
    }

    if (cont->machine.stack) {
        size += cont->machine.stack_size * sizeof(*cont->machine.stack);
    }

    return size;
}

void
rb_fiber_update_self(rb_fiber_t *fiber)
{
    if (fiber->cont.self) {
        fiber->cont.self = rb_gc_location(fiber->cont.self);
    }
    else {
        rb_execution_context_update(&fiber->cont.saved_ec);
    }
}

void
rb_fiber_mark_self(const rb_fiber_t *fiber)
{
    if (fiber->cont.self) {
        rb_gc_mark_movable(fiber->cont.self);
    }
    else {
        rb_execution_context_mark(&fiber->cont.saved_ec);
    }
}

static void
fiber_compact(void *ptr)
{
    rb_fiber_t *fiber = ptr;
    fiber->first_proc = rb_gc_location(fiber->first_proc);

    if (fiber->prev) rb_fiber_update_self(fiber->prev);

    cont_compact(&fiber->cont);
    fiber_verify(fiber);
}

static void
fiber_mark(void *ptr)
{
    rb_fiber_t *fiber = ptr;
    RUBY_MARK_ENTER("cont");
    fiber_verify(fiber);
    rb_gc_mark_movable(fiber->first_proc);
    if (fiber->prev) rb_fiber_mark_self(fiber->prev);
    cont_mark(&fiber->cont);
    RUBY_MARK_LEAVE("cont");
}

static void
fiber_free(void *ptr)
{
    rb_fiber_t *fiber = ptr;
    RUBY_FREE_ENTER("fiber");

    if (DEBUG) fprintf(stderr, "fiber_free: %p[%p]\n", (void *)fiber, fiber->stack.base);

    if (fiber->cont.saved_ec.local_storage) {
        rb_id_table_free(fiber->cont.saved_ec.local_storage);
    }

    cont_free(&fiber->cont);
    RUBY_FREE_LEAVE("fiber");
}

static size_t
fiber_memsize(const void *ptr)
{
    const rb_fiber_t *fiber = ptr;
    size_t size = sizeof(*fiber);
    const rb_execution_context_t *saved_ec = &fiber->cont.saved_ec;
    const rb_thread_t *th = rb_ec_thread_ptr(saved_ec);

    /*
     * vm.c::thread_memsize already counts th->ec->local_storage
     */
    if (saved_ec->local_storage && fiber != th->root_fiber) {
        size += rb_id_table_memsize(saved_ec->local_storage);
        size += rb_obj_memsize_of(saved_ec->storage);
    }

    size += cont_memsize(&fiber->cont);
    return size;
}

VALUE
rb_obj_is_fiber(VALUE obj)
{
    return RBOOL(rb_typeddata_is_kind_of(obj, &fiber_data_type));
}

static void
cont_save_machine_stack(rb_thread_t *th, rb_context_t *cont)
{
    size_t size;

    SET_MACHINE_STACK_END(&th->ec->machine.stack_end);

    if (th->ec->machine.stack_start > th->ec->machine.stack_end) {
        size = cont->machine.stack_size = th->ec->machine.stack_start - th->ec->machine.stack_end;
        cont->machine.stack_src = th->ec->machine.stack_end;
    }
    else {
        size = cont->machine.stack_size = th->ec->machine.stack_end - th->ec->machine.stack_start;
        cont->machine.stack_src = th->ec->machine.stack_start;
    }

    if (cont->machine.stack) {
        REALLOC_N(cont->machine.stack, VALUE, size);
    }
    else {
        cont->machine.stack = ALLOC_N(VALUE, size);
    }

    FLUSH_REGISTER_WINDOWS;
    asan_unpoison_memory_region(cont->machine.stack_src, size, false);
    MEMCPY(cont->machine.stack, cont->machine.stack_src, VALUE, size);
}

static const rb_data_type_t cont_data_type = {
    "continuation",
    {cont_mark, cont_free, cont_memsize, cont_compact},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static inline void
cont_save_thread(rb_context_t *cont, rb_thread_t *th)
{
    rb_execution_context_t *sec = &cont->saved_ec;

    VM_ASSERT(th->status == THREAD_RUNNABLE);

    /* save thread context */
    *sec = *th->ec;

    /* saved_ec->machine.stack_end should be NULL */
    /* because it may happen GC afterward */
    sec->machine.stack_end = NULL;
}

static rb_nativethread_lock_t jit_cont_lock;

// Register a new continuation with execution context `ec`. Return JIT info about
// the continuation.
static struct rb_jit_cont *
jit_cont_new(rb_execution_context_t *ec)
{
    struct rb_jit_cont *cont;

    // We need to use calloc instead of something like ZALLOC to avoid triggering GC here.
    // When this function is called from rb_thread_alloc through rb_threadptr_root_fiber_setup,
    // the thread is still being prepared and marking it causes SEGV.
    cont = calloc(1, sizeof(struct rb_jit_cont));
    if (cont == NULL)
        rb_memerror();
    cont->ec = ec;

    rb_native_mutex_lock(&jit_cont_lock);
    if (first_jit_cont == NULL) {
        cont->next = cont->prev = NULL;
    }
    else {
        cont->prev = NULL;
        cont->next = first_jit_cont;
        first_jit_cont->prev = cont;
    }
    first_jit_cont = cont;
    rb_native_mutex_unlock(&jit_cont_lock);

    return cont;
}

// Unregister continuation `cont`.
static void
jit_cont_free(struct rb_jit_cont *cont)
{
    if (!cont) return;

    rb_native_mutex_lock(&jit_cont_lock);
    if (cont == first_jit_cont) {
        first_jit_cont = cont->next;
        if (first_jit_cont != NULL)
            first_jit_cont->prev = NULL;
    }
    else {
        cont->prev->next = cont->next;
        if (cont->next != NULL)
            cont->next->prev = cont->prev;
    }
    rb_native_mutex_unlock(&jit_cont_lock);

    free(cont);
}

// Call a given callback against all on-stack ISEQs.
void
rb_jit_cont_each_iseq(rb_iseq_callback callback, void *data)
{
    struct rb_jit_cont *cont;
    for (cont = first_jit_cont; cont != NULL; cont = cont->next) {
        if (cont->ec->vm_stack == NULL)
            continue;

        const rb_control_frame_t *cfp;
        for (cfp = RUBY_VM_END_CONTROL_FRAME(cont->ec) - 1; ; cfp = RUBY_VM_NEXT_CONTROL_FRAME(cfp)) {
            const rb_iseq_t *iseq;
            if (cfp->pc && (iseq = cfp->iseq) != NULL && imemo_type((VALUE)iseq) == imemo_iseq) {
                callback(iseq, data);
            }

            if (cfp == cont->ec->cfp)
                break; // reached the most recent cfp
        }
    }
}

// Finish working with jit_cont.
void
rb_jit_cont_finish(void)
{
    if (!jit_cont_enabled)
        return;

    struct rb_jit_cont *cont, *next;
    for (cont = first_jit_cont; cont != NULL; cont = next) {
        next = cont->next;
        free(cont); // Don't use xfree because it's allocated by calloc.
    }
    rb_native_mutex_destroy(&jit_cont_lock);
}

static void
cont_init_jit_cont(rb_context_t *cont)
{
    VM_ASSERT(cont->jit_cont == NULL);
    if (jit_cont_enabled) {
        cont->jit_cont = jit_cont_new(&(cont->saved_ec));
    }
}

struct rb_execution_context_struct *
rb_fiberptr_get_ec(struct rb_fiber_struct *fiber)
{
    return &fiber->cont.saved_ec;
}

static void
cont_init(rb_context_t *cont, rb_thread_t *th)
{
    /* save thread context */
    cont_save_thread(cont, th);
    cont->saved_ec.thread_ptr = th;
    cont->saved_ec.local_storage = NULL;
    cont->saved_ec.local_storage_recursive_hash = Qnil;
    cont->saved_ec.local_storage_recursive_hash_for_trace = Qnil;
    cont_init_jit_cont(cont);
}

static rb_context_t *
cont_new(VALUE klass)
{
    rb_context_t *cont;
    volatile VALUE contval;
    rb_thread_t *th = GET_THREAD();

    THREAD_MUST_BE_RUNNING(th);
    contval = TypedData_Make_Struct(klass, rb_context_t, &cont_data_type, cont);
    cont->self = contval;
    cont_init(cont, th);
    return cont;
}

VALUE
rb_fiberptr_self(struct rb_fiber_struct *fiber)
{
    return fiber->cont.self;
}

unsigned int
rb_fiberptr_blocking(struct rb_fiber_struct *fiber)
{
    return fiber->blocking;
}

// Start working with jit_cont.
void
rb_jit_cont_init(void)
{
    if (!jit_cont_enabled)
        return;

    rb_native_mutex_initialize(&jit_cont_lock);
    cont_init_jit_cont(&GET_EC()->fiber_ptr->cont);
}

#if 0
void
show_vm_stack(const rb_execution_context_t *ec)
{
    VALUE *p = ec->vm_stack;
    while (p < ec->cfp->sp) {
        fprintf(stderr, "%3d ", (int)(p - ec->vm_stack));
        rb_obj_info_dump(*p);
        p++;
    }
}

void
show_vm_pcs(const rb_control_frame_t *cfp,
            const rb_control_frame_t *end_of_cfp)
{
    int i=0;
    while (cfp != end_of_cfp) {
        int pc = 0;
        if (cfp->iseq) {
            pc = cfp->pc - ISEQ_BODY(cfp->iseq)->iseq_encoded;
        }
        fprintf(stderr, "%2d pc: %d\n", i++, pc);
        cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
}
#endif

static VALUE
cont_capture(volatile int *volatile stat)
{
    rb_context_t *volatile cont;
    rb_thread_t *th = GET_THREAD();
    volatile VALUE contval;
    const rb_execution_context_t *ec = th->ec;

    THREAD_MUST_BE_RUNNING(th);
    rb_vm_stack_to_heap(th->ec);
    cont = cont_new(rb_cContinuation);
    contval = cont->self;

#ifdef CAPTURE_JUST_VALID_VM_STACK
    cont->saved_vm_stack.slen = ec->cfp->sp - ec->vm_stack;
    cont->saved_vm_stack.clen = ec->vm_stack + ec->vm_stack_size - (VALUE*)ec->cfp;
    cont->saved_vm_stack.ptr = ALLOC_N(VALUE, cont->saved_vm_stack.slen + cont->saved_vm_stack.clen);
    MEMCPY(cont->saved_vm_stack.ptr,
           ec->vm_stack,
           VALUE, cont->saved_vm_stack.slen);
    MEMCPY(cont->saved_vm_stack.ptr + cont->saved_vm_stack.slen,
           (VALUE*)ec->cfp,
           VALUE,
           cont->saved_vm_stack.clen);
#else
    cont->saved_vm_stack.ptr = ALLOC_N(VALUE, ec->vm_stack_size);
    MEMCPY(cont->saved_vm_stack.ptr, ec->vm_stack, VALUE, ec->vm_stack_size);
#endif
    // At this point, `cfp` is valid but `vm_stack` should be cleared:
    rb_ec_set_vm_stack(&cont->saved_ec, NULL, 0);
    VM_ASSERT(cont->saved_ec.cfp != NULL);
    cont_save_machine_stack(th, cont);

    /* backup ensure_list to array for search in another context */
    {
        rb_ensure_list_t *p;
        int size = 0;
        rb_ensure_entry_t *entry;
        for (p=th->ec->ensure_list; p; p=p->next)
            size++;
        entry = cont->ensure_array = ALLOC_N(rb_ensure_entry_t,size+1);
        for (p=th->ec->ensure_list; p; p=p->next) {
            if (!p->entry.marker)
                p->entry.marker = rb_ary_hidden_new(0); /* dummy object */
            *entry++ = p->entry;
        }
        entry->marker = 0;
    }

    if (ruby_setjmp(cont->jmpbuf)) {
        VALUE value;

        VAR_INITIALIZED(cont);
        value = cont->value;
        if (cont->argc == -1) rb_exc_raise(value);
        cont->value = Qnil;
        *stat = 1;
        return value;
    }
    else {
        *stat = 0;
        return contval;
    }
}

static inline void
cont_restore_thread(rb_context_t *cont)
{
    rb_thread_t *th = GET_THREAD();

    /* restore thread context */
    if (cont->type == CONTINUATION_CONTEXT) {
        /* continuation */
        rb_execution_context_t *sec = &cont->saved_ec;
        rb_fiber_t *fiber = NULL;

        if (sec->fiber_ptr != NULL) {
            fiber = sec->fiber_ptr;
        }
        else if (th->root_fiber) {
            fiber = th->root_fiber;
        }

        if (fiber && th->ec != &fiber->cont.saved_ec) {
            ec_switch(th, fiber);
        }

        if (th->ec->trace_arg != sec->trace_arg) {
            rb_raise(rb_eRuntimeError, "can't call across trace_func");
        }

        /* copy vm stack */
#ifdef CAPTURE_JUST_VALID_VM_STACK
        MEMCPY(th->ec->vm_stack,
               cont->saved_vm_stack.ptr,
               VALUE, cont->saved_vm_stack.slen);
        MEMCPY(th->ec->vm_stack + th->ec->vm_stack_size - cont->saved_vm_stack.clen,
               cont->saved_vm_stack.ptr + cont->saved_vm_stack.slen,
               VALUE, cont->saved_vm_stack.clen);
#else
        MEMCPY(th->ec->vm_stack, cont->saved_vm_stack.ptr, VALUE, sec->vm_stack_size);
#endif
        /* other members of ec */

        th->ec->cfp = sec->cfp;
        th->ec->raised_flag = sec->raised_flag;
        th->ec->tag = sec->tag;
        th->ec->root_lep = sec->root_lep;
        th->ec->root_svar = sec->root_svar;
        th->ec->ensure_list = sec->ensure_list;
        th->ec->errinfo = sec->errinfo;

        VM_ASSERT(th->ec->vm_stack != NULL);
    }
    else {
        /* fiber */
        fiber_restore_thread(th, (rb_fiber_t*)cont);
    }
}

NOINLINE(static void fiber_setcontext(rb_fiber_t *new_fiber, rb_fiber_t *old_fiber));

static void
fiber_setcontext(rb_fiber_t *new_fiber, rb_fiber_t *old_fiber)
{
    rb_thread_t *th = GET_THREAD();

    /* save old_fiber's machine stack - to ensure efficient garbage collection */
    if (!FIBER_TERMINATED_P(old_fiber)) {
        STACK_GROW_DIR_DETECTION;
        SET_MACHINE_STACK_END(&th->ec->machine.stack_end);
        if (STACK_DIR_UPPER(0, 1)) {
            old_fiber->cont.machine.stack_size = th->ec->machine.stack_start - th->ec->machine.stack_end;
            old_fiber->cont.machine.stack = th->ec->machine.stack_end;
        }
        else {
            old_fiber->cont.machine.stack_size = th->ec->machine.stack_end - th->ec->machine.stack_start;
            old_fiber->cont.machine.stack = th->ec->machine.stack_start;
        }
    }

    /* exchange machine_stack_start between old_fiber and new_fiber */
    old_fiber->cont.saved_ec.machine.stack_start = th->ec->machine.stack_start;

    /* old_fiber->machine.stack_end should be NULL */
    old_fiber->cont.saved_ec.machine.stack_end = NULL;

    // if (DEBUG) fprintf(stderr, "fiber_setcontext: %p[%p] -> %p[%p]\n", (void*)old_fiber, old_fiber->stack.base, (void*)new_fiber, new_fiber->stack.base);

#if defined(COROUTINE_SANITIZE_ADDRESS)
    __sanitizer_start_switch_fiber(FIBER_TERMINATED_P(old_fiber) ? NULL : &old_fiber->context.fake_stack, new_fiber->context.stack_base, new_fiber->context.stack_size);
#endif

    /* swap machine context */
    struct coroutine_context * from = coroutine_transfer(&old_fiber->context, &new_fiber->context);

#if defined(COROUTINE_SANITIZE_ADDRESS)
    __sanitizer_finish_switch_fiber(old_fiber->context.fake_stack, NULL, NULL);
#endif

    if (from == NULL) {
        rb_syserr_fail(errno, "coroutine_transfer");
    }

    /* restore thread context */
    fiber_restore_thread(th, old_fiber);

    // It's possible to get here, and new_fiber is already freed.
    // if (DEBUG) fprintf(stderr, "fiber_setcontext: %p[%p] <- %p[%p]\n", (void*)old_fiber, old_fiber->stack.base, (void*)new_fiber, new_fiber->stack.base);
}

NOINLINE(NORETURN(static void cont_restore_1(rb_context_t *)));

static void
cont_restore_1(rb_context_t *cont)
{
    cont_restore_thread(cont);

    /* restore machine stack */
#if defined(_M_AMD64) && !defined(__MINGW64__)
    {
        /* workaround for x64 SEH */
        jmp_buf buf;
        setjmp(buf);
        _JUMP_BUFFER *bp = (void*)&cont->jmpbuf;
        bp->Frame = ((_JUMP_BUFFER*)((void*)&buf))->Frame;
    }
#endif
    if (cont->machine.stack_src) {
        FLUSH_REGISTER_WINDOWS;
        MEMCPY(cont->machine.stack_src, cont->machine.stack,
               VALUE, cont->machine.stack_size);
    }

    ruby_longjmp(cont->jmpbuf, 1);
}

NORETURN(NOINLINE(static void cont_restore_0(rb_context_t *, VALUE *)));

static void
cont_restore_0(rb_context_t *cont, VALUE *addr_in_prev_frame)
{
    if (cont->machine.stack_src) {
#ifdef HAVE_ALLOCA
#define STACK_PAD_SIZE 1
#else
#define STACK_PAD_SIZE 1024
#endif
        VALUE space[STACK_PAD_SIZE];

#if !STACK_GROW_DIRECTION
        if (addr_in_prev_frame > &space[0]) {
            /* Stack grows downward */
#endif
#if STACK_GROW_DIRECTION <= 0
            volatile VALUE *const end = cont->machine.stack_src;
            if (&space[0] > end) {
# ifdef HAVE_ALLOCA
                volatile VALUE *sp = ALLOCA_N(VALUE, &space[0] - end);
                // We need to make sure that the stack pointer is moved,
                // but some compilers may remove the allocation by optimization.
                // We hope that the following read/write will prevent such an optimization.
                *sp = Qfalse;
                space[0] = *sp;
# else
                cont_restore_0(cont, &space[0]);
# endif
            }
#endif
#if !STACK_GROW_DIRECTION
        }
        else {
            /* Stack grows upward */
#endif
#if STACK_GROW_DIRECTION >= 0
            volatile VALUE *const end = cont->machine.stack_src + cont->machine.stack_size;
            if (&space[STACK_PAD_SIZE] < end) {
# ifdef HAVE_ALLOCA
                volatile VALUE *sp = ALLOCA_N(VALUE, end - &space[STACK_PAD_SIZE]);
                space[0] = *sp;
# else
                cont_restore_0(cont, &space[STACK_PAD_SIZE-1]);
# endif
            }
#endif
#if !STACK_GROW_DIRECTION
        }
#endif
    }
    cont_restore_1(cont);
}

/*
 *  Document-class: Continuation
 *
 *  Continuation objects are generated by Kernel#callcc,
 *  after having +require+d <i>continuation</i>. They hold
 *  a return address and execution context, allowing a nonlocal return
 *  to the end of the #callcc block from anywhere within a
 *  program. Continuations are somewhat analogous to a structured
 *  version of C's <code>setjmp/longjmp</code> (although they contain
 *  more state, so you might consider them closer to threads).
 *
 *  For instance:
 *
 *     require "continuation"
 *     arr = [ "Freddie", "Herbie", "Ron", "Max", "Ringo" ]
 *     callcc{|cc| $cc = cc}
 *     puts(message = arr.shift)
 *     $cc.call unless message =~ /Max/
 *
 *  <em>produces:</em>
 *
 *     Freddie
 *     Herbie
 *     Ron
 *     Max
 *
 *  Also you can call callcc in other methods:
 *
 *     require "continuation"
 *
 *     def g
 *       arr = [ "Freddie", "Herbie", "Ron", "Max", "Ringo" ]
 *       cc = callcc { |cc| cc }
 *       puts arr.shift
 *       return cc, arr.size
 *     end
 *
 *     def f
 *       c, size = g
 *       c.call(c) if size > 1
 *     end
 *
 *     f
 *
 *  This (somewhat contrived) example allows the inner loop to abandon
 *  processing early:
 *
 *     require "continuation"
 *     callcc {|cont|
 *       for i in 0..4
 *         print "#{i}: "
 *         for j in i*5...(i+1)*5
 *           cont.call() if j == 17
 *           printf "%3d", j
 *         end
 *       end
 *     }
 *     puts
 *
 *  <em>produces:</em>
 *
 *     0:   0  1  2  3  4
 *     1:   5  6  7  8  9
 *     2:  10 11 12 13 14
 *     3:  15 16
 */

/*
 *  call-seq:
 *     callcc {|cont| block }   ->  obj
 *
 *  Generates a Continuation object, which it passes to
 *  the associated block. You need to <code>require
 *  'continuation'</code> before using this method. Performing a
 *  <em>cont</em><code>.call</code> will cause the #callcc
 *  to return (as will falling through the end of the block). The
 *  value returned by the #callcc is the value of the
 *  block, or the value passed to <em>cont</em><code>.call</code>. See
 *  class Continuation for more details. Also see
 *  Kernel#throw for an alternative mechanism for
 *  unwinding a call stack.
 */

static VALUE
rb_callcc(VALUE self)
{
    volatile int called;
    volatile VALUE val = cont_capture(&called);

    if (called) {
        return val;
    }
    else {
        return rb_yield(val);
    }
}

static VALUE
make_passing_arg(int argc, const VALUE *argv)
{
    switch (argc) {
      case -1:
        return argv[0];
      case 0:
        return Qnil;
      case 1:
        return argv[0];
      default:
        return rb_ary_new4(argc, argv);
    }
}

typedef VALUE e_proc(VALUE);

/* CAUTION!! : Currently, error in rollback_func is not supported  */
/* same as rb_protect if set rollback_func to NULL */
void
ruby_register_rollback_func_for_ensure(e_proc *ensure_func, e_proc *rollback_func)
{
    st_table **table_p = &GET_VM()->ensure_rollback_table;
    if (UNLIKELY(*table_p == NULL)) {
        *table_p = st_init_numtable();
    }
    st_insert(*table_p, (st_data_t)ensure_func, (st_data_t)rollback_func);
}

static inline e_proc *
lookup_rollback_func(e_proc *ensure_func)
{
    st_table *table = GET_VM()->ensure_rollback_table;
    st_data_t val;
    if (table && st_lookup(table, (st_data_t)ensure_func, &val))
        return (e_proc *) val;
    return (e_proc *) Qundef;
}


static inline void
rollback_ensure_stack(VALUE self,rb_ensure_list_t *current,rb_ensure_entry_t *target)
{
    rb_ensure_list_t *p;
    rb_ensure_entry_t *entry;
    size_t i, j;
    size_t cur_size;
    size_t target_size;
    size_t base_point;
    e_proc *func;

    cur_size = 0;
    for (p=current; p; p=p->next)
        cur_size++;
    target_size = 0;
    for (entry=target; entry->marker; entry++)
        target_size++;

    /* search common stack point */
    p = current;
    base_point = cur_size;
    while (base_point) {
        if (target_size >= base_point &&
            p->entry.marker == target[target_size - base_point].marker)
            break;
        base_point --;
        p = p->next;
    }

    /* rollback function check */
    for (i=0; i < target_size - base_point; i++) {
        if (!lookup_rollback_func(target[i].e_proc)) {
            rb_raise(rb_eRuntimeError, "continuation called from out of critical rb_ensure scope");
        }
    }
    /* pop ensure stack */
    while (cur_size > base_point) {
        /* escape from ensure block */
        (*current->entry.e_proc)(current->entry.data2);
        current = current->next;
        cur_size--;
    }
    /* push ensure stack */
    for (j = 0; j < i; j++) {
        func = lookup_rollback_func(target[i - j - 1].e_proc);
        if (!UNDEF_P((VALUE)func)) {
            (*func)(target[i - j - 1].data2);
        }
    }
}

NORETURN(static VALUE rb_cont_call(int argc, VALUE *argv, VALUE contval));

/*
 *  call-seq:
 *     cont.call(args, ...)
 *     cont[args, ...]
 *
 *  Invokes the continuation. The program continues from the end of
 *  the #callcc block. If no arguments are given, the original #callcc
 *  returns +nil+. If one argument is given, #callcc returns
 *  it. Otherwise, an array containing <i>args</i> is returned.
 *
 *     callcc {|cont|  cont.call }           #=> nil
 *     callcc {|cont|  cont.call 1 }         #=> 1
 *     callcc {|cont|  cont.call 1, 2, 3 }   #=> [1, 2, 3]
 */

static VALUE
rb_cont_call(int argc, VALUE *argv, VALUE contval)
{
    rb_context_t *cont = cont_ptr(contval);
    rb_thread_t *th = GET_THREAD();

    if (cont_thread_value(cont) != th->self) {
        rb_raise(rb_eRuntimeError, "continuation called across threads");
    }
    if (cont->saved_ec.fiber_ptr) {
        if (th->ec->fiber_ptr != cont->saved_ec.fiber_ptr) {
            rb_raise(rb_eRuntimeError, "continuation called across fiber");
        }
    }
    rollback_ensure_stack(contval, th->ec->ensure_list, cont->ensure_array);

    cont->argc = argc;
    cont->value = make_passing_arg(argc, argv);

    cont_restore_0(cont, &contval);
    UNREACHABLE_RETURN(Qnil);
}

/*********/
/* fiber */
/*********/

/*
 *  Document-class: Fiber
 *
 *  Fibers are primitives for implementing light weight cooperative
 *  concurrency in Ruby. Basically they are a means of creating code blocks
 *  that can be paused and resumed, much like threads. The main difference
 *  is that they are never preempted and that the scheduling must be done by
 *  the programmer and not the VM.
 *
 *  As opposed to other stackless light weight concurrency models, each fiber
 *  comes with a stack.  This enables the fiber to be paused from deeply
 *  nested function calls within the fiber block.  See the ruby(1)
 *  manpage to configure the size of the fiber stack(s).
 *
 *  When a fiber is created it will not run automatically. Rather it must
 *  be explicitly asked to run using the Fiber#resume method.
 *  The code running inside the fiber can give up control by calling
 *  Fiber.yield in which case it yields control back to caller (the
 *  caller of the Fiber#resume).
 *
 *  Upon yielding or termination the Fiber returns the value of the last
 *  executed expression
 *
 *  For instance:
 *
 *    fiber = Fiber.new do
 *      Fiber.yield 1
 *      2
 *    end
 *
 *    puts fiber.resume
 *    puts fiber.resume
 *    puts fiber.resume
 *
 *  <em>produces</em>
 *
 *    1
 *    2
 *    FiberError: dead fiber called
 *
 *  The Fiber#resume method accepts an arbitrary number of parameters,
 *  if it is the first call to #resume then they will be passed as
 *  block arguments. Otherwise they will be the return value of the
 *  call to Fiber.yield
 *
 *  Example:
 *
 *    fiber = Fiber.new do |first|
 *      second = Fiber.yield first + 2
 *    end
 *
 *    puts fiber.resume 10
 *    puts fiber.resume 1_000_000
 *    puts fiber.resume "The fiber will be dead before I can cause trouble"
 *
 *  <em>produces</em>
 *
 *    12
 *    1000000
 *    FiberError: dead fiber called
 *
 *  == Non-blocking Fibers
 *
 *  The concept of <em>non-blocking fiber</em> was introduced in Ruby 3.0.
 *  A non-blocking fiber, when reaching a operation that would normally block
 *  the fiber (like <code>sleep</code>, or wait for another process or I/O)
 *  will yield control to other fibers and allow the <em>scheduler</em> to
 *  handle blocking and waking up (resuming) this fiber when it can proceed.
 *
 *  For a Fiber to behave as non-blocking, it need to be created in Fiber.new with
 *  <tt>blocking: false</tt> (which is the default), and Fiber.scheduler
 *  should be set with Fiber.set_scheduler. If Fiber.scheduler is not set in
 *  the current thread, blocking and non-blocking fibers' behavior is identical.
 *
 *  Ruby doesn't provide a scheduler class: it is expected to be implemented by
 *  the user and correspond to Fiber::Scheduler.
 *
 *  There is also Fiber.schedule method, which is expected to immediately perform
 *  the given block in a non-blocking manner. Its actual implementation is up to
 *  the scheduler.
 *
 */

static const rb_data_type_t fiber_data_type = {
    "fiber",
    {fiber_mark, fiber_free, fiber_memsize, fiber_compact,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
fiber_alloc(VALUE klass)
{
    return TypedData_Wrap_Struct(klass, &fiber_data_type, 0);
}

static rb_fiber_t*
fiber_t_alloc(VALUE fiber_value, unsigned int blocking)
{
    rb_fiber_t *fiber;
    rb_thread_t *th = GET_THREAD();

    if (DATA_PTR(fiber_value) != 0) {
        rb_raise(rb_eRuntimeError, "cannot initialize twice");
    }

    THREAD_MUST_BE_RUNNING(th);
    fiber = ZALLOC(rb_fiber_t);
    fiber->cont.self = fiber_value;
    fiber->cont.type = FIBER_CONTEXT;
    fiber->blocking = blocking;
    cont_init(&fiber->cont, th);

    fiber->cont.saved_ec.fiber_ptr = fiber;
    rb_ec_clear_vm_stack(&fiber->cont.saved_ec);

    fiber->prev = NULL;

    /* fiber->status == 0 == CREATED
     * So that we don't need to set status: fiber_status_set(fiber, FIBER_CREATED); */
    VM_ASSERT(FIBER_CREATED_P(fiber));

    DATA_PTR(fiber_value) = fiber;

    return fiber;
}

static rb_fiber_t *
root_fiber_alloc(rb_thread_t *th)
{
    VALUE fiber_value = fiber_alloc(rb_cFiber);
    rb_fiber_t *fiber = th->ec->fiber_ptr;

    VM_ASSERT(DATA_PTR(fiber_value) == NULL);
    VM_ASSERT(fiber->cont.type == FIBER_CONTEXT);
    VM_ASSERT(FIBER_RESUMED_P(fiber));

    th->root_fiber = fiber;
    DATA_PTR(fiber_value) = fiber;
    fiber->cont.self = fiber_value;

    coroutine_initialize_main(&fiber->context);

    return fiber;
}

static inline rb_fiber_t*
fiber_current(void)
{
    rb_execution_context_t *ec = GET_EC();
    if (ec->fiber_ptr->cont.self == 0) {
        root_fiber_alloc(rb_ec_thread_ptr(ec));
    }
    return ec->fiber_ptr;
}

static inline VALUE
current_fiber_storage(void)
{
    rb_execution_context_t *ec = GET_EC();
    return ec->storage;
}

static inline VALUE
inherit_fiber_storage(void)
{
    return rb_obj_dup(current_fiber_storage());
}

static inline void
fiber_storage_set(struct rb_fiber_struct *fiber, VALUE storage)
{
    fiber->cont.saved_ec.storage = storage;
}

static inline VALUE
fiber_storage_get(rb_fiber_t *fiber)
{
    VALUE storage = fiber->cont.saved_ec.storage;
    if (storage == Qnil) {
        storage = rb_hash_new();
        fiber_storage_set(fiber, storage);
    }
    return storage;
}

static void
storage_access_must_be_from_same_fiber(VALUE self)
{
    rb_fiber_t *fiber = fiber_ptr(self);
    rb_fiber_t *current = fiber_current();
    if (fiber != current) {
        rb_raise(rb_eArgError, "Fiber storage can only be accessed from the Fiber it belongs to");
    }
}

/**
 *  call-seq: fiber.storage -> hash (dup)
 *
 *  Returns a copy of the storage hash for the fiber. The method can only be called on the
 *  Fiber.current.
 */
static VALUE
rb_fiber_storage_get(VALUE self)
{
    storage_access_must_be_from_same_fiber(self);
    return rb_obj_dup(fiber_storage_get(fiber_ptr(self)));
}

static int
fiber_storage_validate_each(VALUE key, VALUE value, VALUE _argument)
{
    Check_Type(key, T_SYMBOL);

    return ST_CONTINUE;
}

static void
fiber_storage_validate(VALUE value)
{
    // nil is an allowed value and will be lazily initialized.
    if (value == Qnil) return;

    if (!RB_TYPE_P(value, T_HASH)) {
        rb_raise(rb_eTypeError, "storage must be a hash");
    }

    if (RB_OBJ_FROZEN(value)) {
        rb_raise(rb_eFrozenError, "storage must not be frozen");
    }

    rb_hash_foreach(value, fiber_storage_validate_each, Qundef);
}

/**
 *  call-seq: fiber.storage = hash
 *
 *  Sets the storage hash for the fiber. This feature is experimental
 *  and may change in the future. The method can only be called on the
 *  Fiber.current.
 *
 *  You should be careful about using this method as you may inadvertently clear
 *  important fiber-storage state. You should mostly prefer to assign specific
 *  keys in the storage using Fiber::[]=.
 *
 *  You can also use <tt>Fiber.new(storage: nil)</tt> to create a fiber with an empty
 *  storage.
 *
 *  Example:
 *
 *    while request = request_queue.pop
 *      # Reset the per-request state:
 *      Fiber.current.storage = nil
 *      handle_request(request)
 *    end
 */
static VALUE
rb_fiber_storage_set(VALUE self, VALUE value)
{
    if (rb_warning_category_enabled_p(RB_WARN_CATEGORY_EXPERIMENTAL)) {
        rb_category_warn(RB_WARN_CATEGORY_EXPERIMENTAL,
          "Fiber#storage= is experimental and may be removed in the future!");
    }

    storage_access_must_be_from_same_fiber(self);
    fiber_storage_validate(value);

    fiber_ptr(self)->cont.saved_ec.storage = rb_obj_dup(value);
    return value;
}

/**
 *  call-seq: Fiber[key] -> value
 *
 *  Returns the value of the fiber storage variable identified by +key+.
 *
 *  The +key+ must be a symbol, and the value is set by Fiber#[]= or
 *  Fiber#store.
 *
 *  See also Fiber::[]=.
 */
static VALUE
rb_fiber_storage_aref(VALUE class, VALUE key)
{
    Check_Type(key, T_SYMBOL);

    VALUE storage = fiber_storage_get(fiber_current());

    if (storage == Qnil) return Qnil;

    return rb_hash_aref(storage, key);
}

/**
 *  call-seq: Fiber[key] = value
 *
 *  Assign +value+ to the fiber storage variable identified by +key+.
 *  The variable is created if it doesn't exist.
 *
 *  +key+ must be a Symbol, otherwise a TypeError is raised.
 *
 *  See also Fiber::[].
 */
static VALUE
rb_fiber_storage_aset(VALUE class, VALUE key, VALUE value)
{
    Check_Type(key, T_SYMBOL);

    VALUE storage = fiber_storage_get(fiber_current());

    return rb_hash_aset(storage, key, value);
}

static VALUE
fiber_initialize(VALUE self, VALUE proc, struct fiber_pool * fiber_pool, unsigned int blocking, VALUE storage)
{
    if (storage == Qundef || storage == Qtrue) {
        // The default, inherit storage (dup) from the current fiber:
        storage = inherit_fiber_storage();
    }
    else /* nil, hash, etc. */ {
        fiber_storage_validate(storage);
        storage = rb_obj_dup(storage);
    }

    rb_fiber_t *fiber = fiber_t_alloc(self, blocking);

    fiber->cont.saved_ec.storage = storage;
    fiber->first_proc = proc;
    fiber->stack.base = NULL;
    fiber->stack.pool = fiber_pool;

    return self;
}

static void
fiber_prepare_stack(rb_fiber_t *fiber)
{
    rb_context_t *cont = &fiber->cont;
    rb_execution_context_t *sec = &cont->saved_ec;

    size_t vm_stack_size = 0;
    VALUE *vm_stack = fiber_initialize_coroutine(fiber, &vm_stack_size);

    /* initialize cont */
    cont->saved_vm_stack.ptr = NULL;
    rb_ec_initialize_vm_stack(sec, vm_stack, vm_stack_size / sizeof(VALUE));

    sec->tag = NULL;
    sec->local_storage = NULL;
    sec->local_storage_recursive_hash = Qnil;
    sec->local_storage_recursive_hash_for_trace = Qnil;
}

static struct fiber_pool *
rb_fiber_pool_default(VALUE pool)
{
    return &shared_fiber_pool;
}

VALUE rb_fiber_inherit_storage(struct rb_execution_context_struct *ec, struct rb_fiber_struct *fiber)
{
    VALUE storage = rb_obj_dup(ec->storage);
    fiber->cont.saved_ec.storage = storage;
    return storage;
}

/* :nodoc: */
static VALUE
rb_fiber_initialize_kw(int argc, VALUE* argv, VALUE self, int kw_splat)
{
    VALUE pool = Qnil;
    VALUE blocking = Qfalse;
    VALUE storage = Qundef;

    if (kw_splat != RB_NO_KEYWORDS) {
        VALUE options = Qnil;
        VALUE arguments[3] = {Qundef};

        argc = rb_scan_args_kw(kw_splat, argc, argv, ":", &options);
        rb_get_kwargs(options, fiber_initialize_keywords, 0, 3, arguments);

        if (!UNDEF_P(arguments[0])) {
            blocking = arguments[0];
        }

        if (!UNDEF_P(arguments[1])) {
            pool = arguments[1];
        }

        storage = arguments[2];
    }

    return fiber_initialize(self, rb_block_proc(), rb_fiber_pool_default(pool), RTEST(blocking), storage);
}

/*
 *  call-seq:
 *     Fiber.new(blocking: false, storage: true) { |*args| ... } -> fiber
 *
 *  Creates new Fiber. Initially, the fiber is not running and can be resumed
 *  with #resume. Arguments to the first #resume call will be passed to the
 *  block:
 *
 *    f = Fiber.new do |initial|
 *       current = initial
 *       loop do
 *         puts "current: #{current.inspect}"
 *         current = Fiber.yield
 *       end
 *    end
 *    f.resume(100)     # prints: current: 100
 *    f.resume(1, 2, 3) # prints: current: [1, 2, 3]
 *    f.resume          # prints: current: nil
 *    # ... and so on ...
 *
 *  If <tt>blocking: false</tt> is passed to <tt>Fiber.new</tt>, _and_ current
 *  thread has a Fiber.scheduler defined, the Fiber becomes non-blocking (see
 *  "Non-blocking Fibers" section in class docs).
 *
 *  If the <tt>storage</tt> is unspecified, the default is to inherit a copy of
 *  the storage from the current fiber. This is the same as specifying
 *  <tt>storage: true</tt>.
 *
 *    Fiber[:x] = 1
 *    Fiber.new do
 *      Fiber[:x] # => 1
 *      Fiber[:x] = 2
 *    end.resume
 *    Fiber[:x] # => 1
 *
 *  If the given <tt>storage</tt> is <tt>nil</tt>, this function will lazy
 *  initialize the internal storage, which starts as an empty hash.
 *
 *    Fiber[:x] = "Hello World"
 *    Fiber.new(storage: nil) do
 *      Fiber[:x] # nil
 *    end
 *
 *  Otherwise, the given <tt>storage</tt> is used as the new fiber's storage,
 *  and it must be an instance of Hash.
 *
 *  Explicitly using <tt>storage: true</tt> is currently experimental and may
 *  change in the future.
 */
static VALUE
rb_fiber_initialize(int argc, VALUE* argv, VALUE self)
{
    return rb_fiber_initialize_kw(argc, argv, self, rb_keyword_given_p());
}

VALUE
rb_fiber_new_storage(rb_block_call_func_t func, VALUE obj, VALUE storage)
{
    return fiber_initialize(fiber_alloc(rb_cFiber), rb_proc_new(func, obj), rb_fiber_pool_default(Qnil), 1, storage);
}

VALUE
rb_fiber_new(rb_block_call_func_t func, VALUE obj)
{
    return rb_fiber_new_storage(func, obj, Qtrue);
}

static VALUE
rb_fiber_s_schedule_kw(int argc, VALUE* argv, int kw_splat)
{
    rb_thread_t * th = GET_THREAD();
    VALUE scheduler = th->scheduler;
    VALUE fiber = Qnil;

    if (scheduler != Qnil) {
        fiber = rb_fiber_scheduler_fiber(scheduler, argc, argv, kw_splat);
    }
    else {
        rb_raise(rb_eRuntimeError, "No scheduler is available!");
    }

    return fiber;
}

/*
 *  call-seq:
 *     Fiber.schedule { |*args| ... } -> fiber
 *
 *  The method is <em>expected</em> to immediately run the provided block of code in a
 *  separate non-blocking fiber.
 *
 *     puts "Go to sleep!"
 *
 *     Fiber.set_scheduler(MyScheduler.new)
 *
 *     Fiber.schedule do
 *       puts "Going to sleep"
 *       sleep(1)
 *       puts "I slept well"
 *     end
 *
 *     puts "Wakey-wakey, sleepyhead"
 *
 *  Assuming MyScheduler is properly implemented, this program will produce:
 *
 *     Go to sleep!
 *     Going to sleep
 *     Wakey-wakey, sleepyhead
 *     ...1 sec pause here...
 *     I slept well
 *
 *  ...e.g. on the first blocking operation inside the Fiber (<tt>sleep(1)</tt>),
 *  the control is yielded to the outside code (main fiber), and <em>at the end
 *  of that execution</em>, the scheduler takes care of properly resuming all the
 *  blocked fibers.
 *
 *  Note that the behavior described above is how the method is <em>expected</em>
 *  to behave, actual behavior is up to the current scheduler's implementation of
 *  Fiber::Scheduler#fiber method. Ruby doesn't enforce this method to
 *  behave in any particular way.
 *
 *  If the scheduler is not set, the method raises
 *  <tt>RuntimeError (No scheduler is available!)</tt>.
 *
 */
static VALUE
rb_fiber_s_schedule(int argc, VALUE *argv, VALUE obj)
{
    return rb_fiber_s_schedule_kw(argc, argv, rb_keyword_given_p());
}

/*
 *  call-seq:
 *     Fiber.scheduler -> obj or nil
 *
 *  Returns the Fiber scheduler, that was last set for the current thread with Fiber.set_scheduler.
 *  Returns +nil+ if no scheduler is set (which is the default), and non-blocking fibers'
 *  behavior is the same as blocking.
 *  (see "Non-blocking fibers" section in class docs for details about the scheduler concept).
 *
 */
static VALUE
rb_fiber_s_scheduler(VALUE klass)
{
    return rb_fiber_scheduler_get();
}

/*
 *  call-seq:
 *     Fiber.current_scheduler -> obj or nil
 *
 *  Returns the Fiber scheduler, that was last set for the current thread with Fiber.set_scheduler
 *  if and only if the current fiber is non-blocking.
 *
 */
static VALUE
rb_fiber_current_scheduler(VALUE klass)
{
    return rb_fiber_scheduler_current();
}

/*
 *  call-seq:
 *     Fiber.set_scheduler(scheduler) -> scheduler
 *
 *  Sets the Fiber scheduler for the current thread. If the scheduler is set, non-blocking
 *  fibers (created by Fiber.new with <tt>blocking: false</tt>, or by Fiber.schedule)
 *  call that scheduler's hook methods on potentially blocking operations, and the current
 *  thread will call scheduler's +close+ method on finalization (allowing the scheduler to
 *  properly manage all non-finished fibers).
 *
 *  +scheduler+ can be an object of any class corresponding to Fiber::Scheduler. Its
 *  implementation is up to the user.
 *
 *  See also the "Non-blocking fibers" section in class docs.
 *
 */
static VALUE
rb_fiber_set_scheduler(VALUE klass, VALUE scheduler)
{
    return rb_fiber_scheduler_set(scheduler);
}

NORETURN(static void rb_fiber_terminate(rb_fiber_t *fiber, int need_interrupt, VALUE err));

void
rb_fiber_start(rb_fiber_t *fiber)
{
    rb_thread_t * volatile th = fiber->cont.saved_ec.thread_ptr;

    rb_proc_t *proc;
    enum ruby_tag_type state;
    int need_interrupt = TRUE;

    VM_ASSERT(th->ec == GET_EC());
    VM_ASSERT(FIBER_RESUMED_P(fiber));

    if (fiber->blocking) {
        th->blocking += 1;
    }

    EC_PUSH_TAG(th->ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
        rb_context_t *cont = &VAR_FROM_MEMORY(fiber)->cont;
        int argc;
        const VALUE *argv, args = cont->value;
        GetProcPtr(fiber->first_proc, proc);
        argv = (argc = cont->argc) > 1 ? RARRAY_CONST_PTR(args) : &args;
        cont->value = Qnil;
        th->ec->errinfo = Qnil;
        th->ec->root_lep = rb_vm_proc_local_ep(fiber->first_proc);
        th->ec->root_svar = Qfalse;

        EXEC_EVENT_HOOK(th->ec, RUBY_EVENT_FIBER_SWITCH, th->self, 0, 0, 0, Qnil);
        cont->value = rb_vm_invoke_proc(th->ec, proc, argc, argv, cont->kw_splat, VM_BLOCK_HANDLER_NONE);
    }
    EC_POP_TAG();

    VALUE err = Qfalse;
    if (state) {
        err = th->ec->errinfo;
        VM_ASSERT(FIBER_RESUMED_P(fiber));

        if (state == TAG_RAISE) {
            // noop...
        }
        else if (state == TAG_FATAL) {
            rb_threadptr_pending_interrupt_enque(th, err);
        }
        else {
            err = rb_vm_make_jump_tag_but_local_jump(state, err);
        }
        need_interrupt = TRUE;
    }

    rb_fiber_terminate(fiber, need_interrupt, err);
}

// Set up a "root fiber", which is the fiber that every Ractor has.
void
rb_threadptr_root_fiber_setup(rb_thread_t *th)
{
    rb_fiber_t *fiber = ruby_mimmalloc(sizeof(rb_fiber_t));
    if (!fiber) {
        rb_bug("%s", strerror(errno)); /* ... is it possible to call rb_bug here? */
    }
    MEMZERO(fiber, rb_fiber_t, 1);
    fiber->cont.type = FIBER_CONTEXT;
    fiber->cont.saved_ec.fiber_ptr = fiber;
    fiber->cont.saved_ec.thread_ptr = th;
    fiber->blocking = 1;
    fiber_status_set(fiber, FIBER_RESUMED); /* skip CREATED */
    th->ec = &fiber->cont.saved_ec;
    // When rb_threadptr_root_fiber_setup is called for the first time, mjit_enabled and
    // rb_yjit_enabled_p() are still false. So this does nothing and rb_jit_cont_init() that is
    // called later will take care of it. However, you still have to call cont_init_jit_cont()
    // here for other Ractors, which are not initialized by rb_jit_cont_init().
    cont_init_jit_cont(&fiber->cont);
}

void
rb_threadptr_root_fiber_release(rb_thread_t *th)
{
    if (th->root_fiber) {
        /* ignore. A root fiber object will free th->ec */
    }
    else {
        rb_execution_context_t *ec = GET_EC();

        VM_ASSERT(th->ec->fiber_ptr->cont.type == FIBER_CONTEXT);
        VM_ASSERT(th->ec->fiber_ptr->cont.self == 0);

        if (th->ec == ec) {
            rb_ractor_set_current_ec(th->ractor, NULL);
        }
        fiber_free(th->ec->fiber_ptr);
        th->ec = NULL;
    }
}

void
rb_threadptr_root_fiber_terminate(rb_thread_t *th)
{
    rb_fiber_t *fiber = th->ec->fiber_ptr;

    fiber->status = FIBER_TERMINATED;

    // The vm_stack is `alloca`ed on the thread stack, so it's gone too:
    rb_ec_clear_vm_stack(th->ec);
}

static inline rb_fiber_t*
return_fiber(bool terminate)
{
    rb_fiber_t *fiber = fiber_current();
    rb_fiber_t *prev = fiber->prev;

    if (prev) {
        fiber->prev = NULL;
        prev->resuming_fiber = NULL;
        return prev;
    }
    else {
        if (!terminate) {
            rb_raise(rb_eFiberError, "attempt to yield on a not resumed fiber");
        }

        rb_thread_t *th = GET_THREAD();
        rb_fiber_t *root_fiber = th->root_fiber;

        VM_ASSERT(root_fiber != NULL);

        // search resuming fiber
        for (fiber = root_fiber; fiber->resuming_fiber; fiber = fiber->resuming_fiber) {
        }

        return fiber;
    }
}

VALUE
rb_fiber_current(void)
{
    return fiber_current()->cont.self;
}

// Prepare to execute next_fiber on the given thread.
static inline void
fiber_store(rb_fiber_t *next_fiber, rb_thread_t *th)
{
    rb_fiber_t *fiber;

    if (th->ec->fiber_ptr != NULL) {
        fiber = th->ec->fiber_ptr;
    }
    else {
        /* create root fiber */
        fiber = root_fiber_alloc(th);
    }

    if (FIBER_CREATED_P(next_fiber)) {
        fiber_prepare_stack(next_fiber);
    }

    VM_ASSERT(FIBER_RESUMED_P(fiber) || FIBER_TERMINATED_P(fiber));
    VM_ASSERT(FIBER_RUNNABLE_P(next_fiber));

    if (FIBER_RESUMED_P(fiber)) fiber_status_set(fiber, FIBER_SUSPENDED);

    fiber_status_set(next_fiber, FIBER_RESUMED);
    fiber_setcontext(next_fiber, fiber);
}

static inline VALUE
fiber_switch(rb_fiber_t *fiber, int argc, const VALUE *argv, int kw_splat, rb_fiber_t *resuming_fiber, bool yielding)
{
    VALUE value;
    rb_context_t *cont = &fiber->cont;
    rb_thread_t *th = GET_THREAD();

    /* make sure the root_fiber object is available */
    if (th->root_fiber == NULL) root_fiber_alloc(th);

    if (th->ec->fiber_ptr == fiber) {
        /* ignore fiber context switch
         * because destination fiber is the same as current fiber
         */
        return make_passing_arg(argc, argv);
    }

    if (cont_thread_value(cont) != th->self) {
        rb_raise(rb_eFiberError, "fiber called across threads");
    }

    if (FIBER_TERMINATED_P(fiber)) {
        value = rb_exc_new2(rb_eFiberError, "dead fiber called");

        if (!FIBER_TERMINATED_P(th->ec->fiber_ptr)) {
            rb_exc_raise(value);
            VM_UNREACHABLE(fiber_switch);
        }
        else {
            /* th->ec->fiber_ptr is also dead => switch to root fiber */
            /* (this means we're being called from rb_fiber_terminate, */
            /* and the terminated fiber's return_fiber() is already dead) */
            VM_ASSERT(FIBER_SUSPENDED_P(th->root_fiber));

            cont = &th->root_fiber->cont;
            cont->argc = -1;
            cont->value = value;

            fiber_setcontext(th->root_fiber, th->ec->fiber_ptr);

            VM_UNREACHABLE(fiber_switch);
        }
    }

    VM_ASSERT(FIBER_RUNNABLE_P(fiber));

    rb_fiber_t *current_fiber = fiber_current();

    VM_ASSERT(!current_fiber->resuming_fiber);

    if (resuming_fiber) {
        current_fiber->resuming_fiber = resuming_fiber;
        fiber->prev = fiber_current();
        fiber->yielding = 0;
    }

    VM_ASSERT(!current_fiber->yielding);
    if (yielding) {
        current_fiber->yielding = 1;
    }

    if (current_fiber->blocking) {
        th->blocking -= 1;
    }

    cont->argc = argc;
    cont->kw_splat = kw_splat;
    cont->value = make_passing_arg(argc, argv);

    fiber_store(fiber, th);

    // We cannot free the stack until the pthread is joined:
#ifndef COROUTINE_PTHREAD_CONTEXT
    if (resuming_fiber && FIBER_TERMINATED_P(fiber)) {
        fiber_stack_release(fiber);
    }
#endif

    if (fiber_current()->blocking) {
        th->blocking += 1;
    }

    RUBY_VM_CHECK_INTS(th->ec);

    EXEC_EVENT_HOOK(th->ec, RUBY_EVENT_FIBER_SWITCH, th->self, 0, 0, 0, Qnil);

    current_fiber = th->ec->fiber_ptr;
    value = current_fiber->cont.value;
    if (current_fiber->cont.argc == -1) rb_exc_raise(value);
    return value;
}

VALUE
rb_fiber_transfer(VALUE fiber_value, int argc, const VALUE *argv)
{
    return fiber_switch(fiber_ptr(fiber_value), argc, argv, RB_NO_KEYWORDS, NULL, false);
}

/*
 *  call-seq:
 *     fiber.blocking? -> true or false
 *
 *  Returns +true+ if +fiber+ is blocking and +false+ otherwise.
 *  Fiber is non-blocking if it was created via passing <tt>blocking: false</tt>
 *  to Fiber.new, or via Fiber.schedule.
 *
 *  Note that, even if the method returns +false+, the fiber behaves differently
 *  only if Fiber.scheduler is set in the current thread.
 *
 *  See the "Non-blocking fibers" section in class docs for details.
 *
 */
VALUE
rb_fiber_blocking_p(VALUE fiber)
{
    return RBOOL(fiber_ptr(fiber)->blocking);
}

static VALUE
fiber_blocking_yield(VALUE fiber_value)
{
    rb_fiber_t *fiber = fiber_ptr(fiber_value);
    rb_thread_t * volatile th = fiber->cont.saved_ec.thread_ptr;

    // fiber->blocking is `unsigned int : 1`, so we use it as a boolean:
    fiber->blocking = 1;

    // Once the fiber is blocking, and current, we increment the thread blocking state:
    th->blocking += 1;

    return rb_yield(fiber_value);
}

static VALUE
fiber_blocking_ensure(VALUE fiber_value)
{
    rb_fiber_t *fiber = fiber_ptr(fiber_value);
    rb_thread_t * volatile th = fiber->cont.saved_ec.thread_ptr;

    // We are no longer blocking:
    fiber->blocking = 0;
    th->blocking -= 1;

    return Qnil;
}

/*
 *  call-seq:
 *     Fiber.blocking{|fiber| ...} -> result
 *
 *  Forces the fiber to be blocking for the duration of the block. Returns the
 *  result of the block.
 *
 *  See the "Non-blocking fibers" section in class docs for details.
 *
 */
VALUE
rb_fiber_blocking(VALUE class)
{
    VALUE fiber_value = rb_fiber_current();
    rb_fiber_t *fiber = fiber_ptr(fiber_value);

    // If we are already blocking, this is essentially a no-op:
    if (fiber->blocking) {
        return rb_yield(fiber_value);
    }
    else {
        return rb_ensure(fiber_blocking_yield, fiber_value, fiber_blocking_ensure, fiber_value);
    }
}

/*
 *  call-seq:
 *     Fiber.blocking? -> false or 1
 *
 *  Returns +false+ if the current fiber is non-blocking.
 *  Fiber is non-blocking if it was created via passing <tt>blocking: false</tt>
 *  to Fiber.new, or via Fiber.schedule.
 *
 *  If the current Fiber is blocking, the method returns 1.
 *  Future developments may allow for situations where larger integers
 *  could be returned.
 *
 *  Note that, even if the method returns +false+, Fiber behaves differently
 *  only if Fiber.scheduler is set in the current thread.
 *
 *  See the "Non-blocking fibers" section in class docs for details.
 *
 */
static VALUE
rb_fiber_s_blocking_p(VALUE klass)
{
    rb_thread_t *thread = GET_THREAD();
    unsigned blocking = thread->blocking;

    if (blocking == 0)
        return Qfalse;

    return INT2NUM(blocking);
}

void
rb_fiber_close(rb_fiber_t *fiber)
{
    fiber_status_set(fiber, FIBER_TERMINATED);
}

static void
rb_fiber_terminate(rb_fiber_t *fiber, int need_interrupt, VALUE error)
{
    VALUE value = fiber->cont.value;

    VM_ASSERT(FIBER_RESUMED_P(fiber));
    rb_fiber_close(fiber);

    fiber->cont.machine.stack = NULL;
    fiber->cont.machine.stack_size = 0;

    rb_fiber_t *next_fiber = return_fiber(true);

    if (need_interrupt) RUBY_VM_SET_INTERRUPT(&next_fiber->cont.saved_ec);

    if (RTEST(error))
        fiber_switch(next_fiber, -1, &error, RB_NO_KEYWORDS, NULL, false);
    else
        fiber_switch(next_fiber, 1, &value, RB_NO_KEYWORDS, NULL, false);
    ruby_stop(0);
}

static VALUE
fiber_resume_kw(rb_fiber_t *fiber, int argc, const VALUE *argv, int kw_splat)
{
    rb_fiber_t *current_fiber = fiber_current();

    if (argc == -1 && FIBER_CREATED_P(fiber)) {
        rb_raise(rb_eFiberError, "cannot raise exception on unborn fiber");
    }
    else if (FIBER_TERMINATED_P(fiber)) {
        rb_raise(rb_eFiberError, "attempt to resume a terminated fiber");
    }
    else if (fiber == current_fiber) {
        rb_raise(rb_eFiberError, "attempt to resume the current fiber");
    }
    else if (fiber->prev != NULL) {
        rb_raise(rb_eFiberError, "attempt to resume a resumed fiber (double resume)");
    }
    else if (fiber->resuming_fiber) {
        rb_raise(rb_eFiberError, "attempt to resume a resuming fiber");
    }
    else if (fiber->prev == NULL &&
             (!fiber->yielding && fiber->status != FIBER_CREATED)) {
        rb_raise(rb_eFiberError, "attempt to resume a transferring fiber");
    }

    return fiber_switch(fiber, argc, argv, kw_splat, fiber, false);
}

VALUE
rb_fiber_resume_kw(VALUE self, int argc, const VALUE *argv, int kw_splat)
{
    return fiber_resume_kw(fiber_ptr(self), argc, argv, kw_splat);
}

VALUE
rb_fiber_resume(VALUE self, int argc, const VALUE *argv)
{
    return fiber_resume_kw(fiber_ptr(self), argc, argv, RB_NO_KEYWORDS);
}

VALUE
rb_fiber_yield_kw(int argc, const VALUE *argv, int kw_splat)
{
    return fiber_switch(return_fiber(false), argc, argv, kw_splat, NULL, true);
}

VALUE
rb_fiber_yield(int argc, const VALUE *argv)
{
    return fiber_switch(return_fiber(false), argc, argv, RB_NO_KEYWORDS, NULL, true);
}

void
rb_fiber_reset_root_local_storage(rb_thread_t *th)
{
    if (th->root_fiber && th->root_fiber != th->ec->fiber_ptr) {
        th->ec->local_storage = th->root_fiber->cont.saved_ec.local_storage;
    }
}

/*
 *  call-seq:
 *     fiber.alive? -> true or false
 *
 *  Returns true if the fiber can still be resumed (or transferred
 *  to). After finishing execution of the fiber block this method will
 *  always return +false+.
 */
VALUE
rb_fiber_alive_p(VALUE fiber_value)
{
    return RBOOL(!FIBER_TERMINATED_P(fiber_ptr(fiber_value)));
}

/*
 *  call-seq:
 *     fiber.resume(args, ...) -> obj
 *
 *  Resumes the fiber from the point at which the last Fiber.yield was
 *  called, or starts running it if it is the first call to
 *  #resume. Arguments passed to resume will be the value of the
 *  Fiber.yield expression or will be passed as block parameters to
 *  the fiber's block if this is the first #resume.
 *
 *  Alternatively, when resume is called it evaluates to the arguments passed
 *  to the next Fiber.yield statement inside the fiber's block
 *  or to the block value if it runs to completion without any
 *  Fiber.yield
 */
static VALUE
rb_fiber_m_resume(int argc, VALUE *argv, VALUE fiber)
{
    return rb_fiber_resume_kw(fiber, argc, argv, rb_keyword_given_p());
}

/*
 *  call-seq:
 *     fiber.backtrace -> array
 *     fiber.backtrace(start) -> array
 *     fiber.backtrace(start, count) -> array
 *     fiber.backtrace(start..end) -> array
 *
 *  Returns the current execution stack of the fiber. +start+, +count+ and +end+ allow
 *  to select only parts of the backtrace.
 *
 *     def level3
 *       Fiber.yield
 *     end
 *
 *     def level2
 *       level3
 *     end
 *
 *     def level1
 *       level2
 *     end
 *
 *     f = Fiber.new { level1 }
 *
 *     # It is empty before the fiber started
 *     f.backtrace
 *     #=> []
 *
 *     f.resume
 *
 *     f.backtrace
 *     #=> ["test.rb:2:in `yield'", "test.rb:2:in `level3'", "test.rb:6:in `level2'", "test.rb:10:in `level1'", "test.rb:13:in `block in <main>'"]
 *     p f.backtrace(1) # start from the item 1
 *     #=> ["test.rb:2:in `level3'", "test.rb:6:in `level2'", "test.rb:10:in `level1'", "test.rb:13:in `block in <main>'"]
 *     p f.backtrace(2, 2) # start from item 2, take 2
 *     #=> ["test.rb:6:in `level2'", "test.rb:10:in `level1'"]
 *     p f.backtrace(1..3) # take items from 1 to 3
 *     #=> ["test.rb:2:in `level3'", "test.rb:6:in `level2'", "test.rb:10:in `level1'"]
 *
 *     f.resume
 *
 *     # It is nil after the fiber is finished
 *     f.backtrace
 *     #=> nil
 *
 */
static VALUE
rb_fiber_backtrace(int argc, VALUE *argv, VALUE fiber)
{
    return rb_vm_backtrace(argc, argv, &fiber_ptr(fiber)->cont.saved_ec);
}

/*
 *  call-seq:
 *     fiber.backtrace_locations -> array
 *     fiber.backtrace_locations(start) -> array
 *     fiber.backtrace_locations(start, count) -> array
 *     fiber.backtrace_locations(start..end) -> array
 *
 *  Like #backtrace, but returns each line of the execution stack as a
 *  Thread::Backtrace::Location. Accepts the same arguments as #backtrace.
 *
 *    f = Fiber.new { Fiber.yield }
 *    f.resume
 *    loc = f.backtrace_locations.first
 *    loc.label  #=> "yield"
 *    loc.path   #=> "test.rb"
 *    loc.lineno #=> 1
 *
 *
 */
static VALUE
rb_fiber_backtrace_locations(int argc, VALUE *argv, VALUE fiber)
{
    return rb_vm_backtrace_locations(argc, argv, &fiber_ptr(fiber)->cont.saved_ec);
}

/*
 *  call-seq:
 *     fiber.transfer(args, ...) -> obj
 *
 *  Transfer control to another fiber, resuming it from where it last
 *  stopped or starting it if it was not resumed before. The calling
 *  fiber will be suspended much like in a call to
 *  Fiber.yield.
 *
 *  The fiber which receives the transfer call treats it much like
 *  a resume call. Arguments passed to transfer are treated like those
 *  passed to resume.
 *
 *  The two style of control passing to and from fiber (one is #resume and
 *  Fiber::yield, another is #transfer to and from fiber) can't be freely
 *  mixed.
 *
 *  * If the Fiber's lifecycle had started with transfer, it will never
 *    be able to yield or be resumed control passing, only
 *    finish or transfer back. (It still can resume other fibers that
 *    are allowed to be resumed.)
 *  * If the Fiber's lifecycle had started with resume, it can yield
 *    or transfer to another Fiber, but can receive control back only
 *    the way compatible with the way it was given away: if it had
 *    transferred, it only can be transferred back, and if it had
 *    yielded, it only can be resumed back. After that, it again can
 *    transfer or yield.
 *
 *  If those rules are broken FiberError is raised.
 *
 *  For an individual Fiber design, yield/resume is easier to use
 *  (the Fiber just gives away control, it doesn't need to think
 *  about who the control is given to), while transfer is more flexible
 *  for complex cases, allowing to build arbitrary graphs of Fibers
 *  dependent on each other.
 *
 *
 *  Example:
 *
 *     manager = nil # For local var to be visible inside worker block
 *
 *     # This fiber would be started with transfer
 *     # It can't yield, and can't be resumed
 *     worker = Fiber.new { |work|
 *       puts "Worker: starts"
 *       puts "Worker: Performed #{work.inspect}, transferring back"
 *       # Fiber.yield     # this would raise FiberError: attempt to yield on a not resumed fiber
 *       # manager.resume  # this would raise FiberError: attempt to resume a resumed fiber (double resume)
 *       manager.transfer(work.capitalize)
 *     }
 *
 *     # This fiber would be started with resume
 *     # It can yield or transfer, and can be transferred
 *     # back or resumed
 *     manager = Fiber.new {
 *       puts "Manager: starts"
 *       puts "Manager: transferring 'something' to worker"
 *       result = worker.transfer('something')
 *       puts "Manager: worker returned #{result.inspect}"
 *       # worker.resume    # this would raise FiberError: attempt to resume a transferring fiber
 *       Fiber.yield        # this is OK, the fiber transferred from and to, now it can yield
 *       puts "Manager: finished"
 *     }
 *
 *     puts "Starting the manager"
 *     manager.resume
 *     puts "Resuming the manager"
 *     # manager.transfer  # this would raise FiberError: attempt to transfer to a yielding fiber
 *     manager.resume
 *
 *  <em>produces</em>
 *
 *     Starting the manager
 *     Manager: starts
 *     Manager: transferring 'something' to worker
 *     Worker: starts
 *     Worker: Performed "something", transferring back
 *     Manager: worker returned "Something"
 *     Resuming the manager
 *     Manager: finished
 *
 */
static VALUE
rb_fiber_m_transfer(int argc, VALUE *argv, VALUE self)
{
    return rb_fiber_transfer_kw(self, argc, argv, rb_keyword_given_p());
}

static VALUE
fiber_transfer_kw(rb_fiber_t *fiber, int argc, const VALUE *argv, int kw_splat)
{
  if (fiber->resuming_fiber) {
      rb_raise(rb_eFiberError, "attempt to transfer to a resuming fiber");
  }

  if (fiber->yielding) {
      rb_raise(rb_eFiberError, "attempt to transfer to a yielding fiber");
  }

  return fiber_switch(fiber, argc, argv, kw_splat, NULL, false);
}

VALUE
rb_fiber_transfer_kw(VALUE self, int argc, const VALUE *argv, int kw_splat)
{
    return fiber_transfer_kw(fiber_ptr(self), argc, argv, kw_splat);
}

/*
 *  call-seq:
 *     Fiber.yield(args, ...) -> obj
 *
 *  Yields control back to the context that resumed the fiber, passing
 *  along any arguments that were passed to it. The fiber will resume
 *  processing at this point when #resume is called next.
 *  Any arguments passed to the next #resume will be the value that
 *  this Fiber.yield expression evaluates to.
 */
static VALUE
rb_fiber_s_yield(int argc, VALUE *argv, VALUE klass)
{
    return rb_fiber_yield_kw(argc, argv, rb_keyword_given_p());
}

static VALUE
fiber_raise(rb_fiber_t *fiber, int argc, const VALUE *argv)
{
    VALUE exception = rb_make_exception(argc, argv);

    if (fiber->resuming_fiber) {
        rb_raise(rb_eFiberError, "attempt to raise a resuming fiber");
    }
    else if (FIBER_SUSPENDED_P(fiber) && !fiber->yielding) {
        return fiber_transfer_kw(fiber, -1, &exception, RB_NO_KEYWORDS);
    }
    else {
        return fiber_resume_kw(fiber, -1, &exception, RB_NO_KEYWORDS);
    }
}

VALUE
rb_fiber_raise(VALUE fiber, int argc, const VALUE *argv)
{
    return fiber_raise(fiber_ptr(fiber), argc, argv);
}

/*
 *  call-seq:
 *     fiber.raise                                 -> obj
 *     fiber.raise(string)                         -> obj
 *     fiber.raise(exception [, string [, array]]) -> obj
 *
 *  Raises an exception in the fiber at the point at which the last
 *  +Fiber.yield+ was called. If the fiber has not been started or has
 *  already run to completion, raises +FiberError+. If the fiber is
 *  yielding, it is resumed. If it is transferring, it is transferred into.
 *  But if it is resuming, raises +FiberError+.
 *
 *  With no arguments, raises a +RuntimeError+. With a single +String+
 *  argument, raises a +RuntimeError+ with the string as a message.  Otherwise,
 *  the first parameter should be the name of an +Exception+ class (or an
 *  object that returns an +Exception+ object when sent an +exception+
 *  message). The optional second parameter sets the message associated with
 *  the exception, and the third parameter is an array of callback information.
 *  Exceptions are caught by the +rescue+ clause of <code>begin...end</code>
 *  blocks.
 */
static VALUE
rb_fiber_m_raise(int argc, VALUE *argv, VALUE self)
{
    return rb_fiber_raise(self, argc, argv);
}

/*
 *  call-seq:
 *     Fiber.current -> fiber
 *
 *  Returns the current fiber. If you are not running in the context of
 *  a fiber this method will return the root fiber.
 */
static VALUE
rb_fiber_s_current(VALUE klass)
{
    return rb_fiber_current();
}

static VALUE
fiber_to_s(VALUE fiber_value)
{
    const rb_fiber_t *fiber = fiber_ptr(fiber_value);
    const rb_proc_t *proc;
    char status_info[0x20];

    if (fiber->resuming_fiber) {
        snprintf(status_info, 0x20, " (%s by resuming)", fiber_status_name(fiber->status));
    }
    else {
        snprintf(status_info, 0x20, " (%s)", fiber_status_name(fiber->status));
    }

    if (!rb_obj_is_proc(fiber->first_proc)) {
        VALUE str = rb_any_to_s(fiber_value);
        strlcat(status_info, ">", sizeof(status_info));
        rb_str_set_len(str, RSTRING_LEN(str)-1);
        rb_str_cat_cstr(str, status_info);
        return str;
    }
    GetProcPtr(fiber->first_proc, proc);
    return rb_block_to_s(fiber_value, &proc->block, status_info);
}

#ifdef HAVE_WORKING_FORK
void
rb_fiber_atfork(rb_thread_t *th)
{
    if (th->root_fiber) {
        if (&th->root_fiber->cont.saved_ec != th->ec) {
            th->root_fiber = th->ec->fiber_ptr;
        }
        th->root_fiber->prev = 0;
    }
}
#endif

#ifdef RB_EXPERIMENTAL_FIBER_POOL
static void
fiber_pool_free(void *ptr)
{
    struct fiber_pool * fiber_pool = ptr;
    RUBY_FREE_ENTER("fiber_pool");

    fiber_pool_allocation_free(fiber_pool->allocations);
    ruby_xfree(fiber_pool);

    RUBY_FREE_LEAVE("fiber_pool");
}

static size_t
fiber_pool_memsize(const void *ptr)
{
    const struct fiber_pool * fiber_pool = ptr;
    size_t size = sizeof(*fiber_pool);

    size += fiber_pool->count * fiber_pool->size;

    return size;
}

static const rb_data_type_t FiberPoolDataType = {
    "fiber_pool",
    {NULL, fiber_pool_free, fiber_pool_memsize,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
fiber_pool_alloc(VALUE klass)
{
    struct fiber_pool *fiber_pool;

    return TypedData_Make_Struct(klass, struct fiber_pool, &FiberPoolDataType, fiber_pool);
}

static VALUE
rb_fiber_pool_initialize(int argc, VALUE* argv, VALUE self)
{
    rb_thread_t *th = GET_THREAD();
    VALUE size = Qnil, count = Qnil, vm_stack_size = Qnil;
    struct fiber_pool * fiber_pool = NULL;

    // Maybe these should be keyword arguments.
    rb_scan_args(argc, argv, "03", &size, &count, &vm_stack_size);

    if (NIL_P(size)) {
        size = SIZET2NUM(th->vm->default_params.fiber_machine_stack_size);
    }

    if (NIL_P(count)) {
        count = INT2NUM(128);
    }

    if (NIL_P(vm_stack_size)) {
        vm_stack_size = SIZET2NUM(th->vm->default_params.fiber_vm_stack_size);
    }

    TypedData_Get_Struct(self, struct fiber_pool, &FiberPoolDataType, fiber_pool);

    fiber_pool_initialize(fiber_pool, NUM2SIZET(size), NUM2SIZET(count), NUM2SIZET(vm_stack_size));

    return self;
}
#endif

/*
 *  Document-class: FiberError
 *
 *  Raised when an invalid operation is attempted on a Fiber, in
 *  particular when attempting to call/resume a dead fiber,
 *  attempting to yield from the root fiber, or calling a fiber across
 *  threads.
 *
 *     fiber = Fiber.new{}
 *     fiber.resume #=> nil
 *     fiber.resume #=> FiberError: dead fiber called
 */

void
Init_Cont(void)
{
    rb_thread_t *th = GET_THREAD();
    size_t vm_stack_size = th->vm->default_params.fiber_vm_stack_size;
    size_t machine_stack_size = th->vm->default_params.fiber_machine_stack_size;
    size_t stack_size = machine_stack_size + vm_stack_size;

#ifdef _WIN32
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    pagesize = info.dwPageSize;
#else /* not WIN32 */
    pagesize = sysconf(_SC_PAGESIZE);
#endif
    SET_MACHINE_STACK_END(&th->ec->machine.stack_end);

    fiber_pool_initialize(&shared_fiber_pool, stack_size, FIBER_POOL_INITIAL_SIZE, vm_stack_size);

    fiber_initialize_keywords[0] = rb_intern_const("blocking");
    fiber_initialize_keywords[1] = rb_intern_const("pool");
    fiber_initialize_keywords[2] = rb_intern_const("storage");

    const char *fiber_shared_fiber_pool_free_stacks = getenv("RUBY_SHARED_FIBER_POOL_FREE_STACKS");
    if (fiber_shared_fiber_pool_free_stacks) {
        shared_fiber_pool.free_stacks = atoi(fiber_shared_fiber_pool_free_stacks);
    }

    rb_cFiber = rb_define_class("Fiber", rb_cObject);
    rb_define_alloc_func(rb_cFiber, fiber_alloc);
    rb_eFiberError = rb_define_class("FiberError", rb_eStandardError);
    rb_define_singleton_method(rb_cFiber, "yield", rb_fiber_s_yield, -1);
    rb_define_singleton_method(rb_cFiber, "current", rb_fiber_s_current, 0);
    rb_define_singleton_method(rb_cFiber, "blocking", rb_fiber_blocking, 0);
    rb_define_singleton_method(rb_cFiber, "[]", rb_fiber_storage_aref, 1);
    rb_define_singleton_method(rb_cFiber, "[]=", rb_fiber_storage_aset, 2);

    rb_define_method(rb_cFiber, "initialize", rb_fiber_initialize, -1);
    rb_define_method(rb_cFiber, "blocking?", rb_fiber_blocking_p, 0);
    rb_define_method(rb_cFiber, "storage", rb_fiber_storage_get, 0);
    rb_define_method(rb_cFiber, "storage=", rb_fiber_storage_set, 1);
    rb_define_method(rb_cFiber, "resume", rb_fiber_m_resume, -1);
    rb_define_method(rb_cFiber, "raise", rb_fiber_m_raise, -1);
    rb_define_method(rb_cFiber, "backtrace", rb_fiber_backtrace, -1);
    rb_define_method(rb_cFiber, "backtrace_locations", rb_fiber_backtrace_locations, -1);
    rb_define_method(rb_cFiber, "to_s", fiber_to_s, 0);
    rb_define_alias(rb_cFiber, "inspect", "to_s");
    rb_define_method(rb_cFiber, "transfer", rb_fiber_m_transfer, -1);
    rb_define_method(rb_cFiber, "alive?", rb_fiber_alive_p, 0);

    rb_define_singleton_method(rb_cFiber, "blocking?", rb_fiber_s_blocking_p, 0);
    rb_define_singleton_method(rb_cFiber, "scheduler", rb_fiber_s_scheduler, 0);
    rb_define_singleton_method(rb_cFiber, "set_scheduler", rb_fiber_set_scheduler, 1);
    rb_define_singleton_method(rb_cFiber, "current_scheduler", rb_fiber_current_scheduler, 0);

    rb_define_singleton_method(rb_cFiber, "schedule", rb_fiber_s_schedule, -1);

#ifdef RB_EXPERIMENTAL_FIBER_POOL
    rb_cFiberPool = rb_define_class_under(rb_cFiber, "Pool", rb_cObject);
    rb_define_alloc_func(rb_cFiberPool, fiber_pool_alloc);
    rb_define_method(rb_cFiberPool, "initialize", rb_fiber_pool_initialize, -1);
#endif

    rb_provide("fiber.so");
}

RUBY_SYMBOL_EXPORT_BEGIN

void
ruby_Init_Continuation_body(void)
{
    rb_cContinuation = rb_define_class("Continuation", rb_cObject);
    rb_undef_alloc_func(rb_cContinuation);
    rb_undef_method(CLASS_OF(rb_cContinuation), "new");
    rb_define_method(rb_cContinuation, "call", rb_cont_call, -1);
    rb_define_method(rb_cContinuation, "[]", rb_cont_call, -1);
    rb_define_global_function("callcc", rb_callcc, 0);
}

RUBY_SYMBOL_EXPORT_END
