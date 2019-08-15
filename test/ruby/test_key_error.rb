require 'test/unit'

class TestKeyError < Test::Unit::TestCase
  def test_default
    error = KeyError.new
    assert_equal("KeyError", error.message)
  end

  def test_message
    error = KeyError.new("Message")
    assert_equal("Message", error.message)
  end

  def test_receiver
    receiver = Object.new
    error = KeyError.new(receiver: receiver)
    assert_equal(receiver, error.receiver)
    error = KeyError.new
    assert_raise(ArgumentError) {error.receiver}
  end

  def test_key
    error = KeyError.new(key: :key)
    assert_equal(:key, error.key)
    error = KeyError.new
    assert_raise(ArgumentError) {error.key}
  end

  def test_receiver_and_key
    receiver = Object.new
    error = KeyError.new(receiver: receiver, key: :key)
    assert_equal([receiver, :key],
                 [error.receiver, error.key])
  end

  def test_all
    receiver = Object.new
    error = KeyError.new("Message", receiver: receiver, key: :key)
    assert_equal(["Message", receiver, :key],
                 [error.message, error.receiver, error.key])
  end
end
