module Gem::Util
  ##
  # Zlib::GzipReader wrapper that unzips +data+.

  def self.gunzip(data)
    require 'zlib'
    require 'rubygems/util/stringio'
    data = Gem::StringSource.new data

    unzipped = Zlib::GzipReader.new(data).read
    unzipped.force_encoding Encoding::BINARY if Object.const_defined? :Encoding
    unzipped
  end

  ##
  # Zlib::GzipWriter wrapper that zips +data+.

  def self.gzip(data)
    require 'zlib'
    require 'rubygems/util/stringio'
    zipped = Gem::StringSink.new
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
    begin
      r, = IO.popen command
    rescue TypeError # ruby 1.8 only supports string command
      r, w = IO.pipe

      pid = fork do
        STDIN.close
        STDOUT.reopen w

        exec(*command)
      end

      w.close

      Process.wait pid

      r
    end

    r.read
  end

end
