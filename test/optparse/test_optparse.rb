require 'test/unit'
require 'optparse'

class TestOptionParser < Test::Unit::TestCase
  def setup
    @opt = OptionParser.new
    @flag = self.class		# cannot set by option
  end
  def no_error(*args)
    assert_nothing_raised(*args) {return yield}
  end

  def test_permute
    assert_equal(%w"", no_error {@opt.permute!(%w"")})
    assert_equal(self.class, @flag)
    assert_equal(%w"foo bar", no_error {@opt.permute!(%w"foo bar")})
    assert_equal(self.class, @flag)
    assert_equal(%w"- foo bar", no_error {@opt.permute!(%w"- foo bar")})
    assert_equal(self.class, @flag)
    assert_equal(%w"foo bar", no_error {@opt.permute!(%w"-- foo bar")})
    assert_equal(self.class, @flag)
    assert_equal(%w"foo - bar", no_error {@opt.permute!(%w"foo - bar")})
    assert_equal(self.class, @flag)
    assert_equal(%w"foo bar", no_error {@opt.permute!(%w"foo -- bar")})
    assert_equal(self.class, @flag)
    assert_equal(%w"foo --help bar", no_error {@opt.permute!(%w"foo -- --help bar")})
    assert_equal(self.class, @flag)
  end

  def test_order
    assert_equal(%w"", no_error {@opt.order!(%w"")})
    assert_equal(self.class, @flag)
    assert_equal(%w"foo bar", no_error {@opt.order!(%w"foo bar")})
    assert_equal(self.class, @flag)
    assert_equal(%w"- foo bar", no_error {@opt.order!(%w"- foo bar")})
    assert_equal(self.class, @flag)
    assert_equal(%w"foo bar", no_error {@opt.permute!(%w"-- foo bar")})
    assert_equal(self.class, @flag)
    assert_equal(%w"foo - bar", no_error {@opt.order!(%w"foo - bar")})
    assert_equal(self.class, @flag)
    assert_equal(%w"foo -- bar", no_error {@opt.order!(%w"foo -- bar")})
    assert_equal(self.class, @flag)
    assert_equal(%w"foo -- --help bar", no_error {@opt.order!(%w"foo -- --help bar")})
    assert_equal(self.class, @flag)
  end
end
