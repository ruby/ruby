require 'test/unit'

class TestIO < Test::Unit::TestCase
  def test_gets_rs
    # default_rs
    r, w = IO.pipe
    w.print "aaa\nbbb\n"
    w.close
    assert_equal "aaa\n", r.gets
    assert_equal "bbb\n", r.gets
    assert_nil r.gets
    r.close

    # nil
    r, w = IO.pipe
    w.print "a\n\nb\n\n"
    w.close
    assert_equal "a\n\nb\n\n", r.gets(nil)
    assert_nil r.gets("")
    r.close

    # "\377"
    r, w = IO.pipe('ascii-8bit')
    w.print "\377xyz"
    w.close
    r.binmode
    assert_equal("\377", r.gets("\377"), "[ruby-dev:24460]")
    r.close

    # ""
    r, w = IO.pipe
    w.print "a\n\nb\n\n"
    w.close
    assert_equal "a\n\n", r.gets(""), "[ruby-core:03771]"
    assert_equal "b\n\n", r.gets("")
    assert_nil r.gets("")
    r.close
  end

  # This test cause SEGV.
  def test_ungetc
    r, w = IO.pipe
    w.close
    assert_raise(IOError, "[ruby-dev:31650]") { 20000.times { r.ungetc "a" } }
  ensure
    r.close
  end

  def test_each_byte
    r, w = IO.pipe
    w << "abc def"
    w.close
    r.each_byte {|byte| break if byte == 32 }
    assert_equal("def", r.read, "[ruby-dev:31659]")
  ensure
    r.close
  end
end
