#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'fileutils'
require 'pathname'
require 'rbconfig'

require 'rubygems/format'
require 'rubygems/ext'
require 'rubygems/require_paths_builder'

##
# The installer class processes RubyGem .gem files and installs the
# files contained in the .gem into the Gem.path.
#
# Gem::Installer does the work of putting files in all the right places on the
# filesystem including unpacking the gem into its gem dir, installing the
# gemspec in the specifications dir, storing the cached gem in the cache dir,
# and installing either wrappers or symlinks for executables.

class Gem::Installer

  ##
  # Raised when there is an error while building extensions.
  #
  class ExtensionBuildError < Gem::InstallError; end

  include Gem::UserInteraction

  include Gem::RequirePathsBuilder

  ##
  # The directory a gem's executables will be installed into

  attr_reader :bin_dir

  ##
  # The gem repository the gem will be installed into

  attr_reader :gem_home

  ##
  # The Gem::Specification for the gem being installed

  attr_reader :spec

  @home_install_warning = false
  @path_warning = false

  class << self

    ##
    # True if we've warned about ~/.gems install

    attr_accessor :home_install_warning

    ##
    # True if we've warned about PATH not including Gem.bindir

    attr_accessor :path_warning

    attr_writer :exec_format

    # Defaults to use Ruby's program prefix and suffix.
    def exec_format
      @exec_format ||= Gem.default_exec_format
    end

  end

  ##
  # Constructs an Installer instance that will install the gem located at
  # +gem+.  +options+ is a Hash with the following keys:
  #
  # :env_shebang:: Use /usr/bin/env in bin wrappers.
  # :force:: Overrides all version checks and security policy checks, except
  #          for a signed-gems-only policy.
  # :ignore_dependencies:: Don't raise if a dependency is missing.
  # :install_dir:: The directory to install the gem into.
  # :format_executable:: Format the executable the same as the ruby executable.
  #                      If your ruby is ruby18, foo_exec will be installed as
  #                      foo_exec18.
  # :security_policy:: Use the specified security policy.  See Gem::Security
  # :wrappers:: Install wrappers if true, symlinks if false.

  def initialize(gem, options={})
    @gem = gem

    options = {
      :bin_dir      => nil,
      :env_shebang  => false,
      :exec_format  => false,
      :force        => false,
      :install_dir  => Gem.dir,
      :source_index => Gem.source_index,
    }.merge options

    @env_shebang = options[:env_shebang]
    @force = options[:force]
    gem_home = options[:install_dir]
    @gem_home = Pathname.new(gem_home).expand_path
    @ignore_dependencies = options[:ignore_dependencies]
    @format_executable = options[:format_executable]
    @security_policy = options[:security_policy]
    @wrappers = options[:wrappers]
    @bin_dir = options[:bin_dir]
    @development = options[:development]
    @source_index = options[:source_index]

    begin
      @format = Gem::Format.from_file_by_path @gem, @security_policy
    rescue Gem::Package::FormatError
      raise Gem::InstallError, "invalid gem format for #{@gem}"
    end

    begin
      FileUtils.mkdir_p @gem_home
    rescue Errno::EACCES, Errno::ENOTDIR
      # We'll divert to ~/.gem below
    end

    if not File.writable? @gem_home or
        # TODO: Shouldn't have to test for existence of bindir; tests need it.
        (@gem_home.to_s == Gem.dir and File.exist? Gem.bindir and
         not File.writable? Gem.bindir) then
      if options[:user_install] == false then # You don't want to use ~
        raise Gem::FilePermissionError, @gem_home
      elsif options[:user_install].nil? then
        unless self.class.home_install_warning then
          alert_warning "Installing to ~/.gem since #{@gem_home} and\n\t  #{Gem.bindir} aren't both writable."
          self.class.home_install_warning = true
        end
      end
      options[:user_install] = true
    end

    if options[:user_install] and not options[:unpack] then
      @gem_home = Gem.user_dir

      user_bin_dir = File.join(@gem_home, 'bin')
      unless ENV['PATH'].split(File::PATH_SEPARATOR).include? user_bin_dir then
        unless self.class.path_warning then
          alert_warning "You don't have #{user_bin_dir} in your PATH,\n\t  gem executables will not run."
          self.class.path_warning = true
        end
      end

      FileUtils.mkdir_p @gem_home unless File.directory? @gem_home
      # If it's still not writable, you've got issues.
      raise Gem::FilePermissionError, @gem_home unless File.writable? @gem_home
    end

    @spec = @format.spec

    @gem_dir = File.join(@gem_home, "gems", @spec.full_name).untaint
  end

  ##
  # Installs the gem and returns a loaded Gem::Specification for the installed
  # gem.
  #
  # The gem will be installed with the following structure:
  #
  #   @gem_home/
  #     cache/<gem-version>.gem #=> a cached copy of the installed gem
  #     gems/<gem-version>/... #=> extracted files
  #     specifications/<gem-version>.gemspec #=> the Gem::Specification

  def install
    # If we're forcing the install then disable security unless the security
    # policy says that we only install singed gems.
    @security_policy = nil if @force and @security_policy and
                              not @security_policy.only_signed

    unless @force then
      if rrv = @spec.required_ruby_version then
        unless rrv.satisfied_by? Gem.ruby_version then
          raise Gem::InstallError, "#{@spec.name} requires Ruby version #{rrv}"
        end
      end

      if rrgv = @spec.required_rubygems_version then
        unless rrgv.satisfied_by? Gem::Version.new(Gem::RubyGemsVersion) then
          raise Gem::InstallError,
                "#{@spec.name} requires RubyGems version #{rrgv}"
        end
      end

      unless @ignore_dependencies then
        deps = @spec.runtime_dependencies
        deps |= @spec.development_dependencies if @development

        deps.each do |dep_gem|
          ensure_dependency @spec, dep_gem
        end
      end
    end

    Gem.pre_install_hooks.each do |hook|
      hook.call self
    end

    FileUtils.mkdir_p @gem_home unless File.directory? @gem_home

    Gem.ensure_gem_subdirectories @gem_home

    FileUtils.mkdir_p @gem_dir

    extract_files
    generate_bin
    build_extensions
    write_spec

    write_require_paths_file_if_needed

    # HACK remove?  Isn't this done in multiple places?
    cached_gem = File.join @gem_home, "cache", @gem.split(/\//).pop
    unless File.exist? cached_gem then
      FileUtils.cp @gem, File.join(@gem_home, "cache")
    end

    say @spec.post_install_message unless @spec.post_install_message.nil?

    @spec.loaded_from = File.join(@gem_home, 'specifications',
                                  "#{@spec.full_name}.gemspec")

    @source_index.add_spec @spec

    Gem.post_install_hooks.each do |hook|
      hook.call self
    end

    return @spec
  rescue Zlib::GzipFile::Error
    raise Gem::InstallError, "gzip error installing #{@gem}"
  end

  ##
  # Ensure that the dependency is satisfied by the current installation of
  # gem.  If it is not an exception is raised.
  #
  # spec       :: Gem::Specification
  # dependency :: Gem::Dependency

  def ensure_dependency(spec, dependency)
    unless installation_satisfies_dependency? dependency then
      raise Gem::InstallError, "#{spec.name} requires #{dependency}"
    end

    true
  end

  ##
  # True if the gems in the source_index satisfy +dependency+.

  def installation_satisfies_dependency?(dependency)
    @source_index.find_name(dependency.name, dependency.version_requirements).size > 0
  end

  ##
  # Unpacks the gem into the given directory.

  def unpack(directory)
    @gem_dir = directory
    @format = Gem::Format.from_file_by_path @gem, @security_policy
    extract_files
  end

  ##
  # Writes the .gemspec specification (in Ruby) to the gem home's
  # specifications directory.

  def write_spec
    rubycode = @spec.to_ruby

    file_name = File.join @gem_home, 'specifications',
                          "#{@spec.full_name}.gemspec"

    file_name.untaint

    File.open(file_name, "w") do |file|
      file.puts rubycode
    end
  end

  ##
  # Creates windows .bat files for easy running of commands

  def generate_windows_script(bindir, filename)
    if Gem.win_platform? then
      script_name = filename + ".bat"
      script_path = File.join bindir, File.basename(script_name)
      File.open script_path, 'w' do |file|
        file.puts windows_stub_script(bindir, filename)
      end

      say script_path if Gem.configuration.really_verbose
    end
  end

  def generate_bin
    return if @spec.executables.nil? or @spec.executables.empty?

    # If the user has asked for the gem to be installed in a directory that is
    # the system gem directory, then use the system bin directory, else create
    # (or use) a new bin dir under the gem_home.
    bindir = @bin_dir ? @bin_dir : Gem.bindir(@gem_home)

    Dir.mkdir bindir unless File.exist? bindir
    raise Gem::FilePermissionError.new(bindir) unless File.writable? bindir

    @spec.executables.each do |filename|
      filename.untaint
      bin_path = File.expand_path File.join(@gem_dir, @spec.bindir, filename)
      mode = File.stat(bin_path).mode | 0111
      File.chmod mode, bin_path

      if @wrappers then
        generate_bin_script filename, bindir
      else
        generate_bin_symlink filename, bindir
      end
    end
  end

  ##
  # Creates the scripts to run the applications in the gem.
  #--
  # The Windows script is generated in addition to the regular one due to a
  # bug or misfeature in the Windows shell's pipe.  See
  # http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-talk/193379

  def generate_bin_script(filename, bindir)
    bin_script_path = File.join bindir, formatted_program_filename(filename)

    exec_path = File.join @gem_dir, @spec.bindir, filename

    # HACK some gems don't have #! in their executables, restore 2008/06
    #if File.read(exec_path, 2) == '#!' then
      FileUtils.rm_f bin_script_path # prior install may have been --no-wrappers

      File.open bin_script_path, 'w', 0755 do |file|
        file.print app_script_text(filename)
      end

      say bin_script_path if Gem.configuration.really_verbose

      generate_windows_script bindir, filename
    #else
    #  FileUtils.rm_f bin_script_path
    #  FileUtils.cp exec_path, bin_script_path,
    #               :verbose => Gem.configuration.really_verbose
    #end
  end

  ##
  # Creates the symlinks to run the applications in the gem.  Moves
  # the symlink if the gem being installed has a newer version.

  def generate_bin_symlink(filename, bindir)
    if Gem.win_platform? then
      alert_warning "Unable to use symlinks on Windows, installing wrapper"
      generate_bin_script filename, bindir
      return
    end

    src = File.join @gem_dir, 'bin', filename
    dst = File.join bindir, formatted_program_filename(filename)

    if File.exist? dst then
      if File.symlink? dst then
        link = File.readlink(dst).split File::SEPARATOR
        cur_version = Gem::Version.create(link[-3].sub(/^.*-/, ''))
        return if @spec.version < cur_version
      end
      File.unlink dst
    end

    FileUtils.symlink src, dst, :verbose => Gem.configuration.really_verbose
  end

  ##
  # Generates a #! line for +bin_file_name+'s wrapper copying arguments if
  # necessary.

  def shebang(bin_file_name)
    if @env_shebang then
      "#!/usr/bin/env " + Gem::ConfigMap[:ruby_install_name]
    else
      path = File.join @gem_dir, @spec.bindir, bin_file_name

      File.open(path, "rb") do |file|
        first_line = file.gets
        if first_line =~ /^#!/ then
          # Preserve extra words on shebang line, like "-w".  Thanks RPA.
          shebang = first_line.sub(/\A\#!.*?ruby\S*/, "#!#{Gem.ruby}")
        else
          # Create a plain shebang line.
          shebang = "#!#{Gem.ruby}"
        end

        shebang.strip # Avoid nasty ^M issues.
      end
    end
  end

  ##
  # Return the text for an application file.

  def app_script_text(bin_file_name)
    <<-TEXT
#{shebang bin_file_name}
#
# This file was generated by RubyGems.
#
# The application '#{@spec.name}' is installed as part of a gem, and
# this file is here to facilitate running it.
#

require 'rubygems'

version = "#{Gem::Requirement.default}"

if ARGV.first =~ /^_(.*)_$/ and Gem::Version.correct? $1 then
  version = $1
  ARGV.shift
end

gem '#{@spec.name}', version
load '#{bin_file_name}'
TEXT
  end

  ##
  # return the stub script text used to launch the true ruby script

  def windows_stub_script(bindir, bin_file_name)
    <<-TEXT
@ECHO OFF
IF NOT "%~f0" == "~f0" GOTO :WinNT
@"#{File.basename(Gem.ruby)}" "#{File.join(bindir, bin_file_name)}" %1 %2 %3 %4 %5 %6 %7 %8 %9
GOTO :EOF
:WinNT
@"#{File.basename(Gem.ruby)}" "%~dpn0" %*
TEXT
  end

  ##
  # Builds extensions.  Valid types of extensions are extconf.rb files,
  # configure scripts and rakefiles or mkrf_conf files.

  def build_extensions
    return if @spec.extensions.empty?
    say "Building native extensions.  This could take a while..."
    start_dir = Dir.pwd
    dest_path = File.join @gem_dir, @spec.require_paths.first
    ran_rake = false # only run rake once

    @spec.extensions.each do |extension|
      break if ran_rake
      results = []

      builder = case extension
                when /extconf/ then
                  Gem::Ext::ExtConfBuilder
                when /configure/ then
                  Gem::Ext::ConfigureBuilder
                when /rakefile/i, /mkrf_conf/i then
                  ran_rake = true
                  Gem::Ext::RakeBuilder
                else
                  results = ["No builder for extension '#{extension}'"]
                  nil
                end

      begin
        Dir.chdir File.join(@gem_dir, File.dirname(extension))
        results = builder.build(extension, @gem_dir, dest_path, results)

        say results.join("\n") if Gem.configuration.really_verbose

      rescue => ex
        results = results.join "\n"

        File.open('gem_make.out', 'wb') { |f| f.puts results }

        message = <<-EOF
ERROR: Failed to build gem native extension.

#{results}

Gem files will remain installed in #{@gem_dir} for inspection.
Results logged to #{File.join(Dir.pwd, 'gem_make.out')}
        EOF

        raise ExtensionBuildError, message
      ensure
        Dir.chdir start_dir
      end
    end
  end

  ##
  # Reads the file index and extracts each file into the gem directory.
  #
  # Ensures that files can't be installed outside the gem directory.

  def extract_files
    expand_and_validate_gem_dir

    raise ArgumentError, "format required to extract from" if @format.nil?

    @format.file_entries.each do |entry, file_data|
      path = entry['path'].untaint

      if path =~ /\A\// then # for extra sanity
        raise Gem::InstallError,
              "attempt to install file into #{entry['path'].inspect}"
      end

      path = File.expand_path File.join(@gem_dir, path)

      if path !~ /\A#{Regexp.escape @gem_dir}/ then
        msg = "attempt to install file into %p under %p" %
                [entry['path'], @gem_dir]
        raise Gem::InstallError, msg
      end

      FileUtils.mkdir_p File.dirname(path)

      File.open(path, "wb") do |out|
        out.write file_data
      end

      FileUtils.chmod entry['mode'], path

      say path if Gem.configuration.really_verbose
    end
  end

  ##
  # Prefix and suffix the program filename the same as ruby.

  def formatted_program_filename(filename)
    if @format_executable then
      self.class.exec_format % File.basename(filename)
    else
      filename
    end
  end

  private

  ##
  # HACK Pathname is broken on windows.

  def absolute_path? pathname
    pathname.absolute? or (Gem.win_platform? and pathname.to_s =~ /\A[a-z]:/i)
  end

  def expand_and_validate_gem_dir
    @gem_dir = Pathname.new(@gem_dir).expand_path

    unless absolute_path?(@gem_dir) then # HACK is this possible after #expand_path?
      raise ArgumentError, "install directory %p not absolute" % @gem_dir
    end

    @gem_dir = @gem_dir.to_s
  end

end

