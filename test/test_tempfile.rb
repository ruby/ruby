require 'test/unit'
require 'tempfile'

class TestTempfile < Test::Unit::TestCase
  module M
  end

  def test_extend
    o = Tempfile.new("foo")
    o.extend M
    assert(M === o, "[ruby-dev:32932]")
  end
  def test_tempfile_encoding_nooption
    default_external=Encoding.default_external
    t=Tempfile.new("TEST")
    t.write("\xE6\x9D\xBE\xE6\xB1\x9F")
    t.rewind
    assert_equal(default_external,t.read.encoding)
  end
  def test_tempfile_encoding_ascii8bit
    default_external=Encoding.default_external
    t=Tempfile.new("TEST",:encoding=>"ascii-8bit")
    t.write("\xE6\x9D\xBE\xE6\xB1\x9F")
    t.rewind
    assert_equal(Encoding::ASCII_8BIT,t.read.encoding)
  end
  def test_tempfile_encoding_ascii8bit2
    default_external=Encoding.default_external
    t=Tempfile.new("TEST",Dir::tmpdir,:encoding=>"ascii-8bit")
    t.write("\xE6\x9D\xBE\xE6\xB1\x9F")
    t.rewind
    assert_equal(Encoding::ASCII_8BIT,t.read.encoding)
  end
end

