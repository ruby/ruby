# frozen_string_literal: true

RSpec.describe Bundler::Source::Path do
  before do
    allow(Bundler).to receive(:root) { Pathname.new("root") }
  end

  describe "#eql?" do
    subject { described_class.new("path" => "gems/a") }

    context "with two equivalent relative paths from different roots" do
      let(:a_gem_opts) { { "path" => "../gems/a", "root_path" => Bundler.root.join("nested") } }
      let(:a_gem)      { described_class.new a_gem_opts }

      it "returns true" do
        expect(subject).to eq a_gem
      end
    end

    context "with the same (but not equivalent) relative path from different roots" do
      subject { described_class.new("path" => "gems/a") }

      let(:a_gem_opts) { { "path" => "gems/a", "root_path" => Bundler.root.join("nested") } }
      let(:a_gem)      { described_class.new a_gem_opts }

      it "returns false" do
        expect(subject).to_not eq a_gem
      end
    end
  end
end
