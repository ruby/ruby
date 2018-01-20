#include "ruby/missing.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>

double
nan(const char *spec)
{
#if 0
    /* FIXME: we have not yet seen any situation this is
     * necessary. Please write a proper implementation that
     * covers this branch.  */
    if (spec && spec[0]) {
	double generated_nan;
	int len = snprintf(NULL, 0, "NAN(%s)", spec);
	char *buf = malloc(len + 1); /* +1 for NUL */
	sprintf(buf, "NAN(%s)", spec);
	generated_nan = strtod(buf, NULL);
	free(buf);
	return generated_nan;
    }
    else
#endif
    {
	assert(!spec || !spec[0]);
	return (double)NAN;
    }
}
