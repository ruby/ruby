# frozen_string_literal: false
require 'test/unit'
require 'stringio'
require "rbconfig/sizeof"
require_relative '../ruby/ut_eof'

class TestStringIO < Test::Unit::TestCase
  include TestEOF
  def open_file(content)
    f = StringIO.new(content)
    yield f
  end
  alias open_file_rw open_file

  include TestEOF::Seek

  def test_initialize
    assert_kind_of StringIO, StringIO.new
    assert_kind_of StringIO, StringIO.new('str')
    assert_kind_of StringIO, StringIO.new('str', 'r+')
    assert_raise(ArgumentError) { StringIO.new('', 'x') }
    assert_raise(ArgumentError) { StringIO.new('', 'rx') }
    assert_raise(ArgumentError) { StringIO.new('', 'rbt') }
    assert_raise(TypeError) { StringIO.new(nil) }

    o = Object.new
    def o.to_str
      nil
    end
    assert_raise(TypeError) { StringIO.new(o) }

    o = Object.new
    def o.to_str
      'str'
    end
    assert_kind_of StringIO, StringIO.new(o)
  end

  def test_truncate
    io = StringIO.new("")
    io.puts "abc"
    io.truncate(0)
    io.puts "def"
    assert_equal("\0\0\0\0def\n", io.string, "[ruby-dev:24190]")
    assert_raise(Errno::EINVAL) { io.truncate(-1) }
    io.truncate(10)
    assert_equal("\0\0\0\0def\n\0\0", io.string)
  end

  def test_seek_beyond_eof
    io = StringIO.new
    n = 100
    io.seek(n)
    io.print "last"
    assert_equal("\0" * n + "last", io.string, "[ruby-dev:24194]")
  end

  def test_overwrite
    stringio = StringIO.new
    responses = ['', 'just another ruby', 'hacker']
    responses.each do |resp|
      stringio.puts(resp)
      stringio.rewind
    end
    assert_equal("hacker\nother ruby\n", stringio.string, "[ruby-core:3836]")
  end

  def test_gets
    assert_equal(nil, StringIO.new("").gets)
    assert_equal("\n", StringIO.new("\n").gets)
    assert_equal("a\n", StringIO.new("a\n").gets)
    assert_equal("a\n", StringIO.new("a\nb\n").gets)
    assert_equal("a", StringIO.new("a").gets)
    assert_equal("a\n", StringIO.new("a\nb").gets)
    assert_equal("abc\n", StringIO.new("abc\n\ndef\n").gets)
    assert_equal("abc\n\ndef\n", StringIO.new("abc\n\ndef\n").gets(nil))
    assert_equal("abc\n\n", StringIO.new("abc\n\ndef\n").gets(""))
    stringio = StringIO.new("abc\n\ndef\n")
    assert_equal("abc\n\n", stringio.gets(""))
    assert_equal("def\n", stringio.gets(""))
    assert_raise(TypeError){StringIO.new("").gets(1, 1)}
    assert_nothing_raised {StringIO.new("").gets(nil, nil)}

    assert_string("", Encoding::UTF_8, StringIO.new("foo").gets(0))
  end

  def test_gets_chomp
    assert_equal(nil, StringIO.new("").gets(chomp: true))
    assert_equal("", StringIO.new("\n").gets(chomp: true))
    assert_equal("a", StringIO.new("a\n").gets(chomp: true))
    assert_equal("a", StringIO.new("a\nb\n").gets(chomp: true))
    assert_equal("a", StringIO.new("a").gets(chomp: true))
    assert_equal("a", StringIO.new("a\nb").gets(chomp: true))
    assert_equal("abc", StringIO.new("abc\n\ndef\n").gets(chomp: true))
    assert_equal("abc\n\ndef", StringIO.new("abc\n\ndef\n").gets(nil, chomp: true))
    assert_equal("abc\n", StringIO.new("abc\n\ndef\n").gets("", chomp: true))
    stringio = StringIO.new("abc\n\ndef\n")
    assert_equal("abc\n", stringio.gets("", chomp: true))
    assert_equal("def", stringio.gets("", chomp: true))

    assert_string("", Encoding::UTF_8, StringIO.new("\n").gets(chomp: true))
  end

  def test_gets_chomp_eol
    assert_equal(nil, StringIO.new("").gets(chomp: true))
    assert_equal("", StringIO.new("\r\n").gets(chomp: true))
    assert_equal("a", StringIO.new("a\r\n").gets(chomp: true))
    assert_equal("a", StringIO.new("a\r\nb\r\n").gets(chomp: true))
    assert_equal("a", StringIO.new("a").gets(chomp: true))
    assert_equal("a", StringIO.new("a\r\nb").gets(chomp: true))
    assert_equal("abc", StringIO.new("abc\r\n\r\ndef\r\n").gets(chomp: true))
    assert_equal("abc\r\n\r\ndef", StringIO.new("abc\r\n\r\ndef\r\n").gets(nil, chomp: true))
    assert_equal("abc\r\n", StringIO.new("abc\r\n\r\ndef\r\n").gets("", chomp: true))
    stringio = StringIO.new("abc\r\n\r\ndef\r\n")
    assert_equal("abc\r\n", stringio.gets("", chomp: true))
    assert_equal("def", stringio.gets("", chomp: true))
  end

  def test_readlines
    assert_equal([], StringIO.new("").readlines)
    assert_equal(["\n"], StringIO.new("\n").readlines)
    assert_equal(["a\n"], StringIO.new("a\n").readlines)
    assert_equal(["a\n", "b\n"], StringIO.new("a\nb\n").readlines)
    assert_equal(["a"], StringIO.new("a").readlines)
    assert_equal(["a\n", "b"], StringIO.new("a\nb").readlines)
    assert_equal(["abc\n", "\n", "def\n"], StringIO.new("abc\n\ndef\n").readlines)
    assert_equal(["abc\n\ndef\n"], StringIO.new("abc\n\ndef\n").readlines(nil), "[ruby-dev:34591]")
    assert_equal(["abc\n\n", "def\n"], StringIO.new("abc\n\ndef\n").readlines(""))
  end

  def test_write
    s = ""
    f = StringIO.new(s, "w")
    f.print("foo")
    f.close
    assert_equal("foo", s)

    f = StringIO.new(s, File::WRONLY)
    f.print("bar")
    f.close
    assert_equal("bar", s)

    f = StringIO.new(s, "a")
    o = Object.new
    def o.to_s; "baz"; end
    f.print(o)
    f.close
    assert_equal("barbaz", s)
  ensure
    f.close unless f.closed?
  end

  def test_write_nonblock_no_exceptions
    s = ""
    f = StringIO.new(s, "w")
    f.write_nonblock("foo", exception: false)
    f.close
    assert_equal("foo", s)
  end

  def test_write_nonblock
    s = ""
    f = StringIO.new(s, "w")
    f.write_nonblock("foo")
    f.close
    assert_equal("foo", s)

    f = StringIO.new(s, File::WRONLY)
    f.write_nonblock("bar")
    f.close
    assert_equal("bar", s)

    f = StringIO.new(s, "a")
    o = Object.new
    def o.to_s; "baz"; end
    f.write_nonblock(o)
    f.close
    assert_equal("barbaz", s)
  ensure
    f.close unless f.closed?
  end

  def test_write_encoding
    s = "".force_encoding(Encoding::UTF_8)
    f = StringIO.new(s)
    f.print("\u{3053 3093 306b 3061 306f ff01}".b)
    assert_equal(Encoding::UTF_8, s.encoding, "honor the original encoding over ASCII-8BIT")
  end

  def test_write_encoding_conversion
    convertible = "\u{3042}"
    inconvertible = "\u{1f363}"
    conversion_encoding = Encoding::Windows_31J

    s = StringIO.new.set_encoding(conversion_encoding)
    s.write(convertible)
    assert_equal(conversion_encoding, s.string.encoding)
    s = StringIO.new.set_encoding(Encoding::UTF_8)
    s.write("foo".force_encoding("ISO-8859-1"), convertible)
    assert_equal(Encoding::UTF_8, s.string.encoding)
    all_assertions do |a|
      [
        inconvertible,
        convertible + inconvertible,
        [convertible, inconvertible],
        ["a", inconvertible],
      ].each do |data|
        a.for(data.inspect) do
          s = StringIO.new.set_encoding(conversion_encoding)
          assert_raise(Encoding::CompatibilityError) do
            s.write(*data)
          end
        end
      end
    end
  end

  def test_write_integer_overflow
    f = StringIO.new
    f.pos = RbConfig::LIMITS["LONG_MAX"]
    assert_raise(ArgumentError) {
      f.write("pos + len overflows")
    }
  end

  def test_write_with_multiple_arguments
    s = ""
    f = StringIO.new(s, "w")
    f.write("foo", "bar")
    f.close
    assert_equal("foobar", s)
  ensure
    f.close unless f.closed?
  end

  def test_set_encoding
    bug10285 = '[ruby-core:65240] [Bug #10285]'
    f = StringIO.new()
    f.set_encoding(Encoding::ASCII_8BIT)
    f.write("quz \x83 mat".b)
    s = "foo \x97 bar".force_encoding(Encoding::WINDOWS_1252)
    assert_nothing_raised(Encoding::CompatibilityError, bug10285) {
      f.write(s)
    }
    assert_equal(Encoding::ASCII_8BIT, f.string.encoding, bug10285)

    bug11827 = '[ruby-core:72189] [Bug #11827]'
    f = StringIO.new("foo\x83".freeze)
    assert_nothing_raised(RuntimeError, bug11827) {
      f.set_encoding(Encoding::ASCII_8BIT)
    }
    assert_equal("foo\x83".b, f.gets)
  end

  def test_mode_error
    f = StringIO.new("", "r")
    assert_raise(IOError) { f.write("foo") }

    f = StringIO.new("", "w")
    assert_raise(IOError) { f.read }

    assert_raise(Errno::EACCES) { StringIO.new("".freeze, "w") }
    s = ""
    f = StringIO.new(s, "w")
    s.freeze
    assert_raise(IOError) { f.write("foo") }

    assert_raise(IOError) { StringIO.allocate.read }
  ensure
    f.close unless f.closed?
  end

  def test_open
    s = ""
    StringIO.open("foo") {|f| s = f.read }
    assert_equal("foo", s)
  end

  def test_isatty
    assert_equal(false, StringIO.new("").isatty)
  end

  def test_fsync
    assert_equal(0, StringIO.new("").fsync)
  end

  def test_sync
    assert_equal(true, StringIO.new("").sync)
    assert_equal(false, StringIO.new("").sync = false)
  end

  def test_set_fcntl
    assert_raise(NotImplementedError) { StringIO.new("").fcntl }
  end

  def test_close
    f = StringIO.new("")
    f.close
    assert_nil(f.close)

    f = StringIO.new("")
    f.close_read
    f.close_write
    assert_nil(f.close)
  ensure
    f.close unless f.closed?
  end

  def test_close_read
    f = StringIO.new("")
    f.close_read
    assert_raise(IOError) { f.read }
    assert_nothing_raised(IOError) {f.close_read}
    f.close

    f = StringIO.new("", "w")
    assert_raise(IOError) { f.close_read }
    f.close
  ensure
    f.close unless f.closed?
  end

  def test_close_write
    f = StringIO.new("")
    f.close_write
    assert_raise(IOError) { f.write("foo") }
    assert_nothing_raised(IOError) {f.close_write}
    f.close

    f = StringIO.new("", "r")
    assert_raise(IOError) { f.close_write }
    f.close
  ensure
    f.close unless f.closed?
  end

  def test_closed
    f = StringIO.new("")
    assert_equal(false, f.closed?)
    f.close
    assert_equal(true, f.closed?)
  ensure
    f.close unless f.closed?
  end

  def test_closed_read
    f = StringIO.new("")
    assert_equal(false, f.closed_read?)
    f.close_write
    assert_equal(false, f.closed_read?)
    f.close_read
    assert_equal(true, f.closed_read?)
  ensure
    f.close unless f.closed?
  end

  def test_closed_write
    f = StringIO.new("")
    assert_equal(false, f.closed_write?)
    f.close_read
    assert_equal(false, f.closed_write?)
    f.close_write
    assert_equal(true, f.closed_write?)
  ensure
    f.close unless f.closed?
  end

  def test_dup
    f1 = StringIO.new("1234")
    assert_equal("1", f1.getc)
    f2 = f1.dup
    assert_equal("2", f2.getc)
    assert_equal("3", f1.getc)
    assert_equal("4", f2.getc)
    assert_equal(nil, f1.getc)
    assert_equal(true, f2.eof?)
    f1.close
    assert_equal(false, f2.closed?, '[ruby-core:48443]')
  ensure
    f1.close unless f1.closed?
    f2.close unless f2.closed?
  end

  def test_lineno
    f = StringIO.new("foo\nbar\nbaz\n")
    assert_equal([0, "foo\n"], [f.lineno, f.gets])
    assert_equal([1, "bar\n"], [f.lineno, f.gets])
    f.lineno = 1000
    assert_equal([1000, "baz\n"], [f.lineno, f.gets])
    assert_equal([1001, nil], [f.lineno, f.gets])
  ensure
    f.close unless f.closed?
  end

  def test_pos
    f = StringIO.new("foo\nbar\nbaz\n")
    assert_equal([0, "foo\n"], [f.pos, f.gets])
    assert_equal([4, "bar\n"], [f.pos, f.gets])
    assert_raise(Errno::EINVAL) { f.pos = -1 }
    f.pos = 1
    assert_equal([1, "oo\n"], [f.pos, f.gets])
    assert_equal([4, "bar\n"], [f.pos, f.gets])
    assert_equal([8, "baz\n"], [f.pos, f.gets])
    assert_equal([12, nil], [f.pos, f.gets])
  ensure
    f.close unless f.closed?
  end

  def test_reopen
    f = StringIO.new("foo\nbar\nbaz\n")
    assert_equal("foo\n", f.gets)
    f.reopen("qux\nquux\nquuux\n")
    assert_equal("qux\n", f.gets)

    f2 = StringIO.new("")
    f2.reopen(f)
    assert_equal("quux\n", f2.gets)
  ensure
    f.close unless f.closed?
  end

  def test_seek
    f = StringIO.new("1234")
    assert_raise(Errno::EINVAL) { f.seek(-1) }
    f.seek(-1, 2)
    assert_equal("4", f.getc)
    assert_raise(Errno::EINVAL) { f.seek(1, 3) }
    f.close
    assert_raise(IOError) { f.seek(0) }
  ensure
    f.close unless f.closed?
  end

  def test_each_byte
    f = StringIO.new("1234")
    a = []
    f.each_byte {|c| a << c }
    assert_equal(%w(1 2 3 4).map {|c| c.ord }, a)
  ensure
    f.close unless f.closed?
  end

  def test_getbyte
    f = StringIO.new("1234")
    assert_equal("1".ord, f.getbyte)
    assert_equal("2".ord, f.getbyte)
    assert_equal("3".ord, f.getbyte)
    assert_equal("4".ord, f.getbyte)
    assert_equal(nil, f.getbyte)
  ensure
    f.close unless f.closed?
  end

  def test_ungetbyte
    s = "foo\nbar\n"
    t = StringIO.new(s, "r")
    t.ungetbyte(0x41)
    assert_equal(0x41, t.getbyte)
    t.ungetbyte("qux")
    assert_equal("quxfoo\n", t.gets)
    t.set_encoding("utf-8")
    t.ungetbyte(0x89)
    t.ungetbyte(0x8e)
    t.ungetbyte("\xe7")
    t.ungetbyte("\xe7\xb4\x85")
    assert_equal("\u7d05\u7389bar\n", t.gets)
    assert_equal("q\u7d05\u7389bar\n", s)
    t.pos = 1
    t.ungetbyte("\u{30eb 30d3 30fc}")
    assert_equal(0, t.pos)
    assert_equal("\u{30eb 30d3 30fc}\u7d05\u7389bar\n", s)

    assert_nothing_raised {t.ungetbyte(-1)}
    assert_nothing_raised {t.ungetbyte(256)}
    assert_nothing_raised {t.ungetbyte(1<<64)}
  end

  def test_ungetc
    s = "1234"
    f = StringIO.new(s, "r")
    assert_nothing_raised { f.ungetc("x") }
    assert_equal("x", f.getc) # bug? -> it's a feature from 1.9.
    assert_equal("1", f.getc)

    s = "1234"
    f = StringIO.new(s, "r")
    assert_equal("1", f.getc)
    f.ungetc("y".ord)
    assert_equal("y", f.getc)
    assert_equal("2", f.getc)

    assert_raise(RangeError) {f.ungetc(0x1ffffff)}
    assert_raise(RangeError) {f.ungetc(0xffffffffffffff)}
  ensure
    f.close unless f.closed?
  end

  def test_readchar
    f = StringIO.new("1234")
    a = ""
    assert_raise(EOFError) { loop { a << f.readchar } }
    assert_equal("1234", a)
  end

  def test_readbyte
    f = StringIO.new("1234")
    a = []
    assert_raise(EOFError) { loop { a << f.readbyte } }
    assert_equal("1234".unpack("C*"), a)
  end

  def test_each_char
    f = StringIO.new("1234")
    assert_equal(%w(1 2 3 4), f.each_char.to_a)
  end

  def test_each_codepoint
    f = StringIO.new("1234")
    assert_equal([49, 50, 51, 52], f.each_codepoint.to_a)
  end

  def test_gets2
    f = StringIO.new("foo\nbar\nbaz\n")
    assert_equal("fo", f.gets(2))

    o = Object.new
    def o.to_str; "z"; end
    assert_equal("o\nbar\nbaz", f.gets(o))

    f = StringIO.new("foo\nbar\nbaz\n")
    assert_equal("foo\nbar\nbaz", f.gets("az"))
    f = StringIO.new("a" * 10000 + "zz!")
    assert_equal("a" * 10000 + "zz", f.gets("zz"))
    f = StringIO.new("a" * 10000 + "zz!")
    assert_equal("a" * 10000 + "zz!", f.gets("zzz"))

    bug4112 = '[ruby-dev:42674]'
    ["a".encode("utf-16be"), "\u3042"].each do |s|
      assert_equal(s, StringIO.new(s).gets(1), bug4112)
      assert_equal(s, StringIO.new(s).gets(nil, 1), bug4112)
    end
  end

  def test_each
    f = StringIO.new("foo\nbar\nbaz\n")
    assert_equal(["foo\n", "bar\n", "baz\n"], f.each.to_a)
    f.rewind
    assert_equal(["foo", "bar", "baz"], f.each(chomp: true).to_a)
    f = StringIO.new("foo\nbar\n\nbaz\n")
    assert_equal(["foo\nbar\n\n", "baz\n"], f.each("").to_a)
    f.rewind
    assert_equal(["foo\nbar\n", "baz"], f.each("", chomp: true).to_a)

    f = StringIO.new("foo\r\nbar\r\n\r\nbaz\r\n")
    assert_equal(["foo\r\nbar\r\n\r\n", "baz\r\n"], f.each("").to_a)
    f.rewind
    assert_equal(["foo\r\nbar\r\n", "baz"], f.each("", chomp: true).to_a)
  end

  def test_putc
    s = ""
    f = StringIO.new(s, "w")
    f.putc("1")
    f.putc("2")
    f.putc("3")
    f.close
    assert_equal("123", s)

    s = "foo"
    f = StringIO.new(s, "a")
    f.putc("1")
    f.putc("2")
    f.putc("3")
    f.close
    assert_equal("foo123", s)
  end

  def test_putc_nonascii
    s = ""
    f = StringIO.new(s, "w")
    f.putc("\u{3042}")
    f.putc(0x3044)
    f.close
    assert_equal("\u{3042}D", s)

    s = "foo"
    f = StringIO.new(s, "a")
    f.putc("\u{3042}")
    f.putc(0x3044)
    f.close
    assert_equal("foo\u{3042}D", s)
  end

  def test_read
    f = StringIO.new("\u3042\u3044")
    assert_raise(ArgumentError) { f.read(-1) }
    assert_raise(ArgumentError) { f.read(1, 2, 3) }
    assert_equal("\u3042\u3044", f.read)
    assert_nil(f.read(1))
    f.rewind
    assert_equal("\u3042\u3044".force_encoding(Encoding::ASCII_8BIT), f.read(f.size))

    bug5207 = '[ruby-core:39026]'
    f.rewind
    assert_equal("\u3042\u3044", f.read(nil, nil), bug5207)
    f.rewind
    s = ""
    assert_same(s, f.read(nil, s))
    assert_equal("\u3042\u3044", s, bug5207)
    f.rewind
    # not empty buffer
    s = "0123456789"
    assert_same(s, f.read(nil, s))
    assert_equal("\u3042\u3044", s)

    bug13806 = '[ruby-core:82349] [Bug #13806]'
    assert_string("", Encoding::UTF_8, f.read, bug13806)
    assert_string("", Encoding::UTF_8, f.read(nil, nil), bug13806)
    s.force_encoding(Encoding::US_ASCII)
    assert_same(s, f.read(nil, s))
    assert_string("", Encoding::UTF_8, s, bug13806)
  end

  def test_readpartial
    f = StringIO.new("\u3042\u3044")
    assert_raise(ArgumentError) { f.readpartial(-1) }
    assert_raise(ArgumentError) { f.readpartial(1, 2, 3) }
    assert_equal("\u3042\u3044".force_encoding(Encoding::ASCII_8BIT), f.readpartial(100))
    f.rewind
    assert_equal("\u3042\u3044".force_encoding(Encoding::ASCII_8BIT), f.readpartial(f.size))
    f.rewind
    # not empty buffer
    s = '0123456789'
    assert_equal("\u3042\u3044".force_encoding(Encoding::ASCII_8BIT), f.readpartial(f.size, s))
  end

  def test_read_nonblock
    f = StringIO.new("\u3042\u3044")
    assert_raise(ArgumentError) { f.read_nonblock(-1) }
    assert_raise(ArgumentError) { f.read_nonblock(1, 2, 3) }
    assert_equal("\u3042\u3044".force_encoding("BINARY"), f.read_nonblock(100))
    assert_raise(EOFError) { f.read_nonblock(10) }
    f.rewind
    assert_equal("\u3042\u3044".force_encoding(Encoding::ASCII_8BIT), f.read_nonblock(f.size))
  end

  def test_read_nonblock_no_exceptions
    f = StringIO.new("\u3042\u3044")
    assert_raise(ArgumentError) { f.read_nonblock(-1, exception: false) }
    assert_raise(ArgumentError) { f.read_nonblock(1, 2, 3, exception: false) }
    assert_raise(ArgumentError) { f.read_nonblock }
    assert_equal("\u3042\u3044".force_encoding(Encoding::ASCII_8BIT), f.read_nonblock(100, exception: false))
    assert_equal(nil, f.read_nonblock(10, exception: false))
    f.rewind
    assert_equal("\u3042\u3044".force_encoding(Encoding::ASCII_8BIT), f.read_nonblock(f.size))
    f.rewind
    # not empty buffer
    s = '0123456789'
    assert_equal("\u3042\u3044".force_encoding(Encoding::ASCII_8BIT), f.read_nonblock(f.size, s))
  end

  def test_sysread
    f = StringIO.new("sysread \u{30c6 30b9 30c8}")
    assert_equal "sysread \u{30c6 30b9 30c8}", f.sysread
    assert_equal "", f.sysread
    assert_raise(EOFError) { f.sysread(1) }
    f.rewind
    assert_equal Encoding::ASCII_8BIT, f.sysread(3).encoding
  end

  def test_size
    f = StringIO.new("1234")
    assert_equal(4, f.size)
  end

  # This test is should in ruby/test_method.rb
  # However this test depends on stringio library,
  # we write it here.
  class C < StringIO
    alias old_init initialize
    attr_reader :foo
    def initialize
      @foo = :ok
      old_init
    end
  end

  def test_method
    assert_equal(:ok, C.new.foo, 'Bug #632 [ruby-core:19282]')
  end

  def test_ungetc_pos
    b = '\\b00010001 \\B00010001 \\b1 \\B1 \\b000100011'
    s = StringIO.new( b )
    expected_pos = 0
    while n = s.getc
      assert_equal( expected_pos + 1, s.pos )

      s.ungetc( n )
      assert_equal( expected_pos, s.pos )
      assert_equal( n, s.getc )

      expected_pos += 1
    end
  end

  def test_ungetc_padding
    s = StringIO.new()
    s.pos = 2
    s.ungetc("a")
    assert_equal("\0""a", s.string)
    s.pos = 0
    s.ungetc("b")
    assert_equal("b""\0""a", s.string)
  end

  def test_ungetbyte_pos
    b = '\\b00010001 \\B00010001 \\b1 \\B1 \\b000100011'
    s = StringIO.new( b )
    expected_pos = 0
    while n = s.getbyte
      assert_equal( expected_pos + 1, s.pos )

      s.ungetbyte( n )
      assert_equal( expected_pos, s.pos )
      assert_equal( n, s.getbyte )

      expected_pos += 1
    end
  end

  def test_ungetbyte_padding
    s = StringIO.new()
    s.pos = 2
    s.ungetbyte("a".ord)
    assert_equal("\0""a", s.string)
    s.pos = 0
    s.ungetbyte("b".ord)
    assert_equal("b""\0""a", s.string)
  end

  def test_frozen
    s = StringIO.new
    s.freeze
    bug = '[ruby-core:33648]'
    exception_class = defined?(FrozenError) ? FrozenError : RuntimeError
    assert_raise(exception_class, bug) {s.puts("foo")}
    assert_raise(exception_class, bug) {s.string = "foo"}
    assert_raise(exception_class, bug) {s.reopen("")}
  end

  def test_frozen_string
    s = StringIO.new("".freeze)
    bug = '[ruby-core:48530]'
    assert_raise(IOError, bug) {s.write("foo")}
    assert_raise(IOError, bug) {s.ungetc("a")}
    assert_raise(IOError, bug) {s.ungetbyte("a")}
  end

  def test_readlines_limit_0
    assert_raise(ArgumentError, "[ruby-dev:43392]") { StringIO.new.readlines(0) }
  end

  def test_each_line_limit_0
    assert_raise(ArgumentError, "[ruby-dev:43392]") { StringIO.new.each_line(0){} }
    assert_raise(ArgumentError, "[ruby-dev:43392]") { StringIO.new.each_line("a",0){} }
  end

  def test_binmode
    s = StringIO.new
    s.set_encoding('utf-8')
    assert_same s, s.binmode

    bug_11945 = '[ruby-core:72699] [Bug #11945]'
    assert_equal Encoding::ASCII_8BIT, s.external_encoding, bug_11945
  end

  def test_new_block_warning
    assert_warn(/does not take block/) do
      StringIO.new {}
    end
  end

  def test_overflow
    skip if RbConfig::SIZEOF["void*"] > RbConfig::SIZEOF["long"]
    limit = RbConfig::LIMITS["INTPTR_MAX"] - 0x10
    assert_separately(%w[-rstringio], "#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
      limit = #{limit}
      ary = []
      while true
        x = "a"*0x100000
        break if [x].pack("p").unpack("i!")[0] < 0
        ary << x
        skip if ary.size > 100
      end
      s = StringIO.new(x)
      s.gets("xxx", limit)
      assert_equal(0x100000, s.pos)
    end;
  end

  def test_encoding_write
    s = StringIO.new("", "w:utf-32be")
    s.print "abc"
    assert_equal("abc".encode("utf-32be"), s.string)
  end

  def test_encoding_read
    s = StringIO.new("abc".encode("utf-32be"), "r:utf-8")
    assert_equal("\0\0\0a\0\0\0b\0\0\0c", s.read)
  end

  %w/UTF-8 UTF-16BE UTF-16LE UTF-32BE UTF-32LE/.each do |name|
    define_method("test_strip_bom:#{name}") do
      text = "\uFEFF\u0100a"
      content = text.encode(name)
      result = StringIO.new(content, mode: 'rb:BOM|UTF-8').read
      assert_equal(Encoding.find(name), result.encoding, name)
      assert_equal(content[1..-1].b, result.b, name)

      StringIO.open(content) {|f|
        assert_equal(Encoding.find(name), f.set_encoding_by_bom)
      }
    end
  end

  def test_binary_encoding_read_and_default_internal
    verbose, $VERBOSE = $VERBOSE, nil
    default_internal = Encoding.default_internal
    Encoding.default_internal = Encoding::UTF_8
    $VERBOSE = verbose
    assert_equal Encoding::BINARY, StringIO.new("Hello".b).read.encoding
  ensure
    $VERBOSE = nil
    Encoding.default_internal = default_internal
    $VERBOSE = verbose
  end

  def assert_string(content, encoding, str, mesg = nil)
    assert_equal([content, encoding], [str, str.encoding], mesg)
  end
end
