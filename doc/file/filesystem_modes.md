# Filesystem Modes

A filesystem entry has an integer _mode_ that specifies:

- [Permissions][permissions].
- [Special bits][special bits].
- [File type][file type].

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
File.stat('README.md').mode.to_s(8) # => "100664"
File.stat('doc/').mode.to_s(8)      # => "40775"
```

On this page, we use a helper method to display a mode
in a convenient form, showing the mode both as an octal integer and a string.
If you're new to this page, it may be helpful
to read about the [helper method][helper method] now.

## Setting a Mode

The mode for an entry is initialized when the entry is created:

```ruby
filepath = '/tmp/t.txt'
File.write(filepath, 'foo')
mode(filepath) # => "100664 -rw-rw-r--"
dirpath = '/tmp/bar'
Dir.mkdir(dirpath)
mode(dirpath)  # => "040775 drwxrwxr-x"
File.unlink(filepath)
Dir.rmdir(dirpath)
```

You can use one of these methods to change the [permissions][permissions]
and [special bits][special bits] (but not the [file type][file type]):

- File::chmod.
- FileUtils::chmod.
- FileUtils::chmod_R.
- File#chmod.
- Pathname#chmod.
- FileUtils#chmod.
- FileUtils#chmod_R.

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

Examples:

```ruby
File.write(filepath, '')
File.chmod(00644, filepath)
mode(filepath) # => "100644 -rw-r--r--"  # No special bits set.
File.chmod(01644, filepath)
mode(filepath) # => "101644 -rw-r--r-T"  # 'T' shows that sticky bit is set.
File.chmod(02644, filepath)
mode(filepath) # => "102644 -rw-r-Sr--"  # 'S' shows that setuid bit is set.
File.chmod(04644, filepath)
mode(filepath) # => "104644 -rwSr--r--"  # 'S' shows that setgid bit is set.
File.chmod(07644, filepath)
mode(filepath) # => "107644 -rwSr-Sr-T"  # All set.
```

In each case, if the execute bit is also set,
lowercase letters `'t'` and `'s'` are displayed instead of uppercase `'T'` and `'S'`:

```ruby
File.chmod(00755, filepath)
mode(filepath) # => "100755 -rwxr-xr-x"
File.chmod(01755, filepath)
mode(filepath) # => "101755 -rwxr-xr-t"
File.chmod(02755, filepath)
mode(filepath) # => "102755 -rwxr-sr-x"
File.chmod(04755, filepath)
mode(filepath) # => "104755 -rwsr-xr-x"
File.chmod(07755, filepath)
mode(filepath) # => "107755 -rwsr-sr-t"
```

## \File Type

The fifth and sixth octal digits in a mode represent a file type:

| Octal    | Character | \File Type        |
|----------|:---------:|-------------------|
| `010000` |   `'p'`   | Pipe.             |
| `020000` |   `'c'`   | Character device. |
| `040000` |   `'d'`   | Directory.        |
| `060000` |   `'b'`   | Block device.     |
| `100000` |   `'-'`   | Regular file.     |
| `120000` |   `'l'`   | Symbolic link.    |
| `140000` |   `'s'`   | \Socket.          |

Examples:

```ruby
File.mkfifo('/tmp/pipe', 0666)
mode('/tmp/pipe')   # => "010664 prw-rw-r--"  # 01; pipe.
mode('/dev/tty')    # => "020666 crw-rw-rw-"  # 02; character device.
mode('doc/')        # => "040775 drwxrwxr-x"  # 04; directory.
mode('/dev/loop0')  # => "060660 brw-rw----"  # 06; block device.
mode('README.md')   # => "100664 -rw-rw-r--"  # 10; regular file.
File.symlink('lib', '/tmp/link')
mode('/tmp/link')   # => "120777 lrwxrwxrwx"  # 12; symbolic link.
require 'socket'
UNIXServer.new('/tmp/socket')
mode('/tmp/socket') # => "140775 srwxrwxr-x"  # 14; socket.
File.unlink('/tmp/pipe', '/tmp/link' ,'/tmp/socket')
```

## Helper Method

On this page, we use a helper method, `mode`, to show the mode information for a given path:

```ruby
mode('README.md') # => "0100664 -rw-rw-r--"
mode('/etc')      # => "0040755 drwxr-xr-x"
```

The [permissions][permissions] are expressed both in:

- The trailing three digits of the octal value (e.g., `755`, `644`).

    - Left digit: owner permissions.
    - Middle digit: group permissions.
    - Right digit: world permissions.

- The trailing nine characters of the string string value
  (e.g., `'rwxr-xr-x'`, `'rw-r--r--'`).

    - Left three characters: owner permissions.
    - Middle three characters: group permissions.
    - Right three characters: world permissions.

The [special bits][special bits] are expressed in the fourth digit.

The [file type][file type] is expressed the fifth and sixth digits.

For the code-curious:

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

[permissions]:   #permissions
[special bits]:  #special-bits
[file type]:     #file-type
[helper method]: #helper-method

[sticky bit]: https://en.wikipedia.org/wiki/Sticky_bit
[setuid bit]: https://en.wikipedia.org/wiki/Setuid
[setgid bit]: https://en.wikipedia.org/wiki/Setuid
