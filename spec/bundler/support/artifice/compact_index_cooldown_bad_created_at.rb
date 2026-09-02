# frozen_string_literal: true

require_relative "helpers/compact_index_cooldown"

# Serves every version with a created_at year that Time.iso8601 accepts but
# whose distance from now overflows Float.
class CompactIndexCooldownBadCreatedAt < CompactIndexCooldownAPI
  helpers do
    def build_gem_version(spec, deps, checksum)
      CompactIndex::GemVersionV2.new(spec.version.version, spec.platform.to_s, checksum, nil,
        deps, spec.required_ruby_version.to_s, spec.required_rubygems_version.to_s, "#{"9" * 400}-01-01T00:00:00Z")
    end
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(CompactIndexCooldownBadCreatedAt)
