#if defined(__MINGW32__)
/* before stdio.h in ruby/define.h */
# define MINGW_HAS_SECURE_API 1
#endif
#include "ruby/ruby.h"
#include "ruby/encoding.h"
#include "internal.h"
#include "internal/error.h"
#include <winbase.h>
#include <wchar.h>
#include <shlwapi.h>
#include "win32/file.h"

#ifndef INVALID_FILE_ATTRIBUTES
# define INVALID_FILE_ATTRIBUTES ((DWORD)-1)
#endif

/* cache 'encoding name' => 'code page' into a hash */
static struct code_page_table {
    USHORT *table;
    unsigned int count;
} rb_code_page;

#define IS_DIR_SEPARATOR_P(c) (c == L'\\' || c == L'/')
#define IS_DIR_UNC_P(c) (IS_DIR_SEPARATOR_P(c[0]) && IS_DIR_SEPARATOR_P(c[1]))
static int
IS_ABSOLUTE_PATH_P(const WCHAR *path, size_t len)
{
    if (len < 2) return FALSE;
    if (ISALPHA(path[0]))
        return len > 2 && path[1] == L':' && IS_DIR_SEPARATOR_P(path[2]);
    else
        return IS_DIR_UNC_P(path);
}

/* MultiByteToWideChar() doesn't work with code page 51932 */
#define INVALID_CODE_PAGE 51932
#define PATH_BUFFER_SIZE MAX_PATH * 2

#define insecure_obj_p(obj, level) ((level) > 0 && OBJ_TAINTED(obj))

/* defined in win32/win32.c */
#define system_code_page rb_w32_filecp
#define mbstr_to_wstr rb_w32_mbstr_to_wstr
#define wstr_to_mbstr rb_w32_wstr_to_mbstr

static inline void
replace_wchar(wchar_t *s, int find, int replace)
{
    while (*s != 0) {
	if (*s == find)
	    *s = replace;
	s++;
    }
}

/* Remove trailing invalid ':$DATA' of the path. */
static inline size_t
remove_invalid_alternative_data(wchar_t *wfullpath, size_t size)
{
    static const wchar_t prime[] = L":$DATA";
    enum { prime_len = (sizeof(prime) / sizeof(wchar_t)) -1 };

    if (size <= prime_len || _wcsnicmp(wfullpath + size - prime_len, prime, prime_len) != 0)
	return size;

    /* alias of stream */
    /* get rid of a bug of x64 VC++ */
    if (wfullpath[size - (prime_len + 1)] == ':') {
	/* remove trailing '::$DATA' */
	size -= prime_len + 1; /* prime */
	wfullpath[size] = L'\0';
    }
    else {
	/* remove trailing ':$DATA' of paths like '/aa:a:$DATA' */
	wchar_t *pos = wfullpath + size - (prime_len + 1);
	while (!IS_DIR_SEPARATOR_P(*pos) && pos != wfullpath) {
	    if (*pos == L':') {
		size -= prime_len; /* alternative */
		wfullpath[size] = L'\0';
		break;
	    }
	    pos--;
	}
    }
    return size;
}

void rb_enc_foreach_name(int (*func)(st_data_t name, st_data_t idx, st_data_t arg), st_data_t arg);

static int
code_page_i(st_data_t name, st_data_t idx, st_data_t arg)
{
    const char *n = (const char *)name;
    if (strncmp("CP", n, 2) == 0) {
	int code_page = atoi(n + 2);
	if (code_page != 0) {
	    struct code_page_table *cp = (struct code_page_table *)arg;
	    unsigned int count = cp->count;
	    USHORT *table = cp->table;
	    if (count <= idx) {
		unsigned int i = count;
		count = (((idx + 4) & ~31) | 28);
		table = realloc(table, count * sizeof(*table));
		if (!table) return ST_CONTINUE;
		cp->count = count;
		cp->table = table;
		while (i < count) table[i++] = INVALID_CODE_PAGE;
	    }
	    table[idx] = (USHORT)code_page;
	}
    }
    return ST_CONTINUE;
}

/*
  Return code page number of the encoding.
  Cache code page into a hash for performance since finding the code page in
  Encoding#names is slow.
*/
static UINT
code_page(rb_encoding *enc)
{
    int enc_idx;

    if (!enc)
	return system_code_page();

    enc_idx = rb_enc_to_index(enc);

    /* map US-ASCII and ASCII-8bit as code page 1252 (us-ascii) */
    if (enc_idx == rb_usascii_encindex() || enc_idx == rb_ascii8bit_encindex()) {
	return 1252;
    }
    if (enc_idx == rb_utf8_encindex()) {
	return CP_UTF8;
    }

    if (0 <= enc_idx && (unsigned int)enc_idx < rb_code_page.count)
	return rb_code_page.table[enc_idx];

    return INVALID_CODE_PAGE;
}

#define fix_string_encoding(str, encoding) rb_str_conv_enc((str), (encoding), rb_utf8_encoding())

/*
  Replace the last part of the path to long name.
  We try to avoid to call FindFirstFileW() since it takes long time.
*/
static inline size_t
replace_to_long_name(wchar_t **wfullpath, size_t size, size_t buffer_size)
{
    WIN32_FIND_DATAW find_data;
    HANDLE find_handle;

    /*
      Skip long name conversion if the path is already long name.
      Short name is 8.3 format.
      https://en.wikipedia.org/wiki/8.3_filename
      This check can be skipped for directory components that have file
      extensions longer than 3 characters, or total lengths longer than
      12 characters.
      http://msdn.microsoft.com/en-us/library/windows/desktop/aa364980(v=vs.85).aspx
    */
    size_t const max_short_name_size = 8 + 1 + 3;
    size_t const max_extension_size = 3;
    size_t path_len = 1, extension_len = 0;
    wchar_t *pos = *wfullpath;

    if (size == 3 && pos[1] == L':' && pos[2] == L'\\' && pos[3] == L'\0') {
	/* root path doesn't need short name expansion */
	return size;
    }

    /* skip long name conversion if path contains wildcard characters */
    if (wcspbrk(pos, L"*?")) {
	return size;
    }

    pos = *wfullpath + size - 1;
    while (!IS_DIR_SEPARATOR_P(*pos) && pos != *wfullpath) {
	if (!extension_len && *pos == L'.') {
	    extension_len = path_len - 1;
	}
	if (path_len > max_short_name_size || extension_len > max_extension_size) {
	    return size;
	}
	path_len++;
	pos--;
    }

    if ((pos >= *wfullpath + 2) &&
        (*wfullpath)[0] == L'\\' && (*wfullpath)[1] == L'\\') {
        /* UNC path: no short file name, and needs Network Share
         * Management functions instead of FindFirstFile. */
        if (pos == *wfullpath + 2) {
            /* //host only */
            return size;
        }
        if (!wmemchr(*wfullpath + 2, L'\\', pos - *wfullpath - 2)) {
            /* //host/share only */
            return size;
        }
    }

    find_handle = FindFirstFileW(*wfullpath, &find_data);
    if (find_handle != INVALID_HANDLE_VALUE) {
	size_t trail_pos = pos - *wfullpath + IS_DIR_SEPARATOR_P(*pos);
	size_t file_len = wcslen(find_data.cFileName);
	size_t oldsize = size;

	FindClose(find_handle);
	size = trail_pos + file_len;
	if (size > (buffer_size ? buffer_size-1 : oldsize)) {
	    wchar_t *buf = ALLOC_N(wchar_t, (size + 1));
	    wcsncpy(buf, *wfullpath, trail_pos);
	    if (!buffer_size)
		xfree(*wfullpath);
	    *wfullpath = buf;
	}
	wcsncpy(*wfullpath + trail_pos, find_data.cFileName, file_len + 1);
    }
    return size;
}

static inline size_t
user_length_in_path(const wchar_t *wuser, size_t len)
{
    size_t i;

    for (i = 0; i < len && !IS_DIR_SEPARATOR_P(wuser[i]); i++)
	;

    return i;
}

static VALUE
append_wstr(VALUE dst, const WCHAR *ws, ssize_t len, UINT cp, rb_encoding *enc)
{
    long olen, nlen = (long)len;

    if (cp != INVALID_CODE_PAGE) {
	if (len == -1) len = lstrlenW(ws);
	nlen = WideCharToMultiByte(cp, 0, ws, len, NULL, 0, NULL, NULL);
	olen = RSTRING_LEN(dst);
	rb_str_modify_expand(dst, nlen);
	WideCharToMultiByte(cp, 0, ws, len, RSTRING_PTR(dst) + olen, nlen, NULL, NULL);
	rb_enc_associate(dst, enc);
	rb_str_set_len(dst, olen + nlen);
    }
    else {
	const int replaceflags = ECONV_UNDEF_REPLACE|ECONV_INVALID_REPLACE;
	char *utf8str = wstr_to_mbstr(CP_UTF8, ws, (int)len, &nlen);
	rb_econv_t *ec = rb_econv_open("UTF-8", rb_enc_name(enc), replaceflags);
	dst = rb_econv_append(ec, utf8str, nlen, dst, replaceflags);
	rb_econv_close(ec);
	free(utf8str);
    }
    return dst;
}

VALUE
rb_default_home_dir(VALUE result)
{
    WCHAR *dir = rb_w32_home_dir();
    if (!dir) {
	rb_raise(rb_eArgError, "couldn't find HOME environment -- expanding `~'");
    }
    append_wstr(result, dir, -1,
		       rb_w32_filecp(), rb_filesystem_encoding());
    xfree(dir);
    return result;
}

VALUE
rb_file_expand_path_internal(VALUE fname, VALUE dname, int abs_mode, int long_name, VALUE result)
{
    size_t size = 0, whome_len = 0;
    size_t buffer_len = 0;
    long wpath_len = 0, wdir_len = 0;
    wchar_t *wfullpath = NULL, *wpath = NULL, *wpath_pos = NULL;
    wchar_t *wdir = NULL, *wdir_pos = NULL;
    wchar_t *whome = NULL, *buffer = NULL, *buffer_pos = NULL;
    UINT path_cp, cp;
    VALUE path = fname, dir = dname;
    wchar_t wfullpath_buffer[PATH_BUFFER_SIZE];
    wchar_t path_drive = L'\0', dir_drive = L'\0';
    int ignore_dir = 0;
    rb_encoding *path_encoding;
    int tainted = 0;

    /* tainted if path is tainted */
    tainted = OBJ_TAINTED(path);

    /* get path encoding */
    if (NIL_P(dir)) {
	path_encoding = rb_enc_get(path);
    }
    else {
	path_encoding = rb_enc_check(path, dir);
    }

    cp = path_cp = code_page(path_encoding);

    /* workaround invalid codepage */
    if (path_cp == INVALID_CODE_PAGE) {
	cp = CP_UTF8;
	if (!NIL_P(path)) {
	    path = fix_string_encoding(path, path_encoding);
	}
    }

    /* convert char * to wchar_t */
    if (!NIL_P(path)) {
	const long path_len = RSTRING_LEN(path);
#if SIZEOF_INT < SIZEOF_LONG
	if ((long)(int)path_len != path_len) {
	    rb_raise(rb_eRangeError, "path (%ld bytes) is too long",
		     path_len);
	}
#endif
	wpath = mbstr_to_wstr(cp, RSTRING_PTR(path), path_len, &wpath_len);
	wpath_pos = wpath;
    }

    /* determine if we need the user's home directory */
    /* expand '~' only if NOT rb_file_absolute_path() where `abs_mode` is 1 */
    if (abs_mode == 0 && wpath_len > 0 && wpath_pos[0] == L'~' &&
	(wpath_len == 1 || IS_DIR_SEPARATOR_P(wpath_pos[1]))) {
	/* tainted if expanding '~' */
	tainted = 1;

	whome = rb_w32_home_dir();
	if (whome == NULL) {
	    free(wpath);
	    rb_raise(rb_eArgError, "couldn't find HOME environment -- expanding `~'");
	}
	whome_len = wcslen(whome);

	if (!IS_ABSOLUTE_PATH_P(whome, whome_len)) {
	    free(wpath);
	    xfree(whome);
	    rb_raise(rb_eArgError, "non-absolute home");
	}

	if (path_cp == INVALID_CODE_PAGE || rb_enc_str_asciionly_p(path)) {
	    /* use filesystem encoding if expanding home dir */
	    path_encoding = rb_filesystem_encoding();
	    cp = path_cp = system_code_page();
	}

	/* ignores dir since we are expanding home */
	ignore_dir = 1;

	/* exclude ~ from the result */
	wpath_pos++;
	wpath_len--;

	/* exclude separator if present */
	if (wpath_len && IS_DIR_SEPARATOR_P(wpath_pos[0])) {
	    wpath_pos++;
	    wpath_len--;
	}
    }
    else if (wpath_len >= 2 && wpath_pos[1] == L':') {
	if (wpath_len >= 3 && IS_DIR_SEPARATOR_P(wpath_pos[2])) {
	    /* ignore dir since path contains a drive letter and a root slash */
	    ignore_dir = 1;
	}
	else {
	    /* determine if we ignore dir or not later */
	    path_drive = wpath_pos[0];
	    wpath_pos += 2;
	    wpath_len -= 2;
	}
    }
    else if (abs_mode == 0 && wpath_len >= 2 && wpath_pos[0] == L'~') {
	result = rb_str_new_cstr("can't find user ");
	result = append_wstr(result, wpath_pos + 1, user_length_in_path(wpath_pos + 1, wpath_len - 1),
			     path_cp, path_encoding);

	if (wpath)
	    free(wpath);

	rb_exc_raise(rb_exc_new_str(rb_eArgError, result));
    }

    /* convert dir */
    if (!ignore_dir && !NIL_P(dir)) {
	/* fix string encoding */
	if (path_cp == INVALID_CODE_PAGE) {
	    dir = fix_string_encoding(dir, path_encoding);
	}

	/* convert char * to wchar_t */
	if (!NIL_P(dir)) {
	    const long dir_len = RSTRING_LEN(dir);
#if SIZEOF_INT < SIZEOF_LONG
	    if ((long)(int)dir_len != dir_len) {
		if (wpath) free(wpath);
		rb_raise(rb_eRangeError, "base directory (%ld bytes) is too long",
			 dir_len);
	    }
#endif
	    wdir = mbstr_to_wstr(cp, RSTRING_PTR(dir), dir_len, &wdir_len);
	    wdir_pos = wdir;
	}

	if (abs_mode == 0 && wdir_len > 0 && wdir_pos[0] == L'~' &&
	    (wdir_len == 1 || IS_DIR_SEPARATOR_P(wdir_pos[1]))) {
	    /* tainted if expanding '~' */
	    tainted = 1;

	    whome = rb_w32_home_dir();
	    if (whome == NULL) {
		free(wpath);
		free(wdir);
		rb_raise(rb_eArgError, "couldn't find HOME environment -- expanding `~'");
	    }
	    whome_len = wcslen(whome);

	    if (!IS_ABSOLUTE_PATH_P(whome, whome_len)) {
		free(wpath);
		free(wdir);
		xfree(whome);
		rb_raise(rb_eArgError, "non-absolute home");
	    }

	    /* exclude ~ from the result */
	    wdir_pos++;
	    wdir_len--;

	    /* exclude separator if present */
	    if (wdir_len && IS_DIR_SEPARATOR_P(wdir_pos[0])) {
		wdir_pos++;
		wdir_len--;
	    }
	}
	else if (wdir_len >= 2 && wdir[1] == L':') {
	    dir_drive = wdir[0];
	    if (wpath_len && IS_DIR_SEPARATOR_P(wpath_pos[0])) {
		wdir_len = 2;
	    }
	}
	else if (wdir_len >= 2 && IS_DIR_UNC_P(wdir)) {
	    /* UNC path */
	    if (wpath_len && IS_DIR_SEPARATOR_P(wpath_pos[0])) {
		/* cut the UNC path tail to '//host/share' */
		long separators = 0;
		long pos = 2;
		while (pos < wdir_len && separators < 2) {
		    if (IS_DIR_SEPARATOR_P(wdir[pos])) {
			separators++;
		    }
		    pos++;
		}
		if (separators == 2)
		    wdir_len = pos - 1;
	    }
	}
	else if (abs_mode == 0 && wdir_len >= 2 && wdir_pos[0] == L'~') {
	    result = rb_str_new_cstr("can't find user ");
	    result = append_wstr(result, wdir_pos + 1, user_length_in_path(wdir_pos + 1, wdir_len - 1),
				 path_cp, path_encoding);
	    if (wpath)
		free(wpath);

	    if (wdir)
		free(wdir);

	    rb_exc_raise(rb_exc_new_str(rb_eArgError, result));
	}
    }

    /* determine if we ignore dir or not */
    if (!ignore_dir && path_drive && dir_drive) {
	if (towupper(path_drive) != towupper(dir_drive)) {
	    /* ignore dir since path drive is different from dir drive */
	    ignore_dir = 1;
	    wdir_len = 0;
	    dir_drive = 0;
	}
    }

    if (!ignore_dir && wpath_len >= 2 && IS_DIR_UNC_P(wpath)) {
	/* ignore dir since path has UNC root */
	ignore_dir = 1;
	wdir_len = 0;
    }
    else if (!ignore_dir && wpath_len >= 1 && IS_DIR_SEPARATOR_P(wpath[0]) &&
	     !dir_drive && !(wdir_len >= 2 && IS_DIR_UNC_P(wdir))) {
	/* ignore dir since path has root slash and dir doesn't have drive or UNC root */
	ignore_dir = 1;
	wdir_len = 0;
    }

    buffer_len = wpath_len + 1 + wdir_len + 1 + whome_len + 1;

    buffer = buffer_pos = ALLOC_N(wchar_t, (buffer_len + 1));

    /* add home */
    if (whome_len) {
	wcsncpy(buffer_pos, whome, whome_len);
	buffer_pos += whome_len;
    }

    /* Add separator if required */
    if (whome_len && wcsrchr(L"\\/:", buffer_pos[-1]) == NULL) {
	buffer_pos[0] = L'\\';
	buffer_pos++;
    }
    else if (!dir_drive && path_drive) {
	*buffer_pos++ = path_drive;
	*buffer_pos++ = L':';
    }

    if (wdir_len) {
	/* tainted if dir is used and dir is tainted */
	if (!tainted && OBJ_TAINTED(dir))
	    tainted = 1;

	wcsncpy(buffer_pos, wdir_pos, wdir_len);
	buffer_pos += wdir_len;
    }

    /* add separator if required */
    if (wdir_len && wcsrchr(L"\\/:", buffer_pos[-1]) == NULL) {
	buffer_pos[0] = L'\\';
	buffer_pos++;
    }

    /* now deal with path */
    if (wpath_len) {
	wcsncpy(buffer_pos, wpath_pos, wpath_len);
	buffer_pos += wpath_len;
    }

    /* GetFullPathNameW requires at least "." to determine current directory */
    if (wpath_len == 0) {
	buffer_pos[0] = L'.';
	buffer_pos++;
    }

    /* Ensure buffer is NULL terminated */
    buffer_pos[0] = L'\0';

    /* tainted if path is relative */
    if (!tainted && !IS_ABSOLUTE_PATH_P(buffer, buffer_len))
	tainted = 1;

    /* FIXME: Make this more robust */
    /* Determine require buffer size */
    size = GetFullPathNameW(buffer, PATH_BUFFER_SIZE, wfullpath_buffer, NULL);
    if (size > PATH_BUFFER_SIZE) {
	/* allocate more memory than allotted originally by PATH_BUFFER_SIZE */
	wfullpath = ALLOC_N(wchar_t, size);
	size = GetFullPathNameW(buffer, size, wfullpath, NULL);
    }
    else {
	wfullpath = wfullpath_buffer;
    }

    /* Remove any trailing slashes */
    if (IS_DIR_SEPARATOR_P(wfullpath[size - 1]) &&
	wfullpath[size - 2] != L':' &&
	!(size == 2 && IS_DIR_UNC_P(wfullpath))) {
	size -= 1;
	wfullpath[size] = L'\0';
    }

    /* Remove any trailing dot */
    if (wfullpath[size - 1] == L'.') {
	size -= 1;
	wfullpath[size] = L'\0';
    }

    /* removes trailing invalid ':$DATA' */
    size = remove_invalid_alternative_data(wfullpath, size);

    /* Replace the trailing path to long name */
    if (long_name) {
	size_t bufsize = wfullpath == wfullpath_buffer ? PATH_BUFFER_SIZE : 0;
	size = replace_to_long_name(&wfullpath, size, bufsize);
    }

    /* sanitize backslashes with forwardslashes */
    replace_wchar(wfullpath, L'\\', L'/');

    /* convert to VALUE and set the path encoding */
    rb_str_set_len(result, 0);
    result = append_wstr(result, wfullpath, size, path_cp, path_encoding);

    /* makes the result object tainted if expanding tainted strings or returning modified path */
    if (tainted)
	OBJ_TAINT(result);

    /* TODO: better cleanup */
    if (buffer)
	xfree(buffer);

    if (wpath)
	free(wpath);

    if (wdir)
	free(wdir);

    if (whome)
	xfree(whome);

    if (wfullpath != wfullpath_buffer)
	xfree(wfullpath);

    rb_enc_associate(result, path_encoding);
    return result;
}

VALUE
rb_readlink(VALUE path, rb_encoding *resultenc)
{
    DWORD len;
    VALUE wtmp = 0, wpathbuf, str;
    rb_w32_reparse_buffer_t rbuf, *rp = &rbuf;
    WCHAR *wpath, *wbuf;
    rb_encoding *enc;
    UINT cp, path_cp;
    int e;

    FilePathValue(path);
    enc = rb_enc_get(path);
    cp = path_cp = code_page(enc);
    if (cp == INVALID_CODE_PAGE) {
	path = fix_string_encoding(path, enc);
	cp = CP_UTF8;
    }
    len = MultiByteToWideChar(cp, 0, RSTRING_PTR(path), RSTRING_LEN(path), NULL, 0);
    wpath = ALLOCV_N(WCHAR, wpathbuf, len+1);
    MultiByteToWideChar(cp, 0, RSTRING_PTR(path), RSTRING_LEN(path), wpath, len);
    wpath[len] = L'\0';
    e = rb_w32_read_reparse_point(wpath, rp, sizeof(rbuf), &wbuf, &len);
    if (e == ERROR_MORE_DATA) {
	size_t size = rb_w32_reparse_buffer_size(len + 1);
	rp = ALLOCV(wtmp, size);
	e = rb_w32_read_reparse_point(wpath, rp, size, &wbuf, &len);
    }
    ALLOCV_END(wpathbuf);
    if (e) {
	ALLOCV_END(wtmp);
	if (e != -1)
	    rb_syserr_fail_path(rb_w32_map_errno(e), path);
	else /* not symlink; maybe volume mount point */
	    rb_syserr_fail_path(EINVAL, path);
    }
    enc = resultenc;
    path_cp = code_page(enc);
    len = lstrlenW(wbuf);
    str = append_wstr(rb_enc_str_new(0, 0, enc), wbuf, len, path_cp, enc);
    ALLOCV_END(wtmp);
    return str;
}

int
rb_file_load_ok(const char *path)
{
    DWORD attr;
    int ret = 1;
    long len;
    wchar_t* wpath;

    wpath = mbstr_to_wstr(CP_UTF8, path, -1, &len);
    if (!wpath) return 0;

    attr = GetFileAttributesW(wpath);
    if (attr == INVALID_FILE_ATTRIBUTES ||
	(attr & FILE_ATTRIBUTE_DIRECTORY)) {
	ret = 0;
    }
    else {
	HANDLE h = CreateFileW(wpath, GENERIC_READ,
			       FILE_SHARE_READ | FILE_SHARE_WRITE,
			       NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	if (h != INVALID_HANDLE_VALUE) {
	    CloseHandle(h);
	}
	else {
	    ret = 0;
	}
    }
    free(wpath);
    return ret;
}

int
rb_freopen(VALUE fname, const char *mode, FILE *file)
{
    WCHAR *wname, wmode[4];
    VALUE wtmp;
    char *name;
    long len;
    int e = 0, n = MultiByteToWideChar(CP_ACP, 0, mode, -1, NULL, 0);
    if (n > numberof(wmode)) return EINVAL;
    MultiByteToWideChar(CP_ACP, 0, mode, -1, wmode, numberof(wmode));
    RSTRING_GETMEM(fname, name, len);
    n = rb_long2int(len);
    len = MultiByteToWideChar(CP_UTF8, 0, name, n, NULL, 0);
    wname = ALLOCV_N(WCHAR, wtmp, len + 1);
    len = MultiByteToWideChar(CP_UTF8, 0, name, n, wname, len);
    wname[len] = L'\0';
    RB_GC_GUARD(fname);
#if RUBY_MSVCRT_VERSION < 80 && !defined(HAVE__WFREOPEN_S)
    e = _wfreopen(wname, wmode, file) ? 0 : errno;
#else
    {
	FILE *newfp = 0;
	e = _wfreopen_s(&newfp, wname, wmode, file);
    }
#endif
    ALLOCV_END(wtmp);
    return e;
}

void
Init_w32_codepage(void)
{
    if (rb_code_page.count) return;
    rb_enc_foreach_name(code_page_i, (st_data_t)&rb_code_page);
}
