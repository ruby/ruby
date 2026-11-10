# Hard Links

A _hard link_ is a filesystem entry pointing to
an [inode](https://en.wikipedia.org/wiki/Inode) in the filesystem;
in effect, the hard link is a name for the inode.

An inode is one of these types (see File.ftype):

- Regular file.
- Directory.
- Symbolic link.
- FIFO.
- \Socket.
- Block-special device.
- Character-special device.

When an inode is created, it initially has one hard link -- its original "name":

```ruby
path0 = '/tmp/t0.tmp'
File.write(path0, 'foo')
stat0 = File.stat(path0)
stat0.ino   # => 26345482  # Inode identifier; unique within filesystem.
stat0.nlink # => 1         # Count of hard link to the inode.
```

## Multiple Hard Links

The inode may have more than one hard link:

```ruby
path1 = '/tmp/t1.tmp'
File.link(path0, path1)
stat1 = File.stat(path1)
stat1.ino   # => 26345482
stat1.nlink # => 2
```

Multiple hard links to the same inode are in effect multiple names for that inode:

```ruby
File.read(path0) # => "foo"
File.read(path1) # => "foo"
```

When an inode has more than one hard link, all its hard links are "equal";
the original hard link is no more "valid" or "important" than the others.

## Unlinking

Unlinking (removing) one hard link does not remove the inode:

```ruby
File.unlink(path1)
File.exist?(path1)     # => false  # Hard link path1 was removed.
File.exist?(path0)     # => true   # Hard link path0 still exists.
File.stat(path0).nlink # => 1      # Now has only one hard link.
```

But removing the last hard link does remove the inode:

```ruby
File.unlink(path0)
File.exist?(path0) # => false  # And the inode was removed.
```
