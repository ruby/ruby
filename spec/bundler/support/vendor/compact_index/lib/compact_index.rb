# frozen_string_literal: true

# Vendored from https://github.com/rubygems/compact_index v0.15.0

require_relative "compact_index/gem"
require_relative "compact_index/gem_version"
require_relative "compact_index/dependency"

require_relative "compact_index/versions_file"

module VendoredCompactIndex
  def self.names(gem_names)
    gem_names.join("\n").prepend("---\n") << "\n"
  end

  def self.versions(versions_file, gems = nil, args = {})
    versions_file.contents(gems, args)
  end

  def self.info(versions)
    versions.inject(+"---\n") do |output, version|
      output << version.to_line << "\n"
    end
  end
end
