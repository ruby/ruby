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

  def test_valid_ruby_abi
    assert Gem::ContentAddress.valid_ruby_abi?("3.4")
    assert Gem::ContentAddress.valid_ruby_abi?("10.0")
    refute Gem::ContentAddress.valid_ruby_abi?("3")
    refute Gem::ContentAddress.valid_ruby_abi?("3.4.0")
    refute Gem::ContentAddress.valid_ruby_abi?("x.y")
    refute Gem::ContentAddress.valid_ruby_abi?(nil)
    refute Gem::ContentAddress.valid_ruby_abi?(3.4)
  end

  def test_ruby_abi_for_with_abi_shaped_requirement
    assert_equal "3.4", Gem::ContentAddress.ruby_abi_for(Gem::Requirement.new("~> 3.4.0"))
  end

  def test_ruby_abi_for_with_nil_requirement
    assert_nil Gem::ContentAddress.ruby_abi_for(nil)
  end

  def test_ruby_abi_for_with_default_requirement
    assert_nil Gem::ContentAddress.ruby_abi_for(Gem::Requirement.default)
  end

  def test_ruby_abi_for_with_non_pessimistic_requirement
    assert_nil Gem::ContentAddress.ruby_abi_for(Gem::Requirement.new(">= 3.0"))
  end

  def test_ruby_abi_for_with_two_segment_pessimistic_requirement
    assert_nil Gem::ContentAddress.ruby_abi_for(Gem::Requirement.new("~> 3.4"))
  end

  def test_ruby_abi_for_with_nonzero_patch_level
    assert_nil Gem::ContentAddress.ruby_abi_for(Gem::Requirement.new("~> 3.4.1"))
  end

  def test_ruby_abi_for_with_compound_requirement
    assert_nil Gem::ContentAddress.ruby_abi_for(Gem::Requirement.new(">= 3.2", "< 3.5"))
  end

  def test_ruby_abi_requirement
    assert_equal Gem::Requirement.new("~> 3.4.0"), Gem::ContentAddress.ruby_abi_requirement("3.4")
  end

  def test_ruby_abi_requirement_round_trips_through_ruby_abi_for
    assert_equal "3.4", Gem::ContentAddress.ruby_abi_for(Gem::ContentAddress.ruby_abi_requirement("3.4"))
  end

  def test_platform_eligible
    assert Gem::ContentAddress.platform_eligible?(Gem::Platform.new("x86_64-linux"))
    refute Gem::ContentAddress.platform_eligible?(Gem::Platform::RUBY)
    refute Gem::ContentAddress.platform_eligible?(nil)
  end

  def test_content_addressed_row_with_ruby_platform
    refute Gem::ContentAddress.content_addressed_row?("abcdef12", Gem::Platform::RUBY, Gem::Requirement.new("~> 3.4.0"))
  end

  def test_eligible_with_abi_shaped_required_ruby_version_and_platform
    spec = Gem::Specification.new "a", 1
    spec.required_ruby_version = "~> 3.4.0"
    spec.platform = "x86_64-linux"
    assert Gem::ContentAddress.eligible?(spec)
  end

  def test_eligible_with_non_abi_shaped_required_ruby_version
    spec = Gem::Specification.new "a", 1
    spec.required_ruby_version = ">= 3.0"
    spec.platform = "x86_64-linux"
    refute Gem::ContentAddress.eligible?(spec)
  end

  def test_eligible_without_required_ruby_version
    spec = Gem::Specification.new "a", 1
    spec.platform = "x86_64-linux"
    refute Gem::ContentAddress.eligible?(spec)
  end

  def test_eligible_with_ruby_platform
    spec = Gem::Specification.new "a", 1
    spec.required_ruby_version = "~> 3.4.0"
    refute Gem::ContentAddress.eligible?(spec)
  end

  def test_eligible_with_nil_platform
    spec = Gem::Specification.new "a", 1
    spec.required_ruby_version = "~> 3.4.0"
    spec.platform = nil
    refute Gem::ContentAddress.eligible?(spec)
  end

  def test_ruby_abi_returns_nil_for_non_numeric_segments
    assert_nil Gem::ContentAddress.ruby_abi_for(Gem::Requirement.new("~> 3.a.0"))
  end

  def test_content_addressed_with_eligible_spec_and_valid_address
    spec = Gem::Specification.new "a", 1
    spec.required_ruby_version = "~> 3.4.0"
    spec.platform = "x86_64-linux"
    spec.content_address = "abcdef12"
    assert Gem::ContentAddress.content_addressed?(spec)
  end

  def test_content_addressed_with_non_abi_shaped_required_ruby_version_and_valid_address
    spec = Gem::Specification.new "a", 1
    spec.required_ruby_version = ">= 3.0"
    spec.platform = "x86_64-linux"
    spec.content_address = "abcdef12"
    refute Gem::ContentAddress.content_addressed?(spec)
  end

  def test_content_addressed_with_eligible_spec_and_no_address
    spec = Gem::Specification.new "a", 1
    spec.required_ruby_version = "~> 3.4.0"
    spec.platform = "x86_64-linux"
    refute Gem::ContentAddress.content_addressed?(spec)
  end

  def test_content_addressed_with_eligible_spec_and_invalid_address
    spec = Gem::Specification.new "a", 1
    spec.required_ruby_version = "~> 3.4.0"
    spec.platform = "x86_64-linux"
    spec.content_address = "x86_64-linux"
    refute Gem::ContentAddress.content_addressed?(spec)
  end

  def test_content_addressed_with_ineligible_spec_and_valid_address
    spec = Gem::Specification.new "a", 1
    spec.content_address = "abcdef12"
    refute Gem::ContentAddress.content_addressed?(spec)
  end

  def test_eligible_without_ruby_abi_validation
    spec = Gem::Specification.new "a", 1
    spec.platform = "x86_64-linux"
    assert Gem::ContentAddress.eligible?(spec, validate_ruby_abi: false)

    spec.required_ruby_version = ">= 3.0"
    assert Gem::ContentAddress.eligible?(spec, validate_ruby_abi: false)
  end

  def test_eligible_without_ruby_abi_validation_still_requires_eligible_platform
    spec = Gem::Specification.new "a", 1
    refute Gem::ContentAddress.eligible?(spec, validate_ruby_abi: false)
  end

  def test_content_addressed_without_ruby_abi_validation
    spec = Gem::Specification.new "a", 1
    spec.platform = "x86_64-linux"
    spec.content_address = "abcdef12"
    refute Gem::ContentAddress.content_addressed?(spec)
    assert Gem::ContentAddress.content_addressed?(spec, validate_ruby_abi: false)
  end

  def test_content_addressed_without_ruby_abi_validation_still_requires_address
    spec = Gem::Specification.new "a", 1
    spec.platform = "x86_64-linux"
    refute Gem::ContentAddress.content_addressed?(spec, validate_ruby_abi: false)
  end

  def test_content_addressed_without_ruby_abi_validation_still_requires_eligible_platform
    spec = Gem::Specification.new "a", 1
    spec.content_address = "abcdef12"
    refute Gem::ContentAddress.content_addressed?(spec, validate_ruby_abi: false)
  end

  def test_content_addressed_row
    assert Gem::ContentAddress.content_addressed_row?("abcdef12", Gem::Platform.new("x86_64-linux"), Gem::Requirement.new("~> 3.4.0"))
  end

  def test_content_addressed_row_without_address_shaped_suffix
    refute Gem::ContentAddress.content_addressed_row?("x86_64-linux", Gem::Platform.new("x86_64-linux"), Gem::Requirement.new("~> 3.4.0"))
  end

  def test_content_addressed_row_without_platform
    refute Gem::ContentAddress.content_addressed_row?("abcdef12", nil, Gem::Requirement.new("~> 3.4.0"))
  end

  def test_content_addressed_row_without_ruby_requirement
    refute Gem::ContentAddress.content_addressed_row?("abcdef12", Gem::Platform.new("x86_64-linux"), nil)
  end

  def test_content_addressed_row_with_non_abi_ruby_requirement
    refute Gem::ContentAddress.content_addressed_row?("abcdef12", Gem::Platform.new("x86_64-linux"), Gem::Requirement.new(">= 3.0"))
  end

  def test_content_addressed_row_without_ruby_abi_validation
    assert Gem::ContentAddress.content_addressed_row?("abcdef12", Gem::Platform.new("x86_64-linux"), validate_ruby_abi: false)
    refute Gem::ContentAddress.content_addressed_row?("abcdef12", nil, validate_ruby_abi: false)
    refute Gem::ContentAddress.content_addressed_row?("x86_64-linux", Gem::Platform.new("x86_64-linux"), validate_ruby_abi: false)
  end

  def test_ruby_abi_compatible_with_unset_requirement
    spec = Gem::Specification.new "a", 1
    assert Gem::ContentAddress.ruby_abi_compatible?(spec, "3.4")
  end

  def test_ruby_abi_compatible_with_matching_abi
    spec = Gem::Specification.new "a", 1
    spec.required_ruby_version = "~> 3.4.0"
    assert Gem::ContentAddress.ruby_abi_compatible?(spec, "3.4")
  end

  def test_ruby_abi_compatible_with_different_abi
    spec = Gem::Specification.new "a", 1
    spec.required_ruby_version = "~> 3.3.0"
    refute Gem::ContentAddress.ruby_abi_compatible?(spec, "3.4")
  end

  def test_ruby_abi_compatible_with_non_abi_shaped_requirement
    spec = Gem::Specification.new "a", 1
    spec.required_ruby_version = ">= 3.0"
    refute Gem::ContentAddress.ruby_abi_compatible?(spec, "3.4")
  end

  def test_address_for
    assert_equal Digest::SHA256.hexdigest("gem bytes")[0, 8], Gem::ContentAddress.address_for("gem bytes")
    assert Gem::ContentAddress.match?(Gem::ContentAddress.address_for("gem bytes"))
  end

  def test_address_for_with_length
    address = Gem::ContentAddress.address_for("gem bytes", length: 64)
    assert_equal Digest::SHA256.hexdigest("gem bytes"), address
    assert Gem::ContentAddress.match?(address)
  end

  def test_file_name_claim_with_address_suffix
    spec = Gem::Specification.new "a", 1
    spec.platform = "x86_64-linux"

    assert_equal "abcdef12", Gem::ContentAddress.file_name_claim("a-1-abcdef12", spec)
  end

  def test_file_name_claim_with_platform_suffix
    spec = Gem::Specification.new "a", 1
    spec.platform = "x86_64-linux"

    assert_nil Gem::ContentAddress.file_name_claim("a-1-x86_64-linux", spec)
  end

  def test_file_name_claim_without_suffix
    spec = Gem::Specification.new "a", 1
    spec.platform = "x86_64-linux"

    assert_nil Gem::ContentAddress.file_name_claim("a-1", spec)
  end

  def test_file_name_claim_with_hex_looking_original_platform
    spec = Gem::Specification.new "a", 1
    spec.platform = "deadbeef"

    assert_nil Gem::ContentAddress.file_name_claim("a-1-deadbeef", spec)
  end

  def test_file_name_claim_with_hex_looking_normalized_platform
    duck_spec = Struct.new(:name, :version, :platform, :original_platform).new("a", "1", "deadbeef", "unknown")
    assert_nil Gem::ContentAddress.file_name_claim("a-1-deadbeef", duck_spec)
  end

  def test_verified_file_name_claim_returns_verified_address
    spec, gem_path = util_gem("a", 2)

    address = Digest::SHA256.file(gem_path).hexdigest[0, 8]
    ca_path = File.join(File.dirname(gem_path), "a-2-#{address}.gem")
    FileUtils.cp gem_path, ca_path

    assert_equal address, Gem::ContentAddress.verified_file_name_claim(ca_path, spec)
  end

  def test_verified_file_name_claim_returns_nil_without_claim
    spec, gem_path = util_gem("a", 2)

    assert_nil Gem::ContentAddress.verified_file_name_claim(gem_path, spec)
  end

  def test_verified_file_name_claim_raises_on_mismatch
    spec, gem_path = util_gem("a", 2)

    ca_path = File.join(File.dirname(gem_path), "a-2-deadbeef.gem")
    FileUtils.cp gem_path, ca_path

    e = assert_raise Gem::InstallError do
      Gem::ContentAddress.verified_file_name_claim(ca_path, spec)
    end

    assert_match(/content address mismatch/, e.message)
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
