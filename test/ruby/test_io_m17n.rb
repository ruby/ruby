require 'test/unit'
require 'tmpdir'

class TestIOM17N < Test::Unit::TestCase
  def with_tmpdir
    Dir.mktmpdir {|dir|
      Dir.chdir dir
      yield dir
    }
  end

  def test_conversion
    with_tmpdir {
      open("tmp", "w") {|f| f.write "before \u00FF after" }
      s = open("tmp", "r:iso-8859-1:utf-8") {|f|
        f.gets("\xFF".force_encoding("iso-8859-1"))
      }
      assert_equal("before \xFF".force_encoding("iso-8859-1"), s, '[ruby-core:14288]')
    }
  end
end

