#include "config.h"
#ifdef HAVE_STRING_H
# include <string.h>
#else
# include <strings.h>
#endif

static double zero()	{ return 0.0; }
static double one()	{ return 1.0; }
static double inf()	{ return one() / zero(); }

int
isinf(n)
    double n;
{
    static double pinf = 0.0;
    static double ninf = 0.0;

    if (pinf == 0.0) {
	pinf = inf();
	ninf = -pinf;
    }
    return memcmp(&n, &pinf, sizeof n) == 0
	|| memcmp(&n, &ninf, sizeof n) == 0;
}
