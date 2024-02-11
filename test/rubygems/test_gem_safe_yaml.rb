# frozen_string_literal: true

require_relative "helper"

Gem.load_yaml

class TestGemSafeYAML < Gem::TestCase
  def test_aliases_enabled_by_default
    assert_predicate Gem::SafeYAML, :aliases_enabled?
    assert_equal({ "a" => "a", "b" => "a" }, Gem::SafeYAML.safe_load("a: &a a\nb: *a\n"))
  end

  def test_aliases_disabled
    aliases_enabled = Gem::SafeYAML.aliases_enabled?
    Gem::SafeYAML.aliases_enabled = false
    refute_predicate Gem::SafeYAML, :aliases_enabled?
    assert_raise Psych::AliasesNotEnabled do
      Gem::SafeYAML.safe_load("a: &a\nb: *a\n")
    end
  ensure
    Gem::SafeYAML.aliases_enabled = aliases_enabled
  end
end
