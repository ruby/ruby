#include <ruby.h>
#include <ruby/st.h>

static st_data_t expect_size = 32;
struct checker {
    st_table *tbl;
    st_index_t nr;
    VALUE test;
};

static void
force_unpack_check(struct checker *c, st_data_t key, st_data_t val)
{
    if (c->nr == 0) {
        st_data_t i;

        if (c->tbl->bins != NULL) rb_bug("should be packed\n");

        /* force unpacking during iteration: */
        for (i = 1; i < expect_size; i++)
            st_add_direct(c->tbl, i, i);

        if (c->tbl->bins == NULL) rb_bug("should be unpacked\n");
    }

    if (key != c->nr) {
        rb_bug("unexpected key: %"PRIuVALUE" (expected %"PRIuVALUE")\n", (VALUE)key, (VALUE)c->nr);
    }
    if (val != c->nr) {
        rb_bug("unexpected val: %"PRIuVALUE" (expected %"PRIuVALUE")\n", (VALUE)val, (VALUE)c->nr);
    }

    c->nr++;
}

static int
unp_fec_i(st_data_t key, st_data_t val, st_data_t args, int error)
{
    struct checker *c = (struct checker *)args;

    if (error) {
        if (c->test == ID2SYM(rb_intern("delete2")))
            return ST_STOP;

        rb_bug("unexpected error");
    }

    force_unpack_check(c, key, val);

    if (c->test == ID2SYM(rb_intern("check"))) {
        return ST_CHECK;
    }
    if (c->test == ID2SYM(rb_intern("delete1"))) {
        if (c->nr == 1) return ST_DELETE;
        return ST_CHECK;
    }
    if (c->test == ID2SYM(rb_intern("delete2"))) {
        if (c->nr == 1) {
            st_data_t k = 0;
            st_data_t v;

            if (!st_delete(c->tbl, &k, &v)) {
                rb_bug("failed to delete\n");
            }
            if (v != 0) {
                rb_bug("unexpected value deleted: %"PRIuVALUE" (expected 0)", (VALUE)v);
            }
        }
        return ST_CHECK;
    }

    rb_raise(rb_eArgError, "unexpected arg: %+"PRIsVALUE, c->test);
}

static VALUE
unp_fec(VALUE self, VALUE test)
{
    st_table *tbl = st_init_numtable();
    struct checker c;

    c.tbl = tbl;
    c.nr = 0;
    c.test = test;

    st_add_direct(tbl, 0, 0);

    if (tbl->bins != NULL) rb_bug("should still be packed\n");

    st_foreach_check(tbl, unp_fec_i, (st_data_t)&c, -1);

    if (c.test == ID2SYM(rb_intern("delete2"))) {
        if (c.nr != 1) {
            rb_bug("mismatched iteration: %"PRIuVALUE" (expected 1)\n", (VALUE)c.nr);
        }
    }
    else if (c.nr != expect_size) {
        rb_bug("mismatched iteration: %"PRIuVALUE" (expected %"PRIuVALUE")\n",
                (VALUE)c.nr, (VALUE)expect_size);
    }

    if (tbl->bins == NULL) rb_bug("should be unpacked\n");

    st_free_table(tbl);

    return Qnil;
}

static int
unp_fe_i(st_data_t key, st_data_t val, st_data_t args)
{
    struct checker *c = (struct checker *)args;

    force_unpack_check(c, key, val);
    if (c->test == ID2SYM(rb_intern("unpacked"))) {
        return ST_CONTINUE;
    }
    else if (c->test == ID2SYM(rb_intern("unpack_delete"))) {
        if (c->nr == 1) {
            st_data_t k = 0;
            st_data_t v;

            if (!st_delete(c->tbl, &k, &v)) {
                rb_bug("failed to delete\n");
            }
            if (v != 0) {
                rb_bug("unexpected value deleted: %"PRIuVALUE" (expected 0)", (VALUE)v);
            }
            return ST_CONTINUE;
        }
        rb_bug("should never get here\n");
    }

    rb_raise(rb_eArgError, "unexpected arg: %+"PRIsVALUE, c->test);
}

static VALUE
unp_fe(VALUE self, VALUE test)
{
    st_table *tbl = st_init_numtable();
    struct checker c;

    c.tbl = tbl;
    c.nr = 0;
    c.test = test;

    st_add_direct(tbl, 0, 0);

    if (tbl->bins != NULL) rb_bug("should still be packed\n");

    st_foreach(tbl, unp_fe_i, (st_data_t)&c);

    if (c.test == ID2SYM(rb_intern("unpack_delete"))) {
        if (c.nr != 1) {
            rb_bug("mismatched iteration: %"PRIuVALUE" (expected 1)\n", (VALUE)c.nr);
        }
    }
    else if (c.nr != expect_size) {
        rb_bug("mismatched iteration: %"PRIuVALUE" (expected %"PRIuVALUE"o)\n",
                (VALUE)c.nr, (VALUE)expect_size);
    }

    if (tbl->bins == NULL) rb_bug("should be unpacked\n");

    st_free_table(tbl);

    return Qnil;
}

void
Init_foreach(void)
{
    VALUE bug = rb_define_module("Bug");
    rb_define_singleton_method(bug, "unp_st_foreach_check", unp_fec, 1);
    rb_define_singleton_method(bug, "unp_st_foreach", unp_fe, 1);
}
