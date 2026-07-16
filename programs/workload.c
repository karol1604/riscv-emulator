volatile unsigned inputs[12] = {
    17u,
    0xfffffff0u,
    123456789u,
    0x80000001u,
    42u,
    99991u,
    0u,
    0xdeadbeefu,
    7u,
    0xabcdef01u,
    314159265u,
    271828182u,
};

volatile unsigned outputs[12];

__attribute__((noinline))
unsigned run_workload(unsigned divisor, unsigned count)
{
    unsigned accumulator = 0x12345678u;

    for (unsigned i = 0; i < count; ++i) {
        const unsigned value = inputs[i];
        const unsigned quotient = value / divisor;
        const unsigned remainder = value % divisor;

        accumulator ^= value + i;
        accumulator = (accumulator << 5) | (accumulator >> 27);
        accumulator += quotient;
        accumulator *= 33u;

        outputs[i] = accumulator ^ remainder;
    }

    return accumulator ^ outputs[0] ^ outputs[count - 1];
}
