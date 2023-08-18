# frozen_string_literal: true

require_relative "helper"
require "rubygems/uri"

class TestUri < Gem::TestCase
  def test_to_s_not_string
    assert_equal "not_a_uri", Gem::Uri.new(:not_a_uri).to_s
  end

  def test_to_s_invalid_uri
    assert_equal "https://www.example.com:80index", Gem::Uri.new("https://www.example.com:80index").to_s
  end

  def test_redacted_with_user_pass
    assert_equal "https://user:REDACTED@example.com", Gem::Uri.new("https://user:pass@example.com").redacted.to_s
  end

  def test_redacted_with_token
    assert_equal "https://REDACTED@example.com", Gem::Uri.new("https://token@example.com").redacted.to_s
  end

  def test_redacted_with_user_x_oauth_basic
    assert_equal "https://REDACTED:x-oauth-basic@example.com", Gem::Uri.new("https://token:x-oauth-basic@example.com").redacted.to_s
  end

  def test_redacted_without_credential
    assert_equal "https://www.example.com", Gem::Uri.new("https://www.example.com").redacted.to_s
  end

  def test_redacted_with_invalid_uri
    assert_equal "https://www.example.com:80index", Gem::Uri.new("https://www.example.com:80index").redacted.to_s
  end

  def test_redacted_does_not_modify_uri
    url = "https://user:password@example.com"
    uri = Gem::Uri.new(url)
    assert_equal "https://user:REDACTED@example.com", uri.redacted.to_s
    assert_equal url, uri.to_s
  end
end
