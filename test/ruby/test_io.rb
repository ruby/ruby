require 'test/unit'
require 'tmpdir'
require 'tempfile'

class TestIO < Test::Unit::TestCase
  def mkcdtmpdir
    Dir.mktmpdir {|d|
      Dir.chdir(d) {
        yield
      }
    }
  end

  def test_gets_rs
    r, w = IO.pipe
    w.print "\377xyz"
    w.close
    assert_equal("\377", r.gets("\377"), "[ruby-dev:24460]")
    r.close
  end

  def test_readpartial_pos
    mkcdtmpdir {
      open("foo", "w") {|f| f << "abc" }
      open("foo") {|f|
        f.seek(0)
        assert_equal("ab", f.readpartial(2))
        assert_equal(2, f.pos)
      }
    }
  end

  def make_tempfile
    t = Tempfile.new("foo")
    t.binmode
    t.puts "foo"
    t.puts "bar"
    t.puts "baz"
    t.close
    t
  end

  def test_binmode_after_closed
    t = make_tempfile
    t.close
    assert_raise(IOError) {t.binmode}
  end
end
