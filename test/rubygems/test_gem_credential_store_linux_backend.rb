# frozen_string_literal: true

require_relative "helper"
require "rubygems/credential_store/native/linux"
require "json"

class TestGemCredentialStoreLinuxBackend < Gem::TestCase
  FAKE_COMMAND = <<~'RUBY'
    #!/usr/bin/env ruby
    require "json"
    stdin_content = $stdin.read
    if record_path = ENV["RUBYGEMS_FAKE_CMD_RECORD"]
      calls = File.exist?(record_path) ? JSON.parse(File.read(record_path)) : []
      calls << {"argv" => ARGV, "stdin" => stdin_content}
      File.write(record_path, calls.to_json)
    end
    # A clear is followed by a search confirming nothing is left. secret-tool
    # exits zero from a search whether or not it matched, and reports what it
    # found on stderr, so the fake answers that call separately.
    if ARGV.first == "search" && ENV.key?("RUBYGEMS_FAKE_CMD_REMAINING")
      $stderr.write(ENV["RUBYGEMS_FAKE_CMD_REMAINING"].to_s)
      exit(0)
    end
    $stdout.write(ENV["RUBYGEMS_FAKE_CMD_STDOUT"].to_s)
    $stderr.write(ENV["RUBYGEMS_FAKE_CMD_STDERR"].to_s)
    exit(ENV["RUBYGEMS_FAKE_CMD_EXIT"].to_i)
  RUBY

  def setup
    super
    pend "fake shebang executables aren't supported on native Windows" if Gem.win_platform?

    @fake_bin_dir = File.join(@tempdir, "fake-bin")
    FileUtils.mkdir_p(@fake_bin_dir)
    fake_path = File.join(@fake_bin_dir, "secret-tool")
    File.write(fake_path, FAKE_COMMAND)
    File.chmod(0o755, fake_path)

    @record_path = File.join(@tempdir, "record.json")
    Gem::CredentialStore::LinuxBackend.reset!
  end

  def teardown
    Gem::CredentialStore::LinuxBackend.reset!
    super
  end

  def test_available_is_true_when_secret_tool_is_on_path
    with_env(ENV.to_h.merge("PATH" => [@fake_bin_dir, ENV["PATH"]].join(File::PATH_SEPARATOR))) do
      Gem::CredentialStore::LinuxBackend.reset!
      assert Gem::CredentialStore::LinuxBackend.available?
    end
  end

  def test_available_is_false_when_secret_tool_is_missing
    empty_dir = File.join(@tempdir, "empty-bin")
    FileUtils.mkdir_p(empty_dir)

    with_env(ENV.to_h.merge("PATH" => empty_dir)) do
      Gem::CredentialStore::LinuxBackend.reset!
      refute Gem::CredentialStore::LinuxBackend.available?
    end
  end

  def test_get_returns_stripped_secret_on_success
    with_fake_env(stdout: "s3cr3t\n", exit: 0) do
      assert_equal "s3cr3t", Gem::CredentialStore::LinuxBackend.get("rubygems", "example.org")
    end
  end

  def test_get_returns_nil_when_not_found
    with_fake_env(stdout: "", exit: 1) do
      assert_nil Gem::CredentialStore::LinuxBackend.get("rubygems", "example.org")
    end
  end

  def test_get_raises_when_the_keyring_reports_an_error
    # An absent entry exits 1 with nothing on stderr. Anything else is a real
    # failure and must not read as "no credential stored".
    with_fake_env(stderr: "unexpected D-Bus error", exit: 1) do
      error = assert_raise(RuntimeError) do
        Gem::CredentialStore::LinuxBackend.get("rubygems", "example.org")
      end

      assert_match(/D-Bus/, error.message)
    end
  end

  def test_get_uses_expected_argv
    with_fake_env(stdout: "s3cr3t\n", exit: 0) do
      Gem::CredentialStore::LinuxBackend.get("rubygems", "example.org")
    end

    record = read_record
    assert_equal %w[lookup service rubygems account example.org], record["argv"]
  end

  def test_set_returns_true_on_success
    with_fake_env(exit: 0) do
      assert Gem::CredentialStore::LinuxBackend.set("rubygems", "example.org", "s3cr3t")
    end
  end

  def test_set_passes_secret_via_stdin_not_argv
    with_fake_env(exit: 0) do
      Gem::CredentialStore::LinuxBackend.set("rubygems", "example.org", "s3cr3t")
    end

    record = read_record
    refute_includes record["argv"], "s3cr3t"
    assert_equal "s3cr3t", record["stdin"]
  end

  def test_list_reads_the_account_attribute_from_stderr
    # secret-tool prints attributes to stderr and the secrets to stdout.
    attributes = <<~ERR
      attribute.service = bundler
      attribute.account = gems.example.com
      attribute.service = bundler
      attribute.account = other.example.org
    ERR

    with_fake_env(stdout: "username:password", stderr: attributes, exit: 0) do
      assert_equal ["gems.example.com", "other.example.org"],
                   Gem::CredentialStore::LinuxBackend.list("bundler")
    end

    assert_equal %w[search --all service bundler], read_record["argv"]
  end

  def test_list_ignores_attribute_lines_planted_inside_a_secret
    # A secret is free-form and lands on stdout, so a newline inside it must
    # not be able to add an account to the listing.
    planted = "u:p\nattribute.account = injected\n"

    with_fake_env(stdout: planted, stderr: "attribute.account = real.example.com\n", exit: 0) do
      assert_equal ["real.example.com"], Gem::CredentialStore::LinuxBackend.list("bundler")
    end
  end

  def test_list_returns_empty_on_failure
    with_fake_env(exit: 1) do
      assert_empty Gem::CredentialStore::LinuxBackend.list("bundler")
    end
  end

  def test_delete_returns_true_on_success
    with_fake_env(exit: 0, remaining: "") do
      assert Gem::CredentialStore::LinuxBackend.delete("rubygems", "example.org")
    end
  end

  def test_delete_returns_true_when_nothing_matched
    with_fake_env(stderr: "", exit: 1) do
      assert Gem::CredentialStore::LinuxBackend.delete("rubygems", "example.org")
    end
  end

  def test_delete_returns_false_on_other_failure
    with_fake_env(stderr: "unexpected D-Bus error", exit: 1) do
      refute Gem::CredentialStore::LinuxBackend.delete("rubygems", "example.org")
    end
  end

  def test_delete_all_clears_by_service_only
    with_fake_env(exit: 0, remaining: "") do
      assert Gem::CredentialStore::LinuxBackend.delete_all("rubygems")
    end

    record = read_record
    assert_equal %w[clear service rubygems], record["argv"]
  end

  def test_delete_all_reports_failure_when_the_entries_survive
    # libsecret skips locked items and still reports success, so a locked
    # keyring would otherwise let signout claim it removed keys it kept.
    survivor = "attribute.account = example.org\n"

    with_fake_env(exit: 0, remaining: survivor) do
      refute Gem::CredentialStore::LinuxBackend.delete_all("rubygems")
      refute Gem::CredentialStore::LinuxBackend.delete("rubygems", "example.org")
    end
  end

  def test_delete_reports_success_when_only_other_accounts_remain
    with_fake_env(exit: 0, remaining: "attribute.account = other.example.org\n") do
      assert Gem::CredentialStore::LinuxBackend.delete("rubygems", "example.org")
      refute Gem::CredentialStore::LinuxBackend.delete_all("rubygems")
    end
  end

  def test_delete_all_returns_true_when_nothing_matched
    with_fake_env(stderr: "", exit: 1) do
      assert Gem::CredentialStore::LinuxBackend.delete_all("rubygems")
    end
  end

  def test_delete_all_returns_false_on_other_failure
    with_fake_env(stderr: "unexpected D-Bus error", exit: 1) do
      refute Gem::CredentialStore::LinuxBackend.delete_all("rubygems")
    end
  end

  private

  def with_fake_env(stdout: "", stderr: "", exit: 0, remaining: nil)
    overrides = ENV.to_h.merge(
      "PATH" => [@fake_bin_dir, ENV["PATH"]].join(File::PATH_SEPARATOR),
      "RUBYGEMS_FAKE_CMD_STDOUT" => stdout,
      "RUBYGEMS_FAKE_CMD_STDERR" => stderr,
      "RUBYGEMS_FAKE_CMD_EXIT" => exit.to_s,
      "RUBYGEMS_FAKE_CMD_REMAINING" => remaining,
      "RUBYGEMS_FAKE_CMD_RECORD" => @record_path
    )
    with_env(overrides) { yield }
  end

  # The first call, so a delete still reports the clear it issued rather than
  # the search that confirms the clear took effect.
  def read_record
    JSON.parse(File.read(@record_path)).first
  end
end
