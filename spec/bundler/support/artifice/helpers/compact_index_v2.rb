# frozen_string_literal: true

require_relative "compact_index"

class CompactIndexV2API < CompactIndexAPI
  helpers do
    def build_gem_version(spec, deps, checksum)
      created_at = spec.date&.utc&.iso8601
      CompactIndex::GemVersionV2.new(spec.version.version, spec.platform.to_s, checksum, nil,
        deps, spec.required_ruby_version.to_s, spec.required_rubygems_version.to_s, created_at,
        spec.ruby_abi, spec.content_address)
    end

    def content_addressable_specs(gem_repo)
      Dir.glob(File.join(gem_repo, "gems", "*.gem")).filter_map do |file|
        token = File.basename(file, ".gem").rpartition("-").last
        next unless Gem::ContentAddress.match?(token)

        spec = Gem::Package.new(file).spec
        next unless Gem::ContentAddress.applicable?(spec)
        spec.content_address = token
        spec
      end
    end
  end

  def gems(gem_repo = default_gem_repo)
    all_gems = super
    ca_specs = content_addressable_specs(gem_repo)
    ca_specs.group_by(&:name).each do |name, versions|
      gem = all_gems.find {|g| g.name == name }
      new_versions = versions.map do |spec|
        deps = spec.runtime_dependencies.map do |d|
          reqs = d.requirement.requirements.map {|r| r.join(" ") }.join(", ")
          CompactIndex::Dependency.new(d.name, reqs)
        end
        begin
          checksum = Digest(:SHA256).file("#{gem_repo}/gems/#{spec.full_name}.gem").hexdigest
        rescue StandardError
          checksum = nil
        end
        build_gem_version(spec, deps, checksum)
      end
      if gem
        gem.versions.concat(new_versions)
      else
        all_gems << CompactIndex::Gem.new(name, new_versions)
      end
    end
    all_gems
  end
end
