#include "ruby/random.h"

#if RUBY_RANDOM_INTERFACE_VERSION_MAJOR < RUBY_RANDOM_INTERFACE_VERSION_MAJOR_MAX
# define DEFINE_VERSION_MAX 1
#else
# define DEFINE_VERSION_MAX 0
#endif

NORETURN(static void must_not_reach(void));
static void
must_not_reach(void)
{
    rb_raise(rb_eTypeError, "must not reach");
}

NORETURN(static void bad_version_init(rb_random_t *, const uint32_t *, size_t));
static void
bad_version_init(rb_random_t *rnd, const uint32_t *buf, size_t len)
{
    must_not_reach();
}

NORETURN(static void bad_version_init_int32(rb_random_t *, uint32_t));
RB_RANDOM_DEFINE_INIT_INT32_FUNC(bad_version)

NORETURN(static void bad_version_get_bytes(rb_random_t *, void *, size_t));
static void
bad_version_get_bytes(rb_random_t *rnd, void *p, size_t n)
{
    must_not_reach();
}

NORETURN(static uint32_t bad_version_get_int32(rb_random_t *));
static uint32_t
bad_version_get_int32(rb_random_t *rnd)
{
    must_not_reach();
    UNREACHABLE_RETURN(0);
}

static VALUE
bad_version_alloc(VALUE klass, const rb_data_type_t *type)
{
    rb_random_t *rnd;
    VALUE obj = TypedData_Make_Struct(klass, rb_random_t, type, rnd);
    rb_random_base_init(rnd);
    return obj;
}

/* version 0 */
static const rb_random_interface_t random_version_zero_if;

static rb_random_data_type_t version_zero_type = {
    "random/version_zero",
    {
        rb_random_mark,
        RUBY_TYPED_DEFAULT_FREE,
    },
    RB_RANDOM_PARENT,
    (void *)&random_version_zero_if,
    RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
version_zero_alloc(VALUE klass)
{
    return bad_version_alloc(klass, &version_zero_type);
}

static void
init_version_zero(VALUE mod, VALUE base)
{
    VALUE c = rb_define_class_under(mod, "VersionZero", base);
    rb_define_alloc_func(c, version_zero_alloc);
    RB_RANDOM_DATA_INIT_PARENT(version_zero_type);
}

#if DEFINE_VERSION_MAX
/* version max */
static const rb_random_interface_t random_version_max_if;
static rb_random_data_type_t version_max_type = {
    "random/version_max",
    {
        rb_random_mark,
        RUBY_TYPED_DEFAULT_FREE,
    },
    RB_RANDOM_PARENT,
    (void *)&random_version_max_if,
    RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
version_max_alloc(VALUE klass)
{
    return bad_version_alloc(klass, &version_max_type);
}

static void
init_version_max(VALUE mod, VALUE base)
{
    VALUE c = rb_define_class_under(mod, "VersionMax", base);
    rb_define_alloc_func(c, version_max_alloc);
    RB_RANDOM_DATA_INIT_PARENT(version_max_type);
}
#else
static void
init_version_max(mod, base)
{
}
#endif

void
Init_random_bad_version(VALUE mod, VALUE base)
{
    init_version_zero(mod, base);
    init_version_max(mod, base);
}

#undef RUBY_RANDOM_INTERFACE_VERSION_MAJOR

#define RUBY_RANDOM_INTERFACE_VERSION_MAJOR 0
static const rb_random_interface_t random_version_zero_if = {
    0,
    RB_RANDOM_INTERFACE_DEFINE(bad_version)
};
#undef RUBY_RANDOM_INTERFACE_VERSION_MAJOR

#if DEFINE_VERSION_MAX
#define RUBY_RANDOM_INTERFACE_VERSION_MAJOR RUBY_RANDOM_INTERFACE_VERSION_MAJOR_MAX
static const rb_random_interface_t random_version_max_if = {
    0,
    RB_RANDOM_INTERFACE_DEFINE(bad_version)
};
#undef RUBY_RANDOM_INTERFACE_VERSION_MAJOR
#endif
