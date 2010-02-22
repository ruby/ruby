require 'fileutils'
require 'rubygems/command'
require 'rubygems/installer'
require 'rubygems/version_option'

class Gem::Commands::UnpackCommand < Gem::Command

  include Gem::VersionOption

  def initialize
    super 'unpack', 'Unpack an installed gem to the current directory',
          :version => Gem::Requirement.default,
          :target  => Dir.pwd

    add_option('--target=DIR', 'target directory for unpacking') do |value, options|
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

  #--
  # TODO: allow, e.g., 'gem unpack rake-0.3.1'.  Find a general solution for
  # this, so that it works for uninstall as well.  (And check other commands
  # at the same time.)

  def execute
    get_all_gem_names.each do |name|
      path = get_path name, options[:version]

      if path then
        basename = File.basename(path, '.gem')
        target_dir = File.expand_path File.join(options[:target], basename)
        FileUtils.mkdir_p target_dir
        Gem::Installer.new(path, :unpack => true).unpack target_dir
        say "Unpacked gem: '#{target_dir}'"
      else
        alert_error "Gem '#{name}' not installed."
      end
    end
  end

  # Return the full path to the cached gem file matching the given
  # name and version requirement.  Returns 'nil' if no match.
  #
  # Example:
  #
  #   get_path('rake', '> 0.4')   # -> '/usr/lib/ruby/gems/1.8/cache/rake-0.4.2.gem'
  #   get_path('rake', '< 0.1')   # -> nil
  #   get_path('rak')             # -> nil (exact name required)
  #--
  # TODO: This should be refactored so that it's a general service. I don't
  # think any of our existing classes are the right place though.  Just maybe
  # 'Cache'?
  #
  # TODO: It just uses Gem.dir for now.  What's an easy way to get the list of
  # source directories?
  def get_path(gemname, version_req)
    return gemname if gemname =~ /\.gem$/i

    specs = Gem::source_index.find_name gemname, version_req

    selected = specs.sort_by { |s| s.version }.last

    return nil if selected.nil?

    # We expect to find (basename).gem in the 'cache' directory.
    # Furthermore, the name match must be exact (ignoring case).
    if gemname =~ /^#{selected.name}$/i
      filename = selected.file_name
      path = nil

      Gem.path.find do |gem_dir|
        path = File.join gem_dir, 'cache', filename
        File.exist? path
      end

      path
    else
      nil
    end
  end

end

