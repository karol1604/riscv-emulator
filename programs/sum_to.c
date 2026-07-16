__attribute__((noinline))
unsigned sum_to(unsigned n)
{
    unsigned sum = 0;

    for (unsigned i = 1; i <= n; ++i) {
        sum += i;
    }

    return sum;
}
