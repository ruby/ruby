# Filesystem Modes

A filesystem entry has an integer _mode_ that specifies:

- [Permissions][permissions].
- [Special bits][special bits].
- [File type][file type].

The mode is most often seen as an octal-format integer:

- Rightmost three digits encode the permissions.
- Next digit encodes the special bits.
- Leftmost two digits encode the file type.

On this page, we show each mode with format `'%06o`,
which displays the mode as a 6-digit octal number.

## Getting a Mode

You can use method File::Stat#mode to get the mode of a filesystem entry.

Each of these methods returns a File::Stat object for a given filesystem entry.
The first three follow symbolic links; the others don't:

- File::stat.
- IO#stat.
- Pathname#stat.
- File::lstat.
- File#lstat.
- Pathname#lstat.

Once you have the File::Stat object, you can fetch the mode for the entry:

```ruby
'%06o' % File.stat('/etc').mode        # => "040755"
'%06o' % File.stat('/etc/passwd').mode # => "100644"
```

## Setting a Mode

The mode for an entry is initialized when the entry is created:

```ruby
filepath = '/tmp/t.txt'
File.write(filepath, 'foo')
'%06o' % File.stat(filepath).mode # => "100664"
File.delete(filepath)             # Clean up.
dirpath = '/tmp/bar'
Dir.mkdir(dirpath)
'%06o' % File.stat(dirpath).mode  # => "040775"
Dir.rmdir(dirpath)                # Clean up.
```

You can use one of these methods to change the [permissions][permissions]
and [special bits][special bits] (but not the [file type][file type]):

- File#chmod.
- File::chmod.
- File::lchmod (does not follow symbolic links).
- FileUtils#chmod.
- FileUtils#chmod_R.
- FileUtils::chmod.
- FileUtils::chmod_R.
- Pathname#chmod.
- Pathname#lchmod (does not follow symbolic links).

The actual effects of these methods is filesystem-dependent.

## Permissions

A filesystem entry has permissions:

- Read: whether the file or directory may be read, and by what processes.
- Write: whether the file of directory may be written, and by what processes.
- Execute/search:

    - File: whether the file may be _executed_, and by what processes.
    - Directory: whether the directory may be _searched_, and by what processes.

For a method that actually creates a file in the underlying filesystem
(as opposed to merely creating a File object), permissions may be specified;
the permissions may also be changed:

```ruby
filepath = '/tmp/t.tmp'
File.write(filepath, 'foo')
'%06o' % File.stat(filepath).mode # => "100664"
File.chmod(0o775, filepath)
'%06o' % File.stat(filepath).mode # => "100775"
File.delete(filepath)             # Clean up.
```

For a method that actually creates a directory in the underlying filesystem
(as opposed to merely creating a Dir object), permissions may be specified;
the permissions may also be changed:

```ruby
dirpath = '/tmp/dir'
Dir.mkdir(dirpath)
'%06o' % File.stat(dirpath).mode # => "040775"
File.chmod(0o644, dirpath)
'%06o' % File.stat(dirpath).mode # => "040644"
Dir.rmdir(dirpath)               # Clean up.
```

On non-Posix operating systems, permissions may include only read-only or read-write,
in which case, the remaining permission will resemble typical values.
On Windows, for instance, the default permissions are `0644`;
The only change that can be made is to make the file
read-only, which is reported as `0444`.

### Directory and \File Permissions

Permissions for directories and files include read and write permissions.

The permissions in this table do not involve execute/search,
and so apply similarly to a directory or a file.

| Octal | \String       | Permissions                              |
|:-----:|---------------|------------------------------------------|
| `000` | `'---------'` | No permissions.                          |
| `400` | `'r--------'` | Owner read-only.                         |
| `600` | `'rw-------'` | Owner read-write.                        |
| `644` | `'rw-r--r--'` | Owner read-write; group/world read-only. |
| `664` | `'rw-rw-r--'` | Owner/group read-write; world read-only. |
| `666` | `'rw-rw-rw-'` | Owner/group/world read-write.            |

### \File Permissions

Permissions for a file include execute permissions,
in addition to the read and write permissions seen above.

The permissions in this table, applied to a file, specify execute permissions.

| Octal    | \String       | Permissions                                                  |
|:--------:|---------------|--------------------------------------------------------------|
|  `700`   | `'rwx------'` | Owner read-write-execute.                                    |
|  `750`   | `'rwxr-x---'` | Owner read-write-execute; group read-execute.                |
|  `755`   | `'rwxr-xr-x'` | Owner read-write-execute; group read-execute; world execute. |
|  `775`   | `'rwxrwxr-x'` | Owner/group read-write-execute; world read-execute.          |
|  `777`   | `'rwxrwxrwx'` | Owner/group/world read-write-execute.                        |

### Directory Permissions

Permissions for a directory include search permissions,
in addition to the read and write permissions seen above.

The permissions in this table, applied to a directory, specify search permissions.

| Octal  | \String       | Permissions                                               |
|:------:|---------------|-----------------------------------------------------------|
| `700`  | `'rwx------'` | Owner read-write-search.                                  |
| `750`  | `'rwxr-x---'` | Owner read-write-search; group read-search.               |
| `755`  | `'rwxr-xr-x'` | Owner read-write-search; group read-search; world search. |
| `775`  | `'rwxrwxr-x'` | Owner/group read-write-search; world read-search.         |
| `777`  | `'rwxrwxrwx'` | Owner/group/world read-write-search.                      |

## Special Bits

The fourth octal digit in a mode represents its special bits:

- Its low-order bit (`1000`) shows whether the [sticky bit][sticky bit]  is set.
- The next bit (`2000`) shows whether the [setuid bit][setuid bit] is set.
- The next bit (`4000`) shows whether the [setgid bit][setgid bit] is set.

| Octal   | Meaning                   |
|:-------:|---------------------------|
| `0000`  | None.                     |
| `1000`  | Sticky.                   |
| `2000`  | Setgid.                   |
| `3000`  | Setgid + sticky.          |
| `4000`  | Setuid.                   |
| `5000`  | Setuid + sticky.          |
| `6000`  | Setuid + setgid.          |
| `7000`  | Setuid + setgid + sticky. |

Examples (note value in special-bits digit -- fourth-from-left):

```ruby
filepath = '/tmp/t.tmp'
File.write(filepath, 'foo')
'%06o' % File.stat(filepath).mode # => "100664"  # No special bits set.
File.chmod(0o1644, filepath)
'%06o' % File.stat(filepath).mode # => "101644"  # Sticky bit set.
File.chmod(0o2644, filepath)
'%06o' % File.stat(filepath).mode # => "102644"  # Setgid bit set.
File.chmod(0o4644, filepath)
'%06o' % File.stat(filepath).mode # => "104644"  # Setuid bit set.
File.chmod(0o7644, filepath)
'%06o' % File.stat(filepath).mode # => "107644"  # All special bits set.
File.delete(filepath)             # Clean up.
```

## \File Type

The fifth and sixth octal digits in a mode represent the file type:

| Octal    | \File Type        |
|----------|-------------------|
| `010000` | Pipe.             |
| `020000` | Character device. |
| `040000` | Directory.        |
| `060000` | Block device.     |
| `100000` | Regular file.     |
| `120000` | Symbolic link.    |
| `140000` | \Socket.          |

Set up a path for each file type:

```ruby
pipe_path =              '/tmp/pipe'
character_special_path = '/dev/tty'
dir_path =               '/tmp'
block_special_path =     '/dev/loop0'
file_path =              '/etc/passwd'
link_path =              '/tmp/link'
socket_path =            '/tmp/socket'
```

These entries we have to create:

```ruby
File.symlink(file_path, link_path)
File.mkfifo(pipe_path, 0666)
require 'socket'
UNIXServer.new(socket_path)
```

Show the modes (note the leftmost two digits):

```ruby
'%06o' % File.stat(pipe_path).mode              # => "010664"
'%06o' % File.stat(character_special_path).mode # => "020666"
'%06o' % File.stat(dir_path).mode               # => "041777"
'%06o' % File.stat(block_special_path).mode     # => "060660"
'%06o' % File.stat(file_path).mode              # => "100644"
'%06o' % File.stat(link_path).mode              # => "100644"
'%06o' % File.stat(socket_path).mode            # => "140775"
File.delete(link_path, socket_path, pipe_path)  # Clean up.
```

[permissions]:   #permissions
[special bits]:  #special-bits
[file type]:     #file-type
[helper method]: #helper-method

[sticky bit]: https://en.wikipedia.org/wiki/Sticky_bit
[setuid bit]: https://en.wikipedia.org/wiki/Setuid
[setgid bit]: https://en.wikipedia.org/wiki/Setuid
