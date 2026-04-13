# \File System Timestamps

A file system entry (the name of a file or directory)
has several times (called timestamps) associated with it.

The Ruby methods that return these timestamps (each as a Time object)
are actually returning "whatever the OS says,"
and so their behaviors may vary among OS platforms.
If a platform does not support a particular timestamp,
the corresponding Ruby methods raise NotImplementedError.

These timestamps are:

|               Name               | Meaning                                | Changes               |
|:--------------------------------:|----------------------------------------|-----------------------|
|  [`birthtime`](#birth-time)      | Create time.                           | Never.                |
|  [`mtime`](#modification-time)   | Modification time.                     | When written.         |
|     [`atime`](#access-time)      | Access time.                           | When read or written. |
| [`ctime`](#metadata-change-time) | Metadata-change time (or create time). | See below.            |

## Birth \Time

The birth time for an entry is the time the entry was created.
The birth time does not change, although if the entry is deleted and re-created,
the birth time will be different.

Each of these methods returns the birth time for an entry as a Time object:

- File::birthtime.
- File#birthtime.
- File::Stat#birthtime.
- Pathname#birthtime.

On Windows, each of these methods also returns the birth time:

- File::ctime.
- File#ctime.
- File::Stat#ctime.
- Pathname#ctime.

## Modification \Time

The modification time for an entry is the time the entry was last modified.
The modification time is updated when the entry is written,
though some file systems may delay the update.

Each of these methods returns the modification time for an entry as a Time object:

- File::mtime.
- File#mtime.
- File::Stat#mtime.
- Pathname#mtime.

## Access \Time

The access time for an entry is the time the entry last read.
The access time is updated when the entry is read,
though some file systems may delay the update.

Each of these methods returns the access time for an entry as a Time object:

- File::atime.
- File#atime.
- File::Stat#atime.
- Pathname#atime.

## Metadata-Change \Time

The metadata-change time for an entry is the time the entry last read.
The metadata-change time is updated when the entry's metadata is changed;
changing access mode or permissions may update the metadata-change time,
though some file systems may delay the update.

On non-Windows systems,
each of these methods returns the metadata-change time for an entry:

- File::ctime.
- File#ctime.
- File::Stat#ctime.
- Pathname#ctime.

On Windows, each `ctime` method returns the birth time,
not the metadata-change time.
