require 'test/unit'
require "#{File.dirname(File.expand_path(__FILE__))}/envutil"

class TestBeginEndBlock < Test::Unit::TestCase
  DIR = File.dirname(File.expand_path(__FILE__))

  def test_beginendblock
    ruby = EnvUtil.rubybin
    io = IO.popen("\"#{ruby}\" \"#{DIR}/beginmainend.rb\"")
    assert_equal("begin\nmain\nend\n", io.read)
  end
end
