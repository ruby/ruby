# frozen_string_literal: true
require "uri"

module Bundler
  class Settings
    autoload :Mirror,  "bundler/mirror"
    autoload :Mirrors, "bundler/mirror"

    BOOL_KEYS = %w(
      allow_offline_install
      auto_install
      cache_all
      cache_all_platforms
      disable_checksum_validation
      disable_exec_load
      disable_local_branch_check
      disable_shared_gems
      disable_version_check
      force_ruby_platform
      frozen
      gem.coc
      gem.mit
      ignore_messages
      major_deprecations
      no_install
      no_prune
      only_update_to_newer_versions
      plugins
      silence_root_warning
    ).freeze

    NUMBER_KEYS = %w(
      redirect
      retry
      ssl_verify_mode
      timeout
    ).freeze

    DEFAULT_CONFIG = {
      :redirect => 5,
      :retry => 3,
      :timeout => 10,
    }.freeze

    attr_accessor :cli_flags_given

    def initialize(root = nil)
      @root            = root
      @local_config    = load_config(local_config_file)
      @global_config   = load_config(global_config_file)
      @cli_flags_given = false
      @temporary       = {}
    end

    def [](name)
      key = key_for(name)
      value = @temporary.fetch(name) do
              @local_config.fetch(key) do
              ENV.fetch(key) do
              @global_config.fetch(key) do
              DEFAULT_CONFIG.fetch(name) do
                nil
              end end end end end

      converted_value(value, name)
    end

    def []=(key, value)
      if cli_flags_given
        command = if value.nil?
          "bundle config --delete #{key}"
        else
          "bundle config #{key} #{Array(value).join(":")}"
        end

        Bundler::SharedHelpers.major_deprecation \
          "flags passed to commands " \
          "will no longer be automatically remembered. Instead please set flags " \
          "you want remembered between commands using `bundle config " \
          "<setting name> <setting value>`, i.e. `#{command}`"
      end
      local_config_file || raise(GemfileNotFound, "Could not locate Gemfile")
      set_key(key, value, @local_config, local_config_file)
    end
    alias_method :set_local, :[]=

    def temporary(update)
      existing = Hash[update.map {|k, _| [k, @temporary[k]] }]
      @temporary.update(update)
      return unless block_given?
      begin
        yield
      ensure
        existing.each {|k, v| v.nil? ? @temporary.delete(k) : @temporary[k] = v }
      end
    end

    def delete(key)
      @local_config.delete(key_for(key))
    end

    def set_global(key, value)
      set_key(key, value, @global_config, global_config_file)
    end

    def all
      env_keys = ENV.keys.select {|k| k =~ /BUNDLE_.*/ }

      keys = @global_config.keys | @local_config.keys | env_keys

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
        mirrors.parse(k, self[k]) if k =~ /^mirror\./
        mirrors
      end
    end

    def locations(key)
      key = key_for(key)
      locations = {}
      locations[:local]  = @local_config[key] if @local_config.key?(key)
      locations[:env]    = ENV[key] if ENV[key]
      locations[:global] = @global_config[key] if @global_config.key?(key)
      locations[:default] = DEFAULT_CONFIG[key] if DEFAULT_CONFIG.key?(key)
      locations
    end

    def pretty_values_for(exposed_key)
      key = key_for(exposed_key)

      locations = []
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

    def without=(array)
      set_array(:without, array)
    end

    def with=(array)
      set_array(:with, array)
    end

    def without
      get_array(:without)
    end

    def with
      get_array(:with)
    end

    # @local_config["BUNDLE_PATH"] should be prioritized over ENV["BUNDLE_PATH"]
    def path
      key  = key_for(:path)
      path = ENV[key] || @global_config[key]
      return path if path && !@local_config.key?(key)

      if path = self[:path]
        "#{path}/#{Bundler.ruby_scope}"
      else
        Bundler.rubygems.gem_dir
      end
    end

    def allow_sudo?
      !@local_config.key?(key_for(:path))
    end

    def ignore_config?
      ENV["BUNDLE_IGNORE_CONFIG"]
    end

    def app_cache_path
      @app_cache_path ||= begin
        path = self[:cache_path] || "vendor/cache"
        raise InvalidOption, "Cache path must be relative to the bundle path" if path.start_with?("/")
        path
      end
    end

  private

    def key_for(key)
      key = Settings.normalize_uri(key).to_s if key.is_a?(String) && /https?:/ =~ key
      key = key.to_s.gsub(".", "__").upcase
      "BUNDLE_#{key}"
    end

    def parent_setting_for(name)
      split_specfic_setting_for(name)[0]
    end

    def specfic_gem_for(name)
      split_specfic_setting_for(name)[1]
    end

    def split_specfic_setting_for(name)
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

    def is_num(value)
      NUMBER_KEYS.include?(value.to_s)
    end

    def get_array(key)
      self[key] ? self[key].split(":").map(&:to_sym) : []
    end

    def set_array(key, array)
      self[key] = (array.empty? ? nil : array.join(":")) if array
    end

    def set_key(key, value, hash, file)
      key = key_for(key)

      unless hash[key] == value
        hash[key] = value
        hash.delete(key) if value.nil?
        SharedHelpers.filesystem_access(file) do |p|
          FileUtils.mkdir_p(p.dirname)
          require "bundler/yaml_serializer"
          p.open("w") {|f| f.write(YAMLSerializer.dump(hash)) }
        end
      end

      value
    end

    def converted_value(value, key)
      if value.nil?
        nil
      elsif is_bool(key) || value == "false"
        to_bool(value)
      elsif is_num(key)
        value.to_i
      else
        value
      end
    end

    def global_config_file
      if ENV["BUNDLE_CONFIG"] && !ENV["BUNDLE_CONFIG"].empty?
        Pathname.new(ENV["BUNDLE_CONFIG"])
      else
        begin
          Bundler.user_bundle_path.join("config")
        rescue PermissionError, GenericSystemCallError
          nil
        end
      end
    end

    def local_config_file
      Pathname.new(@root).join("config") if @root
    end

    CONFIG_REGEX = %r{ # rubocop:disable Style/RegexpLiteral
      ^
      (BUNDLE_.+):\s # the key
      (?: !\s)? # optional exclamation mark found with ruby 1.9.3
      (['"]?) # optional opening quote
      (.* # contents of the value
        (?: # optionally, up until the next key
          (\n(?!BUNDLE).+)*
        )
      )
      \2 # matching closing quote
      $
    }xo

    def load_config(config_file)
      return {} if !config_file || ignore_config?
      SharedHelpers.filesystem_access(config_file, :read) do |file|
        valid_file = file.exist? && !file.size.zero?
        return {} unless valid_file
        require "bundler/yaml_serializer"
        YAMLSerializer.load file.read
      end
    end

    # TODO: duplicates Rubygems#normalize_uri
    # TODO: is this the correct place to validate mirror URIs?
    def self.normalize_uri(uri)
      uri = uri.to_s
      uri = "#{uri}/" unless uri =~ %r{/\Z}
      uri = URI(uri)
      unless uri.absolute?
        raise ArgumentError, format("Gem sources must be absolute. You provided '%s'.", uri)
      end
      uri
    end
  end
end
