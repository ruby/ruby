# frozen_string_literal: true
##
# This module contains various utility methods as module methods.

module Gem::Util

  @silent_mutex = nil

  ##
  # Zlib::GzipReader wrapper that unzips +data+.

  def self.gunzip(data)
    require 'zlib'
    require 'stringio'
    data = StringIO.new(data, 'r')

    unzipped = Zlib::GzipReader.new(data).read
    unzipped.force_encoding Encoding::BINARY if Object.const_defined? :Encoding
    unzipped
  end

  ##
  # Zlib::GzipWriter wrapper that zips +data+.

  def self.gzip(data)
    require 'zlib'
    require 'stringio'
    zipped = StringIO.new(String.new, 'w')
    zipped.set_encoding Encoding::BINARY if Object.const_defined? :Encoding

    Zlib::GzipWriter.wrap zipped do |io| io.write data end

    zipped.string
  end

  ##
  # A Zlib::Inflate#inflate wrapper

  def self.inflate(data)
    require 'zlib'
    Zlib::Inflate.inflate data
  end

  ##
  # This calls IO.popen where it accepts an array for a +command+ (Ruby 1.9+)
  # and implements an IO.popen-like behavior where it does not accept an array
  # for a command.

  def self.popen *command
    IO.popen command, &:read
  rescue TypeError # ruby 1.8 only supports string command
    r, w = IO.pipe

    pid = fork do
      STDIN.close
      STDOUT.reopen w

      exec(*command)
    end

    w.close

    begin
      return r.read
    ensure
      Process.wait pid
    end
  end

  NULL_DEVICE = defined?(IO::NULL) ? IO::NULL : Gem.win_platform? ? 'NUL' : '/dev/null'

  ##
  # Invokes system, but silences all output.

  def self.silent_system *command
    opt = {:out => NULL_DEVICE, :err => [:child, :out]}
    if Hash === command.last
      opt.update(command.last)
      cmds = command[0...-1]
    else
      cmds = command.dup
    end
    return system(*(cmds << opt))
  rescue TypeError
    require 'thread'

    @silent_mutex ||= Mutex.new

    null_device = NULL_DEVICE

    @silent_mutex.synchronize do
      begin
        stdout = STDOUT.dup
        stderr = STDERR.dup

        STDOUT.reopen null_device, 'w'
        STDERR.reopen null_device, 'w'

        return system(*command)
      ensure
        STDOUT.reopen stdout
        STDERR.reopen stderr
        stdout.close
        stderr.close
      end
    end
  end

  ##
  # Enumerates the parents of +directory+.

  def self.traverse_parents directory, &block
    return enum_for __method__, directory unless block_given?

    here = File.expand_path directory
    loop do
      Dir.chdir here, &block
      new_here = File.expand_path('..', here)
      return if new_here == here # toplevel
      here = new_here
    end
  end

end
