# frozen_string_literal: true

RSpec.describe Bundler::StubSpecification do
  let(:with_bundler_stub_spec) do
    gemspec = Gem::Specification.new do |s|
      s.name = "gemname"
      s.version = "1.0.0"
      s.loaded_from = __FILE__
    end

    described_class.from_stub(gemspec)
  end

  describe "#from_stub" do
    it "returns the same stub if already a Bundler::StubSpecification" do
      stub = described_class.from_stub(with_bundler_stub_spec)
      expect(stub).to be(with_bundler_stub_spec)
    end
  end
end
