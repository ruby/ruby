#include <ruby/ruby.h>

#if 0 // Warnings expected, should just suppress them

#elif defined(_MSC_VER)
#pragma warning(disable : 4996)

#elif defined(__INTEL_COMPILER)
#pragma warning(disable : 1786)

#elif defined(__clang__)
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#elif defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

#elif defined(__SUNPRO_CC)
#pragma error_messages (off,symdeprecated)

#else
// :FIXME: improve here for your compiler.

#endif

namespace test_rb_define_virtual_variable {
    VALUE
    getter(ID, VALUE *data)
    {
        return *data;
    }

    void
    setter(VALUE val, ID, VALUE *data)
    {
        *data = val;
    }

    VALUE
    test(VALUE self)
    {
        rb_define_virtual_variable("test",
            RUBY_METHOD_FUNC(getter),
            reinterpret_cast<void(*)(ANYARGS)>(setter)); // old
        rb_define_virtual_variable("test", getter, setter); // new

#ifdef HAVE_NULLPTR
        rb_define_virtual_variable("test", nullptr, reinterpret_cast<void(*)(ANYARGS)>(setter));
        rb_define_virtual_variable("test", nullptr, setter);

        rb_define_virtual_variable("test", RUBY_METHOD_FUNC(getter), nullptr);
        rb_define_virtual_variable("test", getter, nullptr);

        // It doesn't make any sense for both function pointers be nullptr at
        // the same time.
#endif

        return self;
    }
}

struct test_rb_define_hooked_variable {
    static VALUE v;

    static VALUE
    getter(ID, VALUE *data)
    {
        return *data;
    }

    static void
    setter(VALUE val, ID, VALUE *data)
    {
        *data = val;
    }

    static VALUE
    test(VALUE self)
    {
        rb_define_hooked_variable("test", &v,
            RUBY_METHOD_FUNC(getter),
            reinterpret_cast<void(*)(ANYARGS)>(setter)); // old
        rb_define_hooked_variable("test", &v, getter, setter); // new

#ifdef HAVE_NULLPTR
        rb_define_hooked_variable("test", &v, nullptr, reinterpret_cast<void(*)(ANYARGS)>(setter));
        rb_define_hooked_variable("test", &v, nullptr, setter);

        rb_define_hooked_variable("test", &v, RUBY_METHOD_FUNC(getter), nullptr);
        rb_define_hooked_variable("test", &v, getter, nullptr);

        // It doesn't make any sense for both function pointers be nullptr at
        // the same time.
#endif

        return self;
    }
};
VALUE test_rb_define_hooked_variable::v = Qundef;

namespace test_rb_iterate {
    VALUE
    iter(VALUE self)
    {
        return rb_funcall(self, rb_intern("yield"), 0);
    }

    VALUE
    block(RB_BLOCK_CALL_FUNC_ARGLIST(arg, param))
    {
        return rb_funcall(arg, rb_intern("=="), 1, param);
    }

    VALUE
    test(VALUE self)
    {
#ifdef HAVE_NULLPTR
        rb_iterate(iter, self, nullptr, self);
#endif

        rb_iterate(iter, self, RUBY_METHOD_FUNC(block), self); // old
        return rb_iterate(iter, self, block, self); // new
    }
}

namespace test_rb_block_call {
    VALUE
    block(RB_BLOCK_CALL_FUNC_ARGLIST(arg, param))
    {
        return rb_funcall(arg, rb_intern("=="), 1, param);
    }

    VALUE
    test(VALUE self)
    {
        const ID mid = rb_intern("each");
        const VALUE argv[] = { Qundef };

#ifdef HAVE_NULLPTR
        rb_block_call(self, mid, 0, argv, nullptr, self);
#endif

        rb_block_call(self, mid, 0, argv, RUBY_METHOD_FUNC(block), self); // old
        return rb_block_call(self, mid, 0, argv, block, self); // new
    }
}

namespace test_rb_rescue {
    VALUE
    begin(VALUE arg)
    {
        return arg;
    }

    VALUE
    rescue(VALUE arg, VALUE exc)
    {
        return exc;
    }

    VALUE
    test(VALUE self)
    {
#ifdef HAVE_NULLPTR
        rb_rescue(RUBY_METHOD_FUNC(begin), self, nullptr, self);
        rb_rescue(begin, self, nullptr, self);
#endif

        rb_rescue(RUBY_METHOD_FUNC(begin), self, RUBY_METHOD_FUNC(rescue), self); // old
        return rb_rescue(begin, self, rescue, self); // new
    }
}

namespace test_rb_rescue2 {
    VALUE
    begin(VALUE arg)
    {
        return arg;
    }

    VALUE
    rescue(VALUE arg, VALUE exc)
    {
        return exc;
    }

    VALUE
    test(VALUE self)
    {
#ifdef HAVE_NULLPTR
        rb_rescue2(RUBY_METHOD_FUNC(begin), self, nullptr, self, rb_eStandardError, rb_eFatal, (VALUE)0);
        rb_rescue2(begin, self, nullptr, self, rb_eStandardError, rb_eFatal, (VALUE)0);
#endif

        rb_rescue2(RUBY_METHOD_FUNC(begin), self, RUBY_METHOD_FUNC(rescue), self,
                   rb_eStandardError, rb_eFatal, (VALUE)0); // old
        return rb_rescue2(begin, self, rescue, self, rb_eStandardError, rb_eFatal, (VALUE)0); // new
    }
}

namespace test_rb_ensure {
    VALUE
    begin(VALUE arg)
    {
        return arg;
    }

    VALUE
    ensure(VALUE arg)
    {
        return arg;
    }

    VALUE
    test(VALUE self)
    {
#ifdef HAVE_NULLPTR
        rb_ensure(RUBY_METHOD_FUNC(begin), self, nullptr, self);
        rb_ensure(begin, self, nullptr, self);
#endif

        rb_ensure(RUBY_METHOD_FUNC(begin), self, RUBY_METHOD_FUNC(ensure), self); // old
        return rb_ensure(begin, self, ensure, self); // new
    }
}

namespace test_rb_catch {
    VALUE
    catcher(RB_BLOCK_CALL_FUNC_ARGLIST(arg, param))
    {
        return arg;
    }

    VALUE
    test(VALUE self)
    {
        static const char *zero = 0;

#ifdef HAVE_NULLPTR
        // It doesn't make any sense at all to pass nullptr as a catcher.
#endif

        rb_catch(zero, RUBY_METHOD_FUNC(catcher), self); // old
        return rb_catch(zero, catcher, self); // new
    }
}

namespace test_rb_catch_obj {
    VALUE
    catcher(RB_BLOCK_CALL_FUNC_ARGLIST(arg, param))
    {
        return arg;
    }

    VALUE
    test(VALUE self)
    {
#ifdef HAVE_NULLPTR
        // It doesn't make any sense at all to pass nullptr as a catcher.
#endif

        rb_catch_obj(self, RUBY_METHOD_FUNC(catcher), self); // old
        return rb_catch_obj(self, catcher, self); // new
    }
}

namespace test_rb_fiber_new {
    VALUE
    fiber(RB_BLOCK_CALL_FUNC_ARGLIST(arg, param))
    {
        return arg;
    }

    VALUE
    test(VALUE self)
    {
#ifdef HAVE_NULLPTR
        // It doesn't make any sense at all to pass nullptr as a fiber.
#endif

        rb_fiber_new(RUBY_METHOD_FUNC(fiber), self); // old
        return rb_fiber_new(fiber, self); // new
    }
}

namespace test_rb_proc_new {
    VALUE
    proc(RB_BLOCK_CALL_FUNC_ARGLIST(arg, param))
    {
        return arg;
    }

    VALUE
    test(VALUE self)
    {
#ifdef HAVE_NULLPTR
        // It doesn't make any sense at all to pass nullptr as a proc.
#endif

        rb_fiber_new(RUBY_METHOD_FUNC(proc), self); // old
        return rb_fiber_new(proc, self); // new
    }
}

struct test_rb_thread_create {
    static VALUE v;

    static VALUE
    thread(void *ptr)
    {
        const VALUE *w = reinterpret_cast<const VALUE*>(ptr);
        return *w;
    }

    static VALUE
    test(VALUE self)
    {
        v = self;

#ifdef HAVE_NULLPTR
        // It doesn't make any sense at all to pass nullptr as a thread.
#endif

        rb_thread_create(RUBY_METHOD_FUNC(thread), &v); // old
        return rb_thread_create(thread, &v); // new
    }
};
VALUE test_rb_thread_create::v = Qundef;

namespace test_st_foreach {
    static int
    iter(st_data_t, st_data_t, st_data_t)
    {
        return ST_CONTINUE;
    }

    VALUE
    test(VALUE self)
    {
        st_data_t data = 0;
        st_table *st = st_init_numtable();

#ifdef HAVE_NULLPTR
        // It doesn't make any sense at all to pass nullptr as an iterator.
#endif

        st_foreach(st, reinterpret_cast<int(*)(ANYARGS)>(iter), data); // old
        st_foreach(st, iter, data); // new
        return self;
    }
}

namespace test_st_foreach_check {
    static int
    iter(st_data_t, st_data_t, st_data_t, int x)
    {
        return x ? ST_STOP : ST_CONTINUE;
    }

    VALUE
    test(VALUE self)
    {
        st_data_t data = 0;
        st_table *st = st_init_numtable();

#ifdef HAVE_NULLPTR
        // It doesn't make any sense at all to pass nullptr as an iterator.
#endif

        st_foreach_check(st, reinterpret_cast<int(*)(ANYARGS)>(iter), data, data); // old
        st_foreach_check(st, iter, data, data); // new
        return self;
    }
}

namespace test_st_foreach_safe {
    static int
    iter(st_data_t, st_data_t, st_data_t)
    {
        return ST_CONTINUE;
    }

    VALUE
    test(VALUE self)
    {
        st_data_t data = 0;
        st_table *st = st_init_numtable();

#ifdef HAVE_NULLPTR
        // It doesn't make any sense at all to pass nullptr as an iterator.
#endif

        st_foreach_safe(st, reinterpret_cast<int(*)(ANYARGS)>(iter), data); // old
        st_foreach_safe(st, iter, data); // new
        return self;
    }
}

namespace test_rb_hash_foreach {
    static int
    iter(VALUE, VALUE, VALUE)
    {
        return ST_CONTINUE;
    }

    VALUE
    test(VALUE self)
    {
        VALUE h = rb_hash_new();

#ifdef HAVE_NULLPTR
        // It doesn't make any sense at all to pass nullptr as an iterator.
#endif

        rb_hash_foreach(h, reinterpret_cast<int(*)(ANYARGS)>(iter), self); // old
        rb_hash_foreach(h, iter, self); // new
        return self;
    }
}

namespace test_rb_ivar_foreach {
    static int
    iter(VALUE, VALUE, VALUE)
    {
        return ST_CONTINUE;
    }

    VALUE
    test(VALUE self)
    {
#ifdef HAVE_NULLPTR
        // It doesn't make any sense at all to pass nullptr as an iterator.
#endif

        rb_ivar_foreach(self, reinterpret_cast<int(*)(ANYARGS)>(iter), self); // old
        rb_ivar_foreach(self, iter, self); // new
        return self;
    }
}

namespace test_rb_define_method {
    static VALUE
    m1(VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    m2(VALUE, VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    ma(VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    mv(int, VALUE*, VALUE)
    {
        return Qnil;
    }

    static VALUE
    mc(int, const VALUE*, VALUE)
    {
        return Qnil;
    }

    VALUE
    test(VALUE self)
    {
        // No cast
        rb_define_method(self, "m1", m1, 1);
        rb_define_method(self, "m2", m2, 2);
        rb_define_method(self, "ma", ma, -2);
        rb_define_method(self, "mv", mv, -1);
        rb_define_method(self, "mc", mc, -1);

        // Cast by RUBY_METHOD_FUNC
        rb_define_method(self, "m1", RUBY_METHOD_FUNC(m1), 1);
        rb_define_method(self, "m2", RUBY_METHOD_FUNC(m2), 2);
        rb_define_method(self, "ma", RUBY_METHOD_FUNC(ma), -2);
        rb_define_method(self, "mv", RUBY_METHOD_FUNC(mv), -1);
        rb_define_method(self, "mc", RUBY_METHOD_FUNC(mc), -1);

        // Explicit cast instead of RUBY_METHOD_FUNC
        rb_define_method(self, "m1", (VALUE (*)(...))(m1), 1);
        rb_define_method(self, "m2", (VALUE (*)(...))(m2), 2);
        rb_define_method(self, "ma", (VALUE (*)(...))(ma), -2);
        rb_define_method(self, "mv", (VALUE (*)(...))(mv), -1);
        rb_define_method(self, "mc", (VALUE (*)(...))(mc), -1);

        // rb_f_notimplement
        rb_define_method(self, "m1", rb_f_notimplement, 1);
        rb_define_method(self, "m2", rb_f_notimplement, 2);
        rb_define_method(self, "ma", rb_f_notimplement, -2);
        rb_define_method(self, "mv", rb_f_notimplement, -1);
        rb_define_method(self, "mc", rb_f_notimplement, -1);

#ifdef HAVE_NULLPTR
        // It doesn't make any sense at all to pass nullptr as a method.
#endif

        return self;
    }
}

namespace test_rb_define_method_id {
    static VALUE
    m1(VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    m2(VALUE, VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    ma(VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    mv(int, VALUE*, VALUE)
    {
        return Qnil;
    }

    static VALUE
    mc(int, const VALUE*, VALUE)
    {
        return Qnil;
    }

    VALUE
    test(VALUE self)
    {
        // No cast
        rb_define_method_id(self, rb_intern("m1"), m1, 1);
        rb_define_method_id(self, rb_intern("m2"), m2, 2);
        rb_define_method_id(self, rb_intern("ma"), ma, -2);
        rb_define_method_id(self, rb_intern("mv"), mv, -1);
        rb_define_method_id(self, rb_intern("mc"), mc, -1);

        // Cast by RUBY_METHOD_FUNC
        rb_define_method_id(self, rb_intern("m1"), RUBY_METHOD_FUNC(m1), 1);
        rb_define_method_id(self, rb_intern("m2"), RUBY_METHOD_FUNC(m2), 2);
        rb_define_method_id(self, rb_intern("ma"), RUBY_METHOD_FUNC(ma), -2);
        rb_define_method_id(self, rb_intern("mv"), RUBY_METHOD_FUNC(mv), -1);
        rb_define_method_id(self, rb_intern("mc"), RUBY_METHOD_FUNC(mc), -1);

        // Explicit cast instead of RUBY_METHOD_FUNC
        rb_define_method_id(self, rb_intern("m1"), (VALUE (*)(...))(m1), 1);
        rb_define_method_id(self, rb_intern("m2"), (VALUE (*)(...))(m2), 2);
        rb_define_method_id(self, rb_intern("ma"), (VALUE (*)(...))(ma), -2);
        rb_define_method_id(self, rb_intern("mv"), (VALUE (*)(...))(mv), -1);
        rb_define_method_id(self, rb_intern("mc"), (VALUE (*)(...))(mc), -1);

        // rb_f_notimplement
        rb_define_method_id(self, rb_intern("m1"), rb_f_notimplement, 1);
        rb_define_method_id(self, rb_intern("m2"), rb_f_notimplement, 2);
        rb_define_method_id(self, rb_intern("ma"), rb_f_notimplement, -2);
        rb_define_method_id(self, rb_intern("mv"), rb_f_notimplement, -1);
        rb_define_method_id(self, rb_intern("mc"), rb_f_notimplement, -1);

#ifdef HAVE_NULLPTR
        // It doesn't make any sense at all to pass nullptr as a method.
#endif

        return self;
    }
}

namespace test_rb_define_module_function {
    static VALUE
    m1(VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    m2(VALUE, VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    ma(VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    mv(int, VALUE*, VALUE)
    {
        return Qnil;
    }

    static VALUE
    mc(int, const VALUE*, VALUE)
    {
        return Qnil;
    }

    VALUE
    test(VALUE self)
    {
        // No cast
        rb_define_module_function(self, "m1", m1, 1);
        rb_define_module_function(self, "m2", m2, 2);
        rb_define_module_function(self, "ma", ma, -2);
        rb_define_module_function(self, "mv", mv, -1);
        rb_define_module_function(self, "mc", mc, -1);

        // Cast by RUBY_METHOD_FUNC
        rb_define_module_function(self, "m1", RUBY_METHOD_FUNC(m1), 1);
        rb_define_module_function(self, "m2", RUBY_METHOD_FUNC(m2), 2);
        rb_define_module_function(self, "ma", RUBY_METHOD_FUNC(ma), -2);
        rb_define_module_function(self, "mv", RUBY_METHOD_FUNC(mv), -1);
        rb_define_module_function(self, "mc", RUBY_METHOD_FUNC(mc), -1);

        // Explicit cast instead of RUBY_METHOD_FUNC
        rb_define_module_function(self, "m1", (VALUE (*)(...))(m1), 1);
        rb_define_module_function(self, "m2", (VALUE (*)(...))(m2), 2);
        rb_define_module_function(self, "ma", (VALUE (*)(...))(ma), -2);
        rb_define_module_function(self, "mv", (VALUE (*)(...))(mv), -1);
        rb_define_module_function(self, "mc", (VALUE (*)(...))(mc), -1);

        // rb_f_notimplement
        rb_define_module_function(self, "m1", rb_f_notimplement, 1);
        rb_define_module_function(self, "m2", rb_f_notimplement, 2);
        rb_define_module_function(self, "ma", rb_f_notimplement, -2);
        rb_define_module_function(self, "mv", rb_f_notimplement, -1);
        rb_define_module_function(self, "mc", rb_f_notimplement, -1);

#ifdef HAVE_NULLPTR
        // It doesn't make any sense at all to pass nullptr as a method.
#endif

        return self;
    }
}

namespace test_rb_define_singleton_method {
    static VALUE
    m1(VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    m2(VALUE, VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    ma(VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    mv(int, VALUE*, VALUE)
    {
        return Qnil;
    }

    static VALUE
    mc(int, const VALUE*, VALUE)
    {
        return Qnil;
    }

    VALUE
    test(VALUE self)
    {
        // No cast
        rb_define_singleton_method(self, "m1", m1, 1);
        rb_define_singleton_method(self, "m2", m2, 2);
        rb_define_singleton_method(self, "ma", ma, -2);
        rb_define_singleton_method(self, "mv", mv, -1);
        rb_define_singleton_method(self, "mc", mc, -1);

        // Cast by RUBY_METHOD_FUNC
        rb_define_singleton_method(self, "m1", RUBY_METHOD_FUNC(m1), 1);
        rb_define_singleton_method(self, "m2", RUBY_METHOD_FUNC(m2), 2);
        rb_define_singleton_method(self, "ma", RUBY_METHOD_FUNC(ma), -2);
        rb_define_singleton_method(self, "mv", RUBY_METHOD_FUNC(mv), -1);
        rb_define_singleton_method(self, "mc", RUBY_METHOD_FUNC(mc), -1);

        // Explicit cast instead of RUBY_METHOD_FUNC
        rb_define_singleton_method(self, "m1", (VALUE (*)(...))(m1), 1);
        rb_define_singleton_method(self, "m2", (VALUE (*)(...))(m2), 2);
        rb_define_singleton_method(self, "ma", (VALUE (*)(...))(ma), -2);
        rb_define_singleton_method(self, "mv", (VALUE (*)(...))(mv), -1);
        rb_define_singleton_method(self, "mc", (VALUE (*)(...))(mc), -1);

        // rb_f_notimplement
        rb_define_singleton_method(self, "m1", rb_f_notimplement, 1);
        rb_define_singleton_method(self, "m2", rb_f_notimplement, 2);
        rb_define_singleton_method(self, "ma", rb_f_notimplement, -2);
        rb_define_singleton_method(self, "mv", rb_f_notimplement, -1);
        rb_define_singleton_method(self, "mc", rb_f_notimplement, -1);

#ifdef HAVE_NULLPTR
        // It doesn't make any sense at all to pass nullptr as a method.
#endif

        return self;
    }
}

namespace test_rb_define_protected_method {
    static VALUE
    m1(VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    m2(VALUE, VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    ma(VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    mv(int, VALUE*, VALUE)
    {
        return Qnil;
    }

    static VALUE
    mc(int, const VALUE*, VALUE)
    {
        return Qnil;
    }

    VALUE
    test(VALUE self)
    {
        // No cast
        rb_define_protected_method(self, "m1", m1, 1);
        rb_define_protected_method(self, "m2", m2, 2);
        rb_define_protected_method(self, "ma", ma, -2);
        rb_define_protected_method(self, "mv", mv, -1);
        rb_define_protected_method(self, "mc", mc, -1);

        // Cast by RUBY_METHOD_FUNC
        rb_define_protected_method(self, "m1", RUBY_METHOD_FUNC(m1), 1);
        rb_define_protected_method(self, "m2", RUBY_METHOD_FUNC(m2), 2);
        rb_define_protected_method(self, "ma", RUBY_METHOD_FUNC(ma), -2);
        rb_define_protected_method(self, "mv", RUBY_METHOD_FUNC(mv), -1);
        rb_define_protected_method(self, "mc", RUBY_METHOD_FUNC(mc), -1);

        // Explicit cast instead of RUBY_METHOD_FUNC
        rb_define_protected_method(self, "m1", (VALUE (*)(...))(m1), 1);
        rb_define_protected_method(self, "m2", (VALUE (*)(...))(m2), 2);
        rb_define_protected_method(self, "ma", (VALUE (*)(...))(ma), -2);
        rb_define_protected_method(self, "mv", (VALUE (*)(...))(mv), -1);
        rb_define_protected_method(self, "mc", (VALUE (*)(...))(mc), -1);

        // rb_f_notimplement
        rb_define_protected_method(self, "m1", rb_f_notimplement, 1);
        rb_define_protected_method(self, "m2", rb_f_notimplement, 2);
        rb_define_protected_method(self, "ma", rb_f_notimplement, -2);
        rb_define_protected_method(self, "mv", rb_f_notimplement, -1);
        rb_define_protected_method(self, "mc", rb_f_notimplement, -1);

#ifdef HAVE_NULLPTR
        // It doesn't make any sense at all to pass nullptr as a method.
#endif

        return self;
    }
}

namespace test_rb_define_private_method {
    static VALUE
    m1(VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    m2(VALUE, VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    ma(VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    mv(int, VALUE*, VALUE)
    {
        return Qnil;
    }

    static VALUE
    mc(int, const VALUE*, VALUE)
    {
        return Qnil;
    }

    VALUE
    test(VALUE self)
    {
        // No cast
        rb_define_private_method(self, "m1", m1, 1);
        rb_define_private_method(self, "m2", m2, 2);
        rb_define_private_method(self, "ma", ma, -2);
        rb_define_private_method(self, "mv", mv, -1);
        rb_define_private_method(self, "mc", mc, -1);

        // Cast by RUBY_METHOD_FUNC
        rb_define_private_method(self, "m1", RUBY_METHOD_FUNC(m1), 1);
        rb_define_private_method(self, "m2", RUBY_METHOD_FUNC(m2), 2);
        rb_define_private_method(self, "ma", RUBY_METHOD_FUNC(ma), -2);
        rb_define_private_method(self, "mv", RUBY_METHOD_FUNC(mv), -1);
        rb_define_private_method(self, "mc", RUBY_METHOD_FUNC(mc), -1);

        // Explicit cast instead of RUBY_METHOD_FUNC
        rb_define_private_method(self, "m1", (VALUE (*)(...))(m1), 1);
        rb_define_private_method(self, "m2", (VALUE (*)(...))(m2), 2);
        rb_define_private_method(self, "ma", (VALUE (*)(...))(ma), -2);
        rb_define_private_method(self, "mv", (VALUE (*)(...))(mv), -1);
        rb_define_private_method(self, "mc", (VALUE (*)(...))(mc), -1);

        // rb_f_notimplement
        rb_define_private_method(self, "m1", rb_f_notimplement, 1);
        rb_define_private_method(self, "m2", rb_f_notimplement, 2);
        rb_define_private_method(self, "ma", rb_f_notimplement, -2);
        rb_define_private_method(self, "mv", rb_f_notimplement, -1);
        rb_define_private_method(self, "mc", rb_f_notimplement, -1);

#ifdef HAVE_NULLPTR
        // It doesn't make any sense at all to pass nullptr as a method.
#endif

        return self;
    }
}

namespace test_rb_define_global_function {
    static VALUE
    m1(VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    m2(VALUE, VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    ma(VALUE, VALUE)
    {
        return Qnil;
    }

    static VALUE
    mv(int, VALUE*, VALUE)
    {
        return Qnil;
    }

    static VALUE
    mc(int, const VALUE*, VALUE)
    {
        return Qnil;
    }

    VALUE
    test(VALUE self)
    {
        // No cast
        rb_define_global_function("m1", m1, 1);
        rb_define_global_function("m2", m2, 2);
        rb_define_global_function("ma", ma, -2);
        rb_define_global_function("mv", mv, -1);
        rb_define_global_function("mc", mc, -1);

        // Cast by RUBY_METHOD_FUNC
        rb_define_global_function("m1", RUBY_METHOD_FUNC(m1), 1);
        rb_define_global_function("m2", RUBY_METHOD_FUNC(m2), 2);
        rb_define_global_function("ma", RUBY_METHOD_FUNC(ma), -2);
        rb_define_global_function("mv", RUBY_METHOD_FUNC(mv), -1);
        rb_define_global_function("mc", RUBY_METHOD_FUNC(mc), -1);

        // Explicit cast instead of RUBY_METHOD_FUNC
        rb_define_global_function("m1", (VALUE (*)(...))(m1), 1);
        rb_define_global_function("m2", (VALUE (*)(...))(m2), 2);
        rb_define_global_function("ma", (VALUE (*)(...))(ma), -2);
        rb_define_global_function("mv", (VALUE (*)(...))(mv), -1);
        rb_define_global_function("mc", (VALUE (*)(...))(mc), -1);

        // rb_f_notimplement
        rb_define_global_function("m1", rb_f_notimplement, 1);
        rb_define_global_function("m2", rb_f_notimplement, 2);
        rb_define_global_function("ma", rb_f_notimplement, -2);
        rb_define_global_function("mv", rb_f_notimplement, -1);
        rb_define_global_function("mc", rb_f_notimplement, -1);

#ifdef HAVE_NULLPTR
        // It doesn't make any sense at all to pass nullptr as a method.
#endif

        return self;
    }
}

extern "C" void
Init_cxxanyargs(void)
{
    VALUE b = rb_define_module("Bug");
#define test(sym) \
    rb_define_module_function(b, #sym, RUBY_METHOD_FUNC(test_ ## sym::test), 0)

    test(rb_define_virtual_variable);
    test(rb_define_hooked_variable);
    test(rb_iterate);
    test(rb_block_call);
    test(rb_rescue);
    test(rb_rescue2);
    test(rb_ensure);
    test(rb_catch);
    test(rb_catch_obj);
    test(rb_fiber_new);
    test(rb_proc_new);
    test(rb_thread_create);
    test(st_foreach);
    test(st_foreach_check);
    test(st_foreach_safe);
    test(rb_hash_foreach);
    test(rb_ivar_foreach);
    test(rb_define_method);
    test(rb_define_method_id);
    test(rb_define_module_function);
    test(rb_define_singleton_method);
    test(rb_define_protected_method);
    test(rb_define_private_method);
    test(rb_define_global_function);
}
