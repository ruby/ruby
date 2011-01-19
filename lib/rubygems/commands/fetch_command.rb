######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require 'rubygems/command'
require 'rubygems/local_remote_options'
require 'rubygems/version_option'
require 'rubygems/source_info_cache'

class Gem::Commands::FetchCommand < Gem::Command

  include Gem::LocalRemoteOptions
  include Gem::VersionOption

  def initialize
    super 'fetch', 'Download a gem and place it in the current directory'

    add_bulk_threshold_option
    add_proxy_option
    add_source_option

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

  def usage # :nodoc:
    "#{program_name} GEMNAME [GEMNAME ...]"
  end

  def execute
    version = options[:version] || Gem::Requirement.default
    all = Gem::Requirement.default != version

    gem_names = get_all_gem_names

    gem_names.each do |gem_name|
      dep = Gem::Dependency.new gem_name, version
      dep.prerelease = options[:prerelease]

      specs_and_sources = Gem::SpecFetcher.fetcher.fetch(dep, all, true,
                                                         dep.prerelease?)

      specs_and_sources, errors =
        Gem::SpecFetcher.fetcher.fetch_with_errors(dep, all, true,
                                                   dep.prerelease?)

      spec, source_uri = specs_and_sources.sort_by { |s,| s.version }.last

      if spec.nil? then
        show_lookup_failure gem_name, version, errors, options[:domain]
        next
      end

      path = Gem::RemoteFetcher.fetcher.download spec, source_uri
      FileUtils.mv path, spec.file_name

      say "Downloaded #{spec.full_name}"
    end
  end

end

