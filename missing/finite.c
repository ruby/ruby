int
finite(n)
    double n;
{
    return !isnan(n) && !isinf(n);
}
