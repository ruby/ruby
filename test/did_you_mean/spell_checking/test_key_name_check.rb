require "helper"

class KeyNameCheckTest < Test::Unit::TestCase
  def test_corrects_hash_key_name_with_fetch
    hash = { "foo" => 1, bar: 2 }

    error = assert_raise(KeyError) { hash.fetch(:bax) }
    assert_correction ":bar", error.corrections
    assert_match "Did you mean?  :bar", error.to_s

    error = assert_raise(KeyError) { hash.fetch("fooo") }
    assert_correction %("foo"), error.corrections
    assert_match %(Did you mean?  "foo"), error.to_s
  end

  def test_corrects_hash_key_name_with_fetch_values
    hash = { "foo" => 1, bar: 2 }

    error = assert_raise(KeyError) { hash.fetch_values("foo", :bar, :bax) }
    assert_correction ":bar", error.corrections
    assert_match "Did you mean?  :bar", error.to_s

    error = assert_raise(KeyError) { hash.fetch_values("foo", :bar, "fooo") }
    assert_correction %("foo"), error.corrections
    assert_match %(Did you mean?  "foo"), error.to_s
  end

  def test_corrects_sprintf_key_name
    error = assert_raise(KeyError) { sprintf("%<foo>d", {fooo: 1}) }
    assert_correction ":fooo", error.corrections
    assert_match "Did you mean?  :fooo", error.to_s
  end

  def test_corrects_env_key_name
    ENV["FOO"] = "1"
    ENV["BAR"] = "2"
    error = assert_raise(KeyError) { ENV.fetch("BAX") }
    assert_correction %("BAR"), error.corrections
    assert_match %(Did you mean?  "BAR"), error.to_s
  ensure
    ENV.delete("FOO")
    ENV.delete("BAR")
  end
end
