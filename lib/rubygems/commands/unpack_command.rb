######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require 'rubygems/command'
require 'rubygems/installer'
require 'rubygems/version_option'

class Gem::Commands::UnpackCommand < Gem::Command

  include Gem::VersionOption

  def initialize
    require 'fileutils'

    super 'unpack', 'Unpack an installed gem to the current directory',
          :version => Gem::Requirement.default,
          :target  => Dir.pwd

    add_option('--target=DIR',
               'target directory for unpacking') do |value, options|
      options[:target] = value
    end

    add_version_option
  end

  def arguments # :nodoc:
    "GEMNAME       name of gem to unpack"
  end

  def defaults_str # :nodoc:
    "--version '#{Gem::Requirement.default}'"
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME"
  end

  def download dependency
    found = Gem::SpecFetcher.fetcher.fetch dependency

    return if found.empty?

    spec, source_uri = found.first

    Gem::RemoteFetcher.fetcher.download spec, source_uri
  end

  #--
  # TODO: allow, e.g., 'gem unpack rake-0.3.1'.  Find a general solution for
  # this, so that it works for uninstall as well.  (And check other commands
  # at the same time.)

  def execute
    get_all_gem_names.each do |name|
      dependency = Gem::Dependency.new name, options[:version]
      path = get_path dependency

      if path then
        basename = File.basename path, '.gem'
        target_dir = File.expand_path basename, options[:target]
        FileUtils.mkdir_p target_dir
        Gem::Installer.new(path, :unpack => true).unpack target_dir
        say "Unpacked gem: '#{target_dir}'"
      else
        alert_error "Gem '#{name}' not installed."
      end
    end
  end

  ##
  # Return the full path to the cached gem file matching the given
  # name and version requirement.  Returns 'nil' if no match.
  #
  # Example:
  #
  #   get_path 'rake', '> 0.4' # "/usr/lib/ruby/gems/1.8/cache/rake-0.4.2.gem"
  #   get_path 'rake', '< 0.1' # nil
  #   get_path 'rak'           # nil (exact name required)
  #--
  # TODO: This should be refactored so that it's a general service. I don't
  # think any of our existing classes are the right place though.  Just maybe
  # 'Cache'?
  #
  # TODO: It just uses Gem.dir for now.  What's an easy way to get the list of
  # source directories?

  def get_path dependency
    return dependency.name if dependency.name =~ /\.gem$/i

    specs = Gem.source_index.search dependency

    selected = specs.sort_by { |s| s.version }.last

    return download(dependency) if selected.nil?

    return unless dependency.name =~ /^#{selected.name}$/i

    # We expect to find (basename).gem in the 'cache' directory.  Furthermore,
    # the name match must be exact (ignoring case).
    filename = selected.file_name
    path = nil

    Gem.path.find do |gem_dir|
      path = File.join gem_dir, 'cache', filename
      File.exist? path
    end

    path
  end

end

