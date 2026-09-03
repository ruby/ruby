# Symbolic Links

A [symbolic link][symbolic link] (sometimes called a _symlink_ or _soft link_)
is a filesystem entry that stores a filesystem path.
The stored path refers to a _target_ filesystem entry, which may or may not exist.
Further, the stored path need not even be a valid path.

## Methods That Follow Symlinks

Most Ruby methods that deal with filesystem paths "follow" symbolic links;
that is, if the path refers to a symlink, the method does not operate on the entry
at that path, but instead operates on the path stored in the symlink:

```ruby
File.symlink('README.md', 'foo')
File.read('foo').size # => 3463  # Size of README.md, not foo.
File.delete('foo')
```

## Creating Symlinks

Each of these methods creates a symlink:

- File::symlink
- FileUtils::ln_s
- Pathname#make_symlink

If the target path is itself a symlink, that symlink is not followed.

Examples:

```ruby
# Symlink for a file.
File.symlink('README.md', 'foo')
# Symlink for another symlink.
File.symlink('foo', 'bar')
File.read('README.md').size      # => 3463
File.read('foo').size            # => 3463
File.read('bar').size            # => 3463
# Symlink for a directory.
File.symlink('doc/', 'baz')
Dir.entries('doc/').size         # => 33
Dir.entries('baz').size          # => 33
File.unlink('foo', 'bar', 'baz') # Clean up.
```

## Querying Symlinks

### `lstat`

Each of these methods creates a File::Stat object for a filesystem entry:

- File::lstat
- Pathname#lstat

The object contains information for the entry at the given path,
even if that entry is a symlink;
i.e., symlinks are not followed.

By contrast, each of the methods File::stat and Pathname#stat
_do_ follow symlinks.

Examples:

```ruby
linkpath = 'foo'
File.symlink('README.md', linkpath)
File::stat(linkpath).size  # => 3469  # Size of file README.md.
File::lstat(linkpath).size # => 9     # Size of symlink linkpath.
File.unlink(linkpath)      # Clean up.
```

### `symlink?`

Each of these methods returns whether the entry at a given path is a symlink:

- File::symlink?
- File::Stat#symlink?
- Pathname#symlink?

If the entry is a symlink, it is not followed.

Examples:

```ruby
linkpath = 'foo'
File.symlink('README.md', 'foo')
File.symlink?(linkpath)    # => true
File.symlink?('README.md') # => false
File.symlink?('nosuch')    # => false
File.delete(linkpath)      # Clean up.
```

### `readlink`

Each of these methods returns the path stored in a symlink:

- File::readlink
- Pathname#readlink

Examples:

```ruby
linkpath = 'foo'
File.symlink('README.md', 'foo')
File.readlink(linkpath)     # => "README.md"
File.delete(linkpath)       # Clean up.
```

## Modifying Symlinks

### `lchmod`

Each of these methods changes the mode of the symlink entry:

- File::lchmod
- Pathname#lchmod

These methods are not supported on Windows or Linux (raise Errno::ENOTSUP).

### `lchown`

Each of these methods changes the ownership of a symlink entry:

- File::lchown
- Pathname#lchown

Example:

```ruby
# Super user; all privileges.
Process.uid # => 0
Process.gid # => 0
# Create regular file and symlink to it.
filepath = 't.tmp'
linkpath = 'foo'
File.write(filepath, '')
File.symlink(filepath, linkpath)
# Capture original statuses.
fstat0 = File.stat(filepath)
lstat0 = File.lstat(linkpath)
fstat0.uid # => 0
fstat0.gid # => 0
lstat0.uid # => 0
lstat0.gid # => 0
# Change owner for the symlink.
File.lchown(1000, 1000, linkpath)
# Capture new statuses.
fstat1 = File.stat(filepath)
lstat1 = File.lstat(linkpath)
# User id and group id for file not changed.
fstat1.uid # => 0
fstat1.gid # => 0
# User is and group id for link changed.
lstat1.uid # => 1000
lstat1.gid # => 1000
# Clean up.
File.delete(filepath, linkpath)
```

### `lutime`

Each of these methods updates timestamps for a symlink entry:

- File::lutime
- Pathname#lutime

Example:

```ruby
filepath = 'README.md'
linkpath = 'foo'
File.symlink(filepath, linkpath)
# Take snapshots of both.
fstat0 = File.stat(filepath)
lstat0 = File.lstat(linkpath)
# Fetch access times and modification times of both.
fstat0.atime    # => 2026-09-03 07:46:04.940377552 -0500
fstat0.mtime    # => 2026-09-01 09:09:28.378987388 -0500
lstat0.atime    # => 2026-09-03 09:14:13.753865727 -0500
lstat0.mtime    # => 2026-09-03 09:14:13.753865727 -0500
# Update access time and modification time of the symlink.
time = Time.now # => 2026-09-03 09:16:42.619702232 -0500
File.lutime(time, time, linkpath)
# Take fresh snapshots of both.
fstat1 = File.stat(filepath)
lstat1 = File.lstat(linkpath)
# Fetch access time and modification time of file (not changed).
fstat1.atime    # => 2026-09-03 07:46:04.940377552 -0500
fstat1.mtime    # => 2026-09-01 09:09:28.378987388 -0500
# Fetch access time and modification time of link (changed).
lstat1.atime    # => 2026-09-03 09:16:52.77029217 -0500
lstat1.mtime    # => 2026-09-03 09:16:42.619702232 -0500
# Clean up.
File.delete(linkpath)
```

### `rename`

Each of these methods changes the name of an entry (which need not be a symlink):

- File::rename
- Pathname#rename

Examples:

```ruby
File.symlink('README.md', 'foo')
File.rename('foo', 'bar')
File.symlink?('bar') # => true
File.rename('bar', 'baz')
File.symlink?('baz') # => true
File.delete('baz')   # Clean up.
```

## Removing Symlinks

### `unlink`

Each of these methods removes an entry (which need not be a symlink):

- File::delete
- File::unlink
- Pathname#unlink (aliased as Pathname#delete)

Example:

```ruby
linkpath = 'foo'
File.symlink('README.md', linkpath)
File.unlink(linkpath)
```

## Methods That Don't Follow Symlinks

Sometimes it's necessary to query, modify, or delete a symlink;
therefore certain Ruby methods do not follow symlinks,
but instead operate directly on the symlinks.

### Symlink-Specific Methods

Each method in the table below has a symlink-specific purpose.

| Method Name           | Effect                                              |
|-----------------------|-----------------------------------------------------|
| File::Stat#symlink?   | Returns whether a path is a symlink.                |
| File::lchmod          | Changes the mode of the symlink. See Note 1.        |
| File::lchown          | Changes the ownership of the symlink. See Note 2.   |
| File::lstat           | Creates a File::Stat object for a link. See Note 3. |
| File::lutime          | Updates timestamps for the symlink. See Note 4.     |
| File::readlink        | Returns the path stored in a symlink.               |
| File::symlink         | Creates a symlink.                                  |
| File::symlink?        | Returns whether a path is a symlink.                |
| FileUtils::ln_s       | Creates a symlink.                                  |
| FileUtils::ln_sf      | Creates a symlink.                                  |
| FileUtils::ln_sr      | Creates a symlink.                                  |
| Pathname#lchmod       | Changes the mode of the symlink. See Note 1.        |
| Pathname#lchown       | Changes the ownership of the symlink. See Note 2.   |
| Pathname#lstat        | Creates a File::Stat object for a link. See Note 3. |
| Pathname#lutime       | Updates timestamps for the symlink. See Note 4.     |
| Pathname#make_symlink | Creates a symlink.                                  |
| Pathname#readlink     | Returns the path stored in a symlink.               |
| Pathname#symlink?     | Returns whether a path is a symlink.                |

Notes:

1. File::chmod and Pathname#chmod follow symlinks before changing the mode.
1. File::chown and Pathname#chown follow symlinks before changing the ownership.
1. File::stat and Pathname#stat follow symlinks before creating the File::Stat object.
1. File::utime and Pathname#utime follow symlinks before updating timestamps.

### Other Non-Following Methods

The methods in the table below do not follow symlinks,
but instead operate directly on the entry at the path
(which may or may not be a symlink).

| Method                                       | Effect                           |
|----------------------------------------------|----------------------------------|
| File::delete                                 | Removes the entry.               |
| File::link                                   | Creates a hard link.             |
| File::rename                                 | Changes the name of the entry.   |
| File::unlink                                 | Removes the entry.               |
| FileUtils::link_entry                        | Creates a hard link.             |
| FileUtils::ln (aliased as FileUtils.link)    | Creates a hard link.             |
| Pathname#rename                              | Changes the name of the entry.   |
| Pathname#unlink (aliased as Pathname#delete) | Removes the entry.               |

[symbolic link]: https://en.wikipedia.org/wiki/Symbolic_link
