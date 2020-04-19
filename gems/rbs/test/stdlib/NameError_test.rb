require_relative "test_helper"

class NameErrorTest < StdlibTest
  target NameError
  using hook.refinement

  def test_initialize
    NameError.new
    NameError.new('')
    NameError.new(ToStr.new(''))
    NameError.new('', 'foo', receiver: 42)
    NameError.new("", nil, receiver: nil)
  end

  def test_receiver
    begin
      1.foo
    rescue NameError => error
      error.receiver
    end
  end

  def test_local_variables
    NameError.new.local_variables
  end

  def test_name
    NameError.new("", 'foo').name
    NameError.new("", nil).name
  end
end
