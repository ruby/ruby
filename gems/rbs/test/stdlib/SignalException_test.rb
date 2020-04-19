require_relative "test_helper"

class SignalExceptionTest < StdlibTest
  target SignalException
  using hook.refinement

  def test_new
    SignalException.new("INT")
    SignalException.new(ToStr.new("INT")).signm
    SignalException.new(9)
    SignalException.new(9, "KILL")
    SignalException.new(ToInt.new(9), ToStr.new("KILL"))
  end

  def test_signm
    SignalException.new("INT").signm
  end

  def test_signo
    SignalException.new("INT").signo
  end
end
