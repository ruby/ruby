# frozen_string_literal: true

##
# This module contains various utility methods as module methods.

module Gem::Util
  ##
  # Zlib::GzipReader wrapper that unzips +data+.

  def self.gunzip(data)
    require "zlib"
    require "stringio"
    data = StringIO.new(data, "r")

    gzip_reader = begin
                    Zlib::GzipReader.new(data)
                  rescue Zlib::GzipFile::Error => e
                    raise e.class, e.inspect, e.backtrace
                  end

    unzipped = gzip_reader.read
    unzipped.force_encoding Encoding::BINARY
    unzipped
  end

  ##
  # Zlib::GzipWriter wrapper that zips +data+.

  def self.gzip(data)
    require "zlib"
    require "stringio"
    zipped = StringIO.new(String.new, "w")
    zipped.set_encoding Encoding::BINARY

    Zlib::GzipWriter.wrap zipped do |io|
      io.write data
    end

    zipped.string
  end

  ##
  # A Zlib::Inflate#inflate wrapper

  def self.inflate(data)
    require "zlib"
    Zlib::Inflate.inflate data
  end

  ##
  # This calls IO.popen and reads the result

  def self.popen(*command)
    IO.popen command, &:read
  end

  ##
  # Enumerates the parents of +directory+.

  def self.traverse_parents(directory, &block)
    return enum_for __method__, directory unless block_given?

    here = File.expand_path directory
    loop do
      begin
        Dir.chdir here, &block
      rescue StandardError
        Errno::EACCES
      end

      new_here = File.expand_path("..", here)
      return if new_here == here # toplevel
      here = new_here
    end
  end

  ##
  # Globs for entries matching +glob+ inside of +base_path+, returning
  # absolute paths to the matching files and directories. Unlike a plain
  # Dir.glob with an interpolated path, glob metacharacters in +base_path+
  # are not treated as part of the pattern. Matched entries are joined to
  # +base_path+ literally, so an entry starting with `~` is not expanded
  # into a home directory, and no other normalization is applied to them.

  def self.glob_files_in_dir(glob, base_path)
    expanded_path = nil
    Dir.glob(glob, base: base_path).map! do |f|
      # File.join instead of File.expand_path, so that matched entries
      # starting with `~` are not expanded into the home directory
      File.join(expanded_path ||= File.expand_path(base_path), f)
    end
  end

  ##
  # Corrects +path+ (usually returned by `Gem::URI.parse().path` on Windows), that
  # comes with a leading slash.

  def self.correct_for_windows_path(path)
    if path[0].chr == "/" && path[1].chr.match?(/[a-z]/i) && path[2].chr == ":"
      path[1..-1]
    else
      path
    end
  end
end
