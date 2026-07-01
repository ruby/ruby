#include "ruby.h"

/*
 * Regression test for a heap-use-after-free in rb_gc_unregister_address().
 *
 * This mirrors the pattern used by some C extensions (e.g. Nokogiri's XPath
 * argument marshalling): a buffer is ruby_xcalloc()'d, the address of each of
 * its slots is registered with rb_gc_register_address(), and later each slot
 * is unregistered before the buffer is ruby_xfree()'d.
 * https://github.com/sparklemotion/nokogiri/blob/fea733159ad8c0328c591125bb1fb30681859a0d/ext/nokogiri/xml_xpath_context.c#L231-L255
 *
 * A buggy rb_gc_unregister_address() wrote *through* the address being removed
 * (corrupting the sibling slots) and failed to drop the entry from its internal
 * list, leaving a dangling pointer into the freed buffer that the next GC would
 * dereference.
 *
 * Returns true if unregistering one slot leaves the other registered slots
 * untouched. The trailing ruby_xfree()+gc additionally reproduces the literal
 * use-after-free for ASAN/Valgrind builds.
 */
static VALUE
gc_unregister_address_keeps_siblings(VALUE self)
{
    const int n = 4;
    VALUE *buf = ruby_xcalloc((size_t)n, sizeof(VALUE));
    VALUE saved = rb_ary_new_capa(n);
    VALUE result = Qtrue;

    for (int i = 0; i < n; i++) {
        buf[i] = rb_sprintf("registered address %d", i);
        rb_gc_register_address(&buf[i]);
        rb_ary_push(saved, buf[i]); /* keep the objects reachable */
    }

    /* Unregistering a middle slot must only update the internal list; it must
     * not write through &buf[1] and corrupt the sibling slots. */
    rb_gc_unregister_address(&buf[1]);
    for (int i = 0; i < n; i++) {
        if (i == 1) continue;
        if (buf[i] != rb_ary_entry(saved, i)) result = Qfalse;
    }

    /* Clean up the way an extension would. With the bug, a dangling registered
     * address into this freed buffer triggers a use-after-free in the GC. */
    rb_gc_unregister_address(&buf[0]);
    rb_gc_unregister_address(&buf[2]);
    rb_gc_unregister_address(&buf[3]);
    ruby_xfree(buf);
    rb_gc();

    RB_GC_GUARD(saved);
    return result;
}

void
Init_register(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE mGC = rb_define_module_under(mBug, "GC");
    rb_define_singleton_method(mGC, "unregister_address_keeps_siblings?",
                               gc_unregister_address_keeps_siblings, 0);
}
