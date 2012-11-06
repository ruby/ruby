require "test/unit"
require "net/protocol"
require "stringio"

class TestProtocol < Test::Unit::TestCase
  def test_each_crlf_line
    assert_output('', '') do
      Net::InternetMessageIO.new(StringIO.new("")).write_message("\u3042\r\n\u3044\r\n\u3046")
    end
  end
end
