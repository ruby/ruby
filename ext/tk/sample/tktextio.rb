#!/usr/bin/env ruby
#
#  sample class of handling I/O stream on a TkText widget
#                                               by Hidetoshi NAGAI
#
#  NOTE: TkTextIO supports 'character' (not 'byte') access only. 
#        So, for example, TkTextIO#getc returns a character, TkTextIO#pos 
#        means the character position, TkTextIO#read(size) counts by 
#        characters, and so on.
#        Of course, it is available to make TkTextIO class to suuport 
#        'byte' access. However, it may break multi-byte characters. 
#        and then, displayed string on the text widget may be garbled.
#        I think that it is not good on the supposed situation of using 
#        TkTextIO. 
#
require 'tk'

class TkTextIO < TkText
  def create_self(keys)
    mode = nil
    wrap = 'char'
    if keys.kind_of?(Hash)
      mode = keys.delete('mode')
      wrap = nil if keys.has_key?('wrap')
    end

    super(keys)

    self['wrap'] = wrap if wrap

    @open  = {:r => true,  :w => true}
    @close = {:r => false, :w => false}
    @txtpos = TkTextMark.new(self, '1.0')
    @sync = true
    @lineno = 0
    @line_offset = 0
    @count_var = TkVariable.new

    case mode
    when 'r'
      @open[:r] = true;  @open[:w] = false

    when 'r+'
      @open[:r] = true;  @open[:w] = true

    when 'w'
      @open[:r] = false; @open[:w] = true
      self.value=''

    when 'w+'
      @open[:r] = true;  @open[:w] = true
      self.value=''

    when 'a'
      @open[:r] = false; @open[:w] = true
      @txtpos.set('end - 1 char')

    when 'a+'
      @open[:r] = true;  @open[:w] = true
      @txtpos.set('end - 1 char')
    end
  end

  def <<(obj)
    _write(obj)
    self
  end

  def binmode
    self
  end

  def clone
    fail NotImplementedError, 'cannot clone TkTextIO'
  end
  def dup
    fail NotImplementedError, 'cannot duplicate TkTextIO'
  end

  def close
    @close[:r] = true; @close[:w] = true
    nil
  end
  def close_read
    @close[:r] = true
    nil
  end
  def close_write
    @close[:w] = true
    nil
  end

  def closed?
    @close[:r] && @close[:w]
  end
  def closed_read?
    @close[:r]
  end
  def closed_write?
    @close[:w]
  end

  def _check_readable
    fail IOError, "not opened for reading" unless @open[:r]
    fail IOError, "closed stream" if @close[:r]
  end
  def _check_writable
    fail IOError, "not opened for writing" unless @open[:w]
    fail IOError, "closed stream" if @close[:w]
  end
  private :_check_readable, :_check_writable

  def each_line(rs = $/)
    _check_readable
    while(s = gets)
      yield(s)
    end
    self
  end
  alias each each_line

  def each_char
    _check_readable
    while(c = getc)
      yield(c)
    end
    self
  end
  alias each_byte each_char

  def eof?
    compare(@txtpos, '==', 'end - 1 char')
  end
  alias eof eof?

  def fcntl(*args)
    fail NotImplementedError, 'fcntl is not implemented on TkTextIO'
  end

  def fsync
    0
  end

  def fileno
    nil
  end

  def flush
    Tk.update if @open[:w] && @sync
    self
  end

  def getc
    _check_readable
    return nil if eof?
    c = get(@txtpos)
    @txtpos.set(@txtpos + '1 char')
    c
  end

  def gets(rs = $/)
    _check_readable
   return nil if eof?
    _readline(rs)
  end

  def ioctrl(*args)
    fail NotImplementedError, 'iocntl is not implemented on TkTextIO'
  end

  def isatty
    false
  end
  def tty?
    false
  end

  def lineno
    @lineno + @line_offset
  end

  def lineno=(num)
    @line_offset = num - @lineno
    num
  end

  def pid
    nil
  end

  def index_pos
    index(@txtpos)
  end
  alias tell_index index_pos

  def pos
    s = get('1.0', @txtpos)
    tk_call('string', 'length', s)
  end
  alias tell pos

  def pos=(idx)
    # @txtpos.set((idx.kind_of?(Numeric))? "1.0 + #{idx} char": idx)
    seek(idx, IO::SEEK_SET)
    idx
  end

  def print(arg=$_, *args)
    _check_writable
    args.unshift(arg)
    args.map!{|val| (val == nil)? 'nil': val.to_s }
    str = args.join($,)
    str << $\ if $\
    _write(str)
    nil
  end
  def printf(*args)
    _check_writable
    _write(sprintf(*args))
    nil
  end

  def putc(c)
    _check_writable
    c = c.chr if c.kind_of?(Fixnum)
    _write(c)
    c
  end

  def puts(*args)
    _check_writable
    if args.empty?
      _write("\n")
      return nil
    end
    args.each{|arg|
      if arg == nil
        _write("nil\n")
      elsif arg.kind_of?(Array)
        puts(*arg)
      elsif arg.kind_of?(String)
        _write(arg.chomp)
        _write("\n")
      else
        begin
          arg = arg.to_ary
          puts(*arg)
        rescue
          puts(arg.to_s)
        end
      end
    }
    nil
  end

  def _read(len)
    epos = @txtpos + "#{len} char"
    s = get(@txtpos, epos)
    @txtpos.set(epos)
    s
  end
  private :_read

  def read(len=nil, buf=nil)
    _check_readable
    if len
      return "" if len == 0
      return nil if eof?
      s = _read(len)
    else
      s = get(@txtpos, 'end - 1 char')
      @txtpos.set('end - 1 char')
    end
    buf.replace(s) if buf.kind_of?(String)
    s
  end

  def readchar
    _check_readable
    fail EOFError if eof?
    c = get(@txtpos)
    @txtpos.set(@txtpos + '1 char')
    c
  end

  def _readline(rs = $/)
    if rs == nil
      s = get(@txtpos, 'end - 1 char')
      @txtpos.set('end - 1 char')
    elsif rs == ''
      idx = tksearch_with_count([:regexp], @count_var, 
                                   "\n(\n)+", @txtpos, 'end - 1 char')
      if idx
        s = get(@txtpos, idx) << "\n"
        @txtpos.set("#{idx} + #{@count_var.value} char")
      else
        s = get(@txtpos, 'end - 1 char')
        @txtpos.set('end - 1 char')
      end
    else
      idx = tksearch_with_count(@count_var, rs, @txtpos, 'end - 1 char')
      if idx
        s = get(@txtpos, "#{idx} + #{@count_var.value} char")
        @txtpos.set("#{idx} + #{@count_var.value} char")
      else
        s = get(@txtpos, 'end - 1 char')
        @txtpos.set('end - 1 char')
      end
    end

    @lineno += 1
    $_ = s
  end
  private :_readline

  def readline(rs = $/)
    _check_readable
    fail EOFError if eof?
    _readline(rs)
  end

  def readlines(rs = $/)
    _check_readable
    lines = []
    until(eof?)
      lines << _readline(rs)
    end
    $_ = nil
    lines
  end

  def readpartial(maxlen, buf=nil)
    _check_readable
    s = _read(maxlen)
    buf.replace(s) if buf.kind_of?(String)
    s
  end

  def reopen(*args)
    fail NotImplementedError, 'reopen is not implemented on TkTextIO'
  end

  def rewind
    @txtpos.set('1.0')
    @lineno = 0
    @line_offset = 0
    self
  end

  def seek(offset, whence=IO::SEEK_SET)
    case whence
    when IO::SEEK_SET
      offset = "1.0 + #{offset} char" if offset.kind_of?(Numeric)
      @txtpos.set(offset)

    when IO::SEEK_CUR
      offset = "#{offset} char" if offset.kind_of?(Numeric)
      @txtpos.set(@txtpos + offset)

    when IO::SEEK_END
      offset = "#{offset} char" if offset.kind_of?(Numeric)
      @txtpos.set("end - 1 char + #{offset}")

    else
      fail Errno::EINVAL, 'invalid whence argument'
    end

    0
  end
  alias sysseek seek

  def stat
    fail NotImplementedError, 'stat is not implemented on TkTextIO'
  end

  def sync
    @sync
  end

  def sync=(mode)
    @sync = mode
  end

  def sysread(len, buf=nil)
    _check_readable
    fail EOFError if eof?
    s = _read(len)
    buf.replace(s) if buf.kind_of?(String)
    s
  end

  def syswrite(obj)
    _write(obj)
  end

  def to_io
    self
  end

  def trancate(len)
    delete("1.0 + #{len} char", :end)
    0
  end

  def ungetc(c)
    _check_readable
    c = c.chr if c.kind_of?(Fixnum)
    if compare(@txtpos, '>', '1.0')
      delete(@txtpos - '1 char')
      insert(@txtpos, tk_call('string', 'range', c, 0, 1))
    end
    nil
  end

  def _write(obj)
    s = _get_eval_string(obj)
    n = number(tk_call('string', 'length', s))
    delete(@txtpos, @txtpos + "#{n} char")
    self.insert(@txtpos, s)
    @txtpos.set(@txtpos + "#{n} char")
    Tk.update if @sync
    n
  end
  private :_write

  def write(obj)
    _check_writable
    _write(obj)
  end
end

####################
#  TEST
####################
if __FILE__ == $0
  f = TkFrame.new.pack
  tio = TkTextIO.new(f){
    yscrollbar(TkScrollbar.new(f).pack(:side=>:right, :fill=>:y))
    pack(:side=>:left, :fill=>:both, :expand=>true)
  }

  $stdin  = tio
  $stdout = tio
  $stderr = tio

  puts "On this sample, a text widget works as if it is a I/O stream."
  puts "Please see the code."
  puts
  printf("printf message: %d %X\n", 123456, 255);
  puts
  p tio
  puts
  warn("This is a warning message generated by 'warn' method.\n")
  puts
  print("---------------------------------------------------------\n")

  STDOUT.print("\n=============== TkTextIO#readlines =============\n\n")

  tio.seek(0)
  lines = readlines
  STDOUT.puts(lines)

  STDOUT.print("\n================== TkTextIO#each ===============\n\n")

  tio.rewind
  tio.each{|line| STDOUT.printf("%2d: %s\n", tio.lineno, line.chomp)}

  STDOUT.print("\n================================================\n\n")

  Tk.mainloop
end
