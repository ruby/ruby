# Symbolic Links

A [symbolic link][symbolic link] (often called a _symlink_ or _soft link_)
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

## Methods That Don't Follow Symlinks

Sometimes it's necessary to query, modify, or delete a symlink;
therefore certain Ruby methods do not follow symlinks,
but instead operate directly on the symlinks.

### Symlink-Specific Methods

Each method in the table below is symlink-specific.

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

#### `symlink`, `ln_s`

Each of the methods File::symlink, FileUtils::ln_s, and Pathname#make_symlink
creates a symlink;
in each case, if the target path is itself a symlink, that symlink is not followed:

```ruby
# Make some symlinks.
File.symlink('README.md', 'foo')
FileUtils.ln_s('README.md', 'bar')
Pathname('baz').make_symlink('README.md')
# A symlink may refer to another symlink.
File.symlink('foo', 'bat')
# All are symlinks.
%w[foo bar baz bat].map {|s| File.symlink?(s) }  # => [true, true, true, true]
# Each refers, directly or indirectly, to README.md.
File.read('README.md').size                      # => 3463
%w[foo bar baz bat].map {|s| File.read(s).size } # => [3463, 3463, 3463, 3463]
File.delete(*%w[foo bar baz bat])                # Clean up.
```


#### `lstat`

Each of the methods File::lstat and Pathname#lstat
creates a File::Stat object for a filesystem entry.
That object contains information for the entry at the given path,
even if that entry is a symlink;
i.e., symlinks are not followed.

By contrast, each of the methods File::stat and Pathname#stat
_do_ follow symlinks.

Examples:

```ruby
linkpath = 'foo'
File.symlink('README.md', linkpath)
File::stat(linkpath).size     # => 3469  # Size of file README.md.
File::lstat(linkpath).size    # => 9     # Size of symlink linkpath.
Pathname(linkpath).lstat.size # => 9
file = File.new(linkpath)
file.lstat.size               # => 9
# Clean up.
file.close
File.unlink(linkpath)
```

#### `symlink?`

Each of the methods File::symlink?, File::Stat#symlink?, and Pathname#symlink?
returns whether the entry at a given path is a symlink;
if the entry is a symlink, it is not followed:

```ruby
linkpath = 'foo'
File.symlink('README.md', 'foo')
File.symlink?(linkpath)     # => true
Pathname(linkpath).symlink? # => true
file = File.new(linkpath)
file.stat.symlink?          # => false # Follows symlink to README.md.
file.lstat.symlink?         # => true  # Does not follow symlink.
# Clean up.
file.close
File.delete(linkpath)
```

#### `readlink`

Each method named `readlink` returns the path stored in a symlink:

- File::readlink, Pathname#readlink.

#### `lchmod`

Each method named `lchmod` changes the mode of the symlink entry:

- File::lchmod, Pathname#lchmod.

#### `lchown`

Each method named `lchown` changes the ownership of a symlink entry:

- File::lchown, Pathname#lchown.

#### `lutime`

Each method named `lutime` updates timestamps for a symlink entry:

- File::lutime, Pathname#lutime.

### Other Methods

The methods in the table below do not follow symlinks,
but instead operate directly on the entry at the path
(which may or may not be a symlink).

| Method                                       | Effect                           |
|----------------------------------------------|----------------------------------|
| Dir::[]                                      | Finds entry names.               |
| Dir::children                                | Returns an array of child names. |
| Dir::each_child                              | Traverses child names.           |
| Dir::entries                                 | Returns an array of entry names. |
| Dir::foreach                                 | Traverses entry names.           |
| Dir::glob                                    | Finds entry names.               |
| Dir::unlink (aliased as Dir::delete)         | Removes the entry.               |
| File::delete                                 | Removes the entry.               |
| File::rename                                 | Changes the name of the entry.   |
| File::unlink                                 | Removes the entry.               |
| Pathname#rename                              | Changes the name of the entry.   |
| Pathname#unlink (aliased as Pathname#delete) | Removes the entry.               |
| Tempfile#unlink (aliased as Tempfile#delete) | Removes the entry.               |


[symbolic link]: https://en.wikipedia.org/wiki/Symbolic_link
