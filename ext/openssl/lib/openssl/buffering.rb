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

module OpenSSL
module Buffering
  include Enumerable
  attr_accessor :sync
  BLOCK_SIZE = 1024*16

  def initialize(*args)
    @eof = false
    @rbuffer = ""
    @sync = @io.sync
  end

  #
  # for reading.
  #
  private

  def fill_rbuff
    begin
      @rbuffer << self.sysread(BLOCK_SIZE)
    rescue Errno::EAGAIN
      retry
    rescue EOFError
      @eof = true
    end
  end

  def consume_rbuff(size=nil)
    if @rbuffer.empty?
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
    if size == 0
      if buf
        buf.clear
        return buf
      else
        return ""
      end
    end
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

  def readpartial(maxlen, buf=nil)
    if maxlen == 0
      if buf
        buf.clear
        return buf
      else
        return ""
      end
    end
    if @rbuffer.empty?
      begin
        return sysread(maxlen, buf)
      rescue Errno::EAGAIN
        retry
      end
    end
    ret = consume_rbuff(maxlen)
    if buf
      buf.replace(ret)
      ret = buf
    end
    raise EOFError if ret.empty?
    ret
  end

  # Reads at most _maxlen_ bytes in the non-blocking manner.
  #
  # When no data can be read without blocking,
  # It raises OpenSSL::SSL::SSLError extended by
  # IO::WaitReadable or IO::WaitWritable.
  #
  # IO::WaitReadable means SSL needs to read internally.
  # So read_nonblock should be called again after
  # underlying IO is readable.
  #
  # IO::WaitWritable means SSL needs to write internally.
  # So read_nonblock should be called again after
  # underlying IO is writable.
  #
  # So OpenSSL::Buffering#read_nonblock needs two rescue clause as follows.
  # 
  #  # emulates blocking read (readpartial).
  #  begin
  #    result = ssl.read_nonblock(maxlen)
  #  rescue IO::WaitReadable
  #    IO.select([io])
  #    retry
  #  rescue IO::WaitWritable
  #    IO.select(nil, [io])
  #    retry
  #  end
  #
  # Note that one reason that read_nonblock write to a underlying IO
  # is the peer requests a new TLS/SSL handshake.
  # See openssl FAQ for more details.
  # http://www.openssl.org/support/faq.html
  #
  def read_nonblock(maxlen, buf=nil)
    if maxlen == 0
      if buf
        buf.clear
        return buf
      else
        return ""
      end
    end
    if @rbuffer.empty?
      return sysread_nonblock(maxlen, buf)
    end
    ret = consume_rbuff(maxlen)
    if buf
      buf.replace(ret)
      ret = buf
    end
    raise EOFError if ret.empty?
    ret
  end

  def gets(eol=$/, limit=nil)
    idx = @rbuffer.index(eol)
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
    if limit and limit >= 0
      size = [size, limit].min
    end
    consume_rbuff(size)
  end

  def each(eol=$/)
    while line = self.gets(eol)
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
    raise EOFError if eof?
    gets(eol)
  end

  def getc
    c = read(1)
    c ? c[0] : nil
  end

  def each_byte
    while c = getc
      yield(c)
    end
  end

  def readchar
    raise EOFError if eof?
    getc
  end

  def ungetc(c)
    @rbuffer[0,0] = c.chr
  end

  def eof?
    fill_rbuff if !@eof && @rbuffer.empty?
    @eof && @rbuffer.empty?
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
        str = @wbuffer[nwritten,remain]
        begin
          nwrote = syswrite(str)
        rescue Errno::EAGAIN
          retry
        end
        remain -= nwrote
        nwritten += nwrote
      end
      @wbuffer[0,nwritten] = ""
    end
  end

  public

  def write(s)
    do_write(s)
    s.length
  end

  # Writes _str_ in the non-blocking manner.
  #
  # If there are buffered data, it is flushed at first.
  # This may block.
  #
  # write_nonblock returns number of bytes written to the SSL connection.
  #
  # When no data can be written without blocking,
  # It raises OpenSSL::SSL::SSLError extended by
  # IO::WaitReadable or IO::WaitWritable.
  #
  # IO::WaitReadable means SSL needs to read internally.
  # So write_nonblock should be called again after
  # underlying IO is readable.
  #
  # IO::WaitWritable means SSL needs to write internally.
  # So write_nonblock should be called again after
  # underlying IO is writable.
  #
  # So OpenSSL::Buffering#write_nonblock needs two rescue clause as follows.
  # 
  #  # emulates blocking write.
  #  begin
  #    result = ssl.write_nonblock(str)
  #  rescue IO::WaitReadable
  #    IO.select([io])
  #    retry
  #  rescue IO::WaitWritable
  #    IO.select(nil, [io])
  #    retry
  #  end
  #
  # Note that one reason that write_nonblock read from a underlying IO
  # is the peer requests a new TLS/SSL handshake.
  # See openssl FAQ for more details.
  # http://www.openssl.org/support/faq.html
  #
  def write_nonblock(s)
    flush
    syswrite_nonblock(s)
  end

  def << (s)
    do_write(s)
    self
  end

  def puts(*args)
    s = ""
    if args.empty?
      s << "\n"
    end
    args.each{|arg|
      s << arg.to_s
      if $/ && /\n\z/ !~ s
        s << "\n"
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
    return self
  ensure
    @sync = osync
  end

  def close
    flush rescue nil
    sysclose
  end
end
end
