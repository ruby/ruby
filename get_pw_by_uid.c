#include <stdio.h>
#include <stdlib.h>
#include <pwd.h>

int main(int argc, char *argv[])
{
    int status = EXIT_SUCCESS;
    uid_t uid;
    struct passwd *pw;

    if (argc < 2) {
        status = EXIT_FAILURE;
        fprintf(stderr, "An argument is required.\n");
        goto end;
    }
    uid = (uid_t)strtol(argv[1], NULL, 10);
    printf("INFO: Input uid: [%d]\n", uid);
    pw = getpwuid(uid);
    printf("INFO: uid: %d\n", pw->pw_uid);
    printf("INFO: gid: %d\n", pw->pw_gid);
end:
    return status;
}
