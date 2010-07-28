/* public domain rewrite of hypot */

#include "missing.h"
#include <math.h>

double hypot(x,y)
    double x, y;
{
    if (x < 0) x = -x;
    if (y < 0) y = -y;
    if (x < y) {
	double tmp = x;
	x = y; y = tmp;
    }
    if (y == 0.0) return x;
    y /= x;
    return x * sqrt(1.0+y*y);
}
