# frozen_string_literal: true
require "spec_helper"
require "bundler/settings"

RSpec.describe Bundler::Settings do
  subject(:settings) { described_class.new(bundled_app) }

  describe "#set_local" do
    context "when the local config file is not found" do
      subject(:settings) { described_class.new(nil) }

      it "raises a GemfileNotFound error with explanation" do
        expect { subject.set_local("foo", "bar") }.
          to raise_error(Bundler::GemfileNotFound, "Could not locate Gemfile")
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
--asdf --fdsa --ty=oh man i hope this doesnt break bundler because
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
        settings[key] = value
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
      context "when $TMPDIR is not writable" do
        it "does not raise" do
          expect(Bundler.rubygems).to receive(:user_home).twice.and_return(nil)
          expect(FileUtils).to receive(:mkpath).twice.with(File.join(Dir.tmpdir, "bundler", "home")).and_raise(Errno::EROFS, "Read-only file system @ dir_s_mkdir - /tmp/bundler")

          expect(subject.send(:global_config_file)).to be_nil
        end
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
        settings[:frozen] = "true"
        expect(settings[:frozen]).to be true
      end
      context "when specific gem is configured" do
        it "returns a boolean" do
          settings["ignore_messages.foobar"] = "true"
          expect(settings["ignore_messages.foobar"]).to be true
        end
      end
    end

    context "when is number" do
      it "returns a number" do
        settings[:ssl_verify_mode] = "1"
        expect(settings[:ssl_verify_mode]).to be 1
      end
    end

    context "when it's not possible to write to the file" do
      it "raises an PermissionError with explanation" do
        expect(FileUtils).to receive(:mkdir_p).with(settings.send(:local_config_file).dirname).
          and_raise(Errno::EACCES)
        expect { settings[:frozen] = "1" }.
          to raise_error(Bundler::PermissionError, /config/)
      end
    end
  end

  describe "#temporary" do
    it "reset after used" do
      Bundler.settings[:no_install] = true

      Bundler.settings.temporary(:no_install => false) do
        expect(Bundler.settings[:no_install]).to eq false
      end

      expect(Bundler.settings[:no_install]).to eq true
    end
  end

  describe "#set_global" do
    context "when it's not possible to write to the file" do
      it "raises an PermissionError with explanation" do
        expect(FileUtils).to receive(:mkdir_p).with(settings.send(:global_config_file).dirname).
          and_raise(Errno::EACCES)
        expect { settings.set_global(:frozen, "1") }.
          to raise_error(Bundler::PermissionError, %r{\.bundle/config})
      end
    end
  end

  describe "#pretty_values_for" do
    it "prints the converted value rather than the raw string" do
      bool_key = described_class::BOOL_KEYS.first
      settings[bool_key] = false
      expect(subject.pretty_values_for(bool_key)).to eq [
        "Set for your local app (#{bundled_app("config")}): false",
      ]
    end
  end

  describe "#mirror_for" do
    let(:uri) { URI("https://rubygems.org/") }

    context "with no configured mirror" do
      it "returns the original URI" do
        expect(settings.mirror_for(uri)).to eq(uri)
      end

      it "converts a string parameter to a URI" do
        expect(settings.mirror_for("https://rubygems.org/")).to eq(uri)
      end
    end

    context "with a configured mirror" do
      let(:mirror_uri) { URI("https://rubygems-mirror.org/") }

      before { settings["mirror.https://rubygems.org/"] = mirror_uri.to_s }

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
    end
  end

  describe "#credentials_for" do
    let(:uri) { URI("https://gemserver.example.org/") }
    let(:credentials) { "username:password" }

    context "with no configured credentials" do
      it "returns nil" do
        expect(settings.credentials_for(uri)).to be_nil
      end
    end

    context "with credentials configured by URL" do
      before { settings["https://gemserver.example.org/"] = credentials }

      it "returns the configured credentials" do
        expect(settings.credentials_for(uri)).to eq(credentials)
      end
    end

    context "with credentials configured by hostname" do
      before { settings["gemserver.example.org"] = credentials }

      it "returns the configured credentials" do
        expect(settings.credentials_for(uri)).to eq(credentials)
      end
    end
  end

  describe "URI normalization" do
    it "normalizes HTTP URIs in credentials configuration" do
      settings["http://gemserver.example.org"] = "username:password"
      expect(settings.all).to include("http://gemserver.example.org/")
    end

    it "normalizes HTTPS URIs in credentials configuration" do
      settings["https://gemserver.example.org"] = "username:password"
      expect(settings.all).to include("https://gemserver.example.org/")
    end

    it "normalizes HTTP URIs in mirror configuration" do
      settings["mirror.http://rubygems.org"] = "http://rubygems-mirror.org"
      expect(settings.all).to include("mirror.http://rubygems.org/")
    end

    it "normalizes HTTPS URIs in mirror configuration" do
      settings["mirror.https://rubygems.org"] = "http://rubygems-mirror.org"
      expect(settings.all).to include("mirror.https://rubygems.org/")
    end

    it "does not normalize other config keys that happen to contain 'http'" do
      settings["local.httparty"] = home("httparty")
      expect(settings.all).to include("local.httparty")
    end

    it "does not normalize other config keys that happen to contain 'https'" do
      settings["local.httpsmarty"] = home("httpsmarty")
      expect(settings.all).to include("local.httpsmarty")
    end

    it "reads older keys without trailing slashes" do
      settings["mirror.https://rubygems.org"] = "http://rubygems-mirror.org"
      expect(settings.mirror_for("https://rubygems.org/")).to eq(
        URI("http://rubygems-mirror.org/")
      )
    end
  end

  describe "BUNDLE_ keys format" do
    let(:settings) { described_class.new(bundled_app(".bundle")) }

    it "converts older keys without double dashes" do
      config("BUNDLE_MY__PERSONAL.RACK" => "~/Work/git/rack")
      expect(settings["my.personal.rack"]).to eq("~/Work/git/rack")
    end

    it "converts older keys without trailing slashes and double dashes" do
      config("BUNDLE_MIRROR__HTTPS://RUBYGEMS.ORG" => "http://rubygems-mirror.org")
      expect(settings["mirror.https://rubygems.org/"]).to eq("http://rubygems-mirror.org")
    end

    it "reads newer keys format properly" do
      config("BUNDLE_MIRROR__HTTPS://RUBYGEMS__ORG/" => "http://rubygems-mirror.org")
      expect(settings["mirror.https://rubygems.org/"]).to eq("http://rubygems-mirror.org")
    end
  end
end
