# frozen_string_literal: false
require 'test/unit'
require 'optparse'

class TestOptionParser < Test::Unit::TestCase
  def setup
    @opt = OptionParser.new
    @flag = self.class		# cannot set by option
  end

  class DummyOutput < String
    alias write <<
  end
  def assert_no_error(*args)
    $stderr, stderr = DummyOutput.new, $stderr
    assert_nothing_raised(*args) {return yield}
  ensure
    stderr, $stderr = $stderr, stderr
    $!.backtrace.delete_if {|e| /\A#{Regexp.quote(__FILE__)}:#{__LINE__-2}/o =~ e} if $!
    assert_empty(stderr)
  end
  alias no_error assert_no_error

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

  def test_regexp
    return unless defined?(@reopt)
    assert_equal(%w"", no_error {@opt.parse!(%w"--regexp=/foo/")})
    assert_equal(/foo/, @reopt)
    assert_equal(%w"", no_error {@opt.parse!(%w"--regexp=/foo/i")})
    assert_equal(/foo/i, @reopt)
    assert_equal(%w"", no_error {@opt.parse!(%w"--regexp=/foo/n")})
    assert_equal(/foo/n, @reopt)
  end

  def test_into
    @opt.def_option "-h", "--host=HOST", "hostname"
    @opt.def_option "-p", "--port=PORT", "port", Integer
    @opt.def_option "-v", "--verbose" do @verbose = true end
    @opt.def_option "-q", "--quiet" do @quiet = true end
    result = {}
    @opt.parse %w(--host localhost --port 8000 -v), into: result
    assert_equal({host: "localhost", port: 8000, verbose: true}, result)
    assert_equal(true, @verbose)
  end
end
