#include "test_initialize_destroy.h"
#include "test_pthread_resume.h"
#include "test_transfer_repeat.h"
#include "test_transfer_return.h"

#include <stdlib.h>

static int
run_tests(void)
{
    int result = EXIT_SUCCESS;

    if (test_initialize_destroy() != EXIT_SUCCESS) result = EXIT_FAILURE;
    if (test_pthread_resume() != EXIT_SUCCESS) result = EXIT_FAILURE;
    if (test_transfer_repeat() != EXIT_SUCCESS) result = EXIT_FAILURE;
    if (test_transfer_return() != EXIT_SUCCESS) result = EXIT_FAILURE;

    return result;
}

int
#ifdef _WIN32
wmain(void)
#else
main(void)
#endif
{
    return run_tests();
}
