/* public domain rewrite of isnan(3) */

static int double_ne();

int
isnan(n)
    double n;
{
    return double_ne(n, n);
}

static int
double_ne(n1, n2)
    double n1, n2;
{
    return n1 != n2;
}
