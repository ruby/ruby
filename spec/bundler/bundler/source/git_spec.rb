# frozen_string_literal: true

RSpec.describe Bundler::Source::Git do
  before do
    allow(Bundler).to receive(:root) { Pathname.new("root") }
  end

  let(:uri) { "https://github.com/foo/bar.git" }
  let(:options) do
    { "uri" => uri }
  end

  subject { described_class.new(options) }

  describe "#to_s" do
    it "returns a description" do
      expect(subject.to_s).to eq "https://github.com/foo/bar.git"
    end

    context "when the URI contains credentials" do
      let(:uri) { "https://my-secret-token:x-oauth-basic@github.com/foo/bar.git" }

      it "filters credentials" do
        expect(subject.to_s).to eq "https://x-oauth-basic@github.com/foo/bar.git"
      end
    end

    context "when the source has a glob specifier" do
      let(:glob) { "bar/baz/*.gemspec" }
      let(:options) do
        { "uri" => uri, "glob" => glob }
      end

      it "includes it" do
        expect(subject.to_s).to eq "https://github.com/foo/bar.git (glob: bar/baz/*.gemspec)"
      end
    end

    context "when the source has a reference" do
      let(:git_proxy_stub) do
        instance_double(Bundler::Source::Git::GitProxy, :revision => "123abc", :branch => "v1.0.0")
      end
      let(:options) do
        { "uri" => uri, "ref" => "v1.0.0" }
      end

      before do
        allow(Bundler::Source::Git::GitProxy).to receive(:new).and_return(git_proxy_stub)
      end

      it "includes it" do
        expect(subject.to_s).to eq "https://github.com/foo/bar.git (at v1.0.0@123abc)"
      end
    end

    context "when the source has both reference and glob specifiers" do
      let(:git_proxy_stub) do
        instance_double(Bundler::Source::Git::GitProxy, :revision => "123abc", :branch => "v1.0.0")
      end
      let(:options) do
        { "uri" => uri, "ref" => "v1.0.0", "glob" => "gems/foo/*.gemspec" }
      end

      before do
        allow(Bundler::Source::Git::GitProxy).to receive(:new).and_return(git_proxy_stub)
      end

      it "includes both" do
        expect(subject.to_s).to eq "https://github.com/foo/bar.git (at v1.0.0@123abc, glob: gems/foo/*.gemspec)"
      end
    end
  end
end
