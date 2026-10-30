#include "test_initialize_destroy.h"
#include "test_pthread_resume.h"
#include "test_transfer_repeat.h"
#include "test_transfer_return.h"

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static const char success[] = "\033[32;1m";
static const char failure[] = "\033[31;1m";
static const char info[] = "\033[36m";
static const char reset[] = "\033[m";

static int
run_tests(int verbose, int highlight)
{
    int result = EXIT_SUCCESS;

# define hi(s) ((highlight) ? (s) : "")
# define pass() ((verbose) && printf("%spass%s\n", hi(success), hi(reset)))
# define fail() ((verbose) && printf("%sfail%s\n", hi(failure), hi(reset)))
# define run(test) ((verbose) && printf("Testing %s" #test "%s... ", hi(info), hi(reset)), \
                    (test_##test() == EXIT_SUCCESS) ? \
                    pass() : (fail(), result = EXIT_FAILURE))

    run(initialize_destroy);
    run(pthread_resume);
    run(transfer_repeat);
    run(transfer_return);

    return result;
}

static int
color(void)
{
    char *no_color = getenv("NO_COLOR");
    if (no_color && *no_color) return 0;
    return isatty(fileno(stdout));
}

int
main(int argc, char **argv)
{
    int verbose = 0;
    for (int i = 1; i < argc; ++i) {
        if (argv[i][0] != '-') continue;
        const char *opt = &argv[i][1];
        if (*opt == '-') continue;
        for (; *opt; ++opt) {
            switch (*opt) {
              case 'v':
                verbose = 1;
                break;
              case 'h':
                printf("usage: %s [-v]\n", argv[0]);
                return EXIT_SUCCESS;
              default:
                fprintf(stderr, "unknown option: -%c\n", *opt);
                return EXIT_FAILURE;
            }
        }
    }
    return run_tests(verbose, color());
}
