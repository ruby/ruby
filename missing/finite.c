/* public domain rewrite of finite(3) */

int
finite(n)
    double n;
{
    return !isnan(n) && !isinf(n);
}
