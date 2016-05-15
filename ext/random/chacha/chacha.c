#include "ruby/random.h"

#define KEYSTREAM_ONLY
#define u8 uint8_t
#define u32 uint32_t
#include "chacha_private.h"

#ifndef numberof
# define numberof(array) (sizeof(array)/sizeof((array)[0]))
#endif
#ifndef FALSE
# define FALSE 0
#endif
#ifndef TRUE
# define TRUE 1
#endif

#define KEYSZ	(256/8)
#define IVSZ	8
#define BLOCKSZ	64
#define RSBUFSZ	(16*BLOCKSZ)

typedef struct {
    chacha_ctx rs_chacha;    /* chacha context for random keystream */
    uint16_t rs_have;	     /* valid bytes at end of rs_buf */
    uint8_t rs_buf[RSBUFSZ];  /* keystream blocks */
} rs_t;

typedef struct {
    rb_random_t base;
    rs_t rs;
} rand_chacha_t;

RB_RANDOM_INTERFACE_DECLARE(rs)
static const rb_random_interface_t random_chacha_if = {
    (KEYSZ + IVSZ) * 8,
    RB_RANDOM_INTERFACE_DEFINE(rs)
};

static size_t
random_chacha_memsize(const void *ptr)
{
    return sizeof(rand_chacha_t);
}

static
#ifndef _MSC_VER
const
#endif
rb_data_type_t random_chacha_type = {
    "random/ChaCha",
    {
	rb_random_mark,
	RUBY_TYPED_DEFAULT_FREE,
	random_chacha_memsize,
    },
#ifndef _MSC_VER
    &rb_random_data_type,
#else
    0,
#endif
    (void *)&random_chacha_if,
    RUBY_TYPED_FREE_IMMEDIATELY
};

static size_t
minimum(size_t x, size_t y)
{
    return x < y ? x : y;
}

static VALUE
rs_alloc(VALUE klass)
{
    rand_chacha_t *rnd;
    VALUE obj = TypedData_Make_Struct(klass, rand_chacha_t, &random_chacha_type, rnd);
    rnd->base.seed = INT2FIX(0);
    return obj;
}

static void
rs_init0(rs_t *rs, const uint8_t *buf, size_t len)
{
    if (len < KEYSZ + IVSZ)
	return;

    chacha_keysetup(&rs->rs_chacha, buf, KEYSZ * 8, 0);
    chacha_ivsetup(&rs->rs_chacha, buf + KEYSZ);
}

static void
rs_rekey(rb_random_t *rnd, const uint8_t *dat, size_t datlen)
{
    rs_t *rs = &((rand_chacha_t *)rnd)->rs;

#ifndef KEYSTREAM_ONLY
    memset(rs->rs_buf, 0, sizeof(rs->rs_buf));
#endif
    /* fill rs_buf with the keystream */
    chacha_encrypt_bytes(&rs->rs_chacha, rs->rs_buf,
			 rs->rs_buf, sizeof(rs->rs_buf));
    /* mix in optional user provided data */
    if (dat) {
	size_t i, m;

	m = minimum(datlen, KEYSZ + IVSZ);
	for (i = 0; i < m; i++)
	    rs->rs_buf[i] ^= dat[i];
    }
    /* immediately reinit for backtracking resistance */
    rs_init0(rs, rs->rs_buf, KEYSZ + IVSZ);
    memset(rs->rs_buf, 0, KEYSZ + IVSZ);
    rs->rs_have = sizeof(rs->rs_buf) - KEYSZ - IVSZ;
}

static void
rs_init(rb_random_t *rnd, const uint32_t *buf, size_t len)
{
    rs_t *rs = &((rand_chacha_t *)rnd)->rs;

    rs_init0(rs, (const uint8_t *)buf, len * sizeof(*buf));
    /* invalidate rs_buf */
    rs->rs_have = 0;
    memset(rs->rs_buf, 0, sizeof(rs->rs_buf));
}

static void
rs_get_bytes(rb_random_t *rnd, void *p, size_t n)
{
    rs_t *rs = &((rand_chacha_t *)rnd)->rs;
    uint8_t *buf = p;
    uint8_t *keystream;
    size_t m;

    while (n > 0) {
	if (rs->rs_have > 0) {
	    m = minimum(n, rs->rs_have);
	    keystream = rs->rs_buf + sizeof(rs->rs_buf)
		- rs->rs_have;
	    memcpy(buf, keystream, m);
	    memset(keystream, 0, m);
	    buf += m;
	    n -= m;
	    rs->rs_have -= m;
	}
	if (rs->rs_have == 0)
	    rs_rekey(rnd, NULL, 0);
    }
}

static uint32_t
rs_get_int32(rb_random_t *rnd)
{
    rs_t *rs = &((rand_chacha_t *)rnd)->rs;
    uint8_t *keystream;
    uint32_t val;

    if (rs->rs_have < sizeof(val))
	rs_rekey(rnd, NULL, 0);
    keystream = rs->rs_buf + sizeof(rs->rs_buf) - rs->rs_have;
    memcpy(&val, keystream, sizeof(val));
    memset(keystream, 0, sizeof(val));
    rs->rs_have -= sizeof(val);
    return val;
}

void
Init_chacha(void)
{
    VALUE random = rb_cRandom;
    VALUE base = rb_const_get(random, rb_intern_const("Base"));
    VALUE c = rb_define_class_under(rb_cRandom, "ChaCha", base);
    rb_define_alloc_func(c, rs_alloc);
#ifdef _MSC_VER
    random_chacha_type.parent = &rb_random_data_type;
#endif
}
