require_relative "test_helper"

class UncaughtThrowErrorTest < StdlibTest
  target UncaughtThrowError
  using hook.refinement

  def test_new
    UncaughtThrowError.new(1, 2)
  end

  def test_tag
    begin
      throw :a
    rescue UncaughtThrowError => error
      error.tag
    end
  end

  def test_value
    begin
      throw :a
    rescue UncaughtThrowError => error
      error.value
    end
  end
end
