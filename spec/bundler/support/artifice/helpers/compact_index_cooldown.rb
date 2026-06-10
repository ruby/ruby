# frozen_string_literal: true

require_relative "compact_index"

class CompactIndexCooldownAPI < CompactIndexAPI
  helpers do
    def build_gem_version(spec, deps, checksum)
      created_at = spec.date&.utc&.iso8601
      CompactIndex::GemVersionV2.new(spec.version.version, spec.platform.to_s, checksum, nil,
        deps, spec.required_ruby_version.to_s, spec.required_rubygems_version.to_s, created_at)
    end
  end
end
