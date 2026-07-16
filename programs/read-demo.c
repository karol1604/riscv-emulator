typedef unsigned u32;

extern u32 sys_read(u32 fd, void *buffer, u32 length);
extern u32 sys_write(u32 fd, const void *buffer, u32 length);

static int write_all(u32 fd, const void *buffer, u32 length)
{
    return sys_write(fd, buffer, length) == length ? 0 : -1;
}

int main(void)
{
    static const char prompt[] = "Type a line: ";
    static const char prefix[] = "Uppercase: ";
    static const char read_error[] = "read failed\n";
    static const char newline[] = "\n";
    char buffer[128];

    if (write_all(1, prompt, sizeof(prompt) - 1) != 0) {
        return 2;
    }

    const u32 count = sys_read(0, buffer, sizeof(buffer));
    if (count > sizeof(buffer)) {
        write_all(2, read_error, sizeof(read_error) - 1);
        return 1;
    }

    for (u32 i = 0; i < count; ++i) {
        if (buffer[i] >= 'a' && buffer[i] <= 'z') {
            buffer[i] -= 'a' - 'A';
        }
    }

    if (write_all(1, prefix, sizeof(prefix) - 1) != 0 ||
        write_all(1, buffer, count) != 0) {
        return 2;
    }

    if (count == 0 || buffer[count - 1] != '\n') {
        if (write_all(1, newline, sizeof(newline) - 1) != 0) {
            return 2;
        }
    }

    return 0;
}
