# frozen_string_literal: true

require "rubygems/installer"

module Bundler
  class RubyGemsGemInstaller < Gem::Installer
    def check_executable_overwrite(filename)
      # Bundler needs to install gems regardless of binstub overwriting
    end

    def install
      pre_install_checks

      run_pre_install_hooks

      spec.loaded_from = spec_file

      # Completely remove any previous gem files
      strict_rm_rf gem_dir
      strict_rm_rf spec.extension_dir

      SharedHelpers.filesystem_access(gem_dir, :create) do
        FileUtils.mkdir_p gem_dir, :mode => 0o755
      end

      extract_files

      build_extensions if spec.extensions.any?
      write_build_info_file
      run_post_build_hooks

      generate_bin
      generate_plugins

      write_spec

      SharedHelpers.filesystem_access("#{gem_home}/cache", :write) do
        write_cache_file
      end

      say spec.post_install_message unless spec.post_install_message.nil?

      run_post_install_hooks

      spec
    end

    def generate_plugins
      return unless Gem::Installer.instance_methods(false).include?(:generate_plugins)

      latest = Gem::Specification.stubs_for(spec.name).first
      return if latest && latest.version > spec.version

      ensure_writable_dir @plugins_dir

      if spec.plugins.empty?
        remove_plugins_for(spec, @plugins_dir)
      else
        regenerate_plugins_for(spec, @plugins_dir)
      end
    end

    def pre_install_checks
      super && validate_bundler_checksum(options[:bundler_checksum_store])
    end

    def build_extensions
      extension_cache_path = options[:bundler_extension_cache_path]
      extension_dir = spec.extension_dir
      unless extension_cache_path && extension_dir
        prepare_extension_build(extension_dir)
        return super
      end

      build_complete = SharedHelpers.filesystem_access(extension_cache_path.join("gem.build_complete"), :read, &:file?)
      if build_complete && !options[:force]
        SharedHelpers.filesystem_access(File.dirname(extension_dir)) do |p|
          FileUtils.mkpath p
        end
        SharedHelpers.filesystem_access(extension_cache_path) do
          FileUtils.cp_r extension_cache_path, extension_dir
        end
      else
        prepare_extension_build(extension_dir)
        super
        SharedHelpers.filesystem_access(extension_cache_path.parent, &:mkpath)
        SharedHelpers.filesystem_access(extension_cache_path) do
          FileUtils.cp_r extension_dir, extension_cache_path
        end
      end
    end

    def spec
      if Bundler.rubygems.provides?("< 3.3.12") # RubyGems implementation rescues and re-raises errors before 3.3.12 and we don't want that
        @package.spec
      else
        super
      end
    end

    private

    def prepare_extension_build(extension_dir)
      SharedHelpers.filesystem_access(extension_dir, :create) do
        FileUtils.mkdir_p extension_dir
      end
      require "shellwords" unless Bundler.rubygems.provides?(">= 3.2.25")
    end

    def strict_rm_rf(dir)
      Bundler.rm_rf dir
    rescue StandardError => e
      raise unless File.exist?(dir)

      raise DirectoryRemovalError.new(e, "Could not delete previous installation of `#{dir}`")
    end

    def validate_bundler_checksum(checksum_store)
      return true if Bundler.settings[:disable_checksum_validation]

      return true unless source = @package.instance_variable_get(:@gem)
      return true unless source.respond_to?(:with_read_io)
      digests = Bundler::Checksum.digests_from_file_source(source).transform_values(&:hexdigest!)

      checksum = checksum_store[spec]
      unless checksum.match_digests?(digests)
        expected = checksum_store.send(:store)[spec.full_name]

        raise SecurityError, <<~MESSAGE
          Bundler cannot continue installing #{spec.name} (#{spec.version}).
          The checksum for the downloaded `#{spec.full_name}.gem` does not match \
          the known checksum for the gem.
          This means the contents of the downloaded \
          gem is different from what was uploaded to the server \
          or first used by your teammates, and could be a potential security issue.

          To resolve this issue:
          1. delete the downloaded gem located at: `#{source.path}`
          2. run `bundle install`

          If you are sure that the new checksum is correct, you can \
          remove the `#{GemHelpers.lock_name spec.name, spec.version, spec.platform}` entry under the lockfile `CHECKSUMS` \
          section and rerun `bundle install`.

          If you wish to continue installing the downloaded gem, and are certain it does not pose a \
          security issue despite the mismatching checksum, do the following:
          1. run `bundle config set --local disable_checksum_validation true` to turn off checksum verification
          2. run `bundle install`

          #{expected.map do |algo, multi|
            next unless actual = digests[algo]
            next if actual == multi

            "(More info: The expected #{algo.upcase} checksum was #{multi.digest.inspect}, but the " \
            "checksum for the downloaded gem was #{actual.inspect}. The expected checksum came from: #{multi.sources.join(", ")})"
          end.compact.join("\n")}
          MESSAGE
      end
      register_digests(digests, checksum_store, source)
      true
    end

    def register_digests(digests, checksum_store, source)
      checksum_store.register(
        spec,
        digests.map {|algo, digest| Checksum::Single.new(algo, digest, "downloaded gem @ `#{source.path}`") }
      )
    end
  end
end
