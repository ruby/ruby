#include "ruby/random.h"

static const uint32_t max_seeds = 1024;

typedef struct {
    rb_random_t base;
    uint32_t num, idx, *buf;
} rand_loop_t;

RB_RANDOM_INTERFACE_DECLARE_WITH_REAL(loop);
static const rb_random_interface_t random_loop_if = {
    32,
    RB_RANDOM_INTERFACE_DEFINE_WITH_REAL(loop)
};

static size_t
random_loop_memsize(const void *ptr)
{
    const rand_loop_t *r = ptr;
    return sizeof(*r) + r->num * sizeof(r->buf[0]);
}

static rb_random_data_type_t random_loop_type = {
    "random/loop",
    {
        rb_random_mark,
        RUBY_TYPED_DEFAULT_FREE,
        random_loop_memsize,
    },
    RB_RANDOM_PARENT,
    (void *)&random_loop_if,
    RUBY_TYPED_FREE_IMMEDIATELY
};


static VALUE
loop_alloc(VALUE klass)
{
    rand_loop_t *rnd;
    VALUE obj = TypedData_Make_Struct(klass, rand_loop_t, &random_loop_type, rnd);
    rb_random_base_init(&rnd->base);
    return obj;
}

static void
loop_init(rb_random_t *rnd, const uint32_t *buf, size_t len)
{
    rand_loop_t *r = (rand_loop_t *)rnd;

    if (len > max_seeds) len = max_seeds;

    REALLOC_N(r->buf, uint32_t, len);
    MEMCPY(r->buf, buf, uint32_t, (r->num = (uint32_t)len));
}

static void
loop_get_bytes(rb_random_t *rnd, void *p, size_t n)
{
    uint8_t *buf = p;
    while (n > 0) {
        uint32_t x = loop_get_int32(rnd);
        switch (n % 4) {
          case 0:
            *buf++ = (uint8_t)x;
            n--;
            /* FALLTHROUGH */
          case 3:
            *buf++ = (uint8_t)x;
            n--;
            /* FALLTHROUGH */
          case 2:
            *buf++ = (uint8_t)x;
            n--;
            /* FALLTHROUGH */
          case 1:
            *buf++ = (uint8_t)x;
            n--;
        }
    }
}

static uint32_t
loop_get_int32(rb_random_t *rnd)
{
    rand_loop_t *r = (rand_loop_t *)rnd;
    if (r->idx < r->num) {
        uint32_t x = r->buf[r->idx++];
        if (r->idx >= r->num) r->idx = 0;
        return x;
    }
    else if (r->num) {
        return r->buf[r->idx = 0];
    }
    return 0;
}

static double
loop_get_real(rb_random_t *rnd, int excl)
{
    uint32_t a = loop_get_int32(rnd);
    return ldexp(a, -16);
}

void
Init_random_loop(VALUE mod, VALUE base)
{
    VALUE c = rb_define_class_under(mod, "Loop", base);
    rb_define_alloc_func(c, loop_alloc);
    RB_RANDOM_DATA_INIT_PARENT(random_loop_type);
}
