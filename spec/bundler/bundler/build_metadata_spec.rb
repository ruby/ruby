# frozen_string_literal: true

require "bundler"
require "bundler/build_metadata"

RSpec.describe Bundler::BuildMetadata do
  before do
    allow(Time).to receive(:now).and_return(Time.at(0))
    Bundler::BuildMetadata.instance_variable_set(:@built_at, nil)
  end

  describe "#built_at" do
    it "returns %Y-%m-%d formatted time" do
      expect(Bundler::BuildMetadata.built_at).to eq "1970-01-01"
    end
  end

  describe "#release?" do
    it "returns false as default" do
      expect(Bundler::BuildMetadata.release?).to be_falsey
    end
  end

  describe "#git_commit_sha" do
    context "if instance valuable is defined" do
      before do
        Bundler::BuildMetadata.instance_variable_set(:@git_commit_sha, "foo")
      end

      after do
        Bundler::BuildMetadata.remove_instance_variable(:@git_commit_sha)
      end

      it "returns set value" do
        expect(Bundler::BuildMetadata.git_commit_sha).to eq "foo"
      end
    end
  end

  describe "#to_h" do
    subject { Bundler::BuildMetadata.to_h }

    it "returns a hash includes Built At, Git SHA and Released Version" do
      expect(subject["Built At"]).to eq "1970-01-01"
      expect(subject["Git SHA"]).to be_instance_of(String)
      expect(subject["Released Version"]).to be_falsey
    end
  end
end
