require 'test/unit'
require "#{File.dirname(File.expand_path(__FILE__))}/envutil"

class TestBeginEndBlock < Test::Unit::TestCase
  DIR = File.dirname(File.expand_path(__FILE__))

  def test_beginendblock
    ruby = EnvUtil.rubybin
    io = IO.popen("\"#{ruby}\" \"#{DIR}/beginmainend.rb\"")
    assert_equal(%w(begin1 begin2 main end1 end2).join("\n") << "\n", io.read)
  end

  def test_begininmethod
    assert_raises(SyntaxError) do
      eval("def foo; BEGIN {}; end")
    end
  end

  def test_endinmethod
    assert_raises(SyntaxError) do
      eval("def foo; END {}; end")
    end
  end
end
