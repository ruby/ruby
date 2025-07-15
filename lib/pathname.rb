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

class Pathname    # * Find *
  #
  # Iterates over the directory tree in a depth first manner, yielding a
  # Pathname for each file under "this" directory.
  #
  # Returns an Enumerator if no block is given.
  #
  # Since it is implemented by the standard library module Find, Find.prune can
  # be used to control the traversal.
  #
  # If +self+ is +.+, yielded pathnames begin with a filename in the
  # current directory, not +./+.
  #
  # See Find.find
  #
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
  # Creates a full path, including any intermediate directories that don't yet
  # exist.
  #
  # See FileUtils.mkpath and FileUtils.mkdir_p
  def mkpath(mode: nil)
    require 'fileutils'
    FileUtils.mkpath(@path, mode: mode)
    self
  end

  # Recursively deletes a directory, including all directories beneath it.
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
  # Creates a tmp directory and wraps the returned path in a Pathname object.
  #
  # See Dir.mktmpdir
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
