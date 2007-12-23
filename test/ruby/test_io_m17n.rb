require 'test/unit'
require 'tmpdir'

class TestIO_M17N < Test::Unit::TestCase
  def with_tmpdir
    Dir.mktmpdir {|dir|
      Dir.chdir dir
      yield dir
    }
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
      s = open("tmp", "r:iso-8859-1:utf-8") {|f|
        f.gets("\xFF".force_encoding("iso-8859-1"))
      }
      assert_str_equal("before \xFF".force_encoding("iso-8859-1"), s, '[ruby-core:14288]')
    }
  end

  def test_open_ascii
    with_tmpdir {
      src = "abc\n"
      generate_file('tmp', "abc\n")
      [
        Encoding::ASCII_8BIT,
        Encoding::EUC_JP,
        Encoding::Shift_JIS,
        Encoding::UTF_8
      ].each {|enc|
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
      [
        Encoding::ASCII_8BIT,
        Encoding::EUC_JP,
        Encoding::Shift_JIS,
        Encoding::UTF_8
      ].each {|enc|
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
      [
        Encoding::ASCII_8BIT,
        Encoding::EUC_JP,
        Encoding::Shift_JIS,
        Encoding::UTF_8
      ].each {|enc|
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
    encs = [
      Encoding::ASCII_8BIT,
      Encoding::EUC_JP,
      Encoding::Shift_JIS,
      Encoding::UTF_8
    ]
    with_tmpdir {
      open('tmp', "w") {|f|
        encs.each {|enc|
          f.write src.dup.force_encoding(enc)
        }
      }
      open('tmp', 'rb') {|f|
        assert_equal(src*encs.length, f.read)
      }
    }
  end

  def test_write_enc
    utf8 = "\u6666"
    eucjp = "\xb3\xa2".force_encoding("EUC-JP")
    with_tmpdir {
      open('tmp', "w:EUC-JP") {|f|
        f.print utf8
      }
      assert_equal(eucjp, File.read('tmp').force_encoding("EUC-JP"))
      open('tmp', 'r:UTF-8:EUC-JP') {|f|
        assert_equal(Encoding::EUC_JP, f.external_encoding)
        assert_equal(Encoding::UTF_8, f.internal_encoding)
        assert_equal(utf8, f.read)
      }
    }
  end

end

