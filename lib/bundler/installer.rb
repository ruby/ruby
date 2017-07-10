# frozen_string_literal: true
require "erb"
require "rubygems/dependency_installer"
require "bundler/worker"
require "bundler/installer/parallel_installer"
require "bundler/installer/standalone"
require "bundler/installer/gem_installer"

module Bundler
  class Installer
    class << self
      attr_accessor :ambiguous_gems

      Installer.ambiguous_gems = []
    end

    attr_reader :post_install_messages

    # Begins the installation process for Bundler.
    # For more information see the #run method on this class.
    def self.install(root, definition, options = {})
      installer = new(root, definition)
      Plugin.hook("before-install-all", definition.dependencies)
      installer.run(options)
      installer
    end

    def initialize(root, definition)
      @root = root
      @definition = definition
      @post_install_messages = {}
    end

    # Runs the install procedures for a specific Gemfile.
    #
    # Firstly, this method will check to see if Bundler.bundle_path exists
    # and if not then will create it. This is usually the location of gems
    # on the system, be it RVM or at a system path.
    #
    # Secondly, it checks if Bundler has been configured to be "frozen"
    # Frozen ensures that the Gemfile and the Gemfile.lock file are matching.
    # This stops a situation where a developer may update the Gemfile but may not run
    # `bundle install`, which leads to the Gemfile.lock file not being correctly updated.
    # If this file is not correctly updated then any other developer running
    # `bundle install` will potentially not install the correct gems.
    #
    # Thirdly, Bundler checks if there are any dependencies specified in the Gemfile using
    # Bundler::Environment#dependencies. If there are no dependencies specified then
    # Bundler returns a warning message stating so and this method returns.
    #
    # Fourthly, Bundler checks if the default lockfile (Gemfile.lock) exists, and if so
    # then proceeds to set up a defintion based on the default gemfile (Gemfile) and the
    # default lock file (Gemfile.lock). However, this is not the case if the platform is different
    # to that which is specified in Gemfile.lock, or if there are any missing specs for the gems.
    #
    # Fifthly, Bundler resolves the dependencies either through a cache of gems or by remote.
    # This then leads into the gems being installed, along with stubs for their executables,
    # but only if the --binstubs option has been passed or Bundler.options[:bin] has been set
    # earlier.
    #
    # Sixthly, a new Gemfile.lock is created from the installed gems to ensure that the next time
    # that a user runs `bundle install` they will receive any updates from this process.
    #
    # Finally: TODO add documentation for how the standalone process works.
    def run(options)
      create_bundle_path

      if Bundler.settings[:frozen]
        @definition.ensure_equivalent_gemfile_and_lockfile(options[:deployment])
      end

      if @definition.dependencies.empty?
        Bundler.ui.warn "The Gemfile specifies no dependencies"
        lock
        return
      end

      resolve_if_need(options)
      ensure_specs_are_compatible!
      install(options)

      lock unless Bundler.settings[:frozen]
      Standalone.new(options[:standalone], @definition).generate if options[:standalone]
    end

    def generate_bundler_executable_stubs(spec, options = {})
      if options[:binstubs_cmd] && spec.executables.empty?
        options = {}
        spec.runtime_dependencies.each do |dep|
          bins = @definition.specs[dep].first.executables
          options[dep.name] = bins unless bins.empty?
        end
        if options.any?
          Bundler.ui.warn "#{spec.name} has no executables, but you may want " \
            "one from a gem it depends on."
          options.each {|name, bins| Bundler.ui.warn "  #{name} has: #{bins.join(", ")}" }
        else
          Bundler.ui.warn "There are no executables for the gem #{spec.name}."
        end
        return
      end

      # double-assignment to avoid warnings about variables that will be used by ERB
      bin_path = bin_path = Bundler.bin_path
      template = template = File.read(File.expand_path("../templates/Executable", __FILE__))
      relative_gemfile_path = relative_gemfile_path = Bundler.default_gemfile.relative_path_from(bin_path)
      ruby_command = ruby_command = Thor::Util.ruby_command

      exists = []
      spec.executables.each do |executable|
        next if executable == "bundle"

        binstub_path = "#{bin_path}/#{executable}"
        if File.exist?(binstub_path) && !options[:force]
          exists << executable
          next
        end

        File.open(binstub_path, "w", 0o777 & ~File.umask) do |f|
          f.puts ERB.new(template, nil, "-").result(binding)
        end
      end

      if options[:binstubs_cmd] && exists.any?
        case exists.size
        when 1
          Bundler.ui.warn "Skipped #{exists[0]} since it already exists."
        when 2
          Bundler.ui.warn "Skipped #{exists.join(" and ")} since they already exist."
        else
          items = exists[0...-1].empty? ? nil : exists[0...-1].join(", ")
          skipped = [items, exists[-1]].compact.join(" and ")
          Bundler.ui.warn "Skipped #{skipped} since they already exist."
        end
        Bundler.ui.warn "If you want to overwrite skipped stubs, use --force."
      end
    end

    def generate_standalone_bundler_executable_stubs(spec)
      # double-assignment to avoid warnings about variables that will be used by ERB
      bin_path = Bundler.bin_path
      standalone_path = standalone_path = Bundler.root.join(Bundler.settings[:path]).relative_path_from(bin_path)
      template = File.read(File.expand_path("../templates/Executable.standalone", __FILE__))
      ruby_command = ruby_command = Thor::Util.ruby_command

      spec.executables.each do |executable|
        next if executable == "bundle"
        executable_path = executable_path = Pathname(spec.full_gem_path).join(spec.bindir, executable).relative_path_from(bin_path)
        File.open "#{bin_path}/#{executable}", "w", 0o755 do |f|
          f.puts ERB.new(template, nil, "-").result(binding)
        end
      end
    end

  private

    # the order that the resolver provides is significant, since
    # dependencies might affect the installation of a gem.
    # that said, it's a rare situation (other than rake), and parallel
    # installation is SO MUCH FASTER. so we let people opt in.
    def install(options)
      Bundler.rubygems.load_plugins
      force = options["force"]
      jobs = 1
      jobs = [Bundler.settings[:jobs].to_i - 1, 1].max if can_install_in_parallel?
      install_in_parallel jobs, options[:standalone], force
    end

    def ensure_specs_are_compatible!
      system_ruby = Bundler::RubyVersion.system
      rubygems_version = Gem::Version.create(Gem::VERSION)
      @definition.specs.each do |spec|
        if required_ruby_version = spec.required_ruby_version
          unless required_ruby_version.satisfied_by?(system_ruby.gem_version)
            raise InstallError, "#{spec.full_name} requires ruby version #{required_ruby_version}, " \
              "which is incompatible with the current version, #{system_ruby}"
          end
        end
        next unless required_rubygems_version = spec.required_rubygems_version
        unless required_rubygems_version.satisfied_by?(rubygems_version)
          raise InstallError, "#{spec.full_name} requires rubygems version #{required_rubygems_version}, " \
            "which is incompatible with the current version, #{rubygems_version}"
        end
      end
    end

    def can_install_in_parallel?
      if Bundler.rubygems.provides?(">= 2.1.0")
        true
      else
        Bundler.ui.warn "Rubygems #{Gem::VERSION} is not threadsafe, so your "\
          "gems will be installed one at a time. Upgrade to Rubygems 2.1.0 " \
          "or higher to enable parallel gem installation."
        false
      end
    end

    def install_in_parallel(size, standalone, force = false)
      spec_installations = ParallelInstaller.call(self, @definition.specs, size, standalone, force)
      spec_installations.each do |installation|
        post_install_messages[installation.name] = installation.post_install_message if installation.has_post_install_message?
      end
    end

    def create_bundle_path
      SharedHelpers.filesystem_access(Bundler.bundle_path.to_s) do |p|
        Bundler.mkdir_p(p)
      end unless Bundler.bundle_path.exist?
    rescue Errno::EEXIST
      raise PathError, "Could not install to path `#{Bundler.settings[:path]}` " \
        "because a file already exists at that path. Either remove or rename the file so the directory can be created."
    end

    def resolve_if_need(options)
      if !options["update"] && !options[:inline] && Bundler.default_lockfile.file?
        local = Bundler.ui.silence do
          begin
            tmpdef = Definition.build(Bundler.default_gemfile, Bundler.default_lockfile, nil)
            true unless tmpdef.new_platform? || tmpdef.missing_dependencies.any?
          rescue BundlerError
          end
        end
      end

      return if local
      options["local"] ? @definition.resolve_with_cache! : @definition.resolve_remotely!
    end

    def lock(opts = {})
      @definition.lock(Bundler.default_lockfile, opts[:preserve_unknown_sections])
    end
  end
end
