#ifndef PRISM_INTERNAL_ALLOCATOR_H
#define PRISM_INTERNAL_ALLOCATOR_H

/* If you build Prism with a custom allocator, configure it with
 * "-D PRISM_XALLOCATOR" to use your own allocator that defines xmalloc,
 * xrealloc, xcalloc, and xfree.
 *
 * For example, your `prism_xallocator.h` file could look like this:
 *
 * ```
 * #ifndef PRISM_XALLOCATOR_H
 * #define PRISM_XALLOCATOR_H
 * #define xmalloc          my_malloc
 * #define xrealloc         my_realloc
 * #define xcalloc          my_calloc
 * #define xfree            my_free
 * #define xrealloc_sized   my_realloc_sized // (optional)
 * #define xfree_sized      my_free_sized    // (optional)
 * #endif
 * ```
 */
#ifdef PRISM_XALLOCATOR
    #include "prism_xallocator.h"
#else
    #ifndef xmalloc
        /* The malloc function that should be used. This can be overridden with
         * the PRISM_XALLOCATOR define. */
        #define xmalloc malloc
    #endif

    #ifndef xrealloc
        /* The realloc function that should be used. This can be overridden with
         * the PRISM_XALLOCATOR define. */
        #define xrealloc realloc
    #endif

    #ifndef xcalloc
        /* The calloc function that should be used. This can be overridden with
         * the PRISM_XALLOCATOR define. */
        #define xcalloc calloc
    #endif

    #ifndef xfree
        /* The free function that should be used. This can be overridden with
         * the PRISM_XALLOCATOR define. */
        #define xfree free
    #endif
#endif

#ifndef xfree_sized
    /* The free_sized function that should be used. This can be overridden with
     * the PRISM_XALLOCATOR define. If not defined, defaults to calling xfree.
     */
    #define xfree_sized(p, s) xfree(((void)(s), (p)))
#endif

#ifndef xrealloc_sized
    /* The xrealloc_sized function that should be used. This can be overridden
     * with the PRISM_XALLOCATOR define. If not defined, defaults to calling
     * xrealloc. */
    #define xrealloc_sized(p, ns, os) xrealloc((p), ((void)(os), (ns)))
#endif

#ifdef PRISM_BUILD_DEBUG
    #include "prism/internal/allocator_debug.h"
#endif

#endif
