require 'test/unit'
require 'tmpdir'

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
      assert_equal(Encoding.find("euc-jp"), s.encoding)
      assert_str_equal("before \xA1\xA2\xA2\xA3 after".force_encoding("iso-8859-1"), s)
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
    src = "\xc2\xa1\n"
    with_tmpdir {
      open('tmp', "w") {|f|
        ENCS.each {|enc|
          f.write src.dup.force_encoding(enc)
        }
      }
      open('tmp', 'rb') {|f|
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
      puts encdump(s)
      puts encdump(utf8)
      assert_str_equal(utf8, s)
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
  end

end

