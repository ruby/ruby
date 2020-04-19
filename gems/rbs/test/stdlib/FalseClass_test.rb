require_relative "test_helper"

class FalseClassTest < StdlibTest
  target FalseClass
  using hook.refinement

  def test_not
    !false
  end

  def test_and
    false & true
  end

  def test_eqq
    false === false
    false === true
  end

  def test_xor
    false ^ false
    false ^ nil
    false ^ 42
  end

  def test_inspect
    false.inspect
  end

  def test_to_s
    false.to_s
  end

  def test_or
    false | false
    false | nil
    false | 42
  end
end
