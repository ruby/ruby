require "test/unit"
require "net/protocol"
require "stringio"

class TestProtocol < Test::Unit::TestCase
  def test_each_crlf_line
    assert_output('', '') do
      sio = StringIO.new("")
      imio = Net::InternetMessageIO.new(sio)
      assert_equal(23, imio.write_message("\u3042\r\u3044\n\u3046\r\n\u3048"))
      assert_equal("\u3042\r\n\u3044\r\n\u3046\r\n\u3048\r\n.\r\n", sio.string)

      sio = StringIO.new("")
      imio = Net::InternetMessageIO.new(sio)
      assert_equal(8, imio.write_message("\u3042\r"))
      assert_equal("\u3042\r\n.\r\n", sio.string)
    end
  end
end
