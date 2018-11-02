# frozen_string_literal: true

require "bundler/source/rubygems/remote"

RSpec.describe Bundler::Source::Rubygems::Remote do
  def remote(uri)
    Bundler::Source::Rubygems::Remote.new(uri)
  end

  before do
    allow(Digest(:MD5)).to receive(:hexdigest).with(duck_type(:to_s)) {|string| "MD5HEX(#{string})" }
  end

  let(:uri_no_auth) { URI("https://gems.example.com") }
  let(:uri_with_auth) { URI("https://#{credentials}@gems.example.com") }
  let(:credentials) { "username:password" }

  context "when the original URI has no credentials" do
    describe "#uri" do
      it "returns the original URI" do
        expect(remote(uri_no_auth).uri).to eq(uri_no_auth)
      end

      it "applies configured credentials" do
        Bundler.settings.temporary(uri_no_auth.to_s => credentials)
        expect(remote(uri_no_auth).uri).to eq(uri_with_auth)
      end
    end

    describe "#anonymized_uri" do
      it "returns the original URI" do
        expect(remote(uri_no_auth).anonymized_uri).to eq(uri_no_auth)
      end

      it "does not apply given credentials" do
        Bundler.settings.temporary(uri_no_auth.to_s => credentials)
        expect(remote(uri_no_auth).anonymized_uri).to eq(uri_no_auth)
      end
    end

    describe "#cache_slug" do
      it "returns the correct slug" do
        expect(remote(uri_no_auth).cache_slug).to eq("gems.example.com.443.MD5HEX(gems.example.com.443./)")
      end

      it "only applies the given user" do
        Bundler.settings.temporary(uri_no_auth.to_s => credentials)
        expect(remote(uri_no_auth).cache_slug).to eq("gems.example.com.username.443.MD5HEX(gems.example.com.username.443./)")
      end
    end
  end

  context "when the original URI has a username and password" do
    describe "#uri" do
      it "returns the original URI" do
        expect(remote(uri_with_auth).uri).to eq(uri_with_auth)
      end

      it "does not apply configured credentials" do
        Bundler.settings.temporary(uri_no_auth.to_s => "other:stuff")
        expect(remote(uri_with_auth).uri).to eq(uri_with_auth)
      end
    end

    describe "#anonymized_uri" do
      it "returns the URI without username and password" do
        expect(remote(uri_with_auth).anonymized_uri).to eq(uri_no_auth)
      end

      it "does not apply given credentials" do
        Bundler.settings.temporary(uri_no_auth.to_s => "other:stuff")
        expect(remote(uri_with_auth).anonymized_uri).to eq(uri_no_auth)
      end
    end

    describe "#cache_slug" do
      it "returns the correct slug" do
        expect(remote(uri_with_auth).cache_slug).to eq("gems.example.com.username.443.MD5HEX(gems.example.com.username.443./)")
      end

      it "does not apply given credentials" do
        Bundler.settings.temporary(uri_with_auth.to_s => credentials)
        expect(remote(uri_with_auth).cache_slug).to eq("gems.example.com.username.443.MD5HEX(gems.example.com.username.443./)")
      end
    end
  end

  context "when the original URI has only a username" do
    let(:uri) { URI("https://SeCrEt-ToKeN@gem.fury.io/me/") }

    describe "#anonymized_uri" do
      it "returns the URI without username and password" do
        expect(remote(uri).anonymized_uri).to eq(URI("https://gem.fury.io/me/"))
      end
    end

    describe "#cache_slug" do
      it "returns the correct slug" do
        expect(remote(uri).cache_slug).to eq("gem.fury.io.SeCrEt-ToKeN.443.MD5HEX(gem.fury.io.SeCrEt-ToKeN.443./me/)")
      end
    end
  end

  context "when a mirror with inline credentials is configured for the URI" do
    let(:uri) { URI("https://rubygems.org/") }
    let(:mirror_uri_with_auth) { URI("https://username:password@rubygems-mirror.org/") }
    let(:mirror_uri_no_auth) { URI("https://rubygems-mirror.org/") }

    before { Bundler.settings.set_local("mirror.https://rubygems.org/", mirror_uri_with_auth.to_s) }

    specify "#uri returns the mirror URI with credentials" do
      expect(remote(uri).uri).to eq(mirror_uri_with_auth)
    end

    specify "#anonymized_uri returns the mirror URI without credentials" do
      expect(remote(uri).anonymized_uri).to eq(mirror_uri_no_auth)
    end

    specify "#original_uri returns the original source" do
      expect(remote(uri).original_uri).to eq(uri)
    end

    specify "#cache_slug returns the correct slug" do
      expect(remote(uri).cache_slug).to eq("rubygems.org.443.MD5HEX(rubygems.org.443./)")
    end
  end

  context "when a mirror with configured credentials is configured for the URI" do
    let(:uri) { URI("https://rubygems.org/") }
    let(:mirror_uri_with_auth) { URI("https://#{credentials}@rubygems-mirror.org/") }
    let(:mirror_uri_no_auth) { URI("https://rubygems-mirror.org/") }

    before do
      Bundler.settings.temporary("mirror.https://rubygems.org/" => mirror_uri_no_auth.to_s)
      Bundler.settings.temporary(mirror_uri_no_auth.to_s => credentials)
    end

    specify "#uri returns the mirror URI with credentials" do
      expect(remote(uri).uri).to eq(mirror_uri_with_auth)
    end

    specify "#anonymized_uri returns the mirror URI without credentials" do
      expect(remote(uri).anonymized_uri).to eq(mirror_uri_no_auth)
    end

    specify "#original_uri returns the original source" do
      expect(remote(uri).original_uri).to eq(uri)
    end

    specify "#cache_slug returns the original source" do
      expect(remote(uri).cache_slug).to eq("rubygems.org.443.MD5HEX(rubygems.org.443./)")
    end
  end

  context "when there is no mirror set" do
    describe "#original_uri" do
      it "is not set" do
        expect(remote(uri_no_auth).original_uri).to be_nil
      end
    end
  end
end
