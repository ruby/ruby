require_relative 'helper'
require 'uri'
require 'rubygems/printable_uri'

class TestPrintableUri < Gem::TestCase
  def test_parsed_uri
    assert_equal true, Gem::PrintableUri.parse_uri("https://www.example.com").valid_uri?
  end

  def test_valid_uri_with_empty_uri_object
    assert_equal true, Gem::PrintableUri.parse_uri(URI("")).valid_uri?
  end

  def test_valid_uri_with_valid_uri_object
    assert_equal true, Gem::PrintableUri.parse_uri(URI("https://www.example.com")).valid_uri?
  end

  def test_valid_uri_with_other_objects
    assert_equal false, Gem::PrintableUri.parse_uri(Object.new).valid_uri?
  end

  def test_valid_uri_with_invalid_uri
    assert_equal false, Gem::PrintableUri.parse_uri("https://www.example.com:80index").valid_uri?
  end

  def test_credential_redacted_with_user_pass
    assert_equal true, Gem::PrintableUri.parse_uri("https://user:pass@example.com").credential_redacted?
  end

  def test_credential_redacted_with_token
    assert_equal true, Gem::PrintableUri.parse_uri("https://token@example.com").credential_redacted?
  end

  def test_credential_redacted_with_user_x_oauth_basic
    assert_equal true, Gem::PrintableUri.parse_uri("https://token:x-oauth-basic@example.com").credential_redacted?
  end

  def test_credential_redacted_without_credential
    assert_equal false, Gem::PrintableUri.parse_uri("https://www.example.com").credential_redacted?
  end

  def test_credential_redacted_with_empty_uri_object
    assert_equal false, Gem::PrintableUri.parse_uri(URI("")).credential_redacted?
  end

  def test_credential_redacted_with_valid_uri_object
    assert_equal true, Gem::PrintableUri.parse_uri(URI("https://user:pass@example.com")).credential_redacted?
  end

  def test_credential_redacted_with_other_objects
    assert_equal false, Gem::PrintableUri.parse_uri(Object.new).credential_redacted?
  end

  def test_original_password_user_pass
    assert_equal "pass", Gem::PrintableUri.parse_uri("https://user:pass@example.com").original_password
  end

  def test_original_password_with_token
    assert_equal nil, Gem::PrintableUri.parse_uri("https://token@example.com").original_password
  end

  def test_original_password_without_credential
    assert_equal nil, Gem::PrintableUri.parse_uri("https://www.example.com").original_password
  end

  def test_original_password_with_invalid_uri
    assert_equal nil, Gem::PrintableUri.parse_uri("https://www.example.com:80index").original_password
  end

  def test_original_password_with_empty_uri_object
    assert_equal nil, Gem::PrintableUri.parse_uri(URI("")).original_password
  end

  def test_original_password_with_valid_uri_object
    assert_equal "pass", Gem::PrintableUri.parse_uri(URI("https://user:pass@example.com")).original_password
  end

  def test_original_password_with_other_objects
    assert_equal nil, Gem::PrintableUri.parse_uri(Object.new).original_password
  end

  def test_to_s_with_user_pass
    assert_equal "https://user:REDACTED@example.com", Gem::PrintableUri.parse_uri("https://user:pass@example.com").to_s
  end

  def test_to_s_with_token
    assert_equal "https://REDACTED@example.com", Gem::PrintableUri.parse_uri("https://token@example.com").to_s
  end

  def test_to_s_with_user_x_oauth_basic
    assert_equal "https://REDACTED:x-oauth-basic@example.com", Gem::PrintableUri.parse_uri("https://token:x-oauth-basic@example.com").to_s
  end

  def test_to_s_without_credential
    assert_equal "https://www.example.com", Gem::PrintableUri.parse_uri("https://www.example.com").to_s
  end

  def test_to_s_with_invalid_uri
    assert_equal "https://www.example.com:80index", Gem::PrintableUri.parse_uri("https://www.example.com:80index").to_s
  end

  def test_to_s_with_empty_uri_object
    assert_equal "", Gem::PrintableUri.parse_uri(URI("")).to_s
  end

  def test_to_s_with_valid_uri_object
    assert_equal "https://user:REDACTED@example.com", Gem::PrintableUri.parse_uri(URI("https://user:pass@example.com")).to_s
  end

  def test_to_s_with_other_objects
    obj = Object.new
    obj.stub(:to_s, "my-to-s") do
      assert_equal "my-to-s", Gem::PrintableUri.parse_uri(obj).to_s
    end
  end
end
