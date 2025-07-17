# frozen_string_literal: true

require "bundler"
require "bundler/build_metadata"

RSpec.describe Bundler::BuildMetadata do
  before do
    allow(Time).to receive(:now).and_return(Time.at(0))
    Bundler::BuildMetadata.instance_variable_set(:@timestamp, nil)
  end

  describe "#timestamp" do
    it "returns %Y-%m-%d formatted current time if built_at not set" do
      Bundler::BuildMetadata.instance_variable_set(:@built_at, nil)
      expect(Bundler::BuildMetadata.timestamp).to eq "1970-01-01"
    end

    it "returns %Y-%m-%d formatted current time if built_at not set" do
      Bundler::BuildMetadata.instance_variable_set(:@built_at, "2025-01-01")
      expect(Bundler::BuildMetadata.timestamp).to eq "2025-01-01"
    ensure
      Bundler::BuildMetadata.instance_variable_set(:@built_at, nil)
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

    it "returns a hash includes Timestamp, and Git SHA" do
      expect(subject["Timestamp"]).to eq "1970-01-01"
      expect(subject["Git SHA"]).to be_instance_of(String)
    end
  end
end
