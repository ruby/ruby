#ifdef __osf__

#define _IEEE 1
#include <nan.h>

int
isinf(n)
    double n;
{
        if (IsNANorINF(n) && IsINF(n)) {
                return 1;
        } else {
                return 0;
        }
}

#else

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
#endif
