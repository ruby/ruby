require 'test/unit'
require "#{File.dirname(File.expand_path(__FILE__))}/envutil"

class TestBeginEndBlock < Test::Unit::TestCase
  DIR = File.dirname(File.expand_path(__FILE__))

  def test_beginendblock
    ruby = EnvUtil.rubybin
    io = IO.popen("\"#{ruby}\" \"#{DIR}/beginmainend.rb\"")
    assert_equal(%w(begin1 begin2 main innerbegin1 innerbegin2 end1 innerend1 innerend2 end2).join("\n") << "\n", io.read)
  end

  def test_begininmethod
    assert_raises(SyntaxError) do
      eval("def foo; BEGIN {}; end")
    end
  end

  def test_endinmethod
    verbose, $VERBOSE = $VERBOSE, nil
    assert_nothing_raised(SyntaxError) do
      eval("def foo; END {}; end")
    end
  ensure
    $VERBOSE = verbose
  end
end
