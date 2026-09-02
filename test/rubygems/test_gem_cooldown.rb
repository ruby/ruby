# frozen_string_literal: true

require_relative "helper"
require "rubygems/cooldown"

class TestGemCooldown < Gem::TestCase
  def test_skip_eh
    now = Time.now
    cooldown = Gem::Cooldown.new 7, now: now

    assert cooldown.skip?(now - 6 * 86_400)
    refute cooldown.skip?(now - 8 * 86_400)
  end

  def test_skip_eh_boundary
    now = Time.now
    cooldown = Gem::Cooldown.new 7, now: now

    assert cooldown.skip?(now - 7 * 86_400 + 1)
    refute cooldown.skip?(now - 7 * 86_400)
  end

  def test_skip_eh_unknown_publish_time
    refute Gem::Cooldown.new(7).skip?(nil)
  end

  def test_skip_eh_inactive
    cooldown = Gem::Cooldown.new 0

    refute cooldown.active?
    refute cooldown.skip?(Time.now)
  end

  def test_from_options
    orig_cooldown = Gem.configuration.cooldown
    Gem.configuration.cooldown = 5

    assert_equal 5, Gem::Cooldown.from_options({}).days
    assert_equal 7, Gem::Cooldown.from_options(cooldown: 7).days
    refute Gem::Cooldown.from_options(cooldown: 0).active?
  ensure
    Gem.configuration.cooldown = orig_cooldown
  end

  def test_invalid_days_warns_once_and_fails_open
    use_ui @ui do
      refute Gem::Cooldown.new("abc").active?
      refute Gem::Cooldown.new("abc").active?
    end

    assert_equal 1, @ui.error.scan("Invalid cooldown value").size
    assert_match 'Invalid cooldown value "abc", so the cooldown is disabled.', @ui.error
    assert_match "Expected a non-negative integer number of days.", @ui.error
  end

  def test_negative_days_warns_and_fails_open
    use_ui @ui do
      refute Gem::Cooldown.new(-5).active?
    end

    assert_match "Invalid cooldown value -5", @ui.error
  end

  def test_partly_numeric_days_warns_and_fails_open
    use_ui @ui do
      refute Gem::Cooldown.new("7days").active?
    end

    assert_match 'Invalid cooldown value "7days"', @ui.error
  end

  def test_non_numeric_type_warns_instead_of_raising
    use_ui @ui do
      [true, [7], :sym].each do |value|
        refute Gem::Cooldown.new(value).active?
      end
    end

    assert_match "Invalid cooldown value true", @ui.error
  end

  def test_valid_days_do_not_warn
    use_ui @ui do
      Gem::Cooldown.new 7
      Gem::Cooldown.new 0
      Gem::Cooldown.new "3"
      Gem::Cooldown.new nil
    end

    assert_empty @ui.error
  end

  def test_parse_created_at_without_offset_is_utc
    with_tz "Asia/Tokyo" do
      assert_equal Time.utc(2026, 6, 5, 10, 30, 45),
                   Gem::Cooldown.parse_created_at("2026-06-05T10:30:45")
    end
  end

  def test_parse_created_at_keeps_explicit_offset
    assert_equal Time.utc(2026, 6, 5, 8, 30, 45),
                 Gem::Cooldown.parse_created_at("2026-06-05T10:30:45+02:00")

    assert_equal Time.utc(2026, 6, 5, 10, 30, 45),
                 Gem::Cooldown.parse_created_at("2026-06-05T10:30:45Z")
  end

  def test_parse_created_at_invalid
    assert_nil Gem::Cooldown.parse_created_at("not a timestamp")
    assert_nil Gem::Cooldown.parse_created_at("2026")
    assert_nil Gem::Cooldown.parse_created_at("2026-06-05T10")
    assert_nil Gem::Cooldown.parse_created_at(nil)
    assert_nil Gem::Cooldown.parse_created_at(7)
  end

  def test_parse_created_at_rejects_years_outside_four_digits
    # Time.iso8601 accepts these, but the distance from now overflows Float.
    assert_nil Gem::Cooldown.parse_created_at("#{"9" * 400}-01-01T00:00:00Z")
    assert_nil Gem::Cooldown.parse_created_at("-2026-06-05T10:30:45Z")
    assert_nil Gem::Cooldown.parse_created_at("02026-06-05T10:30:45Z")
  end

  def with_tz(tz)
    orig_tz = ENV["TZ"]
    ENV["TZ"] = tz
    yield
  ensure
    ENV["TZ"] = orig_tz
  end

  def test_warn_missing_created_at_warns_once
    source = Gem::Source.new @gem_repo

    use_ui @ui do
      Gem::Cooldown.warn_missing_created_at source
      Gem::Cooldown.warn_missing_created_at source
    end

    assert_equal 1, @ui.error.scan("publish times").size
    assert_match @gem_repo, @ui.error
  end
end
