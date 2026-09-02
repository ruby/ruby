# frozen_string_literal: true

require "bundler/settings"
require "rubygems/credential_store"
require_relative "../support/fake_credential_backend"

RSpec.describe Bundler::Settings do
  subject(:settings) { described_class.new(bundled_app) }

  describe "#set_local" do
    context "root is nil" do
      subject(:settings) { described_class.new(nil) }

      before do
        allow(Pathname).to receive(:new).and_call_original
        allow(Pathname).to receive(:new).with(".bundle").and_return home(".bundle")
      end

      it "works" do
        subject.set_local("foo", "bar")

        expect(subject["foo"]).to eq("bar")
      end
    end
  end

  describe "load_config" do
    let(:hash) do
      {
        "build.thrift" => "--with-cppflags=-D_FORTIFY_SOURCE=0",
        "build.libv8" => "--with-system-v8",
        "build.therubyracer" => "--with-v8-dir",
        "build.pg" => "--with-pg-config=/usr/local/Cellar/postgresql92/9.2.8_1/bin/pg_config",
        "gem.coc" => "false",
        "gem.mit" => "false",
        "gem.test" => "minitest",
        "thingy" => <<-EOS.tr("\n", " "),
--asdf --fdsa --ty=oh man i hope this doesn't break bundler because
that would suck --ehhh=oh geez it looks like i might have broken bundler somehow
--very-important-option=DontDeleteRoo
--very-important-option=DontDeleteRoo
--very-important-option=DontDeleteRoo
--very-important-option=DontDeleteRoo
        EOS
        "xyz" => "zyx",
      }
    end

    before do
      hash.each do |key, value|
        settings.set_local key, value
      end
    end

    it "can load the config" do
      loaded = settings.send(:load_config, bundled_app("config"))
      expected = Hash[hash.map do |k, v|
        [settings.send(:key_for, k), v.to_s]
      end]
      expect(loaded).to eq(expected)
    end

    context "when BUNDLE_IGNORE_CONFIG is set" do
      before { ENV["BUNDLE_IGNORE_CONFIG"] = "TRUE" }

      it "ignores the config" do
        loaded = settings.send(:load_config, bundled_app("config"))
        expect(loaded).to eq({})
      end
    end
  end

  describe "#global_config_file" do
    context "when $HOME is not accessible" do
      it "does not raise" do
        expect(Bundler.rubygems).to receive(:user_home).twice.and_return(nil)

        expect(subject.send(:global_config_file)).to be_nil
      end
    end
  end

  describe "#[]" do
    context "when the local config file is not found" do
      subject(:settings) { described_class.new }

      it "does not raise" do
        expect do
          subject["foo"]
        end.not_to raise_error
      end
    end

    context "when not set" do
      context "when default value present" do
        it "retrieves value" do
          expect(settings[:retry]).to be 3
        end
      end

      it "returns nil" do
        expect(settings[:buttermilk]).to be nil
      end
    end

    context "when is boolean" do
      it "returns a boolean" do
        settings.set_local :frozen, "true"
        expect(settings[:frozen]).to be true
      end
      context "when specific gem is configured" do
        it "returns a boolean" do
          settings.set_local "ignore_messages.foobar", "true"
          expect(settings["ignore_messages.foobar"]).to be true
        end
      end
    end

    context "when is number" do
      it "returns a number" do
        settings.set_local :ssl_verify_mode, "1"
        expect(settings[:ssl_verify_mode]).to be 1
      end

      it "coerces cooldown to integer" do
        settings.set_local :cooldown, "7"
        expect(settings[:cooldown]).to be 7
      end

      it "coerces an unparsable cooldown to 0 without warning here" do
        # The warning lives in CLI::Common so it fires once per command,
        # outside any Bundler.ui.silence block. See cli_common_spec.rb.
        expect(Bundler.ui).not_to receive(:warn)
        settings.set_local :cooldown, "abc"
        expect(settings[:cooldown]).to be 0
      end
    end

    context "when the setting has been renamed" do
      it "reads the value set under the old name" do
        settings.set_local :no_prune, "true"

        expect(settings[:keep_outdated_cache]).to be true
      end

      it "prefers the current name set at the same level" do
        settings.set_local :no_prune, "true"
        settings.set_local :keep_outdated_cache, "false"

        expect(settings[:keep_outdated_cache]).to be false
      end

      it "prefers the old name set at a higher priority level" do
        settings.set_global :keep_outdated_cache, "false"
        settings.set_local :no_prune, "true"

        expect(settings[:keep_outdated_cache]).to be true
      end
    end

    context "when it's not possible to create the settings directory" do
      it "raises an PermissionError with explanation" do
        settings_dir = settings.send(:local_config_file).dirname
        expect(::Bundler::FileUtils).to receive(:mkdir_p).with(settings_dir).
          and_raise(Errno::EACCES.new(settings_dir.to_s))
        expect { settings.set_local :frozen, "1" }.
          to raise_error(Bundler::PermissionError, /#{settings_dir}/)
      end
    end
  end

  describe "#temporary" do
    it "reset after used" do
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)

      Bundler.settings.set_command_option :no_install, true

      Bundler.settings.temporary(no_install: false) do
        expect(Bundler.settings[:no_install]).to eq false
      end

      expect(Bundler.settings[:no_install]).to eq true

      Bundler.settings.set_command_option :no_install, nil
    end

    it "returns the return value of the block" do
      ret = Bundler.settings.temporary({}) { :ret }
      expect(ret).to eq :ret
    end

    context "when called without a block" do
      it "leaves the setting changed" do
        Bundler.settings.temporary(foo: :random)
        expect(Bundler.settings[:foo]).to eq "random"
      end

      it "returns nil" do
        expect(Bundler.settings.temporary(foo: :bar)).to be_nil
      end
    end
  end

  describe "#set_global" do
    context "when it's not possible to write to create the settings directory" do
      it "raises an PermissionError with explanation" do
        settings_dir = settings.send(:global_config_file).dirname
        expect(::Bundler::FileUtils).to receive(:mkdir_p).with(settings_dir).
          and_raise(Errno::EACCES.new(settings_dir.to_s))
        expect { settings.set_global(:frozen, "1") }.
          to raise_error(Bundler::PermissionError, /#{settings_dir}/)
      end
    end
  end

  describe "#pretty_values_for" do
    it "prints the converted value rather than the raw string" do
      bool_key = described_class::BOOL_KEYS.first
      settings.set_local(bool_key, "false")
      expect(subject.pretty_values_for(bool_key)).to eq [
        "Set for your local app (#{bundled_app("config")}): false",
      ]
    end
  end

  describe "#mirror_for" do
    let(:uri) { Gem::URI("https://rubygems.org/") }

    context "with no configured mirror" do
      it "returns the original URI" do
        expect(settings.mirror_for(uri)).to eq(uri)
      end

      it "converts a string parameter to a URI" do
        expect(settings.mirror_for("https://rubygems.org/")).to eq(uri)
      end
    end

    context "with a configured mirror" do
      let(:mirror_uri) { Gem::URI("https://example-mirror.rubygems.org/") }

      before { settings.set_local "mirror.https://rubygems.org/", mirror_uri.to_s }

      it "returns the mirror URI" do
        expect(settings.mirror_for(uri)).to eq(mirror_uri)
      end

      it "converts a string parameter to a URI" do
        expect(settings.mirror_for("https://rubygems.org/")).to eq(mirror_uri)
      end

      it "normalizes the URI" do
        expect(settings.mirror_for("https://rubygems.org")).to eq(mirror_uri)
      end

      it "is case insensitive" do
        expect(settings.mirror_for("HTTPS://RUBYGEMS.ORG/")).to eq(mirror_uri)
      end

      context "with a file URI" do
        let(:mirror_uri) { Gem::URI("file:/foo/BAR/baz/qUx/") }

        it "returns the mirror URI" do
          expect(settings.mirror_for(uri)).to eq(mirror_uri)
        end

        it "converts a string parameter to a URI" do
          expect(settings.mirror_for("file:/foo/BAR/baz/qUx/")).to eq(mirror_uri)
        end

        it "normalizes the URI" do
          expect(settings.mirror_for("file:/foo/BAR/baz/qUx")).to eq(mirror_uri)
        end
      end
    end
  end

  describe "#credential_store_spec" do
    it "is off when the setting is unset" do
      expect(settings.send(:credential_store_spec)).to be_nil
    end

    it "reads the same false spellings as every other Bundler boolean" do
      ["", "false", "FALSE", "f", "no", "n", "0"].each do |off|
        settings.set_local "credential_store", off

        expect(settings.send(:credential_store_spec)).to be_nil, "#{off.inspect} should turn the store off"
      end
    end

    it "reads the boolean true spellings as this platform's native store" do
      %w[true TRUE t yes y on 1].each do |on|
        settings.set_local "credential_store", on

        expect(settings.send(:credential_store_spec)).to be(true), "#{on.inspect} should select the native store"
      end
    end

    it "reads anything else as a backend name, `off` included" do
      %w[1password off 1Password].each do |name|
        settings.set_local "credential_store", name

        expect(settings.send(:credential_store_spec)).to eq(name)
      end
    end

    it "lets a host override the global setting" do
      settings.set_local "credential_store", "1password"
      settings.set_local "credential_store.gemserver.example.org", "false"

      expect(settings.send(:credential_store_spec, "gemserver.example.org")).to be_nil
      expect(settings.send(:credential_store_spec, "other.example.org")).to eq("1password")
    end

    it "survives an undecodable environment variable" do
      # #to_bool refuses these bytes too, not just String#downcase.
      without_env_side_effects do
        ENV["BUNDLE_CREDENTIAL_STORE"] = "\xff".dup.force_encoding("UTF-8")

        expect(settings.send(:credential_store_spec)).to eq(ENV["BUNDLE_CREDENTIAL_STORE"])
      end
    end
  end

  describe "#credentials_for" do
    let(:uri) { Gem::URI("https://gemserver.example.org/") }
    let(:credentials) { "username:password" }

    context "with no configured credentials" do
      it "returns nil" do
        expect(settings.credentials_for(uri)).to be_nil
      end
    end

    context "with credentials configured by URL" do
      before { settings.set_local "https://gemserver.example.org/", credentials }

      it "returns the configured credentials" do
        expect(settings.credentials_for(uri)).to eq(credentials)
      end
    end

    context "with credentials configured by hostname" do
      before { settings.set_local "gemserver.example.org", credentials }

      it "returns the configured credentials" do
        expect(settings.credentials_for(uri)).to eq(credentials)
      end
    end

    context "with credential_store enabled" do
      let(:fake_store) { Gem::CredentialStore.new(backend: FakeCredentialBackend.new) }

      before do
        settings.set_local "credential_store", "true"
        Gem::CredentialStore.instance = fake_store
      end

      after { Gem::CredentialStore.reset! }

      it "returns nil when nothing is configured anywhere" do
        expect(settings.credentials_for(uri)).to be_nil
      end

      it "round-trips credentials set under the full URL" do
        settings.set_local "https://gemserver.example.org/", credentials

        expect(settings.credentials_for(uri)).to eq(credentials)
      end

      it "round-trips credentials set under the hostname" do
        settings.set_local "gemserver.example.org", credentials

        expect(settings.credentials_for(uri)).to eq(credentials)
      end

      it "keeps a password in the source URL out of the store account" do
        # The account reaches the backend as a command argument, where any
        # other user on the machine can read it.
        recorder = Class.new(FakeCredentialBackend) do
          def accounts_seen
            @accounts_seen ||= []
          end

          def get(service, account)
            accounts_seen << account
            super
          end
        end.new
        Gem::CredentialStore.instance = Gem::CredentialStore.new(backend: recorder)
        settings.set_local "gemserver.example.org", credentials

        with_auth = Gem::URI("https://someone:s3cr3t@gemserver.example.org")

        expect(settings.credentials_for(with_auth)).to eq(credentials)
        # key_for upcases, so compare without regard to case.
        expect(recorder.accounts_seen).not_to be_empty
        expect(recorder.accounts_seen.join.downcase).not_to include("s3cr3t")
      end

      it "matches a URL key regardless of a trailing slash, like the config file does" do
        settings.set_local "https://gemserver.example.org", credentials

        expect(settings.credentials_for(Gem::URI("https://gemserver.example.org/"))).to eq(credentials)
      end

      it "does not write the secret to the local config file" do
        settings.set_local "gemserver.example.org", credentials

        expect(settings.locations("gemserver.example.org")[:local]).to be_nil
      end

      it "prefers a credential given in the environment over the credential_store" do
        settings.set_local "gemserver.example.org", credentials

        ENV["BUNDLE_GEMSERVER__EXAMPLE__ORG"] = "ci:token"
        env_settings = Bundler::Settings.new(bundled_app)

        expect(env_settings.credentials_for(uri)).to eq("ci:token")
      end

      it "leaves the layer order alone for a host the store does not hold" do
        # Written straight to the config file so the store never holds it.
        # Resolution must then be exactly what it was before the store
        # existed, with local beating env.
        allow(settings).to receive(:active_credential_store).and_return(nil)
        settings.set_local "other.example.org", "local:pass"
        allow(settings).to receive(:active_credential_store).and_call_original

        ENV["BUNDLE_OTHER__EXAMPLE__ORG"] = "env:pass"
        env_settings = Bundler::Settings.new(bundled_app)

        expect(env_settings.credentials_for(Gem::URI("https://other.example.org/"))).to eq("local:pass")
      end

      it "falls back to the credential_store when the environment has no entry" do
        settings.set_local "gemserver.example.org", credentials

        ENV["BUNDLE_OTHER__EXAMPLE__ORG"] = "ci:token"
        env_settings = Bundler::Settings.new(bundled_app)

        expect(env_settings.credentials_for(uri)).to eq(credentials)
      end

      it "prefers the credential_store over a stale local config value" do
        # A plain-text credential left in the config file before the store
        # was enabled, simulated by routing this one write to the file.
        allow(settings).to receive(:active_credential_store).and_return(nil)
        settings.set_local "gemserver.example.org", "stale:value"
        allow(settings).to receive(:active_credential_store).and_call_original

        settings.set_local "gemserver.example.org", credentials

        expect(settings.credentials_for(uri)).to eq(credentials)
      end
    end

    context "with a named credential_store backend" do
      let(:fake_store) { Gem::CredentialStore.new(backend: FakeCredentialBackend.new) }

      before do
        settings.set_local "credential_store", "1password"
        Gem::CredentialStore.instance = fake_store
      end

      after { Gem::CredentialStore.reset! }

      it "round-trips credentials through the selected backend" do
        settings.set_local "gemserver.example.org", credentials

        expect(settings.credentials_for(uri)).to eq(credentials)
      end
    end

    context "with a per-host credential_store backend" do
      let(:host_backend) { FakeCredentialBackend.new }
      let(:global_backend) { FakeCredentialBackend.new }
      let(:service) { Bundler::Settings::CREDENTIAL_STORE_SERVICE }

      before do
        Gem::CredentialStore.register_backend("fake-host", host_backend)
        Gem::CredentialStore.register_backend("fake-global", global_backend)
        settings.set_local "credential_store", "fake-global"
        settings.set_local "credential_store.gemserver.example.org", "fake-host"
      end

      after { Gem::CredentialStore.reset! }

      it "reads the host's credentials from the backend selected for that host" do
        host_backend.set(service, Bundler::Settings.key_for("gemserver.example.org"), credentials)

        expect(settings.credentials_for(uri)).to eq(credentials)
      end

      it "does not chain to the global backend when the host's backend misses" do
        global_backend.set(service, Bundler::Settings.key_for("gemserver.example.org"), credentials)

        expect(settings.credentials_for(uri)).to be_nil
      end

      it "keeps other hosts on the globally selected backend" do
        global_backend.set(service, Bundler::Settings.key_for("other.example.org"), credentials)

        expect(settings.credentials_for(Gem::URI("https://other.example.org/"))).to eq(credentials)
      end

      it "writes a host credential to the backend selected for that host" do
        settings.set_local "gemserver.example.org", credentials

        expect(host_backend.get(service, Bundler::Settings.key_for("gemserver.example.org"))).to eq(credentials)
        expect(global_backend.get(service, Bundler::Settings.key_for("gemserver.example.org"))).to be_nil
      end

      it "writes a URL-keyed credential to the backend selected for its host" do
        settings.set_local "https://gemserver.example.org/", credentials

        expect(host_backend.get(service, Bundler::Settings.key_for("https://gemserver.example.org/"))).to eq(credentials)
      end

      it "keeps a host on the config file when its store is set to false" do
        settings.set_local "credential_store.gemserver.example.org", "false"

        settings.set_local "gemserver.example.org", credentials

        expect(settings.locations("gemserver.example.org")[:local]).to eq(credentials)
        expect(settings.credentials_for(uri)).to eq(credentials)
      end
    end

    context "with credential_store set to false" do
      before { settings.set_local "credential_store", "false" }

      it "does not consult a credential store" do
        expect(Gem::CredentialStore).not_to receive(:for)
        expect(settings.credentials_for(uri)).to be_nil
      end
    end

    context "when the paired RubyGems has no credential store" do
      before do
        settings.set_local "credential_store", "true"
        allow(settings).to receive(:require).and_call_original
        allow(settings).to receive(:require).with("rubygems/credential_store").and_raise(LoadError)
      end

      it "warns once and falls back to the config file without raising" do
        allow(Bundler.ui).to receive(:warn)

        expect { settings.set_local "gemserver.example.org", "username:password" }.not_to raise_error
        expect(settings.credentials_for(uri)).to eq("username:password")

        expect(Bundler.ui).to have_received(:warn).once
      end
    end
  end

  describe "credential storage with credential_store enabled" do
    let(:fake_store) { Gem::CredentialStore.new(backend: FakeCredentialBackend.new) }

    before do
      settings.set_local "credential_store", "true"
      Gem::CredentialStore.instance = fake_store
    end

    after { Gem::CredentialStore.reset! }

    it "writes a host credential to the credential_store instead of the local config file" do
      settings.set_local "gemserver.example.org", "username:password"

      expect(fake_store.get(Bundler::Settings.key_for("gemserver.example.org"))).to eq("username:password")
      expect(settings.locations("gemserver.example.org")[:local]).to be_nil
    end

    it "leaves the credential_store alone for temporary settings" do
      settings.set_local "gemserver.example.org", "username:password"
      stored = Bundler::Settings.key_for("gemserver.example.org")

      settings.temporary("gemserver.example.org" => "temp:value") do
        # The temporary value must not be persisted to the OS store...
        expect(fake_store.get(stored)).to eq("username:password")
      end

      # ...and restoring it must not delete the real credential either.
      expect(fake_store.get(stored)).to eq("username:password")
    end

    it "names the host and the file it fell back to when the store write fails" do
      Gem::CredentialStore.instance = Gem::CredentialStore.new(backend: nil)
      allow(Bundler.ui).to receive(:warn)

      settings.set_local "gemserver.example.org", "username:password"

      expect(Bundler.ui).to have_received(:warn).
        with(%r{credential for gemserver\.example\.org .* #{Regexp.escape(bundled_app.to_s)}/config in plain text}m)
    end

    it "warns when the credential cannot be removed from the credential_store" do
      # A usable backend that refuses to delete. A missing backend never held
      # the credential, so that case must stay silent.
      refusing = Class.new(FakeCredentialBackend) do
        def delete(_service, _account)
          false
        end
      end.new
      Gem::CredentialStore.instance = Gem::CredentialStore.new(backend: refusing)
      allow(Bundler.ui).to receive(:warn)

      settings.set_local "gemserver.example.org", nil

      expect(Bundler.ui).to have_received(:warn).with(/Could not remove the credential for gemserver\.example\.org/)
    end

    it "says the store was unreachable rather than claiming a removal" do
      # Nothing can be removed from a store that cannot be reached. Reporting
      # a clean removal would be a lie, and reporting a failure would be one
      # too, so the warning says which it is.
      Gem::CredentialStore.instance = Gem::CredentialStore.new(backend: nil)
      allow(Bundler.ui).to receive(:warn)

      settings.set_local "gemserver.example.org", nil

      expect(Bundler.ui).to have_received(:warn).with(/enabled but unavailable/)
      expect(Bundler.ui).not_to have_received(:warn).with(/Could not remove/)
    end

    it "removes the stored credential when the same host is set to a value it cannot store" do
      settings.set_local "gemserver.example.org", "username:password"
      expect(fake_store.get(Bundler::Settings.key_for("gemserver.example.org"))).to eq("username:password")

      # A bare token has no colon, so it goes to the config file. The stored
      # user:pass must not stay behind and keep winning in #credentials_for.
      settings.set_local "gemserver.example.org", "baretoken"

      expect(fake_store.get(Bundler::Settings.key_for("gemserver.example.org"))).to be_nil
      expect(settings.credentials_for(Gem::URI("https://gemserver.example.org/"))).to eq("baretoken")
    end

    it "routes credential store warnings to Bundler.ui" do
      # Bundler replaces Gem.ui with a Gem::SilentUI subclass, so a warning
      # left on Gem.ui would never reach the user during a bundle command.
      allow(Bundler.ui).to receive(:warn)
      settings.set_local "gemserver.example.org", "username:password"

      Gem::CredentialStore.warn_once "store trouble"

      expect(Bundler.ui).to have_received(:warn).with("store trouble")
    end

    it "lists stored credentials by key" do
      settings.set_local "gemserver.example.org", "username:password"

      expect(settings.all_including_stored_credentials).to include("gemserver.example.org")
    end

    it "keeps stored credentials out of the hot-path key list" do
      settings.set_local "gemserver.example.org", "username:password"

      # #all is read per gem source and per download, and its keys go into
      # the User-Agent, so the store must not be consulted there.
      expect(settings.all).not_to include("gemserver.example.org")
    end

    it "omits stored credentials when the backend cannot enumerate them" do
      # A resolver-style third-party backend has nothing to list.
      no_list = Class.new(FakeCredentialBackend) do
        undef_method :list
      end.new
      Gem::CredentialStore.instance = Gem::CredentialStore.new(backend: no_list)

      settings.set_local "gemserver.example.org", "username:password"

      expect(settings.all_including_stored_credentials).not_to include("gemserver.example.org")
      expect(settings.credential_stored?("gemserver.example.org")).to be true
    end

    it "reports a stored credential without revealing it" do
      settings.set_local "gemserver.example.org", "username:password"

      values = settings.pretty_values_for("gemserver.example.org")

      expect(values).to include(/Set in the credential store, which is used ahead of the config files/)
      expect(values.join).not_to include("password")
      expect(settings.credential_stored?("gemserver.example.org")).to be true
    end

    it "does not claim a credential is stored when it is not" do
      expect(settings.credential_stored?("gemserver.example.org")).to be false
      expect(settings.credential_stored?("jobs")).to be false
    end

    it "leaves settings that are not host names in the config file" do
      # ssl_client_cert is not on any known-settings list and a Windows path
      # contains a colon, so a default-allow rule would move it into the
      # store, and Settings#[] would then read it back as nil.
      settings.set_local "ssl_client_cert", 'C:\certs\client.pem'
      settings.set_local "user_agent", "MyCorp/1.0 (build: 123)"

      expect(settings["ssl_client_cert"]).to eq('C:\certs\client.pem')
      expect(settings["user_agent"]).to eq("MyCorp/1.0 (build: 123)")
      expect(fake_store.get(Bundler::Settings.key_for("ssl_client_cert"))).to be_nil
    end

    it "stores a credential keyed by a host with a port" do
      settings.set_local "my-registry.example.com:8080", "username:password"

      expect(fake_store.get(Bundler::Settings.key_for("my-registry.example.com:8080"))).to eq("username:password")
    end

    it "does not route non-credential-shaped values to the credential_store" do
      settings.set_local "jobs", "4"

      expect(settings["jobs"]).to eq(4)
    end

    it "does not route the gem.push_key signing key path to the credential_store" do
      settings.set_local "gem.push_key", "/path/to/key.pem"

      expect(settings["gem.push_key"]).to eq("/path/to/key.pem")
    end

    it "falls back to the local config file and warns when the credential_store write fails" do
      Gem::CredentialStore.instance = Gem::CredentialStore.new(backend: nil)
      allow(Bundler.ui).to receive(:warn)

      settings.set_local "gemserver.example.org", "username:password"

      expect(settings["gemserver.example.org"]).to eq("username:password")
      expect(Bundler.ui).to have_received(:warn).once
    end

    it "removes a stale plaintext credential from the config file once it moves to the store" do
      # written to the config file before the store took over
      allow(settings).to receive(:active_credential_store).and_return(nil)
      settings.set_local "gemserver.example.org", "old:secret"
      expect(settings.locations("gemserver.example.org")[:local]).to eq("old:secret")
      allow(settings).to receive(:active_credential_store).and_call_original

      settings.set_local "gemserver.example.org", "new:secret"

      expect(fake_store.get(Bundler::Settings.key_for("gemserver.example.org"))).to eq("new:secret")
      expect(settings.locations("gemserver.example.org")[:local]).to be_nil
    end

    it "removes a credential_store-stored credential on unset" do
      account = Bundler::Settings.key_for("gemserver.example.org")
      settings.set_local "gemserver.example.org", "username:password"
      expect(fake_store.get(account)).to eq("username:password")

      settings.set_local "gemserver.example.org", nil

      expect(fake_store.get(account)).to be_nil
    end
  end

  describe "URI normalization" do
    it "normalizes HTTP URIs in credentials configuration" do
      settings.set_local "http://gemserver.example.org", "username:password"
      expect(settings.all).to include("http://gemserver.example.org/")
    end

    it "normalizes HTTPS URIs in credentials configuration" do
      settings.set_local "https://gemserver.example.org", "username:password"
      expect(settings.all).to include("https://gemserver.example.org/")
    end

    it "normalizes HTTP URIs in mirror configuration" do
      settings.set_local "mirror.http://rubygems.org", "http://example-mirror.rubygems.org"
      expect(settings.all).to include("mirror.http://rubygems.org/")
    end

    it "normalizes HTTPS URIs in mirror configuration" do
      settings.set_local "mirror.https://rubygems.org", "http://example-mirror.rubygems.org"
      expect(settings.all).to include("mirror.https://rubygems.org/")
    end

    it "does not normalize other config keys that happen to contain 'http'" do
      settings.set_local "local.httparty", home("httparty")
      expect(settings.all).to include("local.httparty")
    end

    it "does not normalize other config keys that happen to contain 'https'" do
      settings.set_local "local.httpsmarty", home("httpsmarty")
      expect(settings.all).to include("local.httpsmarty")
    end

    it "reads older keys without trailing slashes" do
      settings.set_local "mirror.https://rubygems.org", "http://example-mirror.rubygems.org"
      expect(settings.mirror_for("https://rubygems.org/")).to eq(
        Gem::URI("http://example-mirror.rubygems.org/")
      )
    end

    it "normalizes URIs with a fallback_timeout option" do
      settings.set_local "mirror.https://rubygems.org/.fallback_timeout", "true"
      expect(settings.all).to include("mirror.https://rubygems.org/.fallback_timeout")
    end

    it "normalizes URIs with a fallback_timeout option without a trailing slash" do
      settings.set_local "mirror.https://rubygems.org.fallback_timeout", "true"
      expect(settings.all).to include("mirror.https://rubygems.org/.fallback_timeout")
    end
  end

  describe "BUNDLE_ keys format" do
    let(:settings) { described_class.new(bundled_app(".bundle")) }

    it "converts older keys without double underscore" do
      bundle_config("BUNDLE_MY__PERSONAL.MYRACK" => "~/Work/git/myrack")
      expect(settings["my.personal.myrack"]).to eq("~/Work/git/myrack")
    end

    it "converts older keys without trailing slashes and double underscore" do
      bundle_config("BUNDLE_MIRROR__HTTPS://RUBYGEMS.ORG" => "http://example-mirror.rubygems.org")
      expect(settings["mirror.https://rubygems.org/"]).to eq("http://example-mirror.rubygems.org")
    end

    it "ignores commented out keys" do
      create_file bundled_app(".bundle/config"), <<~C
        # BUNDLE_MY-PERSONAL-SERVER__ORG: my-personal-server.org
      C

      expect(Bundler.ui).not_to receive(:warn)
      expect(settings.all).to be_empty
    end

    it "converts older keys with dashes" do
      bundle_config("BUNDLE_MY-PERSONAL-SERVER__ORG" => "my-personal-server.org")
      expect(Bundler.ui).to receive(:warn).with(
        "Your #{bundled_app(".bundle/config")} config includes `BUNDLE_MY-PERSONAL-SERVER__ORG`, which contains the dash character (`-`).\n" \
        "This is deprecated, because configuration through `ENV` should be possible, but `ENV` keys cannot include dashes.\n" \
        "Please edit #{bundled_app(".bundle/config")} and replace any dashes in configuration keys with a triple underscore (`___`)."
      )
      expect(settings["my-personal-server.org"]).to eq("my-personal-server.org")
    end

    it "reads newer keys format properly" do
      bundle_config("BUNDLE_MIRROR__HTTPS://RUBYGEMS__ORG/" => "http://example-mirror.rubygems.org")
      expect(settings["mirror.https://rubygems.org/"]).to eq("http://example-mirror.rubygems.org")
    end
  end

  describe "default_cli_command validation" do
    it "accepts 'install' as a valid value" do
      expect { settings.set_local("default_cli_command", "install") }.not_to raise_error
    end

    it "accepts 'cli_help' as a valid value" do
      expect { settings.set_local("default_cli_command", "cli_help") }.not_to raise_error
    end

    it "rejects invalid values" do
      expect { settings.set_local("default_cli_command", "invalid") }.to raise_error(
        Bundler::InvalidOption,
        /Setting `default_cli_command` to "invalid" failed:\n - default_cli_command must be either 'install' or 'cli_help'\n - must be one of: install, cli_help/
      )
    end

    it "accepts nil values" do
      expect { settings.set_local("default_cli_command", nil) }.not_to raise_error
    end
  end
end
