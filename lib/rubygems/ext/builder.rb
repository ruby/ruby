# frozen_string_literal: true

#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require_relative "../user_interaction"

class Gem::Ext::Builder
  include Gem::UserInteraction

  class NoMakefileError < Gem::InstallError
  end

  attr_accessor :build_args # :nodoc:

  def self.class_name
    name =~ /Ext::(.*)Builder/
    $1.downcase
  end

  def self.make(dest_path, results, make_dir = Dir.pwd, sitedir = nil, targets = ["clean", "", "install"],
    target_rbconfig: Gem.target_rbconfig, n_jobs: nil)
    unless File.exist? File.join(make_dir, "Makefile")
      # No makefile exists, nothing to do.
      raise NoMakefileError, "No Makefile found in #{make_dir}"
    end

    # try to find make program from Ruby configure arguments first
    target_rbconfig["configure_args"] =~ /with-make-prog\=(\w+)/
    make_program_name = ENV["MAKE"] || ENV["make"] || $1
    make_program_name ||= RUBY_PLATFORM.include?("mswin") ? "nmake" : "make"
    make_program = shellsplit_command(make_program_name)

    is_nmake = /\bnmake/i.match?(make_program_name)
    # The installation of the bundled gems is failed when DESTDIR is empty in mswin platform.
    destdir = !is_nmake || ENV["DESTDIR"] && ENV["DESTDIR"] != "" ? format("DESTDIR=%s", ENV["DESTDIR"]) : ""

    # nmake doesn't support parallel build
    unless is_nmake
      have_make_arguments = make_program.size > 1
      n_jobs ||= 0

      if !have_make_arguments && n_jobs > 1 && !ENV["MAKEFLAGS"]&.match(/-j\d*(\s|\Z)/)
        make_program << "-j#{n_jobs}"
      end
    end

    env = [destdir]

    if sitedir
      env << format("sitearchdir=%s", sitedir)
      env << format("sitelibdir=%s", sitedir)
    end

    targets.each do |target|
      # Pass DESTDIR via command line to override what's in MAKEFLAGS
      cmd = [
        *make_program,
        *env,
        target,
      ].reject(&:empty?)
      begin
        run(cmd, results, "make #{target}".rstrip, make_dir)
      rescue Gem::InstallError
        raise unless target == "clean" # ignore clean failure
      end
    end
  end

  def self.ruby
    # Gem.ruby is quoted if it contains whitespace
    cmd = shellsplit(Gem.ruby)

    # This load_path is only needed when running rubygems test without a proper installation.
    # Prepending it in a normal installation will cause problem with order of $LOAD_PATH.
    # Therefore only add load_path if it is not present in the default $LOAD_PATH.
    load_path = File.expand_path("../..", __dir__)
    case load_path
    when RbConfig::CONFIG["sitelibdir"], RbConfig::CONFIG["vendorlibdir"], RbConfig::CONFIG["rubylibdir"]
      cmd
    else
      cmd << "-I#{load_path}"
    end
  end

  def self.run(command, results, command_name = nil, dir = Dir.pwd, env = {})
    verbose = Gem.configuration.really_verbose

    begin
      rubygems_gemdeps = ENV["RUBYGEMS_GEMDEPS"]
      ENV["RUBYGEMS_GEMDEPS"] = nil
      if verbose
        puts("current directory: #{dir}")
        p(command)
      end
      results << "current directory: #{dir}"
      results << shelljoin(command)

      require "open3"
      # Set $SOURCE_DATE_EPOCH for the subprocess.
      # Under Ruby::Box mkmf makes RbConfig.expand recurse until SystemStackError.
      # Drop $RUBY_BOX last so no caller can restore it.
      build_env = { "SOURCE_DATE_EPOCH" => Gem.source_date_epoch_string }.merge(env).merge("RUBY_BOX" => nil)
      # A single-element command would be parsed as a shell command line,
      # splitting an unquoted command path containing spaces. Use the
      # [cmdname, argv0] form to keep exec semantics.
      command = [[command.first, command.first]] if command.size == 1
      output, status = begin
                         Open3.popen2e(build_env, *command, chdir: dir) do |stdin, stdouterr, wait_thread|
                           stdin.close
                           output = String.new
                           while line = stdouterr.gets
                             output << line
                             if verbose
                               print line
                             end
                           end
                           [output, wait_thread.value]
                         end
                       rescue StandardError => error
                         raise Gem::InstallError, "#{command_name || class_name} failed#{error.message}"
                       end
      unless verbose
        results << output
      end
    ensure
      ENV["RUBYGEMS_GEMDEPS"] = rubygems_gemdeps
    end

    unless status.success?
      results << "Building has failed. See above output for more information on the failure." if verbose
    end

    yield(status, results) if block_given?

    unless status.success?
      exit_reason =
        if status.exited?
          ", exit code #{status.exitstatus}"
        elsif status.signaled?
          ", uncaught signal #{status.termsig}"
        end

      raise Gem::InstallError, "#{command_name || class_name} failed#{exit_reason}"
    end
  end

  def self.shellsplit(command)
    require "shellwords"

    Shellwords.split(command)
  end

  ##
  # Splits a command string such as ENV["MAKE"] into an argument list.
  #
  # On Windows, a value that names an existing file, such as
  # <tt>C:\path\nmake.exe</tt>, is taken as a single word because POSIX
  # shell splitting would consume the backslashes as escape characters.
  # Any other value is split like a POSIX shell command line, where a
  # path containing spaces must be quoted.

  def self.shellsplit_command(command)
    return [command] if Gem.win_platform? && File.file?(command)

    shellsplit(command)
  end

  def self.shelljoin(command)
    require "shellwords"

    Shellwords.join(command)
  end

  ##
  # Creates a new extension builder for +spec+.  If the +spec+ does not yet
  # have build arguments, saved, set +build_args+ which is an ARGV-style
  # array.

  def initialize(spec, build_args = spec.build_args, target_rbconfig = Gem.target_rbconfig, build_jobs = nil)
    @spec       = spec
    @build_args = build_args
    @gem_dir    = spec.full_gem_path
    @target_rbconfig = target_rbconfig
    @build_jobs = build_jobs
  end

  ##
  # Chooses the extension builder class for +extension+

  def builder_for(extension) # :nodoc:
    case extension
    when /extconf/ then
      Gem::Ext::ExtConfBuilder
    when /configure/ then
      Gem::Ext::ConfigureBuilder
    when /rakefile/i, /mkrf_conf/i then
      Gem::Ext::RakeBuilder
    when /CMakeLists.txt/ then
      Gem::Ext::CmakeBuilder.new
    when /Cargo.toml/ then
      Gem::Ext::CargoBuilder.new
    else
      build_error("No builder for extension '#{extension}'")
    end
  end

  ##
  # Logs the build +output+, then raises Gem::Ext::BuildError.

  def build_error(output, backtrace = nil) # :nodoc:
    gem_make_out = write_gem_make_out output

    message = <<-EOF
ERROR: Failed to build gem native extension.

    #{output}

Gem files will remain installed in #{@gem_dir} for inspection.
Results logged to #{gem_make_out}
EOF

    raise Gem::Ext::BuildError, message, backtrace
  end

  def build_extension(extension, dest_path) # :nodoc:
    results = []

    builder = builder_for(extension)

    extension_dir =
      File.expand_path File.join(@gem_dir, File.dirname(extension))
    lib_dir = File.join @spec.full_gem_path, @spec.raw_require_paths.first

    begin
      FileUtils.mkdir_p dest_path

      results = builder.build(extension, dest_path,
                              results, @build_args, lib_dir, extension_dir, @target_rbconfig, n_jobs: @build_jobs)

      verbose { results.join("\n") }

      # Build logs are noisy, non-reproducible artifacts that are not meant to
      # be installed. Drop the ones this build left behind, plus any written
      # into the extension directory by a RubyGems old enough to put them there.
      FileUtils.rm_f mkmf_log_candidates(extension_dir, dest_path)
      FileUtils.rm_f File.join(dest_path, "gem_make.out")
      FileUtils.rm_f [build_log_path("mkmf.log"), build_log_path("gem_make.out")]
    rescue StandardError => e
      results << e.message

      # On failure keep the mkmf.log for inspection, but move it out of the
      # installation tree into the build_info directory.
      mkmf_log = mkmf_log_candidates(extension_dir, dest_path).find {|log| File.exist?(log) }
      if mkmf_log
        mkmf_log_dest = build_log_path "mkmf.log"
        FileUtils.mkdir_p @spec.build_info_dir
        FileUtils.mv mkmf_log, mkmf_log_dest

        results << "To see why this extension failed to compile, please check the mkmf.log which can be found here:"
        results << "  #{mkmf_log_dest}"
      end

      build_error(results.join("\n"), $@)
    end
  end

  ##
  # Where a build log of +kind+ for this gem lives in the build_info directory.

  def build_log_path(kind) # :nodoc:
    File.join @spec.build_info_dir, "#{@spec.full_name}.#{kind}"
  end

  ##
  # Places a completed build may have left an mkmf.log, most specific first.
  # Gem::Ext::ExtConfBuilder parks it in +dest_path+ so that the "clean" target
  # cannot delete it; the other builders leave it where extconf ran.

  def mkmf_log_candidates(extension_dir, dest_path) # :nodoc:
    [File.join(dest_path, "mkmf.log"), File.join(extension_dir, "mkmf.log")]
  end

  ##
  # Builds extensions.  Valid types of extensions are extconf.rb files,
  # configure scripts and rakefiles or mkrf_conf files.

  def build_extensions
    return if @spec.extensions.empty?

    if @build_args.empty?
      say "Building native extensions. This could take a while..."
    else
      say "Building native extensions with: '#{@build_args.join " "}'"
      say "This could take a while..."
    end

    dest_path = @spec.extension_dir

    require "fileutils"
    FileUtils.rm_f @spec.gem_build_complete_path

    @spec.extensions.each do |extension|
      build_extension extension, dest_path
    end

    FileUtils.touch @spec.gem_build_complete_path
  end

  ##
  # Writes +output+ to gem_make.out in the build_info directory. Only called
  # on failure (via #build_error), to keep build logs out of the installation
  # tree.

  def write_gem_make_out(output) # :nodoc:
    destination = build_log_path "gem_make.out"

    FileUtils.mkdir_p @spec.build_info_dir

    File.open destination, "wb" do |io|
      io.puts output
    end

    destination
  end
end
