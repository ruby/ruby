#ifndef RUBY_WIN32_FILE_H
#define RUBY_WIN32_FILE_H

#define MAX_REPARSE_PATH_LEN 4092

enum {
    MINIMUM_REPARSE_BUFFER_PATH_LEN = 4
};
/* License: Ruby's */
typedef struct {
    ULONG  ReparseTag;
    USHORT ReparseDataLength;
    USHORT Reserved;
    union {
	struct {
	    USHORT SubstituteNameOffset;
	    USHORT SubstituteNameLength;
	    USHORT PrintNameOffset;
	    USHORT PrintNameLength;
	    ULONG  Flags;
	    WCHAR  PathBuffer[4];
	} SymbolicLinkReparseBuffer;
	struct {
	    USHORT SubstituteNameOffset;
	    USHORT SubstituteNameLength;
	    USHORT PrintNameOffset;
	    USHORT PrintNameLength;
	    WCHAR  PathBuffer[4];
	} MountPointReparseBuffer;
    };
} rb_w32_reparse_buffer_t;

#define rb_w32_reparse_buffer_size(n) \
    (sizeof(rb_w32_reparse_buffer_t) + \
     sizeof(WCHAR)*((n)-MINIMUM_REPARSE_BUFFER_PATH_LEN))

int rb_w32_read_reparse_point(const WCHAR *path, rb_w32_reparse_buffer_t *rp,
			      size_t bufsize, WCHAR **result, DWORD *len);

int lchown(const char *path, int owner, int group);
int rb_w32_ulchown(const char *path, int owner, int group);
int fchmod(int fd, int mode);
#define HAVE_FCHMOD 0

#endif	/* RUBY_WIN32_FILE_H */
