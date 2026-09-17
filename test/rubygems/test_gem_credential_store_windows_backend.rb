# frozen_string_literal: true

require_relative "helper"
require "rubygems/credential_store/native/windows"
require "json"

class TestGemCredentialStoreWindowsBackend < Gem::TestCase
  FAKE_COMMAND = <<~'RUBY'
    #!/usr/bin/env ruby
    require "json"
    stdin_content = $stdin.read
    if record_path = ENV["RUBYGEMS_FAKE_CMD_RECORD"]
      record = {
        "argv" => ARGV,
        "stdin" => stdin_content,
        "service_env" => ENV["RUBYGEMS_CRED_SERVICE"],
        "account_env" => ENV["RUBYGEMS_CRED_ACCOUNT"],
        "secret_env" => ENV["RUBYGEMS_CRED_SECRET"],
      }
      File.write(record_path, record.to_json)
    end
    $stdout.write(ENV["RUBYGEMS_FAKE_CMD_STDOUT"].to_s)
    $stderr.write(ENV["RUBYGEMS_FAKE_CMD_STDERR"].to_s)
    exit(ENV["RUBYGEMS_FAKE_CMD_EXIT"].to_i)
  RUBY

  def setup
    super

    # The stand-in below is reached through MRI's own PATH search, which walks
    # every extension inside one directory before moving to the next and knows
    # to run a batch file through a command line. JRuby spawns through Java,
    # whose search appends only .exe, so it would reach the real powershell.
    pend "the powershell stand-in relies on how MRI resolves a program name" if Gem.java_platform?

    @fake_bin_dir = File.join(@tempdir, "fake-bin")
    FileUtils.mkdir_p(@fake_bin_dir)
    fake_path = File.join(@fake_bin_dir, "powershell")
    File.write(fake_path, FAKE_COMMAND)
    File.chmod(0o755, fake_path)

    # A shebang does not make a file executable on Windows. PATHEXT finds the
    # batch file for the extensionless name the backend spawns, and the batch
    # file hands the script next to it to the running ruby.
    if Gem.win_platform?
      File.write("#{fake_path}.bat", <<~BATCH)
        @ECHO OFF
        @"#{Gem.ruby.tr("/", File::ALT_SEPARATOR || "/")}" "%~dpn0" %*
      BATCH
    end

    @record_path = File.join(@tempdir, "record.json")
  end

  def test_get_returns_stripped_secret_on_success
    with_fake_env(stdout: "s3cr3t\n", exit: 0) do
      assert_equal "s3cr3t", Gem::CredentialStore::WindowsBackend.get("rubygems", "example.org")
    end
  end

  def test_get_returns_nil_when_credential_missing
    with_fake_env(stderr: "Element not found. (Exception from HRESULT: 0x80070490)", exit: 1) do
      assert_nil Gem::CredentialStore::WindowsBackend.get("rubygems", "example.org")
    end
  end

  def test_get_raises_on_any_other_failure
    # A vault that refuses to answer is not the same as one holding nothing.
    # Raising lets the wrapper report why rather than authenticating with no
    # credential at all.
    with_fake_env(stderr: "Access is denied.", exit: 1) do
      error = assert_raise(RuntimeError) do
        Gem::CredentialStore::WindowsBackend.get("rubygems", "example.org")
      end

      assert_match(/Access is denied/, error.message)
    end
  end

  def test_get_passes_service_and_account_via_environment_not_script
    with_fake_env(stdout: "s3cr3t\n", exit: 0) do
      Gem::CredentialStore::WindowsBackend.get("rubygems", "example.org")
    end

    record = read_record
    assert_equal "rubygems", record["service_env"]
    assert_equal "example.org", record["account_env"]
  end

  def test_set_passes_secret_via_environment_not_argv_or_script_text
    with_fake_env(exit: 0) do
      Gem::CredentialStore::WindowsBackend.set("rubygems", "example.org", "s3cr3t")
    end

    record = read_record
    assert_equal "s3cr3t", record["secret_env"]
    refute_includes record["argv"].to_s, "s3cr3t"
  end

  def test_set_returns_true_on_success
    with_fake_env(exit: 0) do
      assert Gem::CredentialStore::WindowsBackend.set("rubygems", "example.org", "s3cr3t")
    end
  end

  def test_list_returns_the_user_names
    with_fake_env(stdout: "gems.example.com\nother.example.org\n", exit: 0) do
      assert_equal ["gems.example.com", "other.example.org"],
                   Gem::CredentialStore::WindowsBackend.list("bundler")
    end

    assert_equal "bundler", read_record["service_env"]
  end

  def test_list_returns_empty_on_failure
    with_fake_env(stderr: "Access is denied.", exit: 1) do
      assert_empty Gem::CredentialStore::WindowsBackend.list("bundler")
    end
  end

  def test_delete_returns_true_on_success
    with_fake_env(exit: 0) do
      assert Gem::CredentialStore::WindowsBackend.delete("rubygems", "example.org")
    end
  end

  def test_delete_returns_true_when_credential_missing
    with_fake_env(stderr: "Element not found. (Exception from HRESULT: 0x80070490)", exit: 1) do
      assert Gem::CredentialStore::WindowsBackend.delete("rubygems", "example.org")
    end
  end

  def test_delete_returns_false_on_other_failure
    with_fake_env(stderr: "Access is denied.", exit: 1) do
      refute Gem::CredentialStore::WindowsBackend.delete("rubygems", "example.org")
    end
  end

  def test_delete_all_passes_service_and_succeeds
    with_fake_env(exit: 0) do
      assert Gem::CredentialStore::WindowsBackend.delete_all("rubygems")
    end

    assert_equal "rubygems", read_record["service_env"]
  end

  def test_delete_all_returns_true_when_resource_missing
    with_fake_env(stderr: "Element not found. (Exception from HRESULT: 0x80070490)", exit: 1) do
      assert Gem::CredentialStore::WindowsBackend.delete_all("rubygems")
    end
  end

  def test_delete_all_returns_false_on_other_failure
    with_fake_env(stderr: "Access is denied.", exit: 1) do
      refute Gem::CredentialStore::WindowsBackend.delete_all("rubygems")
    end
  end

  def test_uses_powershell_exe_not_pwsh
    with_fake_env(stdout: "s3cr3t\n", exit: 0) do
      Gem::CredentialStore::WindowsBackend.get("rubygems", "example.org")
    end

    # No assertion beyond "this succeeded": the fake binary is only
    # discoverable under the literal name powershell.exe, so a pass here
    # proves the backend invokes that name specifically.
    assert File.exist?(@record_path)
  end

  private

  def with_fake_env(stdout: "", stderr: "", exit: 0)
    overrides = ENV.to_h.merge(
      "PATH" => [@fake_bin_dir, ENV["PATH"]].join(File::PATH_SEPARATOR),
      "RUBYGEMS_FAKE_CMD_STDOUT" => stdout,
      "RUBYGEMS_FAKE_CMD_STDERR" => stderr,
      "RUBYGEMS_FAKE_CMD_EXIT" => exit.to_s,
      "RUBYGEMS_FAKE_CMD_RECORD" => @record_path
    )
    with_env(overrides) { yield }
  end

  def read_record
    JSON.parse(File.read(@record_path))
  end
end
