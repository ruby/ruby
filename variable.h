
/* per-object */

struct gen_ivtbl {
    uint32_t numiv;
    VALUE ivptr[FLEX_ARY_LEN];
};

struct st_table *rb_ivar_generic_ivtbl(void);
