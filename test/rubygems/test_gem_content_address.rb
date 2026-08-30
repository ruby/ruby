# frozen_string_literal: true

require_relative "helper"
require "rubygems/content_address"

class TestGemContentAddress < Gem::TestCase
  def test_match
    assert Gem::ContentAddress.match?("78be552b")
    refute Gem::ContentAddress.match?("x86_64-linux")
    refute Gem::ContentAddress.match?(nil)
    refute Gem::ContentAddress.match?("")
    refute Gem::ContentAddress.match?(0xabcdef12)
    refute Gem::ContentAddress.match?(:abcdef12)
    refute Gem::ContentAddress.match?("abcdef12 ")
    refute Gem::ContentAddress.match?(" abcdef12")
  end

  def test_match_boundary_lengths
    assert Gem::ContentAddress.match?("a" * 8)
    assert Gem::ContentAddress.match?("a" * 64)
    refute Gem::ContentAddress.match?("a" * 7)
    refute Gem::ContentAddress.match?("a" * 65)
  end

  def test_match_rejects_uppercase
    refute Gem::ContentAddress.match?("ABCDEF12")
  end

  def test_applicable_with_required_ruby_version_and_platform
    spec = Gem::Specification.new "a", 1
    spec.required_ruby_version = ">= 3.0"
    spec.platform = "x86_64-linux"
    assert Gem::ContentAddress.applicable?(spec)
  end

  def test_applicable_without_required_ruby_version
    spec = Gem::Specification.new "a", 1
    spec.platform = "x86_64-linux"
    refute Gem::ContentAddress.applicable?(spec)
  end

  def test_applicable_with_ruby_platform
    spec = Gem::Specification.new "a", 1
    spec.required_ruby_version = ">= 3.0"
    refute Gem::ContentAddress.applicable?(spec)
  end

  def test_applicable_with_nil_platform
    spec = Gem::Specification.new "a", 1
    spec.required_ruby_version = ">= 3.0"
    spec.platform = nil
    refute Gem::ContentAddress.applicable?(spec)
  end

  def test_content_addressed_with_eligible_spec_and_valid_address
    spec = Gem::Specification.new "a", 1
    spec.required_ruby_version = ">= 3.0"
    spec.platform = "x86_64-linux"
    spec.content_address = "abcdef12"
    assert Gem::ContentAddress.content_addressed?(spec)
  end

  def test_content_addressed_with_eligible_spec_and_no_address
    spec = Gem::Specification.new "a", 1
    spec.required_ruby_version = ">= 3.0"
    spec.platform = "x86_64-linux"
    refute Gem::ContentAddress.content_addressed?(spec)
  end

  def test_content_addressed_with_eligible_spec_and_invalid_address
    spec = Gem::Specification.new "a", 1
    spec.required_ruby_version = ">= 3.0"
    spec.platform = "x86_64-linux"
    spec.content_address = "x86_64-linux"
    refute Gem::ContentAddress.content_addressed?(spec)
  end

  def test_content_addressed_with_ineligible_spec_and_valid_address
    spec = Gem::Specification.new "a", 1
    spec.content_address = "abcdef12"
    refute Gem::ContentAddress.content_addressed?(spec)
  end

  def test_ruby_abi_specificity_match_ranks_content_addressed_spec_for_that_ruby_first
    spec = Gem::Specification.new "a", 1
    spec.platform = "x86_64-linux"
    spec.required_ruby_version = "~> 3.4.0"
    spec.content_address = "abcdef12"

    assert_equal 0, Gem::ContentAddress.ruby_abi_specificity_match(spec, Gem::Version.new("3.4.1"))
  end

  def test_ruby_abi_specificity_match_ranks_non_content_addressed_spec_second
    spec = Gem::Specification.new "a", 1
    spec.platform = "x86_64-linux"
    spec.required_ruby_version = "~> 3.3.0"

    assert_equal 1, Gem::ContentAddress.ruby_abi_specificity_match(spec, Gem::Version.new("3.4.1"))
  end

  def test_ruby_abi_specificity_match_ranks_content_addressed_spec_for_another_ruby_last
    spec = Gem::Specification.new "a", 1
    spec.platform = "x86_64-linux"
    spec.required_ruby_version = "~> 3.3.0"
    spec.content_address = "abcdef12"

    assert_equal 2, Gem::ContentAddress.ruby_abi_specificity_match(spec, Gem::Version.new("3.4.1"))
  end

  def test_ruby_abi_specificity_match_defaults_to_the_running_ruby
    spec = Gem::Specification.new "a", 1
    spec.platform = "x86_64-linux"
    spec.required_ruby_version = "~> 3.4.0"
    spec.content_address = "abcdef12"

    assert_equal Gem::ContentAddress.ruby_abi_specificity_match(spec, Gem.ruby_version),
                 Gem::ContentAddress.ruby_abi_specificity_match(spec)
  end
end
