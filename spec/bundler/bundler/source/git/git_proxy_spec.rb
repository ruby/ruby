# frozen_string_literal: true

RSpec.describe Bundler::Source::Git::GitProxy do
  let(:path) { Pathname("path") }
  let(:uri) { "https://github.com/rubygems/rubygems.git" }
  let(:ref) { "HEAD" }
  let(:revision) { nil }
  let(:git_source) { nil }
  let(:clone_result) { double(Process::Status, :success? => true) }
  let(:base_clone_args) { ["clone", "--bare", "--no-hardlinks", "--quiet", "--no-tags", "--depth", "1", "--single-branch"] }
  subject { described_class.new(path, uri, ref, revision, git_source) }

  context "with configured credentials" do
    it "adds username and password to URI" do
      Bundler.settings.temporary(uri => "u:p") do
        allow(subject).to receive(:git_local).with("--version").and_return("git version 2.14.0")
        expect(subject).to receive(:capture).with([*base_clone_args, "--", "https://u:p@github.com/rubygems/rubygems.git", path.to_s], nil).and_return(["", "", clone_result])
        subject.checkout
      end
    end

    it "adds username and password to URI for host" do
      Bundler.settings.temporary("github.com" => "u:p") do
        allow(subject).to receive(:git_local).with("--version").and_return("git version 2.14.0")
        expect(subject).to receive(:capture).with([*base_clone_args, "--", "https://u:p@github.com/rubygems/rubygems.git", path.to_s], nil).and_return(["", "", clone_result])
        subject.checkout
      end
    end

    it "does not add username and password to mismatched URI" do
      Bundler.settings.temporary("https://u:p@github.com/rubygems/rubygems-mismatch.git" => "u:p") do
        allow(subject).to receive(:git_local).with("--version").and_return("git version 2.14.0")
        expect(subject).to receive(:capture).with([*base_clone_args, "--", uri, path.to_s], nil).and_return(["", "", clone_result])
        subject.checkout
      end
    end

    it "keeps original userinfo" do
      Bundler.settings.temporary("github.com" => "u:p") do
        original = "https://orig:info@github.com/rubygems/rubygems.git"
        subject = described_class.new(Pathname("path"), original, "HEAD")
        allow(subject).to receive(:git_local).with("--version").and_return("git version 2.14.0")
        expect(subject).to receive(:capture).with([*base_clone_args, "--", original, path.to_s], nil).and_return(["", "", clone_result])
        subject.checkout
      end
    end
  end

  describe "#version" do
    context "with a normal version number" do
      before do
        expect(subject).to receive(:git_local).with("--version").
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
        expect(subject).to receive(:git_local).with("--version").
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
        expect(subject).to receive(:git_local).with("--version").
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
        expect(subject).to receive(:git_local).with("--version").
          and_return("git version 1.2.3")
      end

      it "returns the git version number" do
        expect(subject.full_version).to eq("1.2.3")
      end
    end

    context "with a OSX version number" do
      before do
        expect(subject).to receive(:git_local).with("--version").
          and_return("git version 1.2.3 (Apple Git-BS)")
      end

      it "does not strip out OSX specific additions in the version string" do
        expect(subject.full_version).to eq("1.2.3 (Apple Git-BS)")
      end
    end

    context "with a msysgit version number" do
      before do
        expect(subject).to receive(:git_local).with("--version").
          and_return("git version 1.2.3.msysgit.0")
      end

      it "does not strip out msysgit specific additions in the version string" do
        expect(subject.full_version).to eq("1.2.3.msysgit.0")
      end
    end
  end

  it "doesn't allow arbitrary code execution through Gemfile uris with a leading dash" do
    gemfile <<~G
      gem "poc", git: "-u./pay:load.sh"
    G

    file = bundled_app("pay:load.sh")

    create_file file, <<~RUBY
      #!/bin/sh

      touch #{bundled_app("canary")}
    RUBY

    FileUtils.chmod("+x", file)

    bundle :lock, :raise_on_error => false

    expect(Pathname.new(bundled_app("canary"))).not_to exist
  end
end
