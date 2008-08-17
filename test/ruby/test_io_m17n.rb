require 'test/unit'
require 'tmpdir'
require 'timeout'

class TestIO_M17N < Test::Unit::TestCase
  ENCS = [
    Encoding::ASCII_8BIT,
    Encoding::EUC_JP,
    Encoding::Shift_JIS,
    Encoding::UTF_8
  ]

  def with_tmpdir
    Dir.mktmpdir {|dir|
      Dir.chdir(dir) {
        yield dir
      }
    }
  end

  def with_pipe(enc=nil)
    r, w = IO.pipe(enc)
    begin
      yield r, w
    ensure
      r.close if !r.closed?
      w.close if !w.closed?
    end
  end

  def generate_file(path, content)
    open(path, "wb") {|f| f.write content }
  end

  def encdump(str)
    "#{str.dump}.force_encoding(#{str.encoding.name.dump})"
  end

  def assert_str_equal(expected, actual, message=nil)
    full_message = build_message(message, <<EOT)
#{encdump expected} expected but not equal to
#{encdump actual}.
EOT
    assert_block(full_message) { expected == actual }
  end

  def test_open_r
    with_tmpdir {
      generate_file('tmp', "")
      open("tmp", "r") {|f|
        assert_equal(Encoding.default_external, f.external_encoding)
        assert_equal(nil, f.internal_encoding)
      }
    }
  end

  def test_open_rb
    with_tmpdir {
      generate_file('tmp', "")
      open("tmp", "rb") {|f|
        assert_equal(Encoding.default_external, f.external_encoding)
        assert_equal(nil, f.internal_encoding)
      }
    }
  end

  def test_open_r_enc
    with_tmpdir {
      generate_file('tmp', "")
      open("tmp", "r:euc-jp") {|f|
        assert_equal(Encoding::EUC_JP, f.external_encoding)
        assert_equal(nil, f.internal_encoding)
      }
    }
  end

  def test_open_r_enc_enc
    with_tmpdir {
      generate_file('tmp', "")
      open("tmp", "r:euc-jp:utf-8") {|f|
        assert_equal(Encoding::EUC_JP, f.external_encoding)
        assert_equal(Encoding::UTF_8, f.internal_encoding)
      }
    }
  end

  def test_open_w
    with_tmpdir {
      open("tmp", "w") {|f|
        assert_equal(nil, f.external_encoding)
        assert_equal(nil, f.internal_encoding)
      }
    }
  end

  def test_open_wb
    with_tmpdir {
      open("tmp", "wb") {|f|
        assert_equal(nil, f.external_encoding)
        assert_equal(nil, f.internal_encoding)
      }
    }
  end

  def test_open_w_enc
    with_tmpdir {
      open("tmp", "w:euc-jp") {|f|
        assert_equal(Encoding::EUC_JP, f.external_encoding)
        assert_equal(nil, f.internal_encoding)
      }
    }
  end

  def test_open_w_enc_enc
    with_tmpdir {
      open("tmp", "w:euc-jp:utf-8") {|f|
        assert_equal(Encoding::EUC_JP, f.external_encoding)
        assert_equal(Encoding::UTF_8, f.internal_encoding)
      }
    }
  end

  def test_stdin
    assert_equal(Encoding.default_external, STDIN.external_encoding)
    assert_equal(nil, STDIN.internal_encoding)
  end

  def test_stdout
    assert_equal(nil, STDOUT.external_encoding)
    assert_equal(nil, STDOUT.internal_encoding)
  end

  def test_stderr
    assert_equal(nil, STDERR.external_encoding)
    assert_equal(nil, STDERR.internal_encoding)
  end

  def test_terminator_conversion
    with_tmpdir {
      generate_file('tmp', "before \u00FF after")
      s = open("tmp", "r:utf-8:iso-8859-1") {|f|
        f.gets("\xFF".force_encoding("iso-8859-1"))
      }
      assert_equal(Encoding.find("iso-8859-1"), s.encoding)
      assert_str_equal("before \xFF".force_encoding("iso-8859-1"), s, '[ruby-core:14288]')
    }
  end

  def test_terminator_conversion2
    with_tmpdir {
      generate_file('tmp', "before \xA1\xA2\xA2\xA3 after")
      s = open("tmp", "r:euc-jp:utf-8") {|f|
        f.gets("\xA2\xA2".force_encoding("euc-jp").encode("utf-8"))
      }
      assert_equal(Encoding.find("utf-8"), s.encoding)
      assert_str_equal("before \xA1\xA2\xA2\xA3 after".force_encoding("euc-jp").encode("utf-8"), s, '[ruby-core:14319]')
    }
  end

  def test_terminator_stateful_conversion
    with_tmpdir {
      src = "before \e$B\x23\x30\x23\x31\e(B after".force_encoding("iso-2022-jp")
      generate_file('tmp', src)
      assert_raise(NotImplementedError) do
        s = open("tmp", "r:iso-2022-jp:euc-jp") {|f|
          f.gets("0".force_encoding("euc-jp"))
        }
        assert_equal(Encoding.find("euc-jp"), s.encoding)
        assert_str_equal(src.encode("euc-jp"), s)
      end
    }
  end

  def test_nonascii_terminator
    with_tmpdir {
      generate_file('tmp', "before \xA2\xA2 after")
      open("tmp", "r:euc-jp") {|f|
        assert_raise(ArgumentError) {
          f.gets("\xA2\xA2".force_encoding("utf-8"))
        }
      }
    }
  end

  def test_pipe_terminator_conversion
    with_pipe("euc-jp:utf-8") {|r, w|
      w.write "before \xa2\xa2 after"
      rs = "\xA2\xA2".encode("utf-8", "euc-jp")
      w.close
      timeout(1) {
        assert_equal("before \xa2\xa2".encode("utf-8", "euc-jp"),
                     r.gets(rs))
      }
    }
  end

  def test_pipe_conversion
    with_pipe("euc-jp:utf-8") {|r, w|
      w.write "\xa1\xa1"
      assert_equal("\xa1\xa1".encode("utf-8", "euc-jp"), r.getc)
    }
  end

  def test_pipe_convert_partial_read
    with_pipe("euc-jp:utf-8") {|r, w|
      begin
        t = Thread.new {
          w.write "\xa1"
          sleep 0.1
          w.write "\xa1"
        }
        assert_equal("\xa1\xa1".encode("utf-8", "euc-jp"), r.getc)
      ensure
        t.join if t
      end
    }
  end

  def test_getc_invalid
    with_pipe("euc-jp:utf-8") {|r, w|
      w << "\xa1xyz"
      w.close
      err = assert_raise(Encoding::InvalidByteSequence) { r.getc }
      assert_equal("\xA1".force_encoding("ascii-8bit"), err.error_bytes)
      assert_equal("xyz", r.read(10))
    }
  end

  def test_getc_stateful_conversion
    with_tmpdir {
      src = "\e$B\x23\x30\x23\x31\e(B".force_encoding("iso-2022-jp")
      generate_file('tmp', src)
      open("tmp", "r:iso-2022-jp:euc-jp") {|f|
        assert_equal("\xa3\xb0".force_encoding("euc-jp"), f.getc)
        assert_equal("\xa3\xb1".force_encoding("euc-jp"), f.getc)
      }
    }
  end

  def test_ungetc_stateful_conversion
    with_tmpdir {
      src = "before \e$B\x23\x30\x23\x31\e(B after".force_encoding("iso-2022-jp")
      generate_file('tmp', src)
      assert_raise(NotImplementedError) do
        s = open("tmp", "r:iso-2022-jp:euc-jp") {|f|
          f.ungetc("0".force_encoding("euc-jp"))
          f.read
        }
        assert_equal(Encoding.find("euc-jp"), s.encoding)
        assert_str_equal(("0" + src).encode("euc-jp"), s)
      end
    }
  end

  def test_open_ascii
    with_tmpdir {
      src = "abc\n"
      generate_file('tmp', "abc\n")
      ENCS.each {|enc|
        s = open('tmp', "r:#{enc}") {|f| f.gets }
        assert_equal(enc, s.encoding)
        assert_str_equal(src, s)
      }
    }
  end

  def test_open_nonascii
    with_tmpdir {
      src = "\xc2\xa1\n"
      generate_file('tmp', src)
      ENCS.each {|enc|
        content = src.dup.force_encoding(enc)
        s = open('tmp', "r:#{enc}") {|f| f.gets }
        assert_equal(enc, s.encoding)
        assert_str_equal(content, s)
      }
    }
  end

  def test_read_encoding
    with_tmpdir {
      src = "\xc2\xa1\n".force_encoding("ASCII-8BIT")
      generate_file('tmp', "\xc2\xa1\n")
      ENCS.each {|enc|
        content = src.dup.force_encoding(enc)
        open('tmp', "r:#{enc}") {|f|
          s = f.getc
          assert_equal(enc, s.encoding)
          assert_str_equal(content[0], s)
        }
        open('tmp', "r:#{enc}") {|f|
          s = f.readchar
          assert_equal(enc, s.encoding)
          assert_str_equal(content[0], s)
        }
        open('tmp', "r:#{enc}") {|f|
          s = f.gets
          assert_equal(enc, s.encoding)
          assert_str_equal(content, s)
        }
        open('tmp', "r:#{enc}") {|f|
          s = f.readline
          assert_equal(enc, s.encoding)
          assert_str_equal(content, s)
        }
        open('tmp', "r:#{enc}") {|f|
          lines = f.readlines
          assert_equal(1, lines.length)
          s = lines[0]
          assert_equal(enc, s.encoding)
          assert_str_equal(content, s)
        }
        open('tmp', "r:#{enc}") {|f|
          f.each_line {|s|
            assert_equal(enc, s.encoding)
            assert_str_equal(content, s)
          }
        }
        open('tmp', "r:#{enc}") {|f|
          s = f.read
          assert_equal(enc, s.encoding)
          assert_str_equal(content, s)
        }
        open('tmp', "r:#{enc}") {|f|
          s = f.read(1)
          assert_equal(Encoding::ASCII_8BIT, s.encoding)
          assert_str_equal(src[0], s)
        }
        open('tmp', "r:#{enc}") {|f|
          s = f.readpartial(1)
          assert_equal(Encoding::ASCII_8BIT, s.encoding)
          assert_str_equal(src[0], s)
        }
        open('tmp', "r:#{enc}") {|f|
          s = f.sysread(1)
          assert_equal(Encoding::ASCII_8BIT, s.encoding)
          assert_str_equal(src[0], s)
        }
      }
    }
  end

  def test_write_noenc
    src = "\xc2\xa1\n".force_encoding("ascii-8bit")
    with_tmpdir {
      open('tmp', "w") {|f|
        ENCS.each {|enc|
          f.write src.dup.force_encoding(enc)
        }
      }
      open('tmp', 'r:ascii-8bit') {|f|
        assert_equal(src*ENCS.length, f.read)
      }
    }
  end

  def test_write_conversion
    utf8 = "\u6666"
    eucjp = "\xb3\xa2".force_encoding("EUC-JP")
    with_tmpdir {
      open('tmp', "w:EUC-JP") {|f|
        assert_equal(Encoding::EUC_JP, f.external_encoding)
        assert_equal(nil, f.internal_encoding)
        f.print utf8
      }
      assert_equal(eucjp, File.read('tmp').force_encoding("EUC-JP"))
      open('tmp', 'r:EUC-JP:UTF-8') {|f|
        assert_equal(Encoding::EUC_JP, f.external_encoding)
        assert_equal(Encoding::UTF_8, f.internal_encoding)
        assert_equal(utf8, f.read)
      }
    }
  end

  def test_pipe
    utf8 = "\u6666"
    eucjp = "\xb3\xa2".force_encoding("EUC-JP")

    with_pipe {|r,w|
      assert_equal(Encoding.default_external, r.external_encoding)
      assert_equal(nil, r.internal_encoding)
      w << utf8
      w.close
      s = r.read
      assert_equal(Encoding.default_external, s.encoding)
      assert_str_equal(utf8.dup.force_encoding(Encoding.default_external), s)
    }

    with_pipe("EUC-JP") {|r,w|
      assert_equal(Encoding::EUC_JP, r.external_encoding)
      assert_equal(nil, r.internal_encoding)
      w << eucjp
      w.close
      assert_equal(eucjp, r.read)
    }

    with_pipe("UTF-8:EUC-JP") {|r,w|
      assert_equal(Encoding::UTF_8, r.external_encoding)
      assert_equal(Encoding::EUC_JP, r.internal_encoding)
      w << utf8
      w.close
      assert_equal(eucjp, r.read)
    }

    ENCS.each {|enc|
      with_pipe(enc) {|r, w|
        w << "\xc2\xa1"
        w.close
        s = r.getc 
        assert_equal(enc, s.encoding)
      }
    }

    ENCS.each {|enc|
      next if enc == Encoding::ASCII_8BIT
      next if enc == Encoding::UTF_8
      with_pipe("#{enc}:UTF-8") {|r, w|
        w << "\xc2\xa1"
        w.close
        s = r.read
        assert_equal(Encoding::UTF_8, s.encoding)
        assert_equal(s.encode("UTF-8"), s)
      }
    }

  end

  def test_marshal
    with_pipe("EUC-JP") {|r, w|
      data = 56225
      Marshal.dump(data, w)
      w.close
      result = nil
      assert_nothing_raised("[ruby-dev:33264]") { result = Marshal.load(r) }
      assert_equal(data, result)
    }
  end

  def test_gets_nil
    with_pipe("UTF-8:EUC-JP") {|r, w|
      w << "\u{3042}"
      w.close
      result = r.gets(nil)
      assert_equal("\u{3042}".encode("euc-jp"), result)
    }
  end

  def test_gets_limit
    with_pipe("euc-jp") {|r, w| w << "\xa4\xa2\xa4\xa4\xa4\xa6\xa4\xa8\xa4\xaa"; w.close
      assert_equal("\xa4\xa2".force_encoding("euc-jp"), r.gets(1))
    }
    with_pipe("euc-jp") {|r, w| w << "\xa4\xa2\xa4\xa4\xa4\xa6\xa4\xa8\xa4\xaa"; w.close
      assert_equal("\xa4\xa2".force_encoding("euc-jp"), r.gets(2))
    }
    with_pipe("euc-jp") {|r, w| w << "\xa4\xa2\xa4\xa4\xa4\xa6\xa4\xa8\xa4\xaa"; w.close
      assert_equal("\xa4\xa2\xa4\xa4".force_encoding("euc-jp"), r.gets(3))
    }
    with_pipe("euc-jp") {|r, w| w << "\xa4\xa2\xa4\xa4\xa4\xa6\xa4\xa8\xa4\xaa"; w.close
      assert_equal("\xa4\xa2\xa4\xa4".force_encoding("euc-jp"), r.gets(4))
    }

  end

  def test_file_foreach
    with_tmpdir {
      generate_file('tst', 'a' * 8191 + "\xa1\xa1")
      assert_nothing_raised {
        File.foreach('tst', :encoding=>"euc-jp") {|line| line.inspect }
      }
    }
  end
end

