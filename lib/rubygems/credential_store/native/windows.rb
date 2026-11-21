# frozen_string_literal: true

require "open3"

class Gem::CredentialStore; end unless defined?(Gem::CredentialStore)

##
# Stores credentials in the Windows Credential Manager via the
# +Windows.Security.Credentials.PasswordVault+ WinRT API, driven from
# PowerShell. Account/service/secret values are passed as environment
# variables rather than interpolated into the script text, so no quoting
# scheme is needed and values cannot break out of the script.
#
# Windows PowerShell is used rather than PowerShell 7 (+pwsh+) because the
# WinRT projection used here is not reliably available under pwsh. It is
# spawned as +powershell+ rather than +powershell.exe+, the way this codebase
# spawns +git+, so PATHEXT resolves it. That also lets the tests put a shim
# ahead of it on Windows, where a file with a shebang is not executable.

class Gem::CredentialStore::WindowsBackend
  LOAD_VAULT_TYPE = <<~POWERSHELL
    $ErrorActionPreference = 'Stop'
    [void][Windows.Security.Credentials.PasswordVault,Windows.Security.Credentials,ContentType=WindowsRuntime]
  POWERSHELL
  private_constant :LOAD_VAULT_TYPE

  def self.get(service, account)
    script = <<~POWERSHELL
      #{LOAD_VAULT_TYPE}
      $vault = New-Object Windows.Security.Credentials.PasswordVault
      $credential = $vault.Retrieve($env:RUBYGEMS_CRED_SERVICE, $env:RUBYGEMS_CRED_ACCOUNT)
      # Emitting into the pipeline would send the string through PowerShell's
      # formatter, which wraps at the host width and would corrupt a secret.
      [Console]::Out.Write($credential.Password)
    POWERSHELL

    out, err, status = run(script, service, account)
    # An absent credential is ordinary. Any other failure is not, so raise and
    # let the wrapper report why rather than authenticating without one.
    unless status.success?
      return nil if missing_credential?(err)

      raise "powershell exited with #{status.exitstatus}: #{err.strip}"
    end

    secret = out.chomp
    secret.empty? ? nil : secret
  end

  def self.set(service, account, secret)
    script = <<~POWERSHELL
      #{LOAD_VAULT_TYPE}
      $vault = New-Object Windows.Security.Credentials.PasswordVault
      try {
        $existing = $vault.Retrieve($env:RUBYGEMS_CRED_SERVICE, $env:RUBYGEMS_CRED_ACCOUNT)
        $vault.Remove($existing)
      } catch {}
      $credential = New-Object Windows.Security.Credentials.PasswordCredential($env:RUBYGEMS_CRED_SERVICE, $env:RUBYGEMS_CRED_ACCOUNT, $env:RUBYGEMS_CRED_SECRET)
      $vault.Add($credential)
    POWERSHELL

    _out, err, status = run(script, service, account, secret)
    return true if status.success?

    # Raise so the reason reaches the user; see MacOSBackend.set.
    raise "powershell exited with #{status.exitstatus}: #{err.strip}"
  end

  def self.delete(service, account)
    script = <<~POWERSHELL
      #{LOAD_VAULT_TYPE}
      $vault = New-Object Windows.Security.Credentials.PasswordVault
      $credential = $vault.Retrieve($env:RUBYGEMS_CRED_SERVICE, $env:RUBYGEMS_CRED_ACCOUNT)
      $vault.Remove($credential)
    POWERSHELL

    _out, err, status = run(script, service, account)
    status.success? || missing_credential?(err)
  end

  # FindAllByResource raises when the resource has no entries, which is an
  # empty list rather than an error.
  def self.list(service)
    script = <<~POWERSHELL
      #{LOAD_VAULT_TYPE}
      $vault = New-Object Windows.Security.Credentials.PasswordVault
      try {
        $vault.FindAllByResource($env:RUBYGEMS_CRED_SERVICE) | ForEach-Object {
          [Console]::Out.WriteLine($_.UserName)
        }
      } catch {
        if (-not ($_.Exception.Message -match 'not found|0x80070490')) { throw }
      }
    POWERSHELL

    out, _err, status = run(script, service, nil)
    return [] unless status.success?

    out.split("\n").map(&:chomp).reject(&:empty?).uniq
  end

  def self.delete_all(service)
    script = <<~POWERSHELL
      #{LOAD_VAULT_TYPE}
      $vault = New-Object Windows.Security.Credentials.PasswordVault
      try {
        $vault.FindAllByResource($env:RUBYGEMS_CRED_SERVICE) | ForEach-Object { $vault.Remove($_) }
      } catch {
        if (-not ($_.Exception.Message -match 'not found|0x80070490')) { throw }
      }
    POWERSHELL

    _out, err, status = run(script, service, nil)
    status.success? || missing_credential?(err)
  end

  def self.run(script, service, account, secret = nil)
    env = { "RUBYGEMS_CRED_SERVICE" => service, "RUBYGEMS_CRED_ACCOUNT" => account }
    env["RUBYGEMS_CRED_SECRET"] = secret if secret

    Open3.capture3(env, "powershell", "-NoProfile", "-NonInteractive", "-Command", "-", stdin_data: script)
  end
  private_class_method :run

  def self.missing_credential?(message)
    text = message.to_s.downcase
    text.include?("element not found") || text.include?("0x80070490") || text.include?("could not be found")
  end
  private_class_method :missing_credential?
end
