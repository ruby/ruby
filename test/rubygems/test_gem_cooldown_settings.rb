# frozen_string_literal: true

require_relative "helper"
require "rubygems/cooldown_settings"

class TestGemCooldownSettings < Gem::TestCase
  def test_days_reads_non_negative_integers
    assert_equal 7, Gem::CooldownSettings.days(7)
    assert_equal 7, Gem::CooldownSettings.days("7")
    assert_equal 0, Gem::CooldownSettings.days(0)
  end

  def test_days_reads_a_leading_zero_as_base_ten
    assert_equal 10, Gem::CooldownSettings.days("010")
    assert_equal 8, Gem::CooldownSettings.days("08")
    assert_nil Gem::CooldownSettings.days("0x10")
  end

  def test_days_rejects_everything_else
    ["seven", "7days", -1, true, [7], :sym, ""].each do |value|
      assert_nil Gem::CooldownSettings.days(value), value.inspect
    end
  end

  def test_days_of_an_unset_value_is_nil
    assert_nil Gem::CooldownSettings.days(nil)
  end

  def test_invalid_eh
    assert Gem::CooldownSettings.invalid?("seven")
    refute Gem::CooldownSettings.invalid?("7")
    refute Gem::CooldownSettings.invalid?(0)
    refute Gem::CooldownSettings.invalid?(nil)
  end

  def test_combine_takes_the_longest_configured_value
    assert_equal 7, Gem::CooldownSettings.combine(3, 7)
    assert_equal 7, Gem::CooldownSettings.combine(7, 3)
  end

  def test_combine_ignores_unset_and_unusable_values
    assert_equal 7, Gem::CooldownSettings.combine(nil, 7)
    assert_equal 7, Gem::CooldownSettings.combine("seven", 7)
    assert_nil Gem::CooldownSettings.combine(nil, nil)
    assert_nil Gem::CooldownSettings.combine("seven", nil)
  end

  # A configured 0 means "no cooldown here", not "nothing configured here", so
  # it must not be read as unset. The longer value still wins. Only
  # --cooldown 0 bypasses a cooldown the other tool configures.
  def test_combine_treats_a_configured_zero_as_a_value
    assert_equal 7, Gem::CooldownSettings.combine(0, 7)
    assert_equal 0, Gem::CooldownSettings.combine(0, nil)
    assert_equal 0, Gem::CooldownSettings.combine(0, "seven")
  end
end
