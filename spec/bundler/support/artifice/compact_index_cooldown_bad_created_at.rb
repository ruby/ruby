# frozen_string_literal: true

require_relative "helpers/compact_index_v2"

# Serves every version with a created_at year that Time.iso8601 accepts but
# whose distance from now overflows Float.
class CompactIndexCooldownBadCreatedAt < CompactIndexV2API
  helpers do
    def build_gem_version(spec, deps, checksum)
      # The system-RubyGems jobs run this artifice against a Gem::Specification
      # that predates the content-addressable accessors.
      ruby_abi = spec.ruby_abi if spec.respond_to?(:ruby_abi)
      content_address = spec.content_address if spec.respond_to?(:content_address)
      VendoredCompactIndex::GemVersionV2.new(spec.version.version, spec.platform.to_s, checksum, nil,
        deps, spec.required_ruby_version.to_s, spec.required_rubygems_version.to_s, "#{"9" * 400}-01-01T00:00:00Z",
        ruby_abi, content_address)
    end
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(CompactIndexCooldownBadCreatedAt)
