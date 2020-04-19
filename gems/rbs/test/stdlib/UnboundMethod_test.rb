require_relative "test_helper"

class UnboundMethodTest < StdlibTest
  target UnboundMethod
  using hook.refinement

  def test_parameters
    42.method(:to_s).unbind.parameters
    method(:test_parameters).unbind.parameters
  end
end
