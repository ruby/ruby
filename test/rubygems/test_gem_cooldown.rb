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
