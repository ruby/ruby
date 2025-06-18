# frozen_string_literal: true

module Bundler
  class FeatureFlag
    def self.settings_flag(flag, &default)
      unless Bundler::Settings::BOOL_KEYS.include?(flag.to_s)
        raise "Cannot use `#{flag}` as a settings feature flag since it isn't a bool key"
      end

      settings_method("#{flag}?", flag, &default)
    end
    private_class_method :settings_flag

    def self.settings_option(key, &default)
      settings_method(key, key, &default)
    end
    private_class_method :settings_option

    def self.settings_method(name, key, &default)
      define_method(name) do
        value = Bundler.settings[key]
        value = instance_eval(&default) if value.nil?
        value
      end
    end
    private_class_method :settings_method

    (1..10).each {|v| define_method("bundler_#{v}_mode?") { @major_version >= v } }

    settings_flag(:allow_offline_install) { bundler_4_mode? }
    settings_flag(:auto_clean_without_path) { bundler_4_mode? }
    settings_flag(:cache_all) { bundler_4_mode? }
    settings_flag(:default_install_uses_path) { bundler_4_mode? }
    settings_flag(:forget_cli_options) { bundler_4_mode? }
    settings_flag(:global_gem_cache) { bundler_4_mode? }
    settings_flag(:lockfile_checksums) { bundler_4_mode? }
    settings_flag(:path_relative_to_cwd) { bundler_4_mode? }
    settings_flag(:plugins) { @bundler_version >= Gem::Version.new("1.14") }
    settings_flag(:print_only_version_number) { bundler_4_mode? }
    settings_flag(:setup_makes_kernel_gem_public) { !bundler_4_mode? }
    settings_flag(:update_requires_all_flag) { bundler_5_mode? }

    settings_option(:default_cli_command) { bundler_4_mode? ? :cli_help : :install }

    def removed_major?(target_major_version)
      @major_version > target_major_version
    end

    def deprecated_major?(target_major_version)
      @major_version >= target_major_version
    end

    attr_reader :bundler_version

    def initialize(bundler_version)
      @bundler_version = Gem::Version.create(bundler_version)
      @major_version = @bundler_version.segments.first
    end
  end
end
