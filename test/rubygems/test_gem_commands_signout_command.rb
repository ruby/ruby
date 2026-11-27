# frozen_string_literal: true

require_relative "helper"
require "rubygems/commands/signout_command"
require "rubygems/credential_store"
require "rubygems/installer"

class TestGemCommandsSignoutCommand < Gem::TestCase
  def setup
    super
    @cmd = Gem::Commands::SignoutCommand.new
  end

  def test_execute_when_user_is_signed_in
    FileUtils.mkdir_p File.dirname(Gem.configuration.credentials_path)
    FileUtils.touch Gem.configuration.credentials_path

    @sign_out_ui = Gem::MockGemUi.new
    use_ui(@sign_out_ui) { @cmd.execute }

    assert_match(/You have successfully signed out/, @sign_out_ui.output)
    assert_equal false, File.exist?(Gem.configuration.credentials_path)
  end

  def test_execute_keeps_the_original_wording_without_the_credential_store
    # Anyone who never turned the store on should read what they always read,
    # since scripts match on this line.
    FileUtils.mkdir_p File.dirname(Gem.configuration.credentials_path)
    FileUtils.touch Gem.configuration.credentials_path

    @sign_out_ui = Gem::MockGemUi.new
    use_ui(@sign_out_ui) { @cmd.execute }

    assert_match(/You have successfully signed out from all sessions\./, @sign_out_ui.output)
    refute_match(/every registry/, @sign_out_ui.output)
  end

  def test_execute_refuses_to_delete_a_read_only_credentials_file
    pend "chmod not supported" if Gem.win_platform?
    pend "running as root bypasses the write permission check" if Process.uid.zero?

    FileUtils.mkdir_p File.dirname(Gem.configuration.credentials_path)
    FileUtils.touch Gem.configuration.credentials_path
    File.chmod 0o400, Gem.configuration.credentials_path

    @sign_out_ui = Gem::MockGemUi.new
    assert_raise Gem::MockGemUi::TermError do
      use_ui(@sign_out_ui) { @cmd.execute }
    end

    assert File.exist?(Gem.configuration.credentials_path)
    assert_match(/Could not remove the credentials/, @sign_out_ui.error)
    refute_match(/successfully signed out/, @sign_out_ui.output)
  ensure
    if File.exist?(Gem.configuration.credentials_path)
      File.chmod 0o600, Gem.configuration.credentials_path
    end
  end

  def test_execute_when_not_signed_in # i.e. no credential file created
    @sign_out_ui = Gem::MockGemUi.new
    use_ui(@sign_out_ui) { @cmd.execute }

    assert_match(/You are not currently signed in/, @sign_out_ui.error)
  end

  def test_execute_signs_out_of_every_registry_via_credential_store # no credentials file
    Gem.configuration.credential_store = true

    with_fake_credential_store do |store|
      store.set(Gem::ConfigFile::CREDENTIAL_STORE_DEFAULT_ACCOUNT, "rubygems-key")
      store.set("https://other.example", "other-key")

      @sign_out_ui = Gem::MockGemUi.new
      use_ui(@sign_out_ui) { @cmd.execute }

      assert_match(/signed out of every registry, including RubyGems\.org/, @sign_out_ui.output)
      assert_nil store.get(Gem::ConfigFile::CREDENTIAL_STORE_DEFAULT_ACCOUNT)
      assert_nil store.get("https://other.example")
    end
  ensure
    Gem.configuration.credential_store = false
  end

  def test_execute_clears_the_credential_store_even_when_the_file_is_unremovable
    pend "chmod not supported" if Gem.win_platform?
    pend "running as root bypasses the write permission check" if Process.uid.zero?

    Gem.configuration.credential_store = true

    FileUtils.mkdir_p File.dirname(Gem.configuration.credentials_path)
    FileUtils.touch Gem.configuration.credentials_path
    File.chmod 0o400, Gem.configuration.credentials_path

    with_fake_credential_store do |store|
      store.set(Gem::ConfigFile::CREDENTIAL_STORE_DEFAULT_ACCOUNT, "rubygems-key")

      # An unremovable credentials file is a separate problem; it must not
      # keep the stored keys alive.
      @sign_out_ui = Gem::MockGemUi.new
      assert_raise Gem::MockGemUi::TermError do
        use_ui(@sign_out_ui) { @cmd.execute }
      end

      assert_nil store.get(Gem::ConfigFile::CREDENTIAL_STORE_DEFAULT_ACCOUNT)
      assert File.exist?(Gem.configuration.credentials_path)
      assert_match(/Could not remove the credentials from '/, @sign_out_ui.error)
      refute_match(/credential store/, @sign_out_ui.error)
    end
  ensure
    Gem.configuration.credential_store = false
    if File.exist?(Gem.configuration.credentials_path)
      File.chmod 0o600, Gem.configuration.credentials_path
    end
  end

  def test_execute_reports_a_credential_store_that_could_not_be_cleared
    Gem.configuration.credential_store = true

    # A usable backend that refuses to clear. A missing backend is a
    # different case: it never held anything, so there is nothing to fail at.
    refusing = Class.new(Gem::FakeCredentialBackend) do
      def delete_all(_service)
        false
      end
    end.new
    Gem::CredentialStore.instance = Gem::CredentialStore.new(backend: refusing)

    @sign_out_ui = Gem::MockGemUi.new
    assert_raise Gem::MockGemUi::TermError do
      use_ui(@sign_out_ui) { @cmd.execute }
    end

    assert_match(/Could not remove the credentials from the credential store/, @sign_out_ui.error)
    refute_match(/successfully signed out/, @sign_out_ui.output)
  ensure
    Gem::CredentialStore.reset!
    Gem.configuration.credential_store = false
  end

  def test_execute_succeeds_when_the_platform_has_no_credential_store
    Gem.configuration.credential_store = true

    FileUtils.mkdir_p File.dirname(Gem.configuration.credentials_path)
    FileUtils.touch Gem.configuration.credentials_path

    # No native backend on this platform. Nothing was ever stored, so signout
    # must not report a removal failure.
    Gem::CredentialStore.instance = Gem::CredentialStore.new(backend: nil)

    @sign_out_ui = Gem::MockGemUi.new
    use_ui(@sign_out_ui) { @cmd.execute }

    assert_match(/successfully signed out/, @sign_out_ui.output)
  ensure
    Gem::CredentialStore.reset!
    Gem.configuration.credential_store = false
  end
end
