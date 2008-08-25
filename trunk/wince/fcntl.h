
#ifndef FCNTL_H
#define FCNTL_H 1


#define F_SETFL         1
#define F_SETFD         2
#define F_GETFL         3

#define _O_RDONLY       0x0000  /* open for reading only */
#define _O_WRONLY       0x0001  /* open for writing only */
#define _O_RDWR         0x0002  /* open for reading and writing */

#define _O_NONBLOCK     0x0004

#define _O_APPEND       0x0008  /* writes done at eof */
#define _O_CREAT        0x0100  /* create and open file */
#define _O_TRUNC        0x0200  /* open and truncate */
#define _O_EXCL         0x0400  /* open only if file doesn't already exist */
#define _O_TEXT         0x4000  /* file mode is text (translated) */
#define _O_BINARY       0x8000  /* file mode is binary (untranslated) */
#define _O_ACCMODE      0x10000

#define _O_NOINHERIT    0
#define O_NOINHERIT     _O_NOINHERIT

#define O_RDONLY        _O_RDONLY
#define O_WRONLY        _O_WRONLY
#define O_RDWR          _O_RDWR

#define O_NONBLOCK      _O_NONBLOCK

#define O_APPEND        _O_APPEND
#define O_CREAT         _O_CREAT
#define O_TRUNC         _O_TRUNC
#define O_EXCL          _O_EXCL
#define O_TEXT          _O_TEXT
#define O_BINARY        _O_BINARY
#define O_ACCMODE       _O_ACCMODE


#endif
