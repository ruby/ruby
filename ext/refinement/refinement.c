void ruby_Init_refinement(void);
#ifdef __GNUC__
#define PRINTF_ARGS(decl, string_index, first_to_check) \
  decl __attribute__((format(printf, string_index, first_to_check)))
#else
#define PRINTF_ARGS(decl, string_index, first_to_check) decl
#endif
PRINTF_ARGS(void rb_warn(const char*, ...), 1, 2);

void
Init_refinement(void)
{
    rb_warn("Refinements are experimental, and the behavior may change in future versions of Ruby!");
    ruby_Init_refinement();
}
