require_relative "test_helper"

class FrozenErrorTest < StdlibTest
  target FrozenError
  using hook.refinement

  def test_initialize
    FrozenError.new
    FrozenError.new('')
    FrozenError.new(ToStr.new(''))
    FrozenError.new(nil)
    FrozenError.new('', receiver: 42)
  end

  def test_receiver
    begin
      ''.freeze.strip!
      raise
    rescue FrozenError => error
      error.receiver
    end
  end
end
