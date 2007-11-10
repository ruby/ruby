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

    gem_names = get_all_gem_names

    gem_names.each do |gem_name|
      dep = Gem::Dependency.new gem_name, version
      specs_and_sources = Gem::SourceInfoCache.search_with_source dep, true

      specs_and_sources.sort_by { |spec,| spec.version }

      spec, source_uri = specs_and_sources.last

      gem_file = "#{spec.full_name}.gem"

      gem_path = File.join source_uri, 'gems', gem_file

      gem = Gem::RemoteFetcher.fetcher.fetch_path gem_path

      File.open gem_file, 'wb' do |fp|
        fp.write gem
      end

      say "Downloaded #{gem_file}"
    end
  end

end

