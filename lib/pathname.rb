# frozen_string_literal: true
#
# = pathname.rb
#
# Object-Oriented Pathname Class
#
# Author:: Tanaka Akira <akr@m17n.org>
# Documentation:: Author and Gavin Sinclair
#
# For documentation, see class Pathname.
#
class Pathname

  # :markup: markdown
  #
  # call-seq:
  #   Pathname.find(ignore_error: true) -> nil
  #
  # With a block given, performs a depth-first traversal of the path in `self`;
  # calls the block with each found path:
  #
  # ```ruby
  # paths = []
  # Pathname('lib').find {|path| paths << path }
  # paths.size  # => 909
  # paths.take(3)
  # # =>
  # # [#<Pathname:lib>,
  # #  #<Pathname:lib/English.gemspec>,
  # #  #<Pathname:lib/English.rb>]
  # ```
  #
  # When `self` contains `'.'`, the found paths omit the leading `'./'`:
  #
  # ```ruby
  # paths = []
  # Dir.chdir('lib') do
  #   Pathname('.').find {|path| paths << path }
  # end
  # paths.take(3)
  # # # =>
  # # [#<Pathname:.>,
  # #  #<Pathname:English.gemspec>,
  # #  #<Pathname:English.rb>]
  # ```
  #
  # This method calls method Find.find;
  # therefore method Find.prune may be used in the block:
  #
  # ```ruby
  # files = []
  # Pathname('.').find do |path|
  #   Find.prune if File.basename(path) == 'test'
  #   next unless File.file?(path) && File.extname(path) == '.rb'
  #   files << path
  # end
  # files.size # => 6690
  # files.take(3)
  # # # =>
  # # [#<Pathname:KNOWNBUGS.rb>,
  # #  #<Pathname:array.rb>,
  # #  #<Pathname:ast.rb>]
  # ```
  #
  # Raises an exception if the path in `self` cannot be read.
  #
  # When keyword argument `ignore_error` is given as `true` (the default),
  # certain exceptions during traversal are ignored (i.e., silently rescued):
  # Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR, Errno::ELOOP, Errno::ENAMETOOLONG, Errno::EINVAL;
  # when given as `false`, no exceptions are rescued.
  #
  # With no block given, returns a new Enumerator.
  def find(ignore_error: true) # :yield: pathname
    return to_enum(__method__, ignore_error: ignore_error) unless block_given?
    require 'find'
    if @path == '.'
      Find.find(@path, ignore_error: ignore_error) {|f| yield self.class.new(f.delete_prefix('./')) }
    else
      Find.find(@path, ignore_error: ignore_error) {|f| yield self.class.new(f) }
    end
  end
end


class Pathname    # * FileUtils *
  # Recursively deletes a directory, including all directories beneath it.
  #
  # Note that you need to require 'pathname' to use this method.
  #
  # See FileUtils.rm_rf
  def rmtree(noop: nil, verbose: nil, secure: nil)
    # The name "rmtree" is borrowed from File::Path of Perl.
    # File::Path provides "mkpath" and "rmtree".
    require 'fileutils'
    FileUtils.rm_rf(@path, noop: noop, verbose: verbose, secure: secure)
    self
  end
end

class Pathname    # * tmpdir *
  # call-seq:
  #   Pathname.mktmpdir -> new_pathname
  #   Pathname.mktmpdir {|pathname| ... } -> object
  #
  # Creates:
  #
  # - A temporary directory via Dir.mktmpdir.
  # - A \Pathname object that contains the path to that directory.
  #
  # With no block given, returns the created pathname;
  # the caller should delete the created directory when it is no longer needed
  # (FileUtils.rm_r is a convenient method for the deletion):
  #
  #   pathname = Pathname.mktmpdir
  #   dirpath = pathname.to_s
  #   Dir.exist?(dirpath) # => true
  #   # Do something with the directory.
  #   require 'fileutils'
  #   FileUtils.rm_r(dirpath)
  #
  # With a block given, calls the block with the created pathname;
  # on block exit, automatically deletes the created directory and all its contents;
  # returns the block's exit value:
  #
  #   pathname = Pathname.mktmpdir do |p|
  #     # Do something with the directory.
  #     p
  #   end
  #   Dir.exist?(pathname.to_s) # => false
  def self.mktmpdir
    require 'tmpdir' unless defined?(Dir.mktmpdir)
    if block_given?
      Dir.mktmpdir do |dir|
        dir = self.new(dir)
        yield dir
      end
    else
      self.new(Dir.mktmpdir)
    end
  end
end
