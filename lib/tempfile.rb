# frozen_string_literal: true
#
# tempfile - manipulates temporary files
#
# $Id$
#

require 'delegate'
require 'tmpdir'

# A utility class for managing temporary files.
#
# There are two kind of methods of creating a temporary file:
#
# - Tempfile.create (recommended)
# - Tempfile.new and Tempfile.open (mostly for backward compatibility, not recommended)
#
# Tempfile.create creates a usual \File object.
# The timing of file deletion is predictable.
# Also, it supports open-and-unlink technique which
# removes the temporary file immediately after creation.
#
# Tempfile.new and Tempfile.open creates a \Tempfile object.
# The created file is removed by the GC (finalizer).
# The timing of file deletion is not predictable.
#
# == Synopsis
#
#   require 'tempfile'
#
#   # Tempfile.create with a block
#   # The filename are choosen automatically.
#   # (You can specify the prefix and suffix of the filename by an optional argument.)
#   Tempfile.create {|f|
#     f.puts "foo"
#     f.rewind
#     f.read                # => "foo\n"
#   }                       # The file is removed at block exit.
#
#   # Tempfile.create without a block
#   # You need to unlink the file in non-block form.
#   f = Tempfile.create
#   f.puts "foo"
#   f.close
#   File.unlink(f.path)     # You need to unlink the file.
#
#   # Tempfile.create(anonymous: true) without a block
#   f = Tempfile.create(anonymous: true)
#   # The file is already removed because anonymous.
#   f.path                  # => "/tmp/"  (no filename since no file)
#   f.puts "foo"
#   f.rewind
#   f.read                  # => "foo\n"
#   f.close
#
#   # Tempfile.create(anonymous: true) with a block
#   Tempfile.create(anonymous: true) {|f|
#     # The file is already removed because anonymous.
#     f.path                # => "/tmp/"  (no filename since no file)
#     f.puts "foo"
#     f.rewind
#     f.read                # => "foo\n"
#   }
#
#   # Not recommended: Tempfile.new without a block
#   file = Tempfile.new('foo')
#   file.path      # => A unique filename in the OS's temp directory,
#                  #    e.g.: "/tmp/foo.24722.0"
#                  #    This filename contains 'foo' in its basename.
#   file.write("hello world")
#   file.rewind
#   file.read      # => "hello world"
#   file.close
#   file.unlink    # deletes the temp file
#
# == About Tempfile.new and Tempfile.open
#
# This section does not apply to Tempfile.create because
# it returns a File object (not a Tempfile object).
#
# When you create a Tempfile object,
# it will create a temporary file with a unique filename. A Tempfile
# objects behaves just like a File object, and you can perform all the usual
# file operations on it: reading data, writing data, changing its permissions,
# etc. So although this class does not explicitly document all instance methods
# supported by File, you can in fact call any File instance method on a
# Tempfile object.
#
# A Tempfile object has a finalizer to remove the temporary file.
# This means that the temporary file is removed via GC.
# This can cause several problems:
#
# - Long GC intervals and conservative GC can accumulate temporary files that are not removed.
# - Temporary files are not removed if Ruby exits abnormally (such as SIGKILL, SEGV).
#
# There are legacy good practices for Tempfile.new and Tempfile.open as follows.
#
# === Explicit close
#
# When a Tempfile object is garbage collected, or when the Ruby interpreter
# exits, its associated temporary file is automatically deleted. This means
# that it's unnecessary to explicitly delete a Tempfile after use, though
# it's a good practice to do so: not explicitly deleting unused Tempfiles can
# potentially leave behind a large number of temp files on the filesystem
# until they're garbage collected. The existence of these temp files can make
# it harder to determine a new Tempfile filename.
#
# Therefore, one should always call #unlink or close in an ensure block, like
# this:
#
#   file = Tempfile.new('foo')
#   begin
#      # ...do something with file...
#   ensure
#      file.close
#      file.unlink   # deletes the temp file
#   end
#
# Tempfile.create { ... } exists for this purpose and is more convenient to use.
# Note that Tempfile.create returns a File instance instead of a Tempfile, which
# also avoids the overhead and complications of delegation.
#
#   Tempfile.create('foo') do |file|
#      # ...do something with file...
#   end
#
# === Unlink after creation
#
# On POSIX systems, it's possible to unlink a file right after creating it,
# and before closing it. This removes the filesystem entry without closing
# the file handle, so it ensures that only the processes that already had
# the file handle open can access the file's contents. It's strongly
# recommended that you do this if you do not want any other processes to
# be able to read from or write to the Tempfile, and you do not need to
# know the Tempfile's filename either.
#
# Also, this guarantees the temporary file is removed even if Ruby exits abnormally.
# The OS reclaims the storage for the temporary file when the file is closed or
# the Ruby process exits (normally or abnormally).
#
# For example, a practical use case for unlink-after-creation would be this:
# you need a large byte buffer that's too large to comfortably fit in RAM,
# e.g. when you're writing a web server and you want to buffer the client's
# file upload data.
#
# `Tempfile.create(anonymous: true)` supports this behavior.
# It also works on Windows.
#
# == Minor notes
#
# Tempfile's filename picking method is both thread-safe and inter-process-safe:
# it guarantees that no other threads or processes will pick the same filename.
#
# Tempfile itself however may not be entirely thread-safe. If you access the
# same Tempfile object from multiple threads then you should protect it with a
# mutex.
class Tempfile < DelegateClass(File)

  # The version
  VERSION = "0.3.1"

  # Creates a file in the underlying file system;
  # returns a new \Tempfile object based on that file.
  #
  # If possible, consider instead using Tempfile.create, which:
  #
  # - Avoids the performance cost of delegation,
  #   incurred when Tempfile.new calls its superclass <tt>DelegateClass(File)</tt>.
  # - Does not rely on a finalizer to close and unlink the file,
  #   which can be unreliable.
  #
  # Creates and returns file whose:
  #
  # - Class is \Tempfile (not \File, as in Tempfile.create).
  # - Directory is the system temporary directory (system-dependent).
  # - Generated filename is unique in that directory.
  # - Permissions are <tt>0600</tt>;
  #   see {File Permissions}[rdoc-ref:File@File+Permissions].
  # - Mode is <tt>'w+'</tt> (read/write mode, positioned at the end).
  #
  # The underlying file is removed when the \Tempfile object dies
  # and is reclaimed by the garbage collector.
  #
  # Example:
  #
  #   f = Tempfile.new # => #<Tempfile:/tmp/20220505-17839-1s0kt30>
  #   f.class               # => Tempfile
  #   f.path                # => "/tmp/20220505-17839-1s0kt30"
  #   f.stat.mode.to_s(8)   # => "100600"
  #   File.exist?(f.path)   # => true
  #   File.unlink(f.path)   #
  #   File.exist?(f.path)   # => false
  #
  # Argument +basename+, if given, may be one of:
  #
  # - A string: the generated filename begins with +basename+:
  #
  #     Tempfile.new('foo') # => #<Tempfile:/tmp/foo20220505-17839-1whk2f>
  #
  # - An array of two strings <tt>[prefix, suffix]</tt>:
  #   the generated filename begins with +prefix+ and ends with +suffix+:
  #
  #     Tempfile.new(%w/foo .jpg/) # => #<Tempfile:/tmp/foo20220505-17839-58xtfi.jpg>
  #
  # With arguments +basename+ and +tmpdir+, the file is created in directory +tmpdir+:
  #
  #   Tempfile.new('foo', '.') # => #<Tempfile:./foo20220505-17839-xfstr8>
  #
  # Keyword arguments +mode+ and +options+ are passed directly to method
  # {File.open}[rdoc-ref:File.open]:
  #
  # - The value given with +mode+ must be an integer,
  #   and may be expressed as the logical OR of constants defined in
  #   {File::Constants}[rdoc-ref:File::Constants].
  # - For +options+, see {Open Options}[rdoc-ref:IO@Open+Options].
  #
  # Related: Tempfile.create.
  #
  def initialize(basename="", tmpdir=nil, mode: 0, **options)
    warn "Tempfile.new doesn't call the given block.", uplevel: 1 if block_given?

    @unlinked = false
    @mode = mode|File::RDWR|File::CREAT|File::EXCL
    tmpfile = nil
    ::Dir::Tmpname.create(basename, tmpdir, **options) do |tmpname, n, opts|
      opts[:perm] = 0600
      tmpfile = File.open(tmpname, @mode, **opts)
      @opts = opts.freeze
    end

    super(tmpfile)

    @finalizer_manager = FinalizerManager.new(__getobj__.path)
    @finalizer_manager.register(self, __getobj__)
  end

  def initialize_dup(other) # :nodoc:
    initialize_copy_iv(other)
    super(other)
    @finalizer_manager.register(self, __getobj__)
  end

  def initialize_clone(other) # :nodoc:
    initialize_copy_iv(other)
    super(other)
    @finalizer_manager.register(self, __getobj__)
  end

  private def initialize_copy_iv(other) # :nodoc:
    @unlinked = other.unlinked
    @mode = other.mode
    @opts = other.opts
    @finalizer_manager = other.finalizer_manager
  end

  # Opens or reopens the file with mode "r+".
  def open
    _close

    mode = @mode & ~(File::CREAT|File::EXCL)
    __setobj__(File.open(__getobj__.path, mode, **@opts))

    @finalizer_manager.register(self, __getobj__)

    __getobj__
  end

  def _close    # :nodoc:
    __getobj__.close
  end
  protected :_close

  # Closes the file. If +unlink_now+ is true, then the file will be unlinked
  # (deleted) after closing. Of course, you can choose to later call #unlink
  # if you do not unlink it now.
  #
  # If you don't explicitly unlink the temporary file, the removal
  # will be delayed until the object is finalized.
  def close(unlink_now=false)
    _close
    unlink if unlink_now
  end

  # Closes and unlinks (deletes) the file. Has the same effect as called
  # <tt>close(true)</tt>.
  def close!
    close(true)
  end

  # Unlinks (deletes) the file from the filesystem. One should always unlink
  # the file after using it, as is explained in the "Explicit close" good
  # practice section in the Tempfile overview:
  #
  #   file = Tempfile.new('foo')
  #   begin
  #      # ...do something with file...
  #   ensure
  #      file.close
  #      file.unlink   # deletes the temp file
  #   end
  #
  # === Unlink-before-close
  #
  # On POSIX systems it's possible to unlink a file before closing it. This
  # practice is explained in detail in the Tempfile overview (section
  # "Unlink after creation"); please refer there for more information.
  #
  # However, unlink-before-close may not be supported on non-POSIX operating
  # systems. Microsoft Windows is the most notable case: unlinking a non-closed
  # file will result in an error, which this method will silently ignore. If
  # you want to practice unlink-before-close whenever possible, then you should
  # write code like this:
  #
  #   file = Tempfile.new('foo')
  #   file.unlink   # On Windows this silently fails.
  #   begin
  #      # ... do something with file ...
  #   ensure
  #      file.close!   # Closes the file handle. If the file wasn't unlinked
  #                    # because #unlink failed, then this method will attempt
  #                    # to do so again.
  #   end
  def unlink
    return if @unlinked
    begin
      File.unlink(__getobj__.path)
    rescue Errno::ENOENT
    rescue Errno::EACCES
      # may not be able to unlink on Windows; just ignore
      return
    end

    @finalizer_manager.unlinked = true

    @unlinked = true
  end
  alias delete unlink

  # Returns the full path name of the temporary file.
  # This will be nil if #unlink has been called.
  def path
    @unlinked ? nil : __getobj__.path
  end

  # Returns the size of the temporary file.  As a side effect, the IO
  # buffer is flushed before determining the size.
  def size
    if !__getobj__.closed?
      __getobj__.size # File#size calls rb_io_flush_raw()
    else
      File.size(__getobj__.path)
    end
  end
  alias length size

  # :stopdoc:
  def inspect
    if __getobj__.closed?
      "#<#{self.class}:#{path} (closed)>"
    else
      "#<#{self.class}:#{path}>"
    end
  end
  alias to_s inspect

  protected

  attr_reader :unlinked, :mode, :opts, :finalizer_manager

  class FinalizerManager # :nodoc:
    attr_accessor :unlinked

    def initialize(path)
      @open_files = {}
      @path = path
      @pid = Process.pid
      @unlinked = false
    end

    def register(obj, file)
      ObjectSpace.undefine_finalizer(obj)
      ObjectSpace.define_finalizer(obj, self)
      @open_files[obj.object_id] = file
    end

    def call(object_id)
      @open_files.delete(object_id).close

      if @open_files.empty? && !@unlinked && Process.pid == @pid
        $stderr.puts "removing #{@path}..." if $DEBUG
        begin
          File.unlink(@path)
        rescue Errno::ENOENT
        end
        $stderr.puts "done" if $DEBUG
      end
    end
  end

  class << self
    # :startdoc:

    # Creates a new Tempfile.
    #
    # This method is not recommended and exists mostly for backward compatibility.
    # Please use Tempfile.create instead, which avoids the cost of delegation,
    # does not rely on a finalizer, and also unlinks the file when given a block.
    #
    # Tempfile.open is still appropriate if you need the Tempfile to be unlinked
    # by a finalizer and you cannot explicitly know where in the program the
    # Tempfile can be unlinked safely.
    #
    # If no block is given, this is a synonym for Tempfile.new.
    #
    # If a block is given, then a Tempfile object will be constructed,
    # and the block is run with the Tempfile object as argument. The Tempfile
    # object will be automatically closed after the block terminates.
    # However, the file will *not* be unlinked and needs to be manually unlinked
    # with Tempfile#close! or Tempfile#unlink. The finalizer will try to unlink
    # but should not be relied upon as it can keep the file on the disk much
    # longer than intended. For instance, on CRuby, finalizers can be delayed
    # due to conservative stack scanning and references left in unused memory.
    #
    # The call returns the value of the block.
    #
    # In any case, all arguments (<code>*args</code>) will be passed to Tempfile.new.
    #
    #   Tempfile.open('foo', '/home/temp') do |f|
    #      # ... do something with f ...
    #   end
    #
    #   # Equivalent:
    #   f = Tempfile.open('foo', '/home/temp')
    #   begin
    #      # ... do something with f ...
    #   ensure
    #      f.close
    #   end
    def open(*args, **kw)
      tempfile = new(*args, **kw)

      if block_given?
        begin
          yield(tempfile)
        ensure
          tempfile.close
        end
      else
        tempfile
      end
    end
  end
end

# Creates a file in the underlying file system;
# returns a new \File object based on that file.
#
# With no block given and no arguments, creates and returns file whose:
#
# - Class is {File}[rdoc-ref:File] (not \Tempfile).
# - Directory is the system temporary directory (system-dependent).
# - Generated filename is unique in that directory.
# - Permissions are <tt>0600</tt>;
#   see {File Permissions}[rdoc-ref:File@File+Permissions].
# - Mode is <tt>'w+'</tt> (read/write mode, positioned at the end).
#
# The temporary file removal depends on the keyword argument +anonymous+ and
# whether a block is given or not.
# See the description about the +anonymous+ keyword argument later.
#
# Example:
#
#   f = Tempfile.create     # => #<File:/tmp/20220505-9795-17ky6f6>
#   f.class                 # => File
#   f.path                  # => "/tmp/20220505-9795-17ky6f6"
#   f.stat.mode.to_s(8)     # => "100600"
#   f.close
#   File.exist?(f.path)     # => true
#   File.unlink(f.path)
#   File.exist?(f.path)     # => false
#
#   Tempfile.create {|f|
#     f.puts "foo"
#     f.rewind
#     f.read                # => "foo\n"
#     f.path                # => "/tmp/20240524-380207-oma0ny"
#     File.exist?(f.path)   # => true
#   }                       # The file is removed at block exit.
#
#   f = Tempfile.create(anonymous: true)
#   # The file is already removed because anonymous
#   f.path                  # => "/tmp/"  (no filename since no file)
#   f.puts "foo"
#   f.rewind
#   f.read                  # => "foo\n"
#   f.close
#
#   Tempfile.create(anonymous: true) {|f|
#     # The file is already removed because anonymous
#     f.path                # => "/tmp/"  (no filename since no file)
#     f.puts "foo"
#     f.rewind
#     f.read                # => "foo\n"
#   }
#
# The argument +basename+, if given, may be one of the following:
#
# - A string: the generated filename begins with +basename+:
#
#     Tempfile.create('foo') # => #<File:/tmp/foo20220505-9795-1gok8l9>
#
# - An array of two strings <tt>[prefix, suffix]</tt>:
#   the generated filename begins with +prefix+ and ends with +suffix+:
#
#     Tempfile.create(%w/foo .jpg/) # => #<File:/tmp/foo20220505-17839-tnjchh.jpg>
#
# With arguments +basename+ and +tmpdir+, the file is created in the directory +tmpdir+:
#
#   Tempfile.create('foo', '.') # => #<File:./foo20220505-9795-1emu6g8>
#
# Keyword arguments +mode+ and +options+ are passed directly to the method
# {File.open}[rdoc-ref:File.open]:
#
# - The value given for +mode+ must be an integer
#   and may be expressed as the logical OR of constants defined in
#   {File::Constants}[rdoc-ref:File::Constants].
# - For +options+, see {Open Options}[rdoc-ref:IO@Open+Options].
#
# The keyword argument +anonymous+ specifies when the file is removed.
#
# - <tt>anonymous=false</tt> (default) without a block: the file is not removed.
# - <tt>anonymous=false</tt> (default) with a block: the file is removed after the block exits.
# - <tt>anonymous=true</tt> without a block: the file is removed before returning.
# - <tt>anonymous=true</tt> with a block: the file is removed before the block is called.
#
# In the first case (<tt>anonymous=false</tt> without a block),
# the file is not removed automatically.
# It should be explicitly closed.
# It can be used to rename to the desired filename.
# If the file is not needed, it should be explicitly removed.
#
# The File#path method of the created file object returns the temporary directory with a trailing slash
# when +anonymous+ is true.
#
# When a block is given, it creates the file as described above, passes it to the block,
# and returns the block's value.
# Before the returning, the file object is closed and the underlying file is removed:
#
#   Tempfile.create {|file| file.path } # => "/tmp/20220505-9795-rkists"
#
# Implementation note:
#
# The keyword argument +anonymous=true+ is implemented using FILE_SHARE_DELETE on Windows.
# O_TMPFILE is used on Linux.
#
# Related: Tempfile.new.
#
def Tempfile.create(basename="", tmpdir=nil, mode: 0, anonymous: false, **options, &block)
  if anonymous
    create_anonymous(basename, tmpdir, mode: mode, **options, &block)
  else
    create_with_filename(basename, tmpdir, mode: mode, **options, &block)
  end
end

class << Tempfile
private def create_with_filename(basename="", tmpdir=nil, mode: 0, **options)
  tmpfile = nil
  Dir::Tmpname.create(basename, tmpdir, **options) do |tmpname, n, opts|
    mode |= File::RDWR|File::CREAT|File::EXCL
    opts[:perm] = 0600
    tmpfile = File.open(tmpname, mode, **opts)
  end
  if block_given?
    begin
      yield tmpfile
    ensure
      unless tmpfile.closed?
        if File.identical?(tmpfile, tmpfile.path)
          unlinked = File.unlink tmpfile.path rescue nil
        end
        tmpfile.close
      end
      unless unlinked
        begin
          File.unlink tmpfile.path
        rescue Errno::ENOENT
        end
      end
    end
  else
    tmpfile
  end
end

if RUBY_VERSION < "3.2"
  module PathAttr               # :nodoc:
    attr_reader :path

    def self.set_path(file, path)
      file.extend(self).instance_variable_set(:@path, path)
    end
  end
end

private def create_anonymous(basename="", tmpdir=nil, mode: 0, **options, &block)
  tmpfile = nil
  tmpdir = Dir.tmpdir() if tmpdir.nil?
  if defined?(File::TMPFILE) # O_TMPFILE since Linux 3.11
    begin
      tmpfile = File.open(tmpdir, File::RDWR | File::TMPFILE, 0600)
    rescue Errno::EISDIR, Errno::ENOENT, Errno::EOPNOTSUPP
      # kernel or the filesystem does not support O_TMPFILE
      # fallback to create-and-unlink
    end
  end
  if tmpfile.nil?
    mode |= File::SHARE_DELETE | File::BINARY # Windows needs them to unlink the opened file.
    tmpfile = create_with_filename(basename, tmpdir, mode: mode, **options)
    File.unlink(tmpfile.path)
    tmppath = tmpfile.path
  end
  path = File.join(tmpdir, '')
  unless tmppath == path
    # clear path.
    tmpfile.autoclose = false
    tmpfile = File.new(tmpfile.fileno, mode: File::RDWR, path: path)
    PathAttr.set_path(tmpfile, path) if defined?(PathAttr)
  end
  if block
    begin
      yield tmpfile
    ensure
      tmpfile.close
    end
  else
    tmpfile
  end
end
end
