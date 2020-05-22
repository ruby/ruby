require_relative '../helper'

return if !(RUBY_VERSION >= '2.8.0')

class RequirePathCheckTest < Test::Unit::TestCase
  include DidYouMean::TestHelper

  def test_load_error_from_require_has_suggestions
    error = assert_raise LoadError do
              require 'open_struct'
            end

    assert_correction 'ostruct', error.corrections
    assert_match "Did you mean?  ostruct", error.to_s
  end

  def test_load_error_from_require_for_nested_files_has_suggestions
    error = assert_raise LoadError do
              require 'net/htt'
            end

    assert_correction 'net/http', error.corrections
    assert_match "Did you mean?  net/http", error.to_s

    error = assert_raise LoadError do
              require 'net-http'
            end

    assert_correction ['net/http', 'net/https'], error.corrections
    assert_match "Did you mean?  net/http", error.to_s
  end
end
