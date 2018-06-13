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
    # Firstly, this method will check to see if `Bundler.bundle_path` exists
    # and if not then Bundler will create the directory. This is usually the same
    # location as RubyGems which typically is the `~/.gem` directory
    # unless other specified.
    #
    # Secondly, it checks if Bundler has been configured to be "frozen".
    # Frozen ensures that the Gemfile and the Gemfile.lock file are matching.
    # This stops a situation where a developer may update the Gemfile but may not run
    # `bundle install`, which leads to the Gemfile.lock file not being correctly updated.
    # If this file is not correctly updated then any other developer running
    # `bundle install` will potentially not install the correct gems.
    #
    # Thirdly, Bundler checks if there are any dependencies specified in the Gemfile.
    # If there are no dependencies specified then Bundler returns a warning message stating
    # so and this method returns.
    #
    # Fourthly, Bundler checks if the Gemfile.lock exists, and if so
    # then proceeds to set up a definition based on the Gemfile and the Gemfile.lock.
    # During this step Bundler will also download information about any new gems
    # that are not in the Gemfile.lock and resolve any dependencies if needed.
    #
    # Fifthly, Bundler resolves the dependencies either through a cache of gems or by remote.
    # This then leads into the gems being installed, along with stubs for their executables,
    # but only if the --binstubs option has been passed or Bundler.options[:bin] has been set
    # earlier.
    #
    # Sixthly, a new Gemfile.lock is created from the installed gems to ensure that the next time
    # that a user runs `bundle install` they will receive any updates from this process.
    #
    # Finally, if the user has specified the standalone flag, Bundler will generate the needed
    # require paths and save them in a `setup.rb` file. See `bundle standalone --help` for more
    # information.
    def run(options)
      create_bundle_path

      ProcessLock.lock do
        if Bundler.frozen_bundle?
          @definition.ensure_equivalent_gemfile_and_lockfile(options[:deployment])
        end

        if @definition.dependencies.empty?
          Bundler.ui.warn "The Gemfile specifies no dependencies"
          lock
          return
        end

        if resolve_if_needed(options)
          ensure_specs_are_compatible!
          warn_on_incompatible_bundler_deps
          load_plugins
          options.delete(:jobs)
        else
          options[:jobs] = 1 # to avoid the overhead of Bundler::Worker
        end
        install(options)

        lock unless Bundler.frozen_bundle?
        Standalone.new(options[:standalone], @definition).generate if options[:standalone]
      end
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
      bin_path = Bundler.bin_path
      bin_path = bin_path
      relative_gemfile_path = Bundler.default_gemfile.relative_path_from(bin_path)
      relative_gemfile_path = relative_gemfile_path
      ruby_command = Thor::Util.ruby_command
      ruby_command = ruby_command
      template_path = File.expand_path("../templates/Executable", __FILE__)
      if spec.name == "bundler"
        template_path += ".bundler"
        spec.executables = %(bundle)
      end
      template = File.read(template_path)

      exists = []
      spec.executables.each do |executable|
        binstub_path = "#{bin_path}/#{executable}"
        if File.exist?(binstub_path) && !options[:force]
          exists << executable
          next
        end

        File.open(binstub_path, "w", 0o777 & ~File.umask) do |f|
          if RUBY_VERSION >= "2.6"
            f.puts ERB.new(template, :trim_mode => "-").result(binding)
          else
            f.puts ERB.new(template, nil, "-").result(binding)
          end
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
      unless path = Bundler.settings[:path]
        raise "Can't standalone without an explicit path set"
      end
      standalone_path = Bundler.root.join(path).relative_path_from(bin_path)
      standalone_path = standalone_path
      template = File.read(File.expand_path("../templates/Executable.standalone", __FILE__))
      ruby_command = Thor::Util.ruby_command
      ruby_command = ruby_command

      spec.executables.each do |executable|
        next if executable == "bundle"
        executable_path = Pathname(spec.full_gem_path).join(spec.bindir, executable).relative_path_from(bin_path)
        executable_path = executable_path
        File.open "#{bin_path}/#{executable}", "w", 0o755 do |f|
          if RUBY_VERSION >= "2.6"
            f.puts ERB.new(template, :trim_mode => "-").result(binding)
          else
            f.puts ERB.new(template, nil, "-").result(binding)
          end
        end
      end
    end

  private

    # the order that the resolver provides is significant, since
    # dependencies might affect the installation of a gem.
    # that said, it's a rare situation (other than rake), and parallel
    # installation is SO MUCH FASTER. so we let people opt in.
    def install(options)
      force = options["force"]
      jobs = options.delete(:jobs) do
        if can_install_in_parallel?
          [Bundler.settings[:jobs].to_i - 1, 1].max
        else
          1
        end
      end
      install_in_parallel jobs, options[:standalone], force
    end

    def load_plugins
      Bundler.rubygems.load_plugins

      requested_path_gems = @definition.requested_specs.select {|s| s.source.is_a?(Source::Path) }
      path_plugin_files = requested_path_gems.map do |spec|
        begin
          Bundler.rubygems.spec_matches_for_glob(spec, "rubygems_plugin#{Bundler.rubygems.suffix_pattern}")
        rescue TypeError
          error_message = "#{spec.name} #{spec.version} has an invalid gemspec"
          raise Gem::InvalidSpecificationException, error_message
        end
      end.flatten
      Bundler.rubygems.load_plugin_files(path_plugin_files)
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

    def warn_on_incompatible_bundler_deps
      bundler_version = Gem::Version.create(Bundler::VERSION)
      @definition.specs.each do |spec|
        spec.dependencies.each do |dep|
          next if dep.type == :development
          next unless dep.name == "bundler".freeze
          next if dep.requirement.satisfied_by?(bundler_version)

          Bundler.ui.warn "#{spec.name} (#{spec.version}) has dependency" \
            " #{SharedHelpers.pretty_dependency(dep)}" \
            ", which is unsatisfied by the current bundler version #{VERSION}" \
            ", so the dependency is being ignored"
        end
      end
    end

    def can_install_in_parallel?
      if Bundler.rubygems.provides?(">= 2.1.0")
        true
      else
        Bundler.ui.warn "RubyGems #{Gem::VERSION} is not threadsafe, so your "\
          "gems will be installed one at a time. Upgrade to RubyGems 2.1.0 " \
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
      raise PathError, "Could not install to path `#{Bundler.bundle_path}` " \
        "because a file already exists at that path. Either remove or rename the file so the directory can be created."
    end

    # returns whether or not a re-resolve was needed
    def resolve_if_needed(options)
      if !@definition.unlocking? && !options["force"] && !Bundler.settings[:inline] && Bundler.default_lockfile.file?
        return false if @definition.nothing_changed? && !@definition.missing_specs?
      end

      options["local"] ? @definition.resolve_with_cache! : @definition.resolve_remotely!
      true
    end

    def lock(opts = {})
      @definition.lock(Bundler.default_lockfile, opts[:preserve_unknown_sections])
    end
  end
end
