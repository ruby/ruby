#ifdef _MSC_VER

#include <float.h>
int
isnan(n)
  double n;
{
  return _isnan(n);
}

#else

static int double_ne();

int
isnan(n)
  double n;
{
  return double_ne(n, n);
}

static
int
double_ne(n1, n2)
  double n1, n2;
{
  return n1 != n2;
}
#endif
