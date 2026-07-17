typedef unsigned u32;

enum {
    AT_FDCWD = -100,
    O_RDONLY = 0,
};

extern int sys_openat(int dirfd, const char *path, int flags, u32 mode);
extern int sys_close(int fd);
extern int sys_read(int fd, void *buffer, u32 length);
extern int sys_write(int fd, const void *buffer, u32 length);

static int string_length(const char *string)
{
    int length = 0;
    while (string[length] != '\0') {
        ++length;
    }
    return length;
}

static void write_message(int fd, const char *message)
{
    sys_write(fd, message, (u32)string_length(message));
}

int main(int argc, char **argv)
{
    static const char usage[] = "usage: cat-demo <file>\n";
    static const char open_error[] = "cat-demo: openat failed\n";
    static const char read_error[] = "cat-demo: read failed\n";
    static const char write_error[] = "cat-demo: write failed\n";
    static const char close_error[] = "cat-demo: close failed\n";
    char buffer[256];

    if (argc < 2) {
        write_message(2, usage);
        return 2;
    }

    const int fd = sys_openat(AT_FDCWD, argv[1], O_RDONLY, 0);
    if (fd < 0) {
        write_message(2, open_error);
        return 1;
    }

    for (;;) {
        const int count = sys_read(fd, buffer, sizeof(buffer));
        if (count < 0) {
            write_message(2, read_error);
            sys_close(fd);
            return 1;
        }
        if (count == 0) {
            break;
        }

        u32 written = 0;
        while (written < (u32)count) {
            const int result = sys_write(
                1,
                buffer + written,
                (u32)count - written
            );
            if (result <= 0) {
                write_message(2, write_error);
                sys_close(fd);
                return 1;
            }
            written += (u32)result;
        }
    }

    if (sys_close(fd) < 0) {
        write_message(2, close_error);
        return 1;
    }

    return 0;
}
