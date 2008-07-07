#ifdef __BORLANDC__
#  ifndef WIN32_DIR_H_
#    define WIN32_DIR_H_
#    include <sys/types.h>
#  endif
#endif

struct direct
{
    long d_namlen;
    ino_t d_ino;
    char d_name[256];
    char d_isdir; /* directory */
    char d_isrep; /* reparse point */
};
typedef struct {
    char *start;
    char *curr;
    long size;
    long nfiles;
    long loc;  /* [0, nfiles) */
    struct direct dirstr;
    char *bits;  /* used for d_isdir and d_isrep */
} DIR;


DIR*           rb_w32_opendir(const char*);
struct direct* rb_w32_readdir(DIR *);
long           rb_w32_telldir(DIR *);
void           rb_w32_seekdir(DIR *, long);
void           rb_w32_rewinddir(DIR *);
void           rb_w32_closedir(DIR *);

#define opendir   rb_w32_opendir
#define readdir   rb_w32_readdir
#define telldir   rb_w32_telldir
#define seekdir   rb_w32_seekdir
#define rewinddir rb_w32_rewinddir
#define closedir  rb_w32_closedir
