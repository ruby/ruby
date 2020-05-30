# frozen_string_literal: true

require_relative "../worker"
require_relative "gem_installer"

module Bundler
  class ParallelInstaller
    class SpecInstallation
      attr_accessor :spec, :name, :post_install_message, :state, :error
      def initialize(spec)
        @spec = spec
        @name = spec.name
        @state = :none
        @post_install_message = ""
        @error = nil
      end

      def installed?
        state == :installed
      end

      def enqueued?
        state == :enqueued
      end

      def failed?
        state == :failed
      end

      def installation_attempted?
        installed? || failed?
      end

      # Only true when spec in neither installed nor already enqueued
      def ready_to_enqueue?
        !enqueued? && !installation_attempted?
      end

      def has_post_install_message?
        !post_install_message.empty?
      end

      def ignorable_dependency?(dep)
        dep.type == :development || dep.name == @name
      end

      # Checks installed dependencies against spec's dependencies to make
      # sure needed dependencies have been installed.
      def dependencies_installed?(all_specs)
        installed_specs = all_specs.select(&:installed?).map(&:name)
        dependencies.all? {|d| installed_specs.include? d.name }
      end

      # Represents only the non-development dependencies, the ones that are
      # itself and are in the total list.
      def dependencies
        @dependencies ||= begin
          all_dependencies.reject {|dep| ignorable_dependency? dep }
        end
      end

      def missing_lockfile_dependencies(all_spec_names)
        deps = all_dependencies.reject {|dep| ignorable_dependency? dep }
        deps.reject {|dep| all_spec_names.include? dep.name }
      end

      # Represents all dependencies
      def all_dependencies
        @spec.dependencies
      end

      def to_s
        "#<#{self.class} #{@spec.full_name} (#{state})>"
      end
    end

    def self.call(*args)
      new(*args).call
    end

    attr_reader :size

    def initialize(installer, all_specs, size, standalone, force)
      @installer = installer
      @size = size
      @standalone = standalone
      @force = force
      @specs = all_specs.map {|s| SpecInstallation.new(s) }
      @spec_set = all_specs
      @rake = @specs.find {|s| s.name == "rake" }
    end

    def call
      check_for_corrupt_lockfile

      if @size > 1
        install_with_worker
      else
        install_serially
      end

      handle_error if failed_specs.any?
      @specs
    ensure
      worker_pool && worker_pool.stop
    end

    def check_for_corrupt_lockfile
      missing_dependencies = @specs.map do |s|
        [
          s,
          s.missing_lockfile_dependencies(@specs.map(&:name)),
        ]
      end.reject {|a| a.last.empty? }
      return if missing_dependencies.empty?

      warning = []
      warning << "Your lockfile was created by an old Bundler that left some things out."
      if @size != 1
        warning << "Because of the missing DEPENDENCIES, we can only install gems one at a time, instead of installing #{@size} at a time."
        @size = 1
      end
      warning << "You can fix this by adding the missing gems to your Gemfile, running bundle install, and then removing the gems from your Gemfile."
      warning << "The missing gems are:"

      missing_dependencies.each do |spec, missing|
        warning << "* #{missing.map(&:name).join(", ")} depended upon by #{spec.name}"
      end

      Bundler.ui.warn(warning.join("\n"))
    end

  private

    def failed_specs
      @specs.select(&:failed?)
    end

    def install_with_worker
      enqueue_specs
      process_specs until finished_installing?
    end

    def install_serially
      until finished_installing?
        raise "failed to find a spec to enqueue while installing serially" unless spec_install = @specs.find(&:ready_to_enqueue?)
        spec_install.state = :enqueued
        do_install(spec_install, 0)
      end
    end

    def worker_pool
      @worker_pool ||= Bundler::Worker.new @size, "Parallel Installer", lambda {|spec_install, worker_num|
        do_install(spec_install, worker_num)
      }
    end

    def do_install(spec_install, worker_num)
      Plugin.hook(Plugin::Events::GEM_BEFORE_INSTALL, spec_install)
      gem_installer = Bundler::GemInstaller.new(
        spec_install.spec, @installer, @standalone, worker_num, @force
      )
      success, message = gem_installer.install_from_spec
      if success
        spec_install.state = :installed
        spec_install.post_install_message = message unless message.nil?
      else
        spec_install.error = "#{message}\n\n#{require_tree_for_spec(spec_install.spec)}"
        spec_install.state = :failed
      end
      Plugin.hook(Plugin::Events::GEM_AFTER_INSTALL, spec_install)
      spec_install
    end

    # Dequeue a spec and save its post-install message and then enqueue the
    # remaining specs.
    # Some specs might've had to wait til this spec was installed to be
    # processed so the call to `enqueue_specs` is important after every
    # dequeue.
    def process_specs
      worker_pool.deq
      enqueue_specs
    end

    def finished_installing?
      @specs.all? do |spec|
        return true if spec.failed?
        spec.installed?
      end
    end

    def handle_error
      errors = failed_specs.map(&:error)
      if exception = errors.find {|e| e.is_a?(Bundler::BundlerError) }
        raise exception
      end
      raise Bundler::InstallError, errors.join("\n\n")
    end

    def require_tree_for_spec(spec)
      tree = @spec_set.what_required(spec)
      t = String.new("In #{File.basename(SharedHelpers.default_gemfile)}:\n")
      tree.each_with_index do |s, depth|
        t << "  " * depth.succ << s.name
        unless tree.last == s
          t << %( was resolved to #{s.version}, which depends on)
        end
        t << %(\n)
      end
      t
    end

    # Keys in the remains hash represent uninstalled gems specs.
    # We enqueue all gem specs that do not have any dependencies.
    # Later we call this lambda again to install specs that depended on
    # previously installed specifications. We continue until all specs
    # are installed.
    def enqueue_specs
      @specs.select(&:ready_to_enqueue?).each do |spec|
        next if @rake && !@rake.installed? && spec.name != @rake.name

        if spec.dependencies_installed? @specs
          spec.state = :enqueued
          worker_pool.enq spec
        end
      end
    end
  end
end
