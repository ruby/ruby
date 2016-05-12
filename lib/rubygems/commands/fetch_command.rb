# frozen_string_literal: true
require 'rubygems/command'
require 'rubygems/local_remote_options'
require 'rubygems/version_option'

class Gem::Commands::FetchCommand < Gem::Command

  include Gem::LocalRemoteOptions
  include Gem::VersionOption

  def initialize
    super 'fetch', 'Download a gem and place it in the current directory'

    add_bulk_threshold_option
    add_proxy_option
    add_source_option
    add_clear_sources_option

    add_version_option
    add_platform_option
    add_prerelease_option
  end

  def arguments # :nodoc:
    'GEMNAME       name of gem to download'
  end

  def defaults_str # :nodoc:
    "--version '#{Gem::Requirement.default}'"
  end

  def description # :nodoc:
    <<-EOF
The fetch command fetches gem files that can be stored for later use or
unpacked to examine their contents.

See the build command help for an example of unpacking a gem, modifying it,
then repackaging it.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME [GEMNAME ...]"
  end

  def execute
    version = options[:version] || Gem::Requirement.default

    platform  = Gem.platforms.last
    gem_names = get_all_gem_names

    gem_names.each do |gem_name|
      dep = Gem::Dependency.new gem_name, version
      dep.prerelease = options[:prerelease]

      specs_and_sources, errors =
        Gem::SpecFetcher.fetcher.spec_for_dependency dep

      if platform then
        filtered = specs_and_sources.select { |s,| s.platform == platform }
        specs_and_sources = filtered unless filtered.empty?
      end

      spec, source = specs_and_sources.max_by { |s,| s.version }

      if spec.nil? then
        show_lookup_failure gem_name, version, errors, options[:domain]
        next
      end

      source.download spec

      say "Downloaded #{spec.full_name}"
    end
  end

end

