# frozen_string_literal: true

RSpec.describe Bundler::Source::Git::GitProxy do
  let(:path) { Pathname("path") }
  let(:uri) { "https://github.com/rubygems/rubygems.git" }
  let(:ref) { "HEAD" }
  let(:revision) { nil }
  let(:git_source) { nil }
  subject { described_class.new(path, uri, ref, revision, git_source) }

  context "with configured credentials" do
    it "adds username and password to URI" do
      Bundler.settings.temporary(uri => "u:p") do
        expect(subject).to receive(:git_retry).with(match("https://u:p@github.com/rubygems/rubygems.git"))
        subject.checkout
      end
    end

    it "adds username and password to URI for host" do
      Bundler.settings.temporary("github.com" => "u:p") do
        expect(subject).to receive(:git_retry).with(match("https://u:p@github.com/rubygems/rubygems.git"))
        subject.checkout
      end
    end

    it "does not add username and password to mismatched URI" do
      Bundler.settings.temporary("https://u:p@github.com/rubygems/rubygems-mismatch.git" => "u:p") do
        expect(subject).to receive(:git_retry).with(match(uri))
        subject.checkout
      end
    end

    it "keeps original userinfo" do
      Bundler.settings.temporary("github.com" => "u:p") do
        original = "https://orig:info@github.com/rubygems/rubygems.git"
        subject = described_class.new(Pathname("path"), original, "HEAD")
        expect(subject).to receive(:git_retry).with(match(original))
        subject.checkout
      end
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

  describe "#copy_to" do
    let(:cache) { tmpdir("cache_path") }
    let(:destination) { tmpdir("copy_to_path") }
    let(:submodules) { false }

    context "when given a SHA as a revision" do
      let(:revision) { "abcd" * 10 }
      let(:command) { "reset --hard #{revision}" }

      it "fails gracefully when resetting to the revision fails" do
        expect(subject).to receive(:git_retry).with(start_with("clone ")) { destination.mkpath }
        expect(subject).to receive(:git_retry).with(start_with("fetch "), :dir => destination)
        expect(subject).to receive(:git).with(command, :dir => destination).and_raise(Bundler::Source::Git::GitCommandError.new(command, cache, destination))
        expect(subject).not_to receive(:git)

        expect { subject.copy_to(destination, submodules) }.
          to raise_error(
            Bundler::Source::Git::MissingGitRevisionError,
            "Git error: command `git #{command}` in directory #{destination} has failed.\n" \
            "Revision #{revision} does not exist in the repository #{uri}. Maybe you misspelled it?" \
          )
      end
    end
  end
end
