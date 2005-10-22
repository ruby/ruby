/* public domain rewrite of finite(3) */

int
finite(double n)
{
    return !isnan(n) && !isinf(n);
}
