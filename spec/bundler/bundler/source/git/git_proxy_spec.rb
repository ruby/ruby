# frozen_string_literal: true
require "spec_helper"

describe Bundler::Source::Git::GitProxy do
  let(:uri) { "https://github.com/bundler/bundler.git" }
  subject { described_class.new(Pathname("path"), uri, "HEAD") }

  context "with configured credentials" do
    it "adds username and password to URI" do
      Bundler.settings[uri] = "u:p"
      expect(subject).to receive(:git_retry).with(match("https://u:p@github.com/bundler/bundler.git"))
      subject.checkout
    end

    it "adds username and password to URI for host" do
      Bundler.settings["github.com"] = "u:p"
      expect(subject).to receive(:git_retry).with(match("https://u:p@github.com/bundler/bundler.git"))
      subject.checkout
    end

    it "does not add username and password to mismatched URI" do
      Bundler.settings["https://u:p@github.com/bundler/bundler-mismatch.git"] = "u:p"
      expect(subject).to receive(:git_retry).with(match(uri))
      subject.checkout
    end

    it "keeps original userinfo" do
      Bundler.settings["github.com"] = "u:p"
      original = "https://orig:info@github.com/bundler/bundler.git"
      subject = described_class.new(Pathname("path"), original, "HEAD")
      expect(subject).to receive(:git_retry).with(match(original))
      subject.checkout
    end
  end

  describe "#version" do
    context "with a normal version number" do
      before do
        expect(subject).to receive(:git).with("--version").
          and_return("git version 1.2.3")
      end

      it "returns the git version number" do
        expect(subject.version).to eq("1.2.3")
      end

      it "does not raise an error when passed into Gem::Version.create" do
        expect { Gem::Version.create subject.version }.not_to raise_error
      end
    end

    context "with a OSX version number" do
      before do
        expect(subject).to receive(:git).with("--version").
          and_return("git version 1.2.3 (Apple Git-BS)")
      end

      it "strips out OSX specific additions in the version string" do
        expect(subject.version).to eq("1.2.3")
      end

      it "does not raise an error when passed into Gem::Version.create" do
        expect { Gem::Version.create subject.version }.not_to raise_error
      end
    end

    context "with a msysgit version number" do
      before do
        expect(subject).to receive(:git).with("--version").
          and_return("git version 1.2.3.msysgit.0")
      end

      it "strips out msysgit specific additions in the version string" do
        expect(subject.version).to eq("1.2.3")
      end

      it "does not raise an error when passed into Gem::Version.create" do
        expect { Gem::Version.create subject.version }.not_to raise_error
      end
    end
  end

  describe "#full_version" do
    context "with a normal version number" do
      before do
        expect(subject).to receive(:git).with("--version").
          and_return("git version 1.2.3")
      end

      it "returns the git version number" do
        expect(subject.full_version).to eq("1.2.3")
      end
    end

    context "with a OSX version number" do
      before do
        expect(subject).to receive(:git).with("--version").
          and_return("git version 1.2.3 (Apple Git-BS)")
      end

      it "does not strip out OSX specific additions in the version string" do
        expect(subject.full_version).to eq("1.2.3 (Apple Git-BS)")
      end
    end

    context "with a msysgit version number" do
      before do
        expect(subject).to receive(:git).with("--version").
          and_return("git version 1.2.3.msysgit.0")
      end

      it "does not strip out msysgit specific additions in the version string" do
        expect(subject.full_version).to eq("1.2.3.msysgit.0")
      end
    end
  end
end
