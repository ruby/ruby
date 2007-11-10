#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'fileutils'

require 'rubygems'
require 'rubygems/installer'
require 'rubygems/source_info_cache'

module Gem

  class RemoteInstaller

    include UserInteraction

    # <tt>options[:http_proxy]</tt>::
    # * [String]: explicit specification of proxy; overrides any
    #   environment variable setting
    # * nil: respect environment variables (HTTP_PROXY, HTTP_PROXY_USER, HTTP_PROXY_PASS)
    # * <tt>:no_proxy</tt>: ignore environment variables and _don't_
    #   use a proxy
    #
    # * <tt>:cache_dir</tt>: override where downloaded gems are cached.
    def initialize(options={})
      @options = options
      @source_index_hash = nil
    end

    # This method will install package_name onto the local system.
    #
    # gem_name::
    #   [String] Name of the Gem to install
    #
    # version_requirement::
    #   [default = ">= 0"] Gem version requirement to install
    #
    # Returns::
    #   an array of Gem::Specification objects, one for each gem installed.
    #
    def install(gem_name, version_requirement = Gem::Requirement.default,
                force = false, install_dir = Gem.dir)
      unless version_requirement.respond_to?(:satisfied_by?)
        version_requirement = Gem::Requirement.new [version_requirement]
      end
      installed_gems = []
      begin
        spec, source = find_gem_to_install(gem_name, version_requirement)
        dependencies = find_dependencies_not_installed(spec.dependencies)

        installed_gems << install_dependencies(dependencies, force, install_dir)

        cache_dir = @options[:cache_dir] || File.join(install_dir, "cache")
        destination_file = File.join(cache_dir, spec.full_name + ".gem")

        download_gem(destination_file, source, spec)

        installer = new_installer(destination_file)
        installed_gems.unshift installer.install(force, install_dir)
      rescue RemoteInstallationSkipped => e
        alert_error e.message
      end
      installed_gems.flatten
    end

    # Return a hash mapping the available source names to the source
    # index of that source.
    def source_index_hash
      return @source_index_hash if @source_index_hash
      @source_index_hash = {}
      Gem::SourceInfoCache.cache_data.each do |source_uri, sic_entry|
        @source_index_hash[source_uri] = sic_entry.source_index
      end
      @source_index_hash
    end

    # Finds the Gem::Specification objects and the corresponding source URI
    # for gems matching +gem_name+ and +version_requirement+
    def specs_n_sources_matching(gem_name, version_requirement)
      specs_n_sources = []

      source_index_hash.each do |source_uri, source_index|
        specs = source_index.search(/^#{Regexp.escape gem_name}$/i,
                                    version_requirement)
        # TODO move to SourceIndex#search?
        ruby_version = Gem::Version.new RUBY_VERSION
        specs = specs.select do |spec|
          spec.required_ruby_version.nil? or
            spec.required_ruby_version.satisfied_by? ruby_version
        end
        specs.each { |spec| specs_n_sources << [spec, source_uri] }
      end

      if specs_n_sources.empty? then
        raise GemNotFoundException, "Could not find #{gem_name} (#{version_requirement}) in any repository"
      end

      specs_n_sources = specs_n_sources.sort_by { |gs,| gs.version }.reverse

      specs_n_sources
    end

    # Find a gem to be installed by interacting with the user.
    def find_gem_to_install(gem_name, version_requirement)
      specs_n_sources = specs_n_sources_matching gem_name, version_requirement

      top_3_versions = specs_n_sources.map{|gs| gs.first.version}.uniq[0..3]
      specs_n_sources.reject!{|gs| !top_3_versions.include?(gs.first.version)}

      binary_gems = specs_n_sources.reject { |item|
        item[0].platform.nil? || item[0].platform==Platform::RUBY
      }

      # only non-binary gems...return latest
      return specs_n_sources.first if binary_gems.empty?

      list = specs_n_sources.collect { |spec, source_uri|
        "#{spec.name} #{spec.version} (#{spec.platform})"
      }

      list << "Skip this gem"
      list << "Cancel installation"

      string, index = choose_from_list(
        "Select which gem to install for your platform (#{RUBY_PLATFORM})",
        list)

      if index.nil? or index == (list.size - 1) then
        raise RemoteInstallationCancelled, "Installation of #{gem_name} cancelled."
      end

      if index == (list.size - 2) then
        raise RemoteInstallationSkipped, "Installation of #{gem_name} skipped."
      end

      specs_n_sources[index]
    end

    def find_dependencies_not_installed(dependencies)
      to_install = []
      dependencies.each do |dependency|
        srcindex = Gem::SourceIndex.from_installed_gems
        matches = srcindex.find_name(dependency.name, dependency.requirement_list)
        to_install.push dependency if matches.empty?
      end
      to_install
    end

    # Install all the given dependencies.  Returns an array of
    # Gem::Specification objects, one for each dependency installed.
    #
    # TODO: For now, we recursively install, but this is not the right
    # way to do things (e.g.  if a package fails to download, we
    # shouldn't install anything).
    def install_dependencies(dependencies, force, install_dir)
      return if @options[:ignore_dependencies]
      installed_gems = []
      dependencies.each do |dep|
        if @options[:include_dependencies] ||
           ask_yes_no("Install required dependency #{dep.name}?", true)
          remote_installer = RemoteInstaller.new @options
          installed_gems << remote_installer.install(dep.name,
                                                     dep.version_requirements,
                                                     force, install_dir)
        elsif force then
          # ignore
        else
          raise DependencyError, "Required dependency #{dep.name} not installed"
        end
      end
      installed_gems
    end

    def download_gem(destination_file, source, spec)
      return if File.exist? destination_file
      uri = source + "/gems/#{spec.full_name}.gem"
      response = Gem::RemoteFetcher.fetcher.fetch_path uri
      write_gem_to_file response, destination_file
    end

    def write_gem_to_file(body, destination_file)
      FileUtils.mkdir_p(File.dirname(destination_file)) unless File.exist?(destination_file)
      File.open(destination_file, 'wb') do |out|
        out.write(body)
      end
    end

    def new_installer(gem)
      return Installer.new(gem, @options)
    end
  end

end
