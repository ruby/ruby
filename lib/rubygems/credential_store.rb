# frozen_string_literal: true

# Skip reloading when an identical copy (e.g. the one shipped inside the Bundler
# gem) was already required from a different path, to avoid redefinition warnings.
return if defined?(Gem::CredentialStore::SERVICE_NAME)

##
# Gem::CredentialStore is opt-in storage for authentication secrets (API
# keys, host credentials) in the operating system's native secret store
# instead of a plain text file:
#
# * macOS: Keychain, via the +security+ command line tool.
# * Linux: the Secret Service API (GNOME Keyring, KWallet, ...), via
#   +secret-tool+.
# * Windows: Credential Manager, via the +Windows.Security.Credentials.PasswordVault+
#   API from PowerShell.
#
# A third party can add another backend (1Password, pass, HashiCorp Vault,
# ...) by shipping a gem that provides
# <tt>rubygems/credential_store/backends/<name></tt> and calls
# .register_backend from it. Users then select it by name instead of +true+
# (see .resolve_backend).
#
# Every public method traps all errors and returns +nil+/+false+ instead of
# raising, so that callers can transparently fall back to their existing
# file-based storage when the native store is unavailable or fails (a
# locked keychain over SSH, a headless Linux session without a keyring
# daemon, ...).

class Gem::CredentialStore
  SERVICE_NAME = "rubygems"

  ##
  # Returns the store to use for +spec+, or +nil+ when the credential store
  # is off. +spec+ is either +true+ (use this platform's native backend) or
  # the name of a registered backend such as "1password". +service+ names
  # the account namespace within the backend, so RubyGems and Bundler keep
  # separate credentials in one native store. The store is memoized per
  # +spec+ and +service+ for the life of the process, so the read cache and
  # any expensive backend startup are shared across callers. A test may
  # install a stand-in via #instance= that is returned here for any enabled
  # +spec+, or inject a shared backend via #backend=.

  def self.for(spec, service: SERVICE_NAME)
    return nil unless spec
    return @override if defined?(@override) && @override

    backend = defined?(@override_backend) && @override_backend ? @override_backend : backend_for(spec)
    (@instances ||= {})[[spec, service]] ||= new(backend: backend, service: service)
  end

  ##
  # The default-backed store for this platform, i.e. <tt>for(true)</tt>.
  # Kept for callers and tests that only care about the native backend.

  def self.instance
    self.for(true)
  end

  ##
  # Installs a stand-in store that .for returns for any enabled setting.
  # Intended for tests that inject a fake backend.

  def self.instance=(store)
    @override = store
  end

  ##
  # Installs a shared backend that .for wraps for every spec and service.
  # Intended for tests that need RubyGems and Bundler credentials to land in
  # one backend under their own service names.

  def self.backend=(backend)
    @override_backend = backend
  end

  ##
  # Clears the memoized stores, the injected overrides, and the warned
  # messages. Intended for tests only.

  def self.reset!
    @override = nil
    @override_backend = nil
    @instances = nil
    @warned = nil
    @warn_handler = nil
  end

  ##
  # Warns once per distinct message. A single flag for every message would
  # let an early warning about, say, a misspelled backend name suppress the
  # later warning that a secret was written in plain text.

  def self.warn_once(message)
    @warned ||= {}
    return if @warned.key?(message)

    @warned[message] = true

    if defined?(@warn_handler) && @warn_handler
      @warn_handler.call(message)
    else
      Gem.ui.alert_warning message
    end
  end

  ##
  # Sends warnings to +handler+ (anything responding to #call) instead of
  # Gem.ui. Bundler sets this because it replaces Gem.ui with a subclass of
  # Gem::SilentUI, which discards alert_warning entirely, so a credential
  # store failure would otherwise be silent for the whole bundle command.

  def self.warn_handler=(handler)
    @warn_handler = handler
  end

  ##
  # Registers +backend+ under +name+ so it can be selected with
  # <tt>credential_store = <name></tt>. A third-party backend gem calls this
  # from the file RubyGems loads for that name (see .resolve_backend).

  def self.register_backend(name, backend)
    (@backends ||= {})[name.to_s] = backend
  end

  BACKEND_NAME = /\A[a-z0-9_-]+\z/

  ##
  # Resolves a registered backend by +name+, requiring
  # <tt>rubygems/credential_store/backends/<name></tt> on first use so a
  # backend shipped as its own gem loads only when actually selected.
  # Returns +nil+ (warning once) when the name is malformed or no gem
  # provides it, which makes callers fall back to file storage. The fixed
  # require prefix and the restricted name charset keep the setting a piece
  # of data, never a path or a command.

  def self.resolve_backend(name)
    # The setting can carry bytes Regexp#match? would reject. A name that gets
    # past the match is ASCII only, so the require path it builds stays sound.
    name = name.to_s.b
    unless BACKEND_NAME.match?(name)
      warn_once "Ignoring invalid credential store backend name #{name.inspect}."
      return nil
    end

    return @backends[name] if @backends&.key?(name)

    begin
      require "rubygems/credential_store/backends/#{name}"
    rescue LoadError
      warn_once "Credential store backend #{name.inspect} is not installed. " \
                "Install a gem that provides rubygems/credential_store/backends/#{name}, " \
                "or unset the credential_store setting. Falling back to file storage."
      return nil
    end

    @backends && @backends[name]
  end

  def self.backend_for(spec)
    spec == true ? default_backend : resolve_backend(spec)
  end
  private_class_method :backend_for

  def self.default_backend
    if Gem.win_platform?
      require_relative "credential_store/native/windows"
      WindowsBackend
    elsif RUBY_PLATFORM.include?("darwin")
      require_relative "credential_store/native/macos"
      MacOSBackend
    elsif RUBY_PLATFORM.include?("linux")
      require_relative "credential_store/native/linux"
      LinuxBackend if LinuxBackend.available?
    end
  end

  ##
  # +backend+ is only used by tests to inject a fake backend regardless of
  # the platform the test suite happens to run on. +service+ is the account
  # namespace this store reads and writes under.

  def initialize(backend: self.class.default_backend, service: SERVICE_NAME)
    @backend = backend
    @service = service
    @cache = {}
  end

  ##
  # True if a native credential backend is usable on this platform.

  def available?
    !@backend.nil?
  end

  ##
  # Returns the secret stored for +account+, or +nil+ if there is none or
  # the backend is unavailable/fails.

  def get(account)
    return nil unless @backend
    return @cache[account] if @cache.key?(account)

    @cache[account] = @backend.get(@service, account)
  rescue StandardError => e
    warn_failure(:read, e)
    # Retrying means another subprocess and, on some platforms, another
    # authorization prompt. #read_failed? keeps this apart from an absent one.
    (@failed ||= {})[account] = true
    @cache[account] = nil
  end

  ##
  # True when #get returned +nil+ for +account+ because the backend could not
  # answer, rather than because nothing is stored under it. Callers that would
  # otherwise fall back to a different credential need the difference: a
  # missing entry means "use something else", an unreadable one does not.

  def read_failed?(account)
    return false unless defined?(@failed) && @failed

    @failed.key?(account)
  end

  ##
  # Stores +secret+ for +account+. Returns +true+ on success.

  def set(account, secret)
    return false unless @backend

    validate_credential(account, secret)

    if @backend.set(@service, account, secret)
      @cache[account] = secret
      @failed&.delete(account)
      invalidate_list
      true
    else
      false
    end
  rescue StandardError => e
    warn_failure(:write, e)
    false
  end

  ##
  # Removes the secret stored for +account+. Returns +true+ if the entry is
  # gone, whether or not it existed beforehand.

  def delete(account)
    return false unless @backend

    result = @backend.delete(@service, account)
    @cache.delete(account)
    @failed&.delete(account)
    invalidate_list
    result
  rescue StandardError => e
    warn_failure(:remove, e)
    false
  end

  ##
  # The accounts this store holds, or +nil+ when the backend cannot
  # enumerate them. Listing is optional in the backend protocol: the native
  # backends implement it, but a third-party backend that only resolves
  # credentials on demand has nothing to enumerate. Callers must treat +nil+
  # as "unknown", not as "empty". Secrets are never returned.

  def list
    return nil unless @backend.respond_to?(:list)
    return @list if defined?(@list)

    @list = @backend.list(@service)
  rescue StandardError => e
    warn_failure(:list, e)
    # Remembered for the same reason #get remembers a failed read.
    @list = nil
  end

  ##
  # Removes every entry this store owns (all accounts under its service).
  # Returns +true+ when the store is now clear. Used by +gem signout+ to end
  # every session at once, mirroring deletion of the whole credentials file.

  def delete_all
    return false unless @backend

    result = @backend.delete_all(@service)
    @cache.clear
    @failed = nil
    invalidate_list
    result
  rescue StandardError => e
    warn_failure(:remove, e)
    false
  end

  private

  # The listing is memoized, so a write has to drop it.
  def invalidate_list
    remove_instance_variable(:@list) if defined?(@list)
  end

  # The macOS keychain hands non-printable bytes back as hex through the only
  # read-back its CLI offers. Applied to every backend so the same value is
  # stored, or refused for the same reason, everywhere.
  PRINTABLE_ASCII = /\A[\x20-\x7e]*\z/

  # What happens after a failure depends on the operation, so the warning has
  # to say the right thing for each.
  OUTCOMES = {
    read: "any copy left in the config file will be used instead",
    write: "falling back to file storage",
    remove: "the credential is still in the store",
    list: "stored credentials will not be listed",
  }.freeze

  # A newline in an account would start a second command in the macOS batch
  # input. #set turns the raise back into a warning and a false.
  def validate_credential(account, secret)
    raise ArgumentError, "credential secret must be printable ASCII" unless secret.to_s.b.match?(PRINTABLE_ASCII)
    raise ArgumentError, "credential account must not contain a newline" if account.to_s.include?("\n")
    raise ArgumentError, "credential service must not contain a newline" if @service.to_s.include?("\n")
  end

  def warn_failure(operation, error)
    self.class.warn_once "Credential store #{operation} failed for #{@service}" \
                         " (#{error.class}: #{error.message}); #{OUTCOMES[operation]}."
  end
end
