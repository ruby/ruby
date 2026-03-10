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
  # Creates a tmp directory and wraps the returned path in a Pathname object.
  #
  # Note that you need to require 'pathname' to use this method.
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
