# frozen_string_literal: true

require_relative "helper"
require "rubygems/installer"

class Gem::Installer
  ##
  # Available through requiring rubygems/installer_test_case

  attr_writer :bin_dir

  ##
  # Available through requiring rubygems/installer_test_case

  attr_writer :build_args

  ##
  # Available through requiring rubygems/installer_test_case

  attr_writer :gem_dir

  ##
  # Available through requiring rubygems/installer_test_case

  attr_writer :force

  ##
  # Available through requiring rubygems/installer_test_case

  attr_writer :format

  ##
  # Available through requiring rubygems/installer_test_case

  attr_writer :gem_home

  ##
  # Available through requiring rubygems/installer_test_case

  attr_writer :env_shebang

  ##
  # Available through requiring rubygems/installer_test_case

  attr_writer :ignore_dependencies

  ##
  # Available through requiring rubygems/installer_test_case

  attr_writer :format_executable

  ##
  # Available through requiring rubygems/installer_test_case

  attr_writer :security_policy

  ##
  # Available through requiring rubygems/installer_test_case

  attr_writer :wrappers
end

##
# A test case for Gem::Installer.

class Gem::InstallerTestCase < Gem::TestCase
  ##
  # The path where installed executables live

  def util_inst_bindir
    File.join @gemhome, "bin"
  end

  ##
  # Adds an executable named "executable" to +spec+ with the given +shebang+.
  #
  # The executable is also written to the bin dir in @tmpdir and the installed
  # gem directory for +spec+.

  def util_make_exec(spec = @spec, shebang = "#!/usr/bin/ruby", bindir = "bin")
    spec.executables = %w[executable]
    spec.bindir = bindir

    exec_path = spec.bin_file "executable"
    write_file exec_path do |io|
      io.puts shebang
    end

    bin_path = File.join @tempdir, "bin", "executable"
    write_file bin_path do |io|
      io.puts shebang
    end
  end

  ##
  # Creates the following instance variables:
  #
  # @spec::
  #   a spec named 'a', intended for regular installs
  #
  # @gem::
  #   the path to a built gem from @spec
  #
  # And returns a Gem::Installer for the @spec that installs into @gemhome

  def setup_base_installer(force = true)
    @gem = setup_base_gem
    util_installer @spec, @gemhome, force
  end

  ##
  # Creates the following instance variables:
  #
  # @spec::
  #   a spec named 'a', intended for regular installs
  #
  # And returns a gem built for the @spec

  def setup_base_gem
    @spec = setup_base_spec
    util_build_gem @spec
    @spec.cache_file
  end

  ##
  # Sets up a generic specification for testing the rubygems installer
  #
  # And returns it

  def setup_base_spec
    quick_gem "a" do |spec|
      util_make_exec spec
    end
  end

  ##
  # Creates the following instance variables:
  #
  # @spec::
  #   a spec named 'a', intended for regular installs
  # @user_spec::
  #   a spec named 'b', intended for user installs
  #
  # @gem::
  #   the path to a built gem from @spec
  # @user_gem::
  #   the path to a built gem from @user_spec
  #
  # And returns a Gem::Installer for the @user_spec that installs into Gem.user_dir

  def setup_base_user_installer
    @user_spec = quick_gem "b" do |spec|
      util_make_exec spec
    end

    util_build_gem @user_spec

    @user_gem = @user_spec.cache_file

    Gem::Installer.at @user_gem, user_install: true
  end

  ##
  # Sets up the base @gem, builds it and returns an installer for it.
  #
  def util_setup_installer(&block)
    @gem = setup_base_gem

    util_setup_gem(&block)
  end

  ##
  # Builds the @spec gem and returns an installer for it.  The built gem
  # includes:
  #
  #   bin/executable
  #   lib/code.rb
  #   ext/a/mkrf_conf.rb

  def util_setup_gem(ui = @ui, force = true)
    @spec.files << File.join("lib", "code.rb")
    @spec.extensions << File.join("ext", "a", "mkrf_conf.rb")

    Dir.chdir @tempdir do
      FileUtils.mkdir_p "bin"
      FileUtils.mkdir_p "lib"
      FileUtils.mkdir_p File.join("ext", "a")

      File.open File.join("bin", "executable"), "w" do |f|
        f.puts "raise 'ran executable'"
      end

      File.open File.join("lib", "code.rb"), "w" do |f|
        f.puts "1"
      end

      File.open File.join("ext", "a", "mkrf_conf.rb"), "w" do |f|
        f << <<-EOF
          File.open 'Rakefile', 'w' do |rf| rf.puts "task :default" end
        EOF
      end

      yield @spec if block_given?

      use_ui ui do
        FileUtils.rm_f @gem

        @gem = Gem::Package.build @spec
      end
    end

    Gem::Installer.at @gem, force: force
  end

  ##
  # Creates an installer for +spec+ that will install into +gem_home+.

  def util_installer(spec, gem_home, force=true)
    Gem::Installer.at(spec.cache_file,
                       install_dir: gem_home,
                       force: force)
  end

  @@symlink_supported = nil

  # This is needed for Windows environment without symlink support enabled (the default
  # for non admin) to be able to skip test for features using symlinks.
  def symlink_supported?
    if @@symlink_supported.nil?
      begin
        File.symlink("", "")
      rescue Errno::ENOENT, Errno::EEXIST
        @@symlink_supported = true
      rescue NotImplementedError, SystemCallError
        @@symlink_supported = false
      end
    end
    @@symlink_supported
  end
end
