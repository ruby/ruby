require "test/unit"
require "webrick/accesslog"

class TestWEBrickAccessLog < Test::Unit::TestCase
  def test_format
    format = "%{Referer}i and %{User-agent}i"
    params = {"i" => {"Referer" => "ref", "User-agent" => "agent"}}
    assert_equal("ref and agent", WEBrick::AccessLog.format(format, params))
  end
end
