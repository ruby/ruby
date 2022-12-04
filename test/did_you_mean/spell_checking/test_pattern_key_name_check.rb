require_relative '../helper'

return if !defined?(::NoMatchingPatternKeyError)

class PatternKeyNameCheckTest < Test::Unit::TestCase
  include DidYouMean::TestHelper

  def test_corrects_hash_key_name_with_single_pattern_match
    error = assert_raise(NoMatchingPatternKeyError) do
      eval(<<~RUBY, binding, __FILE__, __LINE__)
        hash = {foo: 1, bar: 2, baz: 3}
        hash => {fooo:}
        fooo = 1 # suppress "unused variable: fooo" warning
      RUBY
    end

    assert_correction ":foo", error.corrections
    assert_match "Did you mean?  :foo", get_message(error)
  end
end
