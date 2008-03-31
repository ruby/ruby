#++
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#--

require 'rubygems/package'

class Gem::Package::TarWriter

  class FileOverflow < StandardError; end

  class BoundedStream

    attr_reader :limit, :written

    def initialize(io, limit)
      @io = io
      @limit = limit
      @written = 0
    end

    def write(data)
      if data.size + @written > @limit
        raise FileOverflow, "You tried to feed more data than fits in the file."
      end
      @io.write data
      @written += data.size
      data.size
    end

  end

  class RestrictedStream

    def initialize(io)
      @io = io
    end

    def write(data)
      @io.write data
    end

  end

  def self.new(io)
    writer = super

    return writer unless block_given?

    begin
      yield writer
    ensure
      writer.close
    end

    nil
  end

  def initialize(io)
    @io = io
    @closed = false
  end

  def add_file(name, mode)
    check_closed

    raise Gem::Package::NonSeekableIO unless @io.respond_to? :pos=

    name, prefix = split_name name

    init_pos = @io.pos
    @io.write "\0" * 512 # placeholder for the header

    yield RestrictedStream.new(@io) if block_given?

    size = @io.pos - init_pos - 512

    remainder = (512 - (size % 512)) % 512
    @io.write "\0" * remainder

    final_pos = @io.pos
    @io.pos = init_pos

    header = Gem::Package::TarHeader.new :name => name, :mode => mode,
                                         :size => size, :prefix => prefix

    @io.write header
    @io.pos = final_pos

    self
  end

  def add_file_simple(name, mode, size)
    check_closed

    name, prefix = split_name name

    header = Gem::Package::TarHeader.new(:name => name, :mode => mode,
                                         :size => size, :prefix => prefix).to_s

    @io.write header
    os = BoundedStream.new @io, size

    yield os if block_given?

    min_padding = size - os.written
    @io.write("\0" * min_padding)

    remainder = (512 - (size % 512)) % 512
    @io.write("\0" * remainder)

    self
  end

  def check_closed
    raise IOError, "closed #{self.class}" if closed?
  end

  def close
    check_closed

    @io.write "\0" * 1024
    flush

    @closed = true
  end

  def closed?
    @closed
  end

  def flush
    check_closed

    @io.flush if @io.respond_to? :flush
  end

  def mkdir(name, mode)
    check_closed

    name, prefix = split_name(name)

    header = Gem::Package::TarHeader.new :name => name, :mode => mode,
                                         :typeflag => "5", :size => 0,
                                         :prefix => prefix

    @io.write header

    self
  end

  def split_name(name) # :nodoc:
    raise Gem::Package::TooLongFileName if name.size > 256

    if name.size <= 100 then
      prefix = ""
    else
      parts = name.split(/\//)
      newname = parts.pop
      nxt = ""

      loop do
        nxt = parts.pop
        break if newname.size + 1 + nxt.size > 100
        newname = nxt + "/" + newname
      end

      prefix = (parts + [nxt]).join "/"
      name = newname

      if name.size > 100 or prefix.size > 155 then
        raise Gem::Package::TooLongFileName 
      end
    end

    return name, prefix
  end

end

