# frozen_string_literal: true

##
# Gem::ContentAddress is the single home for content-addressing semantics:
# what an address and a Ruby ABI look like, which specs are eligible, how
# addresses are generated and verified against gem files.
module Gem::ContentAddress
  ##
  # A content address is 8 to 64 lowercase hexadecimal characters -- a
  # prefix of the SHA256 digest of the gem file contents.

  PATTERN = /\A[0-9a-f]{8,64}\z/

  ##
  # A Ruby ABI is a major and minor version pair ("X.Y").

  RUBY_ABI_PATTERN = /\A\d+\.\d+\z/

  private_constant :PATTERN, :RUBY_ABI_PATTERN

  ##
  # Default number of hexadecimal characters in a generated content address.

  DEFAULT_LENGTH = 8

  ##
  # Whether +value+ is a valid content address (a string of 8-64
  # lowercase hexadecimal characters). This only checks the shape of a
  # string: use content_addressed? to ask whether a spec is actually
  # content addressed, and file_name_claim to ask whether a file name
  # claims an address.

  def self.match?(value)
    value.is_a?(String) && PATTERN.match?(value)
  end

  ##
  # Whether +value+ is a well-formed Ruby ABI ("X.Y").

  def self.valid_ruby_abi?(value)
    value.is_a?(String) && RUBY_ABI_PATTERN.match?(value)
  end

  ##
  # Derives the Ruby ABI ("X.Y") from +required_ruby_version+. Only a
  # single pessimistic requirement with three segments ending in zero
  # ("~> X.Y.0") pins an ABI. Returns nil for any other shape.

  def self.ruby_abi_for(required_ruby_version)
    return nil if required_ruby_version.nil?

    requirements = required_ruby_version.requirements
    return nil if requirements.size != 1

    op, version = requirements.first
    return nil if op != "~>" || version.segments.size != 3 || version.segments[2] != 0

    version.segments[0..1].join(".")
  end

  ##
  # The required_ruby_version that pins +ruby_abi+ ("X.Y" to "~> X.Y.0").
  # Inverse of +ruby_abi_for+.

  def self.ruby_abi_requirement(ruby_abi)
    Gem::Requirement.new("~> #{ruby_abi}.0")
  end

  ##
  # Whether +platform+ is eligible for content addressing: present and
  # not the generic RUBY platform.

  def self.platform_eligible?(platform)
    !platform.nil? && platform != Gem::Platform::RUBY
  end

  ##
  # Whether +spec+ is eligible for content addressing. A gem must pin
  # its required_ruby_version to a single Ruby ABI ("~> X.Y.0") and
  # declare a non-RUBY platform to be content addressed. This makes
  # `content_addressed? implies ruby_abi present` structural: no spec
  # can count as content addressed without an ABI to scope it by.

  def self.eligible?(spec, validate_ruby_abi: true)
    return false unless platform_eligible?(spec.platform)
    return true unless validate_ruby_abi

    !ruby_abi_for(spec.required_ruby_version).nil?
  end

  ##
  # Whether +spec+ is content-addressed: it is eligible for content
  # addressing and has a valid content address set. See eligible? for
  # when to pass <tt>validate_ruby_abi: false</tt>.

  def self.content_addressed?(spec, validate_ruby_abi: true)
    eligible?(spec, validate_ruby_abi: validate_ruby_abi) && match?(spec.content_address)
  end

  ##
  # Whether an index row describes a content-addressed gem: an
  # address-shaped +suffix+, a pinned +platform+, and a
  # +required_ruby_version+ pinning a single Ruby ABI. Rows missing any
  # of these must not assign a content address, so specs cannot be
  # constructed half content-addressed. See eligible? for when to pass
  # <tt>validate_ruby_abi: false</tt>.

  def self.content_addressed_row?(suffix, platform, required_ruby_version = nil, validate_ruby_abi: true)
    return false unless match?(suffix) && platform_eligible?(platform)
    return true unless validate_ruby_abi

    !ruby_abi_for(required_ruby_version).nil?
  end

  ##
  # Whether +spec+'s required_ruby_version permits building for +ruby_abi+:
  # an unset or default requirement can still be pinned to the ABI, and
  # anything else must already pin exactly that ABI. Used at build time,
  # before the requirement is injected, where eligible? would be
  # premature.

  def self.ruby_abi_compatible?(spec, ruby_abi)
    required_ruby_version = spec.required_ruby_version
    return true if required_ruby_version.nil? || required_ruby_version.none?

    ruby_abi_for(required_ruby_version) == ruby_abi
  end

  ##
  # Generates the content address for +bytes+: the first +length+
  # characters of the hexadecimal SHA256 digest of the contents.

  def self.address_for(bytes, length: DEFAULT_LENGTH)
    require "digest"
    Digest::SHA256.hexdigest(bytes)[0, length]
  end

  ##
  # The content address claimed by a gem file name, or nil when the name
  # makes no claim. +filename+ is the file's base name without the ".gem"
  # extension ("name-version[-suffix]"). A name claims an address when its
  # suffix is address-shaped and is not just +spec+'s own platform: a
  # platform string that happens to look like hexadecimal (both
  # normalized and original spellings) is a platform name, not a claim.

  def self.file_name_claim(filename, spec)
    suffix = filename.delete_prefix("#{spec.name}-#{spec.version}-")
    return nil if suffix == filename
    return nil unless match?(suffix)
    return nil if [spec.platform.to_s, spec.original_platform.to_s].include?(suffix)

    suffix
  end

  ##
  # Verifies the content address claimed by the gem file at +path+ against
  # the SHA256 digest of its contents. Returns the verified address, or nil
  # when the file name makes no claim. Raises Gem::InstallError when the
  # contents do not match the claim, regardless of whether the packaged
  # +spec+ is eligible, so swapped contents cannot hide behind an
  # ineligible specification.

  def self.verified_file_name_claim(path, spec)
    basename = File.basename(path, ".gem")
    address = file_name_claim(basename, spec)
    return nil unless address

    require "digest"
    digest = Digest::SHA256.file(path).hexdigest
    unless digest.start_with?(address)
      raise Gem::InstallError, "content address mismatch for #{File.basename(path)}"
    end

    address
  end

  ##
  # Ranks +spec+ for candidate selection against +ruby_version+: a
  # content-addressed spec built for that Ruby ranks first (0), any
  # non-content-addressed spec next (1), and a content-addressed spec built
  # for another Ruby last (2), since its binary cannot load there.

  def self.ruby_abi_specificity_match(spec, ruby_version = Gem.ruby_version)
    return 1 unless match?(spec.content_address)

    if spec.required_ruby_version.satisfied_by?(ruby_version)
      0
    else
      2
    end
  end
end
