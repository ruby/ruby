
int rb_ractor_main_p(void);

bool rb_ractor_shareable_p_continue(VALUE obj);

#define RB_OBJ_SHAREABLE_P(obj) FL_TEST_RAW((obj), RUBY_FL_SHAREABLE)

// TODO: deep frozen

static inline bool
rb_ractor_shareable_p(VALUE obj)
{
    if (SPECIAL_CONST_P(obj)) {
        return true;
    }
    else if (RB_OBJ_SHAREABLE_P(obj)) {
        return true;
    }
    else {
        return rb_ractor_shareable_p_continue(obj);
    }
}

RUBY_SYMBOL_EXPORT_BEGIN

VALUE rb_ractor_stdin(void);
VALUE rb_ractor_stdout(void);
VALUE rb_ractor_stderr(void);
void rb_ractor_stdin_set(VALUE);
void rb_ractor_stdout_set(VALUE);
void rb_ractor_stderr_set(VALUE);

RUBY_SYMBOL_EXPORT_END
