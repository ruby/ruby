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
      assert_in_out(%w[-EEUC-JP], <<-'EOS', %w[true], nil, :chdir=>d)
        filename = "\xA4\xA2".force_encoding("euc-jp")
        File.open(filename, "w") {}
        ents = Dir.entries(".")
        ents.each {|e| e.force_encoding("ASCII-8BIT") }
        p ents.include?(filename.force_encoding("ASCII-8BIT"))
      EOS
    }
  end

  def test_filename_euc_jp
    with_tmpdir {|d|
      assert_in_out(%w[-EEUC-JP], <<-'EOS', %w[true], nil, :chdir=>d)
        filename = "\xA4\xA2".force_encoding("euc-jp")
        File.open(filename, "w") {}
        ents = Dir.entries(".")
        p ents.include?(filename)
      EOS
    }
  end

  def test_filename_utf_8
    with_tmpdir {|d|
      assert_in_out(%w[-EUTF-8], <<-'EOS', %w[true], nil, :chdir=>d)
        filename = "\u3042".force_encoding("utf-8")
        File.open(filename, "w") {}
        ents = Dir.entries(".")
        p ents.include?(filename)
      EOS
    }
  end

end

