# frozen_string_literal: true

require "open3"

class Gem::CredentialStore; end unless defined?(Gem::CredentialStore)

##
# Stores credentials in the macOS Keychain via the +security+ command line
# tool. +security+ has no way to read a password from stdin as raw bytes
# for +add-generic-password+, so #set uses +security -i+ (batch/interactive
# mode, one tokenized command per stdin line) to keep the secret off argv
# and out of +ps+ output.
#
# A newline would start a second command in the +security -i+ batch, and
# +security find-generic-password -w+ prints any non-printable byte back as a
# hex string rather than the original value, so a non-ASCII secret would
# round-trip corrupted. Those are the limits Gem::CredentialStore#set enforces
# for every backend, so the caller falls back to file storage rather than
# storing something that cannot be read back.

class Gem::CredentialStore::MacOSBackend
  NOT_FOUND_STATUS = 44

  def self.get(service, account)
    out, err, status = Open3.capture3(
      "security", "find-generic-password", "-a", account, "-s", service, "-w"
    )
    # A locked keychain and an absent entry both yield no secret, but only the
    # second one is ordinary.
    unless status.success?
      return nil if status.exitstatus == NOT_FOUND_STATUS

      raise "security exited with #{status.exitstatus}: #{err.strip}"
    end

    secret = out.chomp
    secret.empty? ? nil : secret
  end

  def self.set(service, account, secret)
    command = "add-generic-password -U -a #{quote(account)} -s #{quote(service)} -w #{quote(secret)}\n"
    _out, err, status = Open3.capture3("security", "-i", stdin_data: command)
    return true if status.success?

    # Raise rather than return false so the reason reaches the user. The
    # wrapper turns it back into false after reporting it.
    raise "security exited with #{status.exitstatus}: #{err.strip}"
  end

  # security has no "list by service" subcommand, so this reads the dump, which
  # never reports the secrets.
  def self.list(service)
    out, status = Open3.capture2("security", "dump-keychain", err: File::NULL)
    return [] unless status.success?

    out.split(/^keychain: /).filter_map do |entry|
      next unless entry[/^\s*"svce"<blob>="(.*)"$/, 1] == service

      entry[/^\s*"acct"<blob>="(.*)"$/, 1]
    end.uniq
  end

  def self.delete(service, account)
    _out, status = Open3.capture2(
      "security", "delete-generic-password", "-a", account, "-s", service,
      err: File::NULL
    )
    status.success? || status.exitstatus == NOT_FOUND_STATUS
  end

  # security deletes one entry per call, so keep going until it reports there
  # is nothing left (exit 44). Other services are untouched.
  def self.delete_all(service)
    loop do
      _out, status = Open3.capture2(
        "security", "delete-generic-password", "-s", service,
        err: File::NULL
      )
      return true if status.exitstatus == NOT_FOUND_STATUS
      return false unless status.success?
    end
  end

  def self.quote(value)
    %("#{value.gsub("\\", "\\\\\\\\").gsub('"', '\\"')}")
  end
  private_class_method :quote
end
