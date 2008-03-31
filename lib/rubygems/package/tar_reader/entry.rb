#++
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#--

require 'rubygems/package'

class Gem::Package::TarReader::Entry

  attr_reader :header

  def initialize(header, io)
    @closed = false
    @header = header
    @io = io
    @orig_pos = @io.pos
    @read = 0
  end

  def check_closed # :nodoc:
    raise IOError, "closed #{self.class}" if closed?
  end

  def bytes_read
    @read
  end

  def close
    @closed = true
  end

  def closed?
    @closed
  end

  def eof?
    check_closed

    @read >= @header.size
  end

  def full_name
    if @header.prefix != "" then
      File.join @header.prefix, @header.name
    else
      @header.name
    end
  end

  def getc
    check_closed

    return nil if @read >= @header.size

    ret = @io.getc
    @read += 1 if ret

    ret
  end

  def directory?
    @header.typeflag == "5"
  end

  def file?
    @header.typeflag == "0"
  end

  def pos
    check_closed

    bytes_read
  end

  def read(len = nil)
    check_closed

    return nil if @read >= @header.size

    len ||= @header.size - @read
    max_read = [len, @header.size - @read].min

    ret = @io.read max_read
    @read += ret.size

    ret
  end

  def rewind
    check_closed

    raise Gem::Package::NonSeekableIO unless @io.respond_to? :pos=

    @io.pos = @orig_pos
    @read = 0
  end

end

