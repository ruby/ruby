#ifndef RUBY_RUBY_BACKWARD_H
#define RUBY_RUBY_BACKWARD_H 1

#ifndef RUBY_SHOW_COPYRIGHT_TO_DIE
# define RUBY_SHOW_COPYRIGHT_TO_DIE 1
#endif
#if RUBY_SHOW_COPYRIGHT_TO_DIE
/* for source code backward compatibility */
DEPRECATED(static inline int ruby_show_copyright_to_die(int));
static inline int
ruby_show_copyright_to_die(int exitcode)
{
    ruby_show_copyright();
    return exitcode;
}
#define ruby_show_copyright() /* defer EXIT_SUCCESS */ \
    (exit(ruby_show_copyright_to_die(EXIT_SUCCESS)))
#endif

#endif /* RUBY_RUBY_BACKWARD_H */
