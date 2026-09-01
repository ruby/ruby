# frozen_string_literal: true

module Bundler
  class Settings
    autoload :Mirror,  File.expand_path("mirror", __dir__)
    autoload :Mirrors, File.expand_path("mirror", __dir__)
    autoload :Validator, File.expand_path("settings/validator", __dir__)

    BOOL_KEYS = %w[
      auto_install
      cache_all
      cache_all_platforms
      clean
      deployment
      disable_checksum_validation
      disable_exec_load
      disable_local_branch_check
      disable_local_revision_check
      disable_shared_gems
      disable_version_check
      force_ruby_platform
      frozen
      gem.changelog
      gem.coc
      gem.mit
      gem.bundle
      git.allow_insecure
      global_gem_cache
      ignore_messages
      init_gems_rb
      inline
      keep_outdated_cache
      lockfile_checksums
      no_build_extension
      no_install
      no_install_plugin
      no_prune
      path.system
      plugins
      prefer_patch
      silence_deprecations
      silence_root_warning
      update_requires_all_flag
      verbose
    ].freeze

    NUMBER_KEYS = %w[
      cooldown
      jobs
      redirect
      retry
      ssl_verify_mode
      timeout
    ].freeze

    ARRAY_KEYS = %w[
      only
      prune
      with
      without
    ].freeze

    STRING_KEYS = %w[
      bin
      cache_path
      console
      credential_store
      default_cli_command
      gem.ci
      gem.github_username
      gem.linter
      gem.rubocop
      gem.test
      gemfile
      lockfile
      path
      shebang
      simulate_version
      system_bindir
      trust-policy
      version
    ].freeze

    DEFAULT_CONFIG = {
      "BUNDLE_SILENCE_DEPRECATIONS" => false,
      "BUNDLE_DISABLE_VERSION_CHECK" => true,
      "BUNDLE_PREFER_PATCH" => false,
      "BUNDLE_REDIRECT" => 5,
      "BUNDLE_RETRY" => 3,
      "BUNDLE_TIMEOUT" => 10,
      "BUNDLE_VERSION" => "lockfile",
      "BUNDLE_LOCKFILE_CHECKSUMS" => true,
      "BUNDLE_CACHE_ALL" => true,
      "BUNDLE_PLUGINS" => true,
      "BUNDLE_GLOBAL_GEM_CACHE" => false,
      "BUNDLE_UPDATE_REQUIRES_ALL_FLAG" => false,
    }.freeze

    ##
    # Settings renamed in Bundler 4, mapping the current name to the one it
    # replaced. The old name is still read, and goes away in Bundler 5.

    RENAMED_KEYS = {
      "keep_outdated_cache" => "no_prune",
    }.freeze

    def initialize(root = nil)
      @root            = root
      @local_config    = load_config(local_config_file)
      @local_root      = root || Pathname.new(".bundle").expand_path

      @env_config      = ENV.to_h
      @env_config.select! {|key, _value| key.start_with?("BUNDLE_") }
      @env_config.delete("BUNDLE_")

      @global_config   = load_config(global_config_file)
      @temporary       = {}

      @key_cache = {}
    end

    def [](name)
      converted_value(configured_value(name), name)
    end

    def set_command_option(key, value)
      temporary(key => value)
      value
    end

    def set_command_option_if_given(key, value)
      return if value.nil?
      set_command_option(key, value)
    end

    def set_local(key, value)
      local_config_file = @local_root.join("config")

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
      keys = @temporary.keys.union(@global_config.keys, @local_config.keys, @env_config.keys)

      keys.map! do |key|
        key = key.delete_prefix("BUNDLE_")
        key.gsub!("___", "-")
        key.gsub!("__", ".")
        key.downcase!
        key
      end.sort!
      keys
    end

    ##
    # #all plus the keys whose credential lives in the credential store. Kept
    # apart from #all because that one is on the hot path (it is read per gem
    # source and per download, and its keys are advertised in the User-Agent),
    # while this one is for the commands that display settings.

    def all_including_stored_credentials
      keys = stored_credential_keys.map do |key|
        key = key.delete_prefix("BUNDLE_")
        key.gsub!("___", "-")
        key.gsub!("__", ".")
        key.downcase!
        key
      end

      # The listing comes from the globally selected store, but a host can name
      # its own, so keep only the keys the per-host lookup agrees are set.
      keys.select! {|key| credential_stored?(key) }

      all.union(keys).sort
    end

    def local_overrides
      repos = {}
      all.each do |k|
        repos[k.delete_prefix("local.")] = self[k] if k.start_with?("local.")
      end
      repos
    end

    def mirror_for(uri)
      if uri.is_a?(String)
        require_relative "vendored_uri"
        uri = Gem::URI(uri)
      end

      gem_mirrors.for(uri.to_s).uri
    end

    def credentials_for(uri)
      stored = credentials_from_store(uri)
      return credentials_from_env(uri) || stored if stored

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
      configs.keys.inject({}) do |partial_locations, level|
        value_on_level = configs[level][key]
        partial_locations[level] = value_on_level unless value_on_level.nil?
        partial_locations
      end
    end

    def pretty_values_for(exposed_key)
      key = key_for(exposed_key)

      locations = []

      if value = @temporary[key]
        locations << "Set for the current command: #{printable_value(value, exposed_key).inspect}"
      end

      if value = @local_config[key]
        locations << "Set for your local app (#{local_config_file}): #{printable_value(value, exposed_key).inspect}"
      end

      if value = @env_config[key]
        locations << "Set via #{key}: #{printable_value(value, exposed_key).inspect}"
      end

      if credential_stored?(exposed_key)
        # The heading calls this a priority order, but a stored credential sits
        # outside it and is used ahead of every config file.
        locations << "Set in the credential store, which is used ahead of the config files"
      end

      if value = @global_config[key]
        locations << "Set for the current user (#{global_config_file}): #{printable_value(value, exposed_key).inspect}"
      end

      return ["You have not configured a value for `#{exposed_key}`"] if locations.empty?
      locations
    end

    ##
    # True when +name+'s credential lives in the credential store. The secret
    # itself is never returned: callers only need to know the setting exists,
    # since Settings#[] cannot see past the config files.

    def credential_stored?(name)
      raw_key = self.class.key_to_s(name)
      return false unless credential_store_key?(raw_key)
      return false unless store = active_credential_store(credential_host(raw_key))

      !store.get(credential_account(raw_key)).nil?
    end

    ##
    # The keys credentials are stored under, in the same encoding the config
    # hashes use, so #all can fold them in. Empty when no store is enabled or
    # when the backend cannot enumerate its entries, which is why
    # bundle-config(1) warns that a third-party backend may not list.

    def stored_credential_keys
      return [] unless store = active_credential_store

      Array(store.list)
    end

    def processor_count
      require "etc"
      Etc.nprocessors
    rescue StandardError
      1
    end

    # for legacy reasons, in Bundler 2, we do not respect :disable_shared_gems
    def path
      configs.each do |_level, settings|
        path = value_for("path", settings)
        path_system = value_for("path.system", settings)
        disabled_shared_gems = value_for("disable_shared_gems", settings)
        next if path.nil? && path_system.nil? && disabled_shared_gems.nil?
        system_path = path_system || (disabled_shared_gems == false)
        return Path.new(path, system_path)
      end

      path = "vendor/bundle" if self[:deployment]

      Path.new(path, false)
    end

    Path = Struct.new(:explicit_path, :system_path) do
      def path
        path = base_path
        path = File.join(path, Bundler.ruby_scope) unless use_system_gems?
        path
      end

      def use_system_gems?
        return true if system_path
        return false if explicit_path
        !Bundler.feature_flag.bundler_5_mode?
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

    def ignore_config?
      ENV["BUNDLE_IGNORE_CONFIG"]
    end

    def app_cache_path
      @app_cache_path ||= self[:cache_path] || "vendor/cache"
    end

    def installation_parallelization
      self[:jobs] || processor_count
    end

    def validate!
      all.each do |raw_key|
        [@local_config, @env_config, @global_config].each do |settings|
          value = value_for(raw_key, settings)
          Validator.validate!(raw_key, value, settings.dup)
        end
      end
    end

    def key_for(key)
      @key_cache[key] ||= self.class.key_for(key)
    end

    private

    def configs
      @configs ||= {
        temporary: @temporary,
        local: @local_config,
        env: @env_config,
        global: @global_config,
        default: DEFAULT_CONFIG,
      }
    end

    def value_for(name, config)
      converted_value(config[key_for(name)], name)
    end

    ##
    # A renamed setting is resolved one level at a time rather than by looking
    # for the current name everywhere first, so that the old name keeps the
    # documented priority order: an old name set locally still beats a current
    # name set globally.

    def configured_value(name)
      key = key_for(name)
      old_name = RENAMED_KEYS[self.class.key_to_s(name)]
      old_key = key_for(old_name) if old_name

      configs.each do |_, config|
        value = config[key]
        return value unless value.nil?

        next if old_key.nil?

        value = config[old_key]
        next if value.nil?

        SharedHelpers.feature_deprecated! "The `#{old_name}` setting has been renamed to `#{name}` and will be " \
                                          "removed in Bundler 5. Use `#{name}` instead."

        return value
      end

      nil
    end

    def parent_setting_for(name)
      split_specific_setting_for(name)[0]
    end

    def split_specific_setting_for(name)
      name.split(".")
    end

    def is_bool(name)
      name = self.class.key_to_s(name)
      BOOL_KEYS.include?(name) || BOOL_KEYS.include?(parent_setting_for(name))
    end

    def is_string(name)
      name = self.class.key_to_s(name)
      STRING_KEYS.include?(name) || name.start_with?("local.") || name.start_with?("mirror.") || name.start_with?("build.") || name.start_with?("credential_store.")
    end

    def to_bool(value)
      self.class.to_bool(value)
    end

    def is_num(key)
      NUMBER_KEYS.include?(self.class.key_to_s(key))
    end

    def is_array(key)
      ARRAY_KEYS.include?(self.class.key_to_s(key))
    end

    def is_credential(key)
      key == "gem.push_key"
    end

    def is_userinfo(value)
      value.include?(":")
    end

    # Kept separate from RubyGems so gem signout does not remove Bundler's
    # host credentials.
    CREDENTIAL_STORE_SERVICE = "bundler"

    ##
    # The Gem::CredentialStore for the spec #credential_store_spec returns,
    # or nil when the setting is off or this RubyGems has no credential store.
    # Guarded by a cheap lookup so reading and writing settings costs nothing
    # extra when the setting is disabled.

    def active_credential_store(host = nil)
      spec = credential_store_spec(host)
      return nil unless spec

      store_class = credential_store_class
      return nil unless store_class

      store_class.for(spec, service: CREDENTIAL_STORE_SERVICE)
    end

    # A `credential_store.<host>` setting overrides the global one for that
    # host only. There is no chain between backends.
    def credential_store_spec(host = nil)
      value = self["credential_store.#{host}"] if host
      value = self[:credential_store] if value.nil?

      # An environment variable can carry bytes String#downcase would reject.
      normalized = value.to_s.b.downcase

      # Tri-state, unlike a BOOL_KEYS setting, so #to_bool is only consulted
      # for the false half.
      return nil unless to_bool(normalized)

      case normalized
      when "true", "1", "yes", "on", "t", "y" then true
      else value.to_s
      end
    end

    def credential_store_class
      return @credential_store_class if defined?(@credential_store_class)

      @credential_store_class =
        begin
          require "rubygems/credential_store"
          Gem::CredentialStore if Gem::CredentialStore.respond_to?(:for)
        rescue LoadError
          nil
        end

      if @credential_store_class.nil?
        Bundler.ui.warn "The `credential_store` setting is set but this RubyGems does not provide a credential store. Falling back to the Bundler config file."
      elsif @credential_store_class.respond_to?(:warn_handler=)
        # Bundler replaces Gem.ui with a Gem::SilentUI subclass, which drops
        # alert_warning, so every store warning would be lost.
        @credential_store_class.warn_handler = ->(message) { Bundler.ui.warn(message) }
      end

      @credential_store_class
    end

    CREDENTIAL_URL_KEY = %r{\Ahttps?://}i
    CREDENTIAL_HOST_KEY = /\A[a-z0-9-]+(\.[a-z0-9-]+)+(:\d+)?\z/i

    ##
    # True for keys that name a host and can therefore hold a credential,
    # like the ones set via `bundle config set gems.example.com user:pass`.
    # Deliberately a positive test: a key this version does not recognize
    # stays in the config file, where Settings#[] can read it back. Matching
    # everything not on the known-settings lists would send values such as
    # `ssl_client_cert` to the credential store, and they would then read
    # back as nil because only #credentials_for consults the store.

    def credential_store_key?(raw_key)
      return false if is_bool(raw_key) || is_num(raw_key) || is_array(raw_key) || is_string(raw_key) || is_credential(raw_key)

      CREDENTIAL_URL_KEY.match?(raw_key) || CREDENTIAL_HOST_KEY.match?(raw_key)
    end

    def remove_from_store(store, key)
      unless store.available?
        Bundler.ui.warn "The credential store is enabled but unavailable, so any credential it holds was left in place."
        return true
      end

      store.delete(key)
    end

    # A write clears the plaintext only from the config file it targets, so a
    # copy in the other scope comes back into use once the setting is off.
    def warn_plaintext_in_other_scope(raw_key, key, hash)
      other, other_file =
        if hash.equal?(@local_config)
          [@global_config, global_config_file]
        else
          [@local_config, @local_root.join("config")]
        end

      return unless other.key?(key)

      # Deliberately not `bundle config unset`, which would clear the store as
      # well and throw away the credential this write moved into it.
      safe_key = self.class.remove_userinfo(raw_key)
      Bundler.ui.warn "The credential for #{safe_key} moved into the credential store, but a plain text copy" \
                      " remains in #{other_file}. Delete the #{key_for(safe_key)} entry from that file to finish the move."
    end

    def warn_unremoved_credential(raw_key)
      Bundler.ui.warn "Could not remove the credential for #{self.class.remove_userinfo(raw_key)} from the credential store." \
                      " It is still there. Remove it with your platform's credential manager."
    end

    # See Gem::ConfigFile.credential_store_account for why userinfo is dropped.
    def credential_account(raw_key)
      key_for(self.class.remove_userinfo(raw_key))
    end

    def credential_host(raw_key)
      return raw_key unless CREDENTIAL_URL_KEY.match?(raw_key)

      require_relative "vendored_uri"
      Gem::URI(raw_key).host || raw_key
    rescue Gem::URI::Error
      raw_key
    end

    # The store stands in for the config file, so it must not override the
    # environment, which already overrides that file. Consulted only when the
    # store answered, so the layer order without a store is unchanged.
    def credentials_from_env(uri)
      @env_config[key_for(uri.to_s)] || @env_config[key_for(uri.host)]
    end

    def credentials_from_store(uri)
      return nil unless store = active_credential_store(uri.host)

      store.get(credential_account(uri.to_s)) || store.get(credential_account(uri.host))
    end

    def to_array(value)
      return [] unless value
      value.tr(" ", ":").split(":").map(&:to_sym)
    end

    def array_to_s(array)
      array = Array(array)
      return nil if array.empty?
      array.join(":").tr(" ", ":")
    end

    def set_key(raw_key, value, hash, file)
      raw_key = self.class.key_to_s(raw_key)
      key = key_for(raw_key)
      account = credential_account(raw_key)

      # #temporary passes a nil file, and storing its value would outlive the
      # block while its restore pass deleted the real entry.
      if file && credential_store_key?(raw_key) && (store = active_credential_store(credential_host(raw_key)))
        if value.nil?
          warn_unremoved_credential(raw_key) unless remove_from_store(store, account)
        elsif value.is_a?(String) && is_userinfo(value)
          if store.set(account, value)
            value = nil
            warn_plaintext_in_other_scope(raw_key, key, hash)
          else
            warn_unremoved_credential(raw_key) if store.available? && !store.delete(account)
            Bundler.ui.warn "Could not write the credential for #{self.class.remove_userinfo(raw_key)} to the credential store," \
                            " so it was written to #{file} in plain text."
          end
        else
          warn_unremoved_credential(raw_key) unless remove_from_store(store, account)
        end
      end

      value = array_to_s(value) if is_array(raw_key)

      return if hash[key] == value

      hash[key] = value
      hash.delete(key) if value.nil?

      Validator.validate!(raw_key, converted_value(value, raw_key), hash)

      return unless file

      SharedHelpers.filesystem_access(file.dirname, :create) do |p|
        FileUtils.mkdir_p(p)
      end

      SharedHelpers.filesystem_access(file) do |p|
        p.open("w") {|f| f.write(serializer_class.dump(hash)) }
      end
    end

    def converted_value(value, key)
      key = self.class.key_to_s(key)

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

    def printable_value(value, key)
      converted = converted_value(value, key)
      return converted unless converted.is_a?(String)

      if is_string(key)
        converted
      elsif is_credential(key)
        "[REDACTED]"
      elsif is_userinfo(converted)
        username, pass = converted.split(":", 2)

        if pass == "x-oauth-basic"
          username = "[REDACTED]"
        else
          pass = "[REDACTED]"
        end

        [username, pass].join(":")
      else
        converted
      end
    end

    def global_config_file
      if ENV["BUNDLE_CONFIG"] && !ENV["BUNDLE_CONFIG"].empty?
        Pathname.new(ENV["BUNDLE_CONFIG"])
      elsif ENV["BUNDLE_USER_CONFIG"] && !ENV["BUNDLE_USER_CONFIG"].empty?
        Pathname.new(ENV["BUNDLE_USER_CONFIG"])
      elsif ENV["BUNDLE_USER_HOME"] && !ENV["BUNDLE_USER_HOME"].empty?
        Pathname.new(ENV["BUNDLE_USER_HOME"]).join("config")
      elsif Bundler.rubygems.user_home && !Bundler.rubygems.user_home.empty?
        Pathname.new(Bundler.rubygems.user_home).join(".bundle/config")
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
        (serializer_class.load(file.read) || {}).inject({}) do |config, (k, v)|
          k = k.dup
          k << "/" if /https?:/i.match?(k) && !k.end_with?("/", "__#{FALLBACK_TIMEOUT_URI_OPTION.upcase}")
          k.gsub!(".", "__")

          unless k.start_with?("#")
            if k.include?("-")
              Bundler.ui.warn "Your #{file} config includes `#{k}`, which contains the dash character (`-`).\n" \
                "This is deprecated, because configuration through `ENV` should be possible, but `ENV` keys cannot include dashes.\n" \
                "Please edit #{file} and replace any dashes in configuration keys with a triple underscore (`___`)."

              # string hash keys are frozen
              k = k.gsub("-", "___")
            end

            config[k] = v
          end

          config
        end
      end
    end

    def serializer_class
      # The Bundler gem ships its own copy of Gem::YAMLSerializer, so this
      # resolves even on RubyGems versions that predate it.
      require "rubygems/yaml_serializer"
      Gem::YAMLSerializer
    end

    FALLBACK_TIMEOUT_URI_OPTION = "fallback_timeout"

    NORMALIZE_URI_OPTIONS_PATTERN =
      /
        \A
        (\w+\.)? # optional prefix key
        (https?.*?) # URI
        (\.#{FALLBACK_TIMEOUT_URI_OPTION})? # optional suffix key
        \z
      /ix

    def self.to_bool(value)
      case value
      when String
        value.match?(/\A(false|f|no|n|0|)\z/i) ? false : true
      when nil, false
        false
      else
        true
      end
    end

    def self.key_for(key)
      key = key_to_s(key)
      key = normalize_uri(key) if key.start_with?("http", "mirror.http")
      key = key.gsub(".", "__")
      key.gsub!("-", "___")
      key.upcase!

      key.gsub(/\A([ #]*)/, '\1BUNDLE_')
    end

    def self.remove_userinfo(key)
      return key unless CREDENTIAL_URL_KEY.match?(key)

      require_relative "vendored_uri"
      uri = Gem::URI(key)
      return key unless uri.userinfo

      uri = uri.dup
      uri.user = uri.password = nil
      uri.to_s
    rescue Gem::URI::Error
      key
    end

    # TODO: duplicates Rubygems#normalize_uri
    # TODO: is this the correct place to validate mirror URIs?
    def self.normalize_uri(uri)
      uri = uri.to_s
      if uri =~ NORMALIZE_URI_OPTIONS_PATTERN
        prefix = $1
        uri = $2
        suffix = $3
      end
      uri = URINormalizer.normalize_suffix(uri)
      require_relative "vendored_uri"
      uri = Gem::URI(uri)
      unless uri.absolute?
        raise ArgumentError, format("Gem sources must be absolute. You provided '%s'.", uri)
      end
      "#{prefix}#{uri}#{suffix}"
    end

    # This is a hot method, so avoid respond_to? checks on every invocation
    if :read.respond_to?(:name)
      def self.key_to_s(key)
        case key
        when String
          key
        when Symbol
          key.name
        when Gem::URI::HTTP
          key.to_s
        else
          raise ArgumentError, "Invalid key: #{key.inspect}"
        end
      end
    else
      def self.key_to_s(key)
        case key
        when String
          key
        when Symbol
          key.to_s
        when Gem::URI::HTTP
          key.to_s
        else
          raise ArgumentError, "Invalid key: #{key.inspect}"
        end
      end
    end
  end
end
