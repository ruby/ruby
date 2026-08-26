# Filesystem Modes

A filesystem entry has a _mode_ that specifies:

- [Permissions](#permissions).
- [Sticky bits](#sticky-bits).
- [File type](#file-type).

On this page, we use a [helper method](#helper-method) to display a mode
in a convenient form, showing the mode both as an octal integer and a string.

## Permissions

A filesystem entry has permissions:

- Read: whether the file or directory may be read, and by what processes.
- Write: whether the file of directory may be written, and by what processes.
- Execute/search:

    - File: whether the file may be _executed_, and by what processes.
    - Directory: whether the directory may be _searched_, and by what processes.

The permissions may be represented by an octal integer
whose trailing three digits show the permissions, respectively,
for the owner, the group, and world (meaning everyone else).

For a method that actually creates a file in the underlying filesystem
(as opposed to merely creating a File object), permissions may be specified;
the permissions may also be changed:

```ruby
filepath = '/tmp/t.tmp'
File.new(filepath, 'w', 0755)
mode(filepath) # => "100755 -rwxr-xr-x"
File.chmod(0644, filepath)
mode(filepath) # => "100644 -rw-r--r--"
```

For a method that actually creates a directory in the underlying filesystem
(as opposed to merely creating a Dir object), permissions may be specified;
the permissions may also be changed:

```ruby
dirpath = '/tmp/dir'
Dir.mkdir(dirpath, 0755)
mode(dirpath) # => "040755 drwxr-xr-x"
File.chmod(0644, dirpath)
mode(dirpath) # => "040644 drw-r--r--"
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

| Octal | \String       | Permissions                                     |
|:-----:|---------------|-------------------------------------------------|
| `000` | `'---------'` | No permissions.                                 |
| `400` | `'r--------'` | Owner read-only.                                |
| `600` | `'rw-------'` | Owner read-write.                               |
| `644` | `'rw-r--r--'` | Owner read-write; group/world read-only.        |
| `664` | `'rw-rw-r--'` | Owner/group read-write; world read-only.        |
| `777` | `'rw-rw-rw-'` | Owner/group/world read-write (generally avoid). |

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
|  `777`   | `'rwxrwxrwx'` | Owner/group/world read-write-execute (enerally avoid).       |

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
| `777`  | `'rwxrwxrwx'` | Owner/group/world read-write-search; generally avoid.     |

## Sticky Bits

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

## File Type

| Octal    | Character | File Type         |
|----------|:---------:|-------------------|
| `100000` |   `'-'`   | Regular file.     |
| `040000` |   `'d'`   | Directory.        |
| `120000` |   `'l'`   | Symbolic link.    |
| `020000` |   `'c'`   | Character device. |
| `060000` |   `'b'`   | Block device.     |
| `010000` |   `'p'`   | Pipe.             |
| `140000` |   `'s'`   | Socket.           |

## Helper Method

On this page, we use a helper method to show the mode information for a given path.

```ruby
# Return a string containing the mode (octal digits and character string)
# for the given path.
def mode(path)
  # Get mode digits from File.lstat.
  mode_digits = File.lstat(path).inspect.split(', ').select {|s| s.match('mode')}.first.split('=').last
  # Format to size.
  formatted_digits = "%06o" % mode_digits
  # Get mode characters from ls command.
  mode_characters = `ls -ld #{path}`.split(' ').first
  # Return both.
  "#{formatted_digits} #{mode_characters}"
end
```

Examples:

```ruby
mode('README.md') # => "0100664 -rw-rw-r--"
mode('/etc')      # => "0040755 drwxr-xr-x"
```

In a value returned by helper method `mode`, the permissions are expressed both in:

- The trailing three digits of the leading octal integer (e.g., `755`, `644`).

    - Third-from-left digit: owner permissions.
    - Second-from-left digit: group permissions.
    - Leftmost digit: world permissions.

- The trailing nine characters of the trailing string (e.g., `'rwxr-xr-x'`, `'rw-r--r--'`).

    - First three characters: owner permissions.
    - Middle three characters: group permissions.
    - Last three characters: world permissions.

