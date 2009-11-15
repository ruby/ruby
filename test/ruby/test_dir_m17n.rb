require 'test/unit'
require 'tmpdir'
require_relative 'envutil'

class TestDir_M17N < Test::Unit::TestCase
  def with_tmpdir
    Dir.mktmpdir {|dir|
      Dir.chdir(dir) {
        yield dir
      }
    }
  end

  def test_filename_bytes_euc_jp
    with_tmpdir {|d|
      assert_ruby_status(%w[-EEUC-JP], <<-'EOS', nil, :chdir=>d)
        filename = "\xA4\xA2".force_encoding("euc-jp")
        File.open(filename, "w") {}
        ents = Dir.entries(".")
        ents.each {|e| e.force_encoding("ASCII-8BIT") }
        exit ents.include?(filename.force_encoding("ASCII-8BIT"))
      EOS
    }
  end

  def test_filename_euc_jp
    with_tmpdir {|d|
      assert_ruby_status(%w[-EEUC-JP], <<-'EOS', nil, :chdir=>d)
        filename = "\xA4\xA2".force_encoding("euc-jp")
        File.open(filename, "w") {}
        ents = Dir.entries(".")
        exit ents.include?(filename)
      EOS
      assert_ruby_status(%w[-EASCII-8BIT], <<-'EOS', nil, :chdir=>d)
        filename = "\xA4\xA2"
        ents = Dir.entries(".")
        exit ents.include?(filename)
      EOS
    }
  end

  def test_filename_utf_8
    with_tmpdir {|d|
      assert_ruby_status(%w[-EUTF-8], <<-'EOS', nil, :chdir=>d)
        filename = "\u3042".force_encoding("utf-8")
        File.open(filename, "w") {}
        ents = Dir.entries(".")
        exit ents.include?(filename)
      EOS
      assert_ruby_status(%w[-EASCII-8BIT], <<-'EOS', nil, :chdir=>d)
        filename = "\u3042".force_encoding("ASCII-8BIT")
        ents = Dir.entries(".")
        exit ents.include?(filename)
      EOS
    }
  end

  def test_filename_ext_euc_jp_and_int_utf_8
    with_tmpdir {|d|
      assert_ruby_status(%w[-EEUC-JP], <<-'EOS', nil, :chdir=>d)
        filename = "\xA4\xA2".force_encoding("euc-jp")
        File.open(filename, "w") {}
        ents = Dir.entries(".")
        exit ents.include?(filename)
      EOS
      assert_ruby_status(%w[-EEUC-JP:UTF-8], <<-'EOS', nil, :chdir=>d)
        filename = "\u3042".force_encoding("utf-8")
        ents = Dir.entries(".")
        exit ents.include?(filename)
      EOS
    }
  end

end

