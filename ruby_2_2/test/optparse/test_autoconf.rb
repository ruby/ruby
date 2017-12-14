require 'test/unit'
require 'optparse/ac'

class TestOptionParser < Test::Unit::TestCase; end

class TestOptionParser::AutoConf < Test::Unit::TestCase
  def setup
    @opt = OptionParser::AC.new
    @foo = @bar = self.class
    @opt.ac_arg_enable("foo", "foo option") {|x| @foo = x}
    @opt.ac_arg_disable("bar", "bar option") {|x| @bar = x}
    @opt.ac_arg_with("zot", "zot option") {|x| @zot = x}
  end

  class DummyOutput < String
    alias write <<
  end
  def no_error(*args)
    $stderr, stderr = DummyOutput.new, $stderr
    assert_nothing_raised(*args) {return yield}
  ensure
    stderr, $stderr = $stderr, stderr
    $!.backtrace.delete_if {|e| /\A#{Regexp.quote(__FILE__)}:#{__LINE__-2}/o =~ e} if $!
    assert_empty(stderr)
  end

  def test_enable
    @opt.parse!(%w"--enable-foo")
    assert_equal(true, @foo)
    @opt.parse!(%w"--enable-bar")
    assert_equal(true, @bar)
  end

  def test_disable
    @opt.parse!(%w"--disable-foo")
    assert_equal(false, @foo)
    @opt.parse!(%w"--disable-bar")
    assert_equal(false, @bar)
  end

  def test_with
    @opt.parse!(%w"--with-zot=foobar")
    assert_equal("foobar", @zot)
    @opt.parse!(%w"--without-zot")
    assert_nil(@zot)
  end

  def test_without
    @opt.parse!(%w"--without-zot")
    assert_nil(@zot)
    assert_raise(OptionParser::NeedlessArgument) {@opt.parse!(%w"--without-zot=foobar")}
  end

  def test_help
    help = @opt.help
    assert_match(/--enable-foo/, help)
    assert_match(/--disable-bar/, help)
    assert_match(/--with-zot/, help)
    assert_not_match(/--disable-foo/, help)
    assert_not_match(/--enable-bar/, help)
    assert_not_match(/--without/, help)
  end
end
