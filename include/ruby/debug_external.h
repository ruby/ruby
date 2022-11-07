#ifndef __DEBUG_EXTERNAL_H
#define __DEBUG_EXTERNAL_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      External debug interface
 *
 * @name External debug interface
 *
 * This header file contains structure definitions which are intended to be used by external
 * tools inspecting the state of a running Ruby process. This includes things like profilers
 * and debuggers.
 *
 * These APIs are intended to be forwards- and backwards- compatible across Ruby versions; it
 * should be safe to use a properly-written application compiled with an old version of this
 * header file against a Ruby process running a newer version, and vice versa.
 *
 * Note that it is important that this header file does NOT depend on or include other Ruby
 * header files. This is for a couple of reasons:
 *   - The applications compiled with this header are profilers & debuggers, and not
 *     nescessarily written in Ruby. Concepts like VALUE make no sense there because there
 *     is no running Ruby GC in the profiler process.
 *   - This header file should be usable in eBPF programs on Linux, where the above
 *     considerations apply doubly.
 *
 * @{
 */

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

typedef struct rb_debug_ext_method_info_struct {
    /* `method_qualifier` and `method_name` are strings of length `method_qualifier_len` and
     * `method_name_len` respectively. They are NOT nescessarily null-terminated.
     * When joined together, they will produce a string which represents the name of the
     * method in a way which makes sense to a human and which can be safely aggregated
     * across processes in profiling tools - that is to say, it contains no memory address
     * strings for e.g. anonymous classes.
     *
     * This is the same string that is returned for Method#debug_name */
    const char *method_qualifier;
    size_t method_qualifier_len;
    const char *method_name;
    size_t method_name_len;
} rb_debug_ext_method_info_t;

typedef struct rb_debug_ext_frame_struct {
    /* Whether this frame is the bottom of the callstack; if true, there are no more
     * frames beyond this one in the list */
    unsigned long frame_end : 1;
    /* Method information for this frame */
    rb_debug_ext_method_info_t method;
} rb_debug_ext_frame_t;

typedef struct rb_debug_ext_ec_struct {
    /* Whether this fiber is the main fiber for the thread its in */
    unsigned long main_fiber_of_thread : 1;
    /* Whether this fiber is the currently active one for its thread */
    unsigned long active_fiber_of_thread : 1;
    /* Whether the thread this fiber is in is the main thread of its ractor */
    unsigned long main_thread_of_ractor : 1;
    /* Whether the ractor that the thread that this fiber is in is the main ractor */
    unsigned long main_ractor_of_program: 1;
    /* The thread ID; this is the actual thread ID from the operating system. */
    pid_t thread_pid;
    /* A unique ractor ID */
    uintptr_t ractor_id;
    /* The current call-stack for this fiber. Accessing this requires a bit of care.
     * This pointer points to a rb_debug_ext_frame_t structure representing the top (i.e.
     * most-recently-called) frame of the call stack. To access the next frame, you
     * must access the memory at (top_frame - rb_debug_ext_section.strideof_frame); that
     * is to say, the subsequent frames is not immediately contigous in memory. You must
     * keep following frames until you find one for which .frame_end = 1, at which point
     * you have found the bottom of the call stack.
     *
     * Also note that strideof_frame is signed and may be negative. */
    rb_debug_ext_frame_t *top_frame;
} rb_debug_ext_ec_t;

/**
 * rb_debug_ext_section_t is the entrypoint for accessing the external debug data.
 * A running Ruby process has a section in its binary (i.e. an ELF/MachO/PE section)
 * called "rb_debug_ext", which contains a single instance of this structure.
 *
 * An external debugging or profiling tool will need to use a platform-specific
 * way to obtain this information from a running Ruby process. On Linux, this might look
 * something like the following:
 *  - Attach to a running Ruby process with ptrace and begin controlling it
 *  - Inspect the Ruby ELF file (which might be the Ruby executable, or libruby.so,
 *    depending on how Ruby was compiled) to figure out the "rb_debug_ext" section offset.
 *  - Combine that offset with the base address of the running ruby/libruby.so  to get
 *    a live memory map.
 *  - Interrupt _all_ threads of the Ruby process with ptrace, and suspend them
 *  - Read the contents of the "rb_debug_ext" section by reading the appropriate offset
 *    & length from /proc/pid/mem.
 *  - Interpret that memory by casting it to this structure, and chase pointers throgh
 *    proc/pid/mem as well.
 *  - Resume the Ruby threads with ptrace.
 * 
 */
typedef struct rb_debug_ext_section_struct {
    /* The size of the rb_debug_ext_section_t type, according to the running Ruby process.
     * Future versions of Ruby might add fields to this structure, but should not remove
     * any. An external debugger/profiler can thus be forwards-compatible with new versions
     * of Ruby by only accessing fields on rb_debug_ext_section_t that it knows about.
     * Likewise, a tool can be backwards compatible with older versions of Ruby than the
     * one it was compiled against by using this sizeof_section information to only access
     * fields in the first `sizeof_section` bytes of the structure. */
    size_t sizeof_section;

    /* Stores the program's opinion of sizeof(rb_debug_ext_ec_t); can be used for maintaining
     * backwards/forwards compatability in the same way that sizeof_section can */
    size_t sizeof_ec;

    /* Stores the program's opinion of sizeof(rb_debug_ext_frame_t) */
    size_t sizeof_frame;
    /* Stores the offset between frames in the rb_debug_ext_ec_t->top_frame list; see
       the documentation for top_frame to understand how to use this. */
    ssize_t strideof_frame;

    /* `ecs is an array of rb_debug_ext_ec_t pointers of length `ecs_size`. Each entry
     * in the array is either NULL or represents an execution context. An execution context
     * is essentially a Ruby Thread or Fiber.
     *
     * Accessing this array is only safe if _all_ threads in the Ruby process have been
     * suspended. However, the individual rb_debug_ext_ec_t structures that are pointed to
     * are safe to access so long as the thread it belongs to is suspended; the rest of the
     * process may continue running.
     *
     * The intended way for an external tool to access this information is to:
     *   - Suspend all threads of the Ruby process, _once_, when attaching to it.
     *   - Iterate through the ecs array, and store a map of (thread ID -> array of
     *     rb_debug_ext_ec_t*) in some internal data structure of its own.
     *   - Attach a probe/breakpoint of some kind to the external_debug_ec_added &
     *     external_debug_ec_removed dtrace/USDT probes. On Linux, this could be by adding
     *     a software breakpoint here or even by attaching an eBPF program.
     *   - Resume all threads of the program.
     *   - When the probe is hit, add/remove the given EC from the tool's internal map as
     *     appropriate
     *
     * Then, when the tool pauses execution of any given thread of the Ruby program (e.g. when
     * a given event of interest happens, or even on a timer), it can look up the EC pointer for
     * this thread in its internal map and dereference it in the Ruby program's address space
     * to find out information about the current thread. */
    rb_debug_ext_ec_t **ecs;
    size_t ecs_size;

} rb_debug_ext_section_t;

/**
 * }@
 */

#endif
