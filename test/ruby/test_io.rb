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

    # "\377" [ruby-dev:24460]
    r, w = IO.pipe
    w.print "\377xyz"
    w.close
    assert_equal("\377", r.gets("\377"), "[ruby-dev:24460]")
    r.close

    # "" [ruby-core:03771]
    r, w = IO.pipe
    w.print "a\n\nb\n\n"
    w.close
    assert_equal "a\n\n", r.gets("")
    assert_equal "b\n\n", r.gets("")
    assert_nil r.gets("")
    r.close
  end
end
