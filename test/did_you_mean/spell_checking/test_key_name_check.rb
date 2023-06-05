require_relative '../helper'

class KeyNameCheckTest < Test::Unit::TestCase
  include DidYouMean::TestHelper

  def test_corrects_hash_key_name_with_fetch
    hash = { "foo" => 1, bar: 2 }

    error = assert_raise(KeyError) { hash.fetch(:bax) }
    assert_correction ":bar", error.corrections
    assert_match "Did you mean?  :bar", get_message(error)

    error = assert_raise(KeyError) { hash.fetch("fooo") }
    assert_correction %("foo"), error.corrections
    assert_match %(Did you mean?  "foo"), get_message(error)
  end

  def test_corrects_hash_key_name_with_fetch_values
    hash = { "foo" => 1, bar: 2 }

    error = assert_raise(KeyError) { hash.fetch_values("foo", :bar, :bax) }
    assert_correction ":bar", error.corrections
    assert_match "Did you mean?  :bar", get_message(error)

    error = assert_raise(KeyError) { hash.fetch_values("foo", :bar, "fooo") }
    assert_correction %("foo"), error.corrections
    assert_match %(Did you mean?  "foo"), get_message(error)
  end

  def test_correct_symbolized_hash_keys_with_string_value
    hash = { foo_1: 1, bar_2: 2 }

    error = assert_raise(KeyError) { hash.fetch('foo_1') }
    assert_correction %(:foo_1), error.corrections
    assert_match %(Did you mean?  :foo_1), get_message(error)
  end

  def test_corrects_sprintf_key_name
    error = assert_raise(KeyError) { sprintf("%<foo>d", {fooo: 1}) }
    assert_correction ":fooo", error.corrections
    assert_match "Did you mean?  :fooo", get_message(error)
  end

  def test_corrects_env_key_name
    ENV["FOO"] = "1"
    ENV["BAR"] = "2"
    error = assert_raise(KeyError) { ENV.fetch("BAX") }
    assert_correction %("BAR"), error.corrections
    assert_match %(Did you mean?  "BAR"), get_message(error)
  ensure
    ENV.delete("FOO")
    ENV.delete("BAR")
  end
end
