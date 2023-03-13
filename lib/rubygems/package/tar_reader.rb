# frozen_string_literal: true
#--
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#++

##
# TarReader reads tar files and allows iteration over their items

class Gem::Package::TarReader
  include Enumerable

  ##
  # Raised if the tar IO is not seekable

  class UnexpectedEOF < StandardError; end

  ##
  # Creates a new TarReader on +io+ and yields it to the block, if given.

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

  ##
  # Creates a new tar file reader on +io+ which needs to respond to #pos,
  # #eof?, #read, #getc and #pos=

  def initialize(io)
    @io = io
    @init_pos = io.pos
  end

  ##
  # Close the tar file

  def close
  end

  ##
  # Iterates over files in the tarball yielding each entry

  def each
    return enum_for __method__ unless block_given?

    until @io.eof? do
      header = Gem::Package::TarHeader.from @io
      return if header.empty?
      entry = Gem::Package::TarReader::Entry.new header, @io
      yield entry
      entry.close
    end
  end

  alias each_entry each

  ##
  # NOTE: Do not call #rewind during #each

  def rewind
    if @init_pos == 0
      @io.rewind
    else
      @io.pos = @init_pos
    end
  end

  ##
  # Seeks through the tar file until it finds the +entry+ with +name+ and
  # yields it.  Rewinds the tar file to the beginning when the block
  # terminates.

  def seek(name) # :yields: entry
    found = find do |entry|
      entry.full_name == name
    end

    return unless found

    return yield found
  ensure
    rewind
  end
end

require_relative "tar_reader/entry"
