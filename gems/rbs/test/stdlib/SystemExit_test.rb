require_relative "test_helper"

class SystemExitTest < StdlibTest
  target SystemExit
  using hook.refinement

  def test_new
    SystemExit.new()
    SystemExit.new("hello world")
    SystemExit.new(ToStr.new("hello"))
    SystemExit.new(true)
    SystemExit.new(false)
    SystemExit.new(3)
    SystemExit.new(ToInt.new(3))
  end

  def test_status
    SystemExit.new(true).status
  end

  def test_success?
    SystemExit.new(true).success?
  end
end
