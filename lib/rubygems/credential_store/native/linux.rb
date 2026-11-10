# frozen_string_literal: true

require "open3"

class Gem::CredentialStore; end unless defined?(Gem::CredentialStore)

##
# Stores credentials in the Secret Service API (GNOME Keyring, KWallet,
# ...) via the +secret-tool+ command line tool from libsecret.

class Gem::CredentialStore::LinuxBackend
  # secret-tool prints an item's attributes to stderr, one per line.
  ACCOUNT_ATTRIBUTE = /^attribute\.account = (.*)$/
  def self.available?
    return @available if defined?(@available)

    @available = ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
      File.executable?(File.join(dir, "secret-tool"))
    end
  end

  ##
  # Clears the memoized #available? result. Intended for tests only.

  def self.reset!
    remove_instance_variable(:@available) if defined?(@available)
  end

  def self.get(service, account)
    out, err, status = Open3.capture3(
      "secret-tool", "lookup", "service", service, "account", account
    )
    # secret-tool exits 1 with nothing on stderr when the entry is simply
    # absent. Anything else is a real failure.
    unless status.success?
      return nil if status.exitstatus == 1 && err.to_s.strip.empty?

      raise "secret-tool exited with #{status.exitstatus}: #{err.strip}"
    end

    secret = out.chomp
    secret.empty? ? nil : secret
  end

  def self.set(service, account, secret)
    _out, status = Open3.capture2(
      "secret-tool", "store", "--label=RubyGems", "service", service, "account", account,
      stdin_data: secret
    )
    status.success?
  end

  # secret-tool writes attributes to stderr and secrets to stdout, so accounts
  # are read from stderr. Discarding stdout also keeps a secret containing a
  # newline from being mistaken for an attribute line.
  def self.list(service)
    _out, err, status = Open3.capture3(
      "secret-tool", "search", "--all", "service", service
    )
    return [] unless status.success?

    err.scan(ACCOUNT_ATTRIBUTE).flatten.uniq
  end

  def self.delete(service, account)
    _out, err, status = Open3.capture3(
      "secret-tool", "clear", "service", service, "account", account
    )
    return cleared?(service, account) if status.success?

    # secret-tool clear exits 1 with no stderr when nothing matched.
    status.exitstatus == 1 && err.to_s.strip.empty?
  end

  def self.delete_all(service)
    _out, err, status = Open3.capture3(
      "secret-tool", "clear", "service", service
    )
    return cleared?(service) if status.success?

    status.exitstatus == 1 && err.to_s.strip.empty?
  end

  # libsecret clears only unlocked items and reports no error for the ones it
  # skipped, so a locked keyring answers a clear with success while keeping
  # every secret. search exits zero either way, so its output is the answer.
  def self.cleared?(service, account = nil)
    _out, err, status = Open3.capture3(
      "secret-tool", "search", "--all", "service", service
    )
    return false unless status.success?

    remaining = err.scan(ACCOUNT_ATTRIBUTE).flatten
    account ? !remaining.include?(account) : remaining.empty?
  end
  private_class_method :cleared?
end
