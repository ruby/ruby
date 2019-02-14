# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems/user_interaction'

class Gem::Ext::Builder

  include Gem::UserInteraction

  ##
  # The builder shells-out to run various commands after changing the
  # directory.  This means multiple installations cannot be allowed to build
  # extensions in parallel as they may change each other's directories leading
  # to broken extensions or failed installations.

  CHDIR_MUTEX = Mutex.new # :nodoc:

  attr_accessor :build_args # :nodoc:

  def self.class_name
    name =~ /Ext::(.*)Builder/
    $1.downcase
  end

  def self.make(dest_path, results)
    unless File.exist? 'Makefile'
      raise Gem::InstallError, 'Makefile not found'
    end

    # try to find make program from Ruby configure arguments first
    RbConfig::CONFIG['configure_args'] =~ /with-make-prog\=(\w+)/
    make_program = ENV['MAKE'] || ENV['make'] || $1
    unless make_program
      make_program = (/mswin/ =~ RUBY_PLATFORM) ? 'nmake' : 'make'
    end

    destdir = '"DESTDIR=%s"' % ENV['DESTDIR']

    ['clean', '', 'install'].each do |target|
      # Pass DESTDIR via command line to override what's in MAKEFLAGS
      cmd = [
        make_program,
        destdir,
        target
      ].join(' ').rstrip
      begin
        run(cmd, results, "make #{target}".rstrip)
      rescue Gem::InstallError
        raise unless target == 'clean' # ignore clean failure
      end
    end
  end

  def self.redirector
    warn "#{caller[0]}: Use IO.popen(..., err: [:child, :out])"
    '2>&1'
  end

  def self.run(command, results, command_name = nil)
    verbose = Gem.configuration.really_verbose

    begin
      rubygems_gemdeps, ENV['RUBYGEMS_GEMDEPS'] = ENV['RUBYGEMS_GEMDEPS'], nil
      if verbose
        puts("current directory: #{Dir.pwd}")
        p(command)
      end
      results << "current directory: #{Dir.pwd}"
      results << (command.respond_to?(:shelljoin) ? command.shelljoin : command)

      redirections = verbose ? {} : {err: [:child, :out]}
      IO.popen(command, "r", redirections) do |io|
        if verbose
          IO.copy_stream(io, $stdout)
        else
          results << io.read
        end
      end
    rescue => error
      raise Gem::InstallError, "#{command_name || class_name} failed#{error.message}"
    ensure
      ENV['RUBYGEMS_GEMDEPS'] = rubygems_gemdeps
    end

    unless $?.success?
      results << "Building has failed. See above output for more information on the failure." if verbose

      exit_reason =
        if $?.exited?
          ", exit code #{$?.exitstatus}"
        elsif $?.signaled?
          ", uncaught signal #{$?.termsig}"
        end

      raise Gem::InstallError, "#{command_name || class_name} failed#{exit_reason}"
    end
  end

  ##
  # Creates a new extension builder for +spec+.  If the +spec+ does not yet
  # have build arguments, saved, set +build_args+ which is an ARGV-style
  # array.

  def initialize(spec, build_args = spec.build_args)
    @spec       = spec
    @build_args = build_args
    @gem_dir    = spec.full_gem_path

    @ran_rake   = nil
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
      @ran_rake = true
      Gem::Ext::RakeBuilder
    when /CMakeLists.txt/ then
      Gem::Ext::CmakeBuilder
    else
      extension_dir = File.join @gem_dir, File.dirname(extension)

      message = "No builder for extension '#{extension}'"
      build_error extension_dir, message
    end
  end

  ##
  # Logs the build +output+ in +build_dir+, then raises Gem::Ext::BuildError.

  def build_error(build_dir, output, backtrace = nil) # :nodoc:
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

    # FIXME: Determine if this line is necessary and, if so, why.
    # Notes:
    # 1. As far as I can tell, this method is only called by +build_extensions+.
    # 2. The existence of this line implies +extension+ is, or previously was,
    #    sometimes +false+ or +nil+.
    # 3. #1 and #2 combined suggests, but does not confirm, that
    #    +@specs.extensions+ sometimes contained +false+ or +nil+ values.
    # 4. Nothing seems to explicitly handle +extension+ being empty,
    #    which makes me wonder both what it should do and what it does.
    #
    # - @duckinator
    extension ||= '' # I wish I knew why this line existed

    extension_dir =
      File.expand_path File.join(@gem_dir, File.dirname(extension))
    lib_dir = File.join @spec.full_gem_path, @spec.raw_require_paths.first

    builder = builder_for extension

    begin
      FileUtils.mkdir_p dest_path

      CHDIR_MUTEX.synchronize do
        pwd = Dir.getwd
        Dir.chdir extension_dir
        begin
          results = builder.build(extension, dest_path,
                                  results, @build_args, lib_dir)

          verbose { results.join("\n") }
        ensure
          begin
            Dir.chdir pwd
          rescue SystemCallError
            Dir.chdir dest_path
          end
        end
      end

      write_gem_make_out results.join "\n"
    rescue => e
      results << e.message
      build_error extension_dir, results.join("\n"), $@
    end
  end

  ##
  # Builds extensions.  Valid types of extensions are extconf.rb files,
  # configure scripts and rakefiles or mkrf_conf files.

  def build_extensions
    return if @spec.extensions.empty?

    if @build_args.empty?
      say "Building native extensions. This could take a while..."
    else
      say "Building native extensions with: '#{@build_args.join ' '}'"
      say "This could take a while..."
    end

    dest_path = @spec.extension_dir

    FileUtils.rm_f @spec.gem_build_complete_path

    # FIXME: action at a distance: @ran_rake modified deep in build_extension(). - @duckinator
    @ran_rake = false # only run rake once

    @spec.extensions.each do |extension|
      break if @ran_rake

      build_extension extension, dest_path
    end

    FileUtils.touch @spec.gem_build_complete_path
  end

  ##
  # Writes +output+ to gem_make.out in the extension install directory.

  def write_gem_make_out(output) # :nodoc:
    destination = File.join @spec.extension_dir, 'gem_make.out'

    FileUtils.mkdir_p @spec.extension_dir

    File.open destination, 'wb' do |io|
      io.puts output
    end

    destination
  end

end
