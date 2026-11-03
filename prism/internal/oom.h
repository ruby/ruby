#ifndef PRISM_INTERNAL_OOM_H
#define PRISM_INTERNAL_OOM_H

/**
 * Called when an allocation that prism cannot recover from fails. By default
 * it writes a message to stderr and aborts. A consumer can define PRISM_OOM
 * before building prism to handle the failure itself.
 */
#ifndef PRISM_OOM
#include <stdio.h>
#include <stdlib.h>
#define PRISM_OOM() do { fputs("prism out of memory; aborting\n", stderr); abort(); } while (0)
#endif

#endif
