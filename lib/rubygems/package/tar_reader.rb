#++
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#--

require 'rubygems/package'

class Gem::Package::TarReader

  include Gem::Package

  class UnexpectedEOF < StandardError; end

  def self.new(io)
    reader = super

    return reader unless block_given?

    begin
      yield reader
    ensure
      reader.close
    end

    nil
  end

  def initialize(io)
    @io = io
    @init_pos = io.pos
  end

  def close
  end

  def each
    loop do
      return if @io.eof?

      header = Gem::Package::TarHeader.from @io
      return if header.empty?

      entry = Gem::Package::TarReader::Entry.new header, @io
      size = entry.header.size

      yield entry

      skip = (512 - (size % 512)) % 512
      pending = size - entry.bytes_read

      begin
        # avoid reading...
        @io.seek pending, IO::SEEK_CUR
        pending = 0
      rescue Errno::EINVAL, NameError
        while pending > 0 do
          bytes_read = @io.read([pending, 4096].min).size
          raise UnexpectedEOF if @io.eof?
          pending -= bytes_read
        end
      end

      @io.read skip # discard trailing zeros

      # make sure nobody can use #read, #getc or #rewind anymore
      entry.close
    end
  end

  alias each_entry each

  ##
  # NOTE: Do not call #rewind during #each

  def rewind
    if @init_pos == 0 then
      raise Gem::Package::NonSeekableIO unless @io.respond_to? :rewind
      @io.rewind
    else
      raise Gem::Package::NonSeekableIO unless @io.respond_to? :pos=
      @io.pos = @init_pos
    end
  end

end

