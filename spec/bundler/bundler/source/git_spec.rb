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
      expect(subject.to_s).to eq "https://github.com/foo/bar.git (at master)"
    end

    context "when the URI contains credentials" do
      let(:uri) { "https://my-secret-token:x-oauth-basic@github.com/foo/bar.git" }

      it "filters credentials" do
        expect(subject.to_s).to eq "https://x-oauth-basic@github.com/foo/bar.git (at master)"
      end
    end
  end
end
