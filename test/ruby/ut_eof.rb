require 'test/unit'

module TestEOF
  def test_eof_0
    open_file("") {|f|
      assert_equal("", f.read(0))
      assert_equal("", f.read(0))
      assert_equal("", f.read)
      assert_equal(nil, f.read(0))
      assert_equal(nil, f.read(0))
    }
    open_file("") {|f|
      assert_equal(nil, f.read(1))
      assert_equal(nil, f.read)
      assert_equal(nil, f.read(1))
    }
  end

  def test_eof_1
    open_file("a") {|f|
      assert_equal("", f.read(0))
      assert_equal("a", f.read(1))
      assert_equal("" , f.read(0))
      assert_equal("" , f.read(0))
      assert_equal("", f.read)
      assert_equal(nil, f.read(0))
      assert_equal(nil, f.read(0))
    }
    open_file("a") {|f|
      assert_equal("a", f.read(1))
      assert_equal(nil, f.read(1))
    }
    open_file("a") {|f|
      assert_equal("a", f.read(2))
      assert_equal(nil, f.read(1))
      assert_equal(nil, f.read)
      assert_equal(nil, f.read(1))
    }
    open_file("a") {|f|
      assert_equal("a", f.read)
      assert_equal(nil, f.read(1))
      assert_equal(nil, f.read)
      assert_equal(nil, f.read(1))
    }
  end
end
