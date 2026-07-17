typedef unsigned u32;

extern u32 sys_write(u32 fd, const void *buffer, u32 length);

static u32 string_length(const char *string)
{
    u32 length = 0;
    while (string[length] != '\0') {
        ++length;
    }
    return length;
}

static int write_string(u32 fd, const char *string)
{
    const u32 length = string_length(string);
    return sys_write(fd, string, length) == length ? 0 : -1;
}

int main(int argc, char **argv)
{
    static const char prefix[] = "argument: ";
    static const char newline[] = "\n";
    static const char usage[] = "expected one argument\n";

    if (argc < 2) {
        write_string(2, usage);
        return 1;
    }

    if (write_string(1, prefix) != 0 ||
        write_string(1, argv[1]) != 0 ||
        write_string(1, newline) != 0) {
        return 2;
    }

    return 0;
}
