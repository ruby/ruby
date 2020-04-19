require_relative "test_helper"

class NilClassTest < StdlibTest
  target NilClass
  using hook.refinement

  def test_and
    nil & true
  end

  def test_eqq
    nil === nil
    nil === false
  end

  def test_match
    nil =~ 42
  end

  def test_xor
    nil ^ nil
    nil ^ false
    nil ^ 42
  end

  def test_inspect
    nil.inspect
  end

  def test_nil?
    nil.nil?
  end

  def test_rationalize
    nil.rationalize
    nil.rationalize(0.01)
  end

  def test_to_a
    nil.to_a
  end

  def test_to_c
    nil.to_c
  end

  def test_to_f
    nil.to_f
  end

  def test_to_h
    nil.to_h
  end

  def test_to_i
    nil.to_i
  end

  def test_to_r
    nil.to_r
  end

  def test_to_s
    nil.to_s
  end

  def test_or
    nil | nil
    nil | false
    nil | 42
  end
end
