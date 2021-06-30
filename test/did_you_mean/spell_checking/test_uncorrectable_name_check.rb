require_relative '../helper'

class UncorrectableNameCheckTest < Test::Unit::TestCase
  class FirstNameError < NameError; end

  def setup
    @error = assert_raise(FirstNameError) do
      raise FirstNameError, "Other name error"
    end
  end

  def test_message
    assert_not_match(/Did you mean\?/, @error.message)
  end
end
