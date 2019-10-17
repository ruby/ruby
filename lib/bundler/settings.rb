# frozen_string_literal: true

require "uri"

module Bundler
  class Settings
    autoload :Mirror,  File.expand_path("mirror", __dir__)
    autoload :Mirrors, File.expand_path("mirror", __dir__)
    autoload :Validator, File.expand_path("settings/validator", __dir__)

    BOOL_KEYS = %w[
      allow_bundler_dependency_conflicts
      allow_deployment_source_credential_changes
      allow_offline_install
      auto_clean_without_path
      auto_install
      auto_config_jobs
      cache_all
      cache_all_platforms
      default_install_uses_path
      deployment
      deployment_means_frozen
      disable_checksum_validation
      disable_exec_load
      disable_local_branch_check
      disable_multisource
      disable_platform_warnings
      disable_shared_gems
      disable_version_check
      force_ruby_platform
      forget_cli_options
      frozen
      gem.coc
      gem.mit
      global_gem_cache
      ignore_messages
      init_gems_rb
      no_install
      no_prune
      only_update_to_newer_versions
      path_relative_to_cwd
      path.system
      plugins
      prefer_patch
      print_only_version_number
      setup_makes_kernel_gem_public
      silence_deprecations
      silence_root_warning
      skip_default_git_sources
      specific_platform
      suppress_install_using_messages
      unlock_source_unlocks_spec
      update_requires_all_flag
      use_gem_version_promoter_for_major_updates
    ].freeze

    NUMBER_KEYS = %w[
      jobs
      redirect
      retry
      ssl_verify_mode
      timeout
    ].freeze

    ARRAY_KEYS = %w[
      with
      without
    ].freeze

    DEFAULT_CONFIG = {
      :silence_deprecations => false,
      :disable_version_check => true,
      :prefer_patch => false,
      :redirect => 5,
      :retry => 3,
      :timeout => 10,
    }.freeze

    def initialize(root = nil)
      @root            = root
      @local_config    = load_config(local_config_file)
      @global_config   = load_config(global_config_file)
      @temporary       = {}
    end

    def [](name)
      key = key_for(name)
      value = @temporary.fetch(key) do
              @local_config.fetch(key) do
              ENV.fetch(key) do
              @global_config.fetch(key) do
              DEFAULT_CONFIG.fetch(name) do
                nil
              end end end end end

      converted_value(value, name)
    end

    def set_command_option(key, value)
      if Bundler.feature_flag.forget_cli_options?
        temporary(key => value)
        value
      else
        set_local(key, value)
      end
    end

    def set_command_option_if_given(key, value)
      return if value.nil?
      set_command_option(key, value)
    end

    def set_local(key, value)
      local_config_file || raise(GemfileNotFound, "Could not locate Gemfile")

      set_key(key, value, @local_config, local_config_file)
    end

    def temporary(update)
      existing = Hash[update.map {|k, _| [k, @temporary[key_for(k)]] }]
      update.each do |k, v|
        set_key(k, v, @temporary, nil)
      end
      return unless block_given?
      begin
        yield
      ensure
        existing.each {|k, v| set_key(k, v, @temporary, nil) }
      end
    end

    def set_global(key, value)
      set_key(key, value, @global_config, global_config_file)
    end

    def all
      env_keys = ENV.keys.grep(/\ABUNDLE_.+/)

      keys = @temporary.keys | @global_config.keys | @local_config.keys | env_keys

      keys.map do |key|
        key.sub(/^BUNDLE_/, "").gsub(/__/, ".").downcase
      end
    end

    def local_overrides
      repos = {}
      all.each do |k|
        repos[$'] = self[k] if k =~ /^local\./
      end
      repos
    end

    def mirror_for(uri)
      uri = URI(uri.to_s) unless uri.is_a?(URI)
      gem_mirrors.for(uri.to_s).uri
    end

    def credentials_for(uri)
      self[uri.to_s] || self[uri.host]
    end

    def gem_mirrors
      all.inject(Mirrors.new) do |mirrors, k|
        mirrors.parse(k, self[k]) if k.start_with?("mirror.")
        mirrors
      end
    end

    def locations(key)
      key = key_for(key)
      locations = {}
      locations[:temporary] = @temporary[key] if @temporary.key?(key)
      locations[:local]  = @local_config[key] if @local_config.key?(key)
      locations[:env]    = ENV[key] if ENV[key]
      locations[:global] = @global_config[key] if @global_config.key?(key)
      locations[:default] = DEFAULT_CONFIG[key] if DEFAULT_CONFIG.key?(key)
      locations
    end

    def pretty_values_for(exposed_key)
      key = key_for(exposed_key)

      locations = []

      if @temporary.key?(key)
        locations << "Set for the current command: #{converted_value(@temporary[key], exposed_key).inspect}"
      end

      if @local_config.key?(key)
        locations << "Set for your local app (#{local_config_file}): #{converted_value(@local_config[key], exposed_key).inspect}"
      end

      if value = ENV[key]
        locations << "Set via #{key}: #{converted_value(value, exposed_key).inspect}"
      end

      if @global_config.key?(key)
        locations << "Set for the current user (#{global_config_file}): #{converted_value(@global_config[key], exposed_key).inspect}"
      end

      return ["You have not configured a value for `#{exposed_key}`"] if locations.empty?
      locations
    end

    # for legacy reasons, in Bundler 2, we do not respect :disable_shared_gems
    def path
      key  = key_for(:path)
      path = ENV[key] || @global_config[key]
      if path && !@temporary.key?(key) && !@local_config.key?(key)
        return Path.new(path, false, false)
      end

      system_path = self["path.system"] || (self[:disable_shared_gems] == false)
      Path.new(self[:path], system_path, Bundler.feature_flag.default_install_uses_path?)
    end

    Path = Struct.new(:explicit_path, :system_path, :default_install_uses_path) do
      def path
        path = base_path
        path = File.join(path, Bundler.ruby_scope) unless use_system_gems?
        path
      end

      def use_system_gems?
        return true if system_path
        return false if explicit_path
        !default_install_uses_path
      end

      def base_path
        path = explicit_path
        path ||= ".bundle" unless use_system_gems?
        path ||= Bundler.rubygems.gem_dir
        path
      end

      def base_path_relative_to_pwd
        base_path = Pathname.new(self.base_path)
        expanded_base_path = base_path.expand_path(Bundler.root)
        relative_path = expanded_base_path.relative_path_from(Pathname.pwd)
        if relative_path.to_s.start_with?("..")
          relative_path = base_path if base_path.absolute?
        else
          relative_path = Pathname.new(File.join(".", relative_path))
        end
        relative_path
      rescue ArgumentError
        expanded_base_path
      end

      def validate!
        return unless explicit_path && system_path
        path = Bundler.settings.pretty_values_for(:path)
        path.unshift(nil, "path:") unless path.empty?
        system_path = Bundler.settings.pretty_values_for("path.system")
        system_path.unshift(nil, "path.system:") unless system_path.empty?
        disable_shared_gems = Bundler.settings.pretty_values_for(:disable_shared_gems)
        disable_shared_gems.unshift(nil, "disable_shared_gems:") unless disable_shared_gems.empty?
        raise InvalidOption,
          "Using a custom path while using system gems is unsupported.\n#{path.join("\n")}\n#{system_path.join("\n")}\n#{disable_shared_gems.join("\n")}"
      end
    end

    def allow_sudo?
      key = key_for(:path)
      path_configured = @temporary.key?(key) || @local_config.key?(key)
      !path_configured
    end

    def ignore_config?
      ENV["BUNDLE_IGNORE_CONFIG"]
    end

    def app_cache_path
      @app_cache_path ||= self[:cache_path] || "vendor/cache"
    end

    def validate!
      all.each do |raw_key|
        [@local_config, ENV, @global_config].each do |settings|
          value = converted_value(settings[key_for(raw_key)], raw_key)
          Validator.validate!(raw_key, value, settings.to_hash.dup)
        end
      end
    end

    def key_for(key)
      key = Settings.normalize_uri(key).to_s if key.is_a?(String) && /https?:/ =~ key
      key = key.to_s.gsub(".", "__").upcase
      "BUNDLE_#{key}"
    end

  private

    def parent_setting_for(name)
      split_specific_setting_for(name)[0]
    end

    def specific_gem_for(name)
      split_specific_setting_for(name)[1]
    end

    def split_specific_setting_for(name)
      name.split(".")
    end

    def is_bool(name)
      BOOL_KEYS.include?(name.to_s) || BOOL_KEYS.include?(parent_setting_for(name.to_s))
    end

    def to_bool(value)
      case value
      when nil, /\A(false|f|no|n|0|)\z/i, false
        false
      else
        true
      end
    end

    def is_num(key)
      NUMBER_KEYS.include?(key.to_s)
    end

    def is_array(key)
      ARRAY_KEYS.include?(key.to_s)
    end

    def to_array(value)
      return [] unless value
      value.split(":").map(&:to_sym)
    end

    def array_to_s(array)
      array = Array(array)
      return nil if array.empty?
      array.join(":").tr(" ", ":")
    end

    def set_key(raw_key, value, hash, file)
      raw_key = raw_key.to_s
      value = array_to_s(value) if is_array(raw_key)

      key = key_for(raw_key)

      return if hash[key] == value

      hash[key] = value
      hash.delete(key) if value.nil?

      Validator.validate!(raw_key, converted_value(value, raw_key), hash)

      return unless file
      SharedHelpers.filesystem_access(file) do |p|
        FileUtils.mkdir_p(p.dirname)
        require_relative "yaml_serializer"
        p.open("w") {|f| f.write(YAMLSerializer.dump(hash)) }
      end
    end

    def converted_value(value, key)
      if is_array(key)
        to_array(value)
      elsif value.nil?
        nil
      elsif is_bool(key) || value == "false"
        to_bool(value)
      elsif is_num(key)
        value.to_i
      else
        value.to_s
      end
    end

    def global_config_file
      if ENV["BUNDLE_CONFIG"] && !ENV["BUNDLE_CONFIG"].empty?
        Pathname.new(ENV["BUNDLE_CONFIG"])
      else
        begin
          Bundler.user_bundle_path("config")
        rescue PermissionError, GenericSystemCallError
          nil
        end
      end
    end

    def local_config_file
      Pathname.new(@root).join("config") if @root
    end

    def load_config(config_file)
      return {} if !config_file || ignore_config?
      SharedHelpers.filesystem_access(config_file, :read) do |file|
        valid_file = file.exist? && !file.size.zero?
        return {} unless valid_file
        require_relative "yaml_serializer"
        YAMLSerializer.load file.read
      end
    end

    PER_URI_OPTIONS = %w[
      fallback_timeout
    ].freeze

    NORMALIZE_URI_OPTIONS_PATTERN =
      /
        \A
        (\w+\.)? # optional prefix key
        (https?.*?) # URI
        (\.#{Regexp.union(PER_URI_OPTIONS)})? # optional suffix key
        \z
      /ix.freeze

    # TODO: duplicates Rubygems#normalize_uri
    # TODO: is this the correct place to validate mirror URIs?
    def self.normalize_uri(uri)
      uri = uri.to_s
      if uri =~ NORMALIZE_URI_OPTIONS_PATTERN
        prefix = $1
        uri = $2
        suffix = $3
      end
      uri = "#{uri}/" unless uri.end_with?("/")
      uri = URI(uri)
      unless uri.absolute?
        raise ArgumentError, format("Gem sources must be absolute. You provided '%s'.", uri)
      end
      "#{prefix}#{uri}#{suffix}"
    end
  end
end
