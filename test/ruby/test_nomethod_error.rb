require 'test/unit'

class TestNoMethodError < Test::Unit::TestCase
  def test_new_default
    error = NoMethodError.new
    assert_equal("NoMethodError", error.message)
  end

  def test_new_message
    error = NoMethodError.new("Message")
    assert_equal("Message", error.message)
  end

  def test_new_name
    error = NoMethodError.new("Message")
    assert_nil(error.name)

    error = NoMethodError.new("Message", :foo)
    assert_equal(:foo, error.name)
  end

  def test_new_name_args
    error = NoMethodError.new("Message", :foo)
    assert_nil(error.args)

    error = NoMethodError.new("Message", :foo, [1, 2])
    assert_equal([:foo, [1, 2]], [error.name, error.args])
  end

  def test_new_name_args_priv
    error = NoMethodError.new("Message", :foo, [1, 2])
    assert_not_predicate(error, :private_call?)

    error = NoMethodError.new("Message", :foo, [1, 2], true)
    assert_equal([:foo, [1, 2], true],
                 [error.name, error.args, error.private_call?])
  end

  def test_new_receiver
    receiver = Object.new

    error = NoMethodError.new
    assert_raise(ArgumentError) {error.receiver}

    error = NoMethodError.new(receiver: receiver)
    assert_equal(receiver, error.receiver)

    error = NoMethodError.new("Message")
    assert_raise(ArgumentError) {error.receiver}

    error = NoMethodError.new("Message", receiver: receiver)
    assert_equal(["Message", receiver],
                 [error.message, error.receiver])

    error = NoMethodError.new("Message", :foo)
    assert_raise(ArgumentError) {error.receiver}

    msg = "Message"

    error = NoMethodError.new("Message", :foo, receiver: receiver)
    assert_match msg, error.message
    assert_equal :foo, error.name
    assert_equal receiver, error.receiver

    error = NoMethodError.new("Message", :foo, [1, 2])
    assert_raise(ArgumentError) {error.receiver}

    error = NoMethodError.new("Message", :foo, [1, 2], receiver: receiver)
    assert_match msg, error.message
    assert_equal :foo, error.name
    assert_equal [1, 2], error.args
    assert_equal receiver, error.receiver

    error = NoMethodError.new("Message", :foo, [1, 2], true)
    assert_raise(ArgumentError) {error.receiver}

    error = NoMethodError.new("Message", :foo, [1, 2], true, receiver: receiver)
    assert_equal :foo, error.name
    assert_equal [1, 2], error.args
    assert_equal receiver, error.receiver
    assert error.private_call?, "private_call? was false."
  end

  def test_message_encoding
    bug3237 = '[ruby-core:29948]'
    str = "\u2600"
    id = :"\u2604"
    msg = "undefined method `#{id}' for \"#{str}\":String"
    assert_raise_with_message(NoMethodError, msg, bug3237) do
      str.__send__(id)
    end
  end
end
