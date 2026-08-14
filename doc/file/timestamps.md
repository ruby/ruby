# \Filesystem Timestamps

A filesystem entry (the name of a file or directory)
has several associated times, called timestamps.

A Ruby method that returns a filesystem timestamp (as a Time object)
is actually returning "whatever the filesystem says";
the returned times may vary among filesystems, even on the same machine.

Each of these methods returns a Time object:

|               Name               | Meaning                                | Changes                               |
|:--------------------------------:|----------------------------------------|---------------------------------------|
|    [`birthtime`](#birth-time)    | Create time.                           | Never.                                |
|  [`mtime`](#modification-time)   | Modification time.                     | When written; see Note 1.             |
|     [`atime`](#access-time)      | Access time.                           | When read; see Note 2.                |
| [`ctime`](#metadata-change-time) | Metadata-change time (or create time). | See [`ctime`](#metadata-change-time). |

Notes:

1. Modification time update may be delayed by the filesystem.
2. Access time may occur immediately, later, or never, depending on filesystem settings.

Each of these methods updates the access time and modification time for an entry:

- File::utime, Pathname#utime: follow symbolic links.
- File::lutime, Pathname#lutime: do not follow symbolic links.

## \File Timestamps

|     Operation      |  Affects<br>birthtime  | Affects<br>ctime | Affects<br>mtime |      Affects<br>atime      |
|:------------------:|:------------------:|:----------------:|:----------------:|:--------------------------:|
|       Create       |      **Yes**       |     **Yes**      |     **Yes**      |          **Yes**           |
|   Write content    |         No         |        No        |       **Yes**    |             No             |
|    Read content    |         No         |        No        |        No        | *Filesystem-<br>dependent* |
|      Rename/Move   |         No         |     **Yes**      |        No        |             No             |
| Change permissions |         No         |     **Yes**      |        No        |             No             |
|  Change ownership  |         No         |     **Yes**      |        No        |             No             |


## Directory Timestamps

|     Operation      | Affects<br>birthtime | Affects<br>ctime | Affects<br>mtime |      Affects<br>atime      |
|:------------------:|:----------------:|:----------------:|:----------------:|:--------------------------:|
|       Create       |     **Yes**      |     **Yes**      |   **Yes**        |          **Yes**           |
|   Write entries    |        No        |        No        |     **Yes**      |             No             |
|    Read entries    |        No        |        No        |        No        | *Filesystem-<br>dependent* |
|     Rename/Move    |        No        |     **Yes**      |        No        |             No             |
| Change permissions |        No        |     **Yes**      |        No        |             No             |
|  Change ownership  |        No        |     **Yes**      |        No        |             No             |




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
though some filesystems may delay the update.

Each of these methods returns the modification time for an entry as a Time object:

- File::mtime.
- File#mtime.
- File::Stat#mtime.
- Pathname#mtime.

The modification time (along with the access time) may also be updated explicitly:

- File::lutime.
- File::utime.
- Pathname#lutime.
- Pathname#utime.

## Access \Time

The access time for an entry is the time of the most recent read for the entry,
as reported by the underlying filesystem.

Depending on a filesystem's settings, reading an entry may cause the access time
to be updated immediately, later, or never.

The access time for a file is commonly the most recent time the file was read,
or if never read, the time it was created.

The access time for a directory is commonly the most recent time its entries were read,
or if never read, the time it was created.

Each of these methods returns the access time for an entry as a Time object:

- File::atime.
- File#atime.
- File::Stat#atime.
- Pathname#atime.

The access time (along with the modification time) may also be updated explicitly:

- File::lutime.
- File::utime.
- Pathname#lutime.
- Pathname#utime.

## Metadata-Change \Time

The metadata-change time for an entry is the time the entry last read.
The metadata-change time is updated when the entry's metadata is changed;
changing access mode or permissions may update the metadata-change time,
though some filesystems may delay the update.

On non-Windows systems,
each of these methods returns the metadata-change time for an entry:

- File::ctime.
- File#ctime.
- File::Stat#ctime.
- Pathname#ctime.

On Windows, each `ctime` method returns the birth time,
not the metadata-change time.
