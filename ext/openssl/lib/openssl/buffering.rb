=begin
= $RCSfile$ -- Buffering mix-in module.

= Info
  'OpenSSL for Ruby 2' project
  Copyright (C) 2001 GOTOU YUUZOU <gotoyuzo@notwork.org>
  All rights reserved.

= Licence
  This program is licenced under the same licence as Ruby.
  (See the file 'LICENCE'.)

= Version
  $Id$
=end

module Buffering
  include Enumerable
  attr_accessor :sync
  BLOCK_SIZE = 1024*16

  def initialize(*args)
    @sync = @io.sync
  end

  #
  # for reading.
  #
  private

  def fill_rbuff
    @rbuffer = "" unless defined? @rbuffer
    begin
      @rbuffer << self.sysread(BLOCK_SIZE)
    rescue EOFError
      @eof = true
    end
  end

  def consume_rbuff(size=nil)
    if @rbuffer.size == 0
      @eof = nil
      nil
    else
      size = @rbuffer.size unless size
      ret = @rbuffer[0, size]
      @rbuffer[0, size] = ""
      ret
    end
  end

  public

  def read(size=nil, buf=nil)
    fill_rbuff unless defined? @rbuffer
    @eof ||= nil
    until @eof
      break if size && size <= @rbuffer.size
      fill_rbuff
    end
    ret = consume_rbuff(size) || ""
    if buf
      buf.replace(ret)
      ret = buf
    end
    (size && ret.empty?) ? nil : ret
  end

  def gets(eol=$/)
    fill_rbuff unless defined? @rbuffer
    idx = @rbuffer.index(eol)
    @eof ||= nil
    until @eof
      break if idx
      fill_rbuff
      idx = @rbuffer.index(eol)
    end
    if eol.is_a?(Regexp)
      size = idx ? idx+$&.size : nil
    else
      size = idx ? idx+eol.size : nil
    end
    consume_rbuff(size)
  end

  def each(eol=$/)
    while line = self.gets(eol?)
      yield line
    end
  end
  alias each_line each

  def readlines(eol=$/)
    ary = []
    while line = self.gets(eol)
      ary << line
    end
    ary
  end

  def readline(eol=$/)
    raise EOFErorr if eof?
    gets(eol)
  end

  def getc
    c = read(1)
    c ? c.to_i : nil
  end

  def each_byte
    while c = getc
      yield(c)
    end
  end

  def readchar
    raise EOFErorr if eof?
    getc
  end

  def ungetc(c)
    @rbuffer[0,0] = c.chr
  end

  def eof?
    @eof ||= nil
    @eof && @rbuffer.size == 0
  end
  alias eof eof?

  #
  # for writing.
  #
  private

  def do_write(s)
    @wbuffer = "" unless defined? @wbuffer
    @wbuffer << s
    @sync ||= false
    if @sync or @wbuffer.size > BLOCK_SIZE or idx = @wbuffer.rindex($/)
      remain = idx ? idx + $/.size : @wbuffer.length
      nwritten = 0
      while remain > 0
        nwrote = syswrite(@wbuffer[nwritten,remain])
        remain -= nwrote
        nwritten += nwrote
      end
      @wbuffer = ""
    end
  end

  public

  def write(s)
    do_write(s)
    s.length
  end

  def << (s)
    do_write(s)
    self
  end

  def puts(*args)
    s = ""
    args.each{|arg|
      s << arg.to_s
      unless /#{$/}\z/o =~ s
        s << $/
      end
    }
    do_write(s)
    nil
  end

  def print(*args)
    s = ""
    args.each{ |arg| s << arg.to_s }
    do_write(s)
    nil
  end

  def printf(s, *args)
    do_write(s % args)
    nil
  end

  def flush
    osync = @sync
    @sync = true
    do_write ""
    @sync = osync
  end

  def close
    flush rescue nil
    sysclose
  end
end
