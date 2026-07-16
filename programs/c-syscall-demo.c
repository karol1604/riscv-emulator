extern unsigned sys_write(unsigned fd, const char *data, unsigned length);

static int write_all(unsigned fd, const char *data, unsigned length)
{
    while (length != 0) {
        const unsigned written = sys_write(fd, data, length);

        // Linux errors are negative values represented as large unsigned values.
        if (written == 0 || written > length) {
            return -1;
        }

        data += written;
        length -= written;
    }

    return 0;
}

static int print_unsigned(unsigned value)
{
    char digits[10];
    unsigned start = sizeof(digits);

    do {
        digits[--start] = (char)('0' + value % 10);
        value /= 10;
    } while (value != 0);

    return write_all(1, digits + start, sizeof(digits) - start);
}

__attribute__((noinline))
static unsigned sum_of_squares(unsigned limit)
{
    unsigned sum = 0;

    for (unsigned i = 1; i <= limit; ++i) {
        sum += i * i;
    }

    return sum;
}

__attribute__((noinline))
static unsigned factorial(unsigned value)
{
    unsigned result = 1;

    while (value > 1) {
        result *= value--;
    }

    return result;
}

int main(void)
{
    static const char heading[] = "Hello from freestanding C!\n";
    static const char squares_label[] = "sum of squares from 1 to 20 = ";
    static const char factorial_label[] = "10! = ";
    static const char newline[] = "\n";
    static const char error_message[] = "C workload produced an unexpected result\n";

    volatile unsigned squares_limit = 20;
    volatile unsigned factorial_input = 10;
    const unsigned squares = sum_of_squares(squares_limit);
    const unsigned factorial_result = factorial(factorial_input);

    if (squares != 2870 || factorial_result != 3628800) {
        (void)write_all(2, error_message, sizeof(error_message) - 1);
        return 1;
    }

    if (write_all(1, heading, sizeof(heading) - 1) != 0 ||
        write_all(1, squares_label, sizeof(squares_label) - 1) != 0 ||
        print_unsigned(squares) != 0 ||
        write_all(1, newline, sizeof(newline) - 1) != 0 ||
        write_all(1, factorial_label, sizeof(factorial_label) - 1) != 0 ||
        print_unsigned(factorial_result) != 0 ||
        write_all(1, newline, sizeof(newline) - 1) != 0) {
        return 2;
    }

    return 0;
}
