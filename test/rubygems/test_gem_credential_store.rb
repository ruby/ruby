# frozen_string_literal: true

require_relative "helper"
require "rubygems/credential_store"

class TestGemCredentialStore < Gem::TestCase
  class FakeBackend
    attr_reader :calls

    def initialize
      @calls = []
      @data = {}
      @get_calls = 0
    end

    def get(service, account)
      @calls << [:get, service, account]
      @get_calls += 1
      @data[[service, account]]
    end

    def set(service, account, secret)
      @calls << [:set, service, account, secret]
      @data[[service, account]] = secret
      true
    end

    def delete(service, account)
      @calls << [:delete, service, account]
      @data.delete([service, account])
      true
    end

    def delete_all(service)
      @calls << [:delete_all, service]
      @data.reject! {|(entry_service, _account), _secret| entry_service == service }
      true
    end

    def get_call_count
      @get_calls
    end
  end

  # Fails until #raising is turned off, so a test can show the store noticing
  # that a backend started answering again.
  class SometimesRaisingBackend < Gem::FakeCredentialBackend
    attr_accessor :raising

    def initialize
      super
      @raising = true
    end

    def get(service, account)
      raise Errno::ENOENT, "security" if @raising

      super
    end
  end

  class RaisingBackend
    def get(_service, _account)
      raise Errno::ENOENT, "security"
    end

    def set(_service, _account, _secret)
      raise Errno::ENOENT, "security"
    end

    def delete(_service, _account)
      raise Errno::ENOENT, "security"
    end

    def delete_all(_service)
      raise Errno::ENOENT, "security"
    end
  end

  def setup
    super
    Gem::CredentialStore.reset!
  end

  def teardown
    Gem::CredentialStore.reset!
    super
  end

  def test_available_without_backend
    store = Gem::CredentialStore.new(backend: nil)
    refute store.available?
  end

  def test_available_with_backend
    store = Gem::CredentialStore.new(backend: FakeBackend.new)
    assert store.available?
  end

  def test_get_set_delete_roundtrip
    store = Gem::CredentialStore.new(backend: FakeBackend.new)

    assert_nil store.get("example.org")
    assert store.set("example.org", "s3cr3t")
    assert_equal "s3cr3t", store.get("example.org")
    assert store.delete("example.org")
  end

  def test_set_uses_service_name
    backend = FakeBackend.new
    store = Gem::CredentialStore.new(backend: backend)

    store.set("example.org", "s3cr3t")

    assert_includes backend.calls, [:set, Gem::CredentialStore::SERVICE_NAME, "example.org", "s3cr3t"]
  end

  def test_get_is_memoized_per_account
    backend = FakeBackend.new
    backend.set(Gem::CredentialStore::SERVICE_NAME, "example.org", "s3cr3t")
    store = Gem::CredentialStore.new(backend: backend)

    3.times { store.get("example.org") }

    assert_equal 1, backend.get_call_count
  end

  def test_set_updates_cache_without_extra_get
    backend = FakeBackend.new
    store = Gem::CredentialStore.new(backend: backend)

    store.set("example.org", "s3cr3t")
    assert_equal "s3cr3t", store.get("example.org")

    assert_equal 0, backend.get_call_count
  end

  def test_delete_clears_cache
    backend = FakeBackend.new
    backend.set(Gem::CredentialStore::SERVICE_NAME, "example.org", "s3cr3t")
    store = Gem::CredentialStore.new(backend: backend)
    store.get("example.org")

    store.delete("example.org")
    store.get("example.org")

    assert_equal 2, backend.get_call_count
  end

  def test_operations_without_backend_are_safe_noops
    store = Gem::CredentialStore.new(backend: nil)

    assert_nil store.get("example.org")
    refute store.set("example.org", "s3cr3t")
    refute store.delete("example.org")
  end

  def test_get_swallows_backend_errors_and_returns_nil
    store = Gem::CredentialStore.new(backend: RaisingBackend.new)

    assert_nil store.get("example.org")
  end

  def test_set_refuses_a_value_no_backend_can_round_trip
    # The macOS keychain returns non-printable bytes as hex through the only
    # read-back its CLI offers, so the rule applies to every backend and the
    # caller falls back to the file rather than storing something unreadable.
    backend = FakeBackend.new
    store = Gem::CredentialStore.new(backend: backend)

    use_ui(@ui) do
      assert_equal false, store.set("example.org", "p\u00e9\u3042")
      assert_equal false, store.set("example.org", "line1\nline2")
      assert_equal false, store.set("acct\nadd-generic-password", "secret")
    end

    assert_nil backend.get("rubygems", "example.org")
    assert_match(/Credential store write failed/, @ui.errs.string)
  end

  def test_set_swallows_backend_errors_and_returns_false
    store = Gem::CredentialStore.new(backend: RaisingBackend.new)

    refute store.set("example.org", "s3cr3t")
  end

  def test_delete_swallows_backend_errors_and_returns_false
    store = Gem::CredentialStore.new(backend: RaisingBackend.new)

    refute store.delete("example.org")
  end

  def test_read_failed_distinguishes_an_unreadable_account_from_an_absent_one
    store = Gem::CredentialStore.new(backend: Gem::FakeCredentialBackend.new)

    use_ui(@ui) { assert_nil store.get("absent.example") }
    refute store.read_failed?("absent.example")

    failing = Gem::CredentialStore.new(backend: RaisingBackend.new)
    use_ui(@ui) { assert_nil failing.get("unreadable.example") }

    assert failing.read_failed?("unreadable.example")
  end

  def test_a_successful_write_clears_the_read_failure
    backend = SometimesRaisingBackend.new
    store = Gem::CredentialStore.new(backend: backend)

    use_ui(@ui) { store.get("example.org") }
    assert store.read_failed?("example.org")

    backend.raising = false
    store.set("example.org", "s3cr3t")

    refute store.read_failed?("example.org")
  end

  def test_repeated_failures_of_one_operation_warn_only_once
    store = Gem::CredentialStore.new(backend: RaisingBackend.new)

    use_ui(@ui) do
      store.get("a")
      store.get("b")
    end

    assert_equal 1, @ui.errs.string.scan(/WARNING:/).length
  end

  def test_each_operation_reports_its_own_outcome
    store = Gem::CredentialStore.new(backend: RaisingBackend.new)

    use_ui(@ui) do
      store.get("a")
      store.set("c", "x")
    end

    # A failed write lands in the config file, a failed read does not come
    # back with anything, so one warning cannot stand for both.
    assert_match(/read failed .* any copy left in the config file/, @ui.errs.string)
    assert_match(/write failed .* falling back to file storage/, @ui.errs.string)
  end

  def test_list_returns_nil_when_the_backend_cannot_enumerate
    backend = Class.new(Gem::FakeCredentialBackend) { undef_method :list }.new
    store = Gem::CredentialStore.new(backend: backend)
    store.set("example.org", "s3cr3t")

    # nil means "unknown", which callers must not confuse with "empty".
    assert_nil store.list
  end

  def test_list_returns_the_accounts_when_the_backend_can_enumerate
    store = Gem::CredentialStore.new(backend: Gem::FakeCredentialBackend.new)
    store.set("example.org", "s3cr3t")
    store.set("other.example", "other")

    assert_equal ["example.org", "other.example"], store.list
  end

  def test_warn_handler_receives_the_message_instead_of_gem_ui
    received = []
    Gem::CredentialStore.warn_handler = ->(message) { received << message }

    use_ui(@ui) do
      Gem::CredentialStore.warn_once "routed elsewhere"
    end

    assert_equal ["routed elsewhere"], received
    refute_match(/routed elsewhere/, @ui.errs.string)
  end

  def test_different_warnings_are_each_emitted
    use_ui(@ui) do
      Gem::CredentialStore.warn_once "first problem"
      Gem::CredentialStore.warn_once "first problem"
      # A warning about one problem must not suppress a different one, or a
      # plain text fallback would go unreported after any earlier warning.
      Gem::CredentialStore.warn_once "second problem"
    end

    assert_equal 2, @ui.errs.string.scan(/WARNING:/).length
  end

  def test_instance_returns_the_same_object
    assert_same Gem::CredentialStore.instance, Gem::CredentialStore.instance
  end

  def test_delete_all_clears_the_service
    backend = FakeBackend.new
    backend.set(Gem::CredentialStore::SERVICE_NAME, "acct", "s")
    store = Gem::CredentialStore.new(backend: backend)

    assert store.delete_all
    assert_nil backend.get(Gem::CredentialStore::SERVICE_NAME, "acct")
  end

  def test_delete_all_without_backend_is_safe
    store = Gem::CredentialStore.new(backend: nil)
    refute store.delete_all
  end

  def test_delete_all_swallows_backend_errors
    store = Gem::CredentialStore.new(backend: RaisingBackend.new)
    refute store.delete_all
  end

  def test_delete_all_only_removes_its_own_service
    backend = FakeBackend.new
    Gem::CredentialStore.backend = backend
    gem_store = Gem::CredentialStore.for(true, service: "rubygems")
    bundler_store = Gem::CredentialStore.for(true, service: "bundler")
    gem_store.set("acct", "gem-key")
    bundler_store.set("gems.example.com", "user:pass")

    gem_store.delete_all

    assert_nil gem_store.get("acct")
    assert_equal "user:pass", bundler_store.get("gems.example.com")
  end

  def test_for_returns_nil_when_disabled
    assert_nil Gem::CredentialStore.for(false)
    assert_nil Gem::CredentialStore.for(nil)
  end

  def test_for_memoizes_per_spec
    Gem::CredentialStore.register_backend("faux", FakeBackend.new)

    assert_same Gem::CredentialStore.for("faux"), Gem::CredentialStore.for("faux")
  end

  def test_register_and_resolve_backend_roundtrip
    backend = FakeBackend.new
    Gem::CredentialStore.register_backend("faux", backend)

    assert_same backend, Gem::CredentialStore.resolve_backend("faux")

    store = Gem::CredentialStore.for("faux")
    assert store.set("example.org", "s3cr3t")
    assert_equal "s3cr3t", store.get("example.org")
    assert_includes backend.calls, [:set, Gem::CredentialStore::SERVICE_NAME, "example.org", "s3cr3t"]
  end

  def test_resolve_backend_rejects_invalid_name
    use_ui(@ui) do
      assert_nil Gem::CredentialStore.resolve_backend("../evil")
      assert_nil Gem::CredentialStore.resolve_backend("Foo Bar")
    end

    assert_match(/invalid credential store backend name/, @ui.errs.string)
  end

  def test_resolve_backend_rejects_an_undecodable_name_without_raising
    # The setting can carry any bytes the environment hands over, and every
    # public method on this class promises to warn rather than raise.
    use_ui(@ui) do
      assert_nil Gem::CredentialStore.resolve_backend("\xff".dup.force_encoding("UTF-8"))
    end

    assert_match(/invalid credential store backend name/, @ui.errs.string)
  end

  def test_resolve_backend_requires_convention_path_and_registers
    backends_dir = File.join(@tempdir, "rubygems", "credential_store", "backends")
    FileUtils.mkdir_p(backends_dir)
    File.write(File.join(backends_dir, "faux_ext.rb"), <<~RUBY)
      Gem::CredentialStore.register_backend("faux_ext", Object.new)
    RUBY

    $LOAD_PATH.unshift(@tempdir)

    refute_nil Gem::CredentialStore.resolve_backend("faux_ext")
  ensure
    $LOAD_PATH.delete(@tempdir)
  end

  def test_resolve_backend_unknown_name_returns_nil_and_warns
    use_ui(@ui) do
      assert_nil Gem::CredentialStore.resolve_backend("definitely_not_installed_xyz")
    end

    assert_match(/is not installed/, @ui.errs.string)
  end

  def test_instance_override_wins_for_any_enabled_spec
    fake = Gem::CredentialStore.new(backend: FakeBackend.new)
    Gem::CredentialStore.instance = fake

    assert_same fake, Gem::CredentialStore.for(true)
    assert_same fake, Gem::CredentialStore.for("1password")
  end
end
