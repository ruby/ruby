struct direct
{
    long d_namlen;
    ino_t d_ino;
    char d_name[256];
};
typedef struct {
    char *start;
    char *curr;
    long size;
    long nfiles;
    struct direct dirstr;
} DIR;

DIR* opendir(const char*);
struct direct* readdir(DIR *);
long telldir(DIR *);
void seekdir(DIR *, long);
void rewinddir(DIR *);
void closedir(DIR *);
