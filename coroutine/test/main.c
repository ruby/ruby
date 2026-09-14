#include "test_initialize_destroy.h"
#include "test_transfer_repeat.h"
#include "test_transfer_return.h"

#include <stdlib.h>

int
main(void)
{
    int result = EXIT_SUCCESS;

    if (test_initialize_destroy() != EXIT_SUCCESS) result = EXIT_FAILURE;
    if (test_transfer_repeat() != EXIT_SUCCESS) result = EXIT_FAILURE;
    if (test_transfer_return() != EXIT_SUCCESS) result = EXIT_FAILURE;

    return result;
}
