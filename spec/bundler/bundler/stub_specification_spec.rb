# frozen_string_literal: true

RSpec.describe Bundler::StubSpecification do
  let(:with_bundler_stub_spec) do
    gemspec = Gem::Specification.new do |s|
      s.name = "gemname"
      s.version = "1.0.0"
      s.loaded_from = __FILE__
      s.extensions = "ext/gemname"
    end

    described_class.from_stub(gemspec)
  end

  describe "#from_stub" do
    it "returns the same stub if already a Bundler::StubSpecification" do
      stub = described_class.from_stub(with_bundler_stub_spec)
      expect(stub).to be(with_bundler_stub_spec)
    end
  end

  describe "#manually_installed?" do
    it "returns true if installed_by_version is nil or 0" do
      stub = described_class.from_stub(with_bundler_stub_spec)
      expect(stub.manually_installed?).to be true
    end

    it "returns false if installed_by_version is greater than 0" do
      stub = described_class.from_stub(with_bundler_stub_spec)
      stub.installed_by_version = Gem::Version.new(1)
      expect(stub.manually_installed?).to be false
    end
  end

  describe "#missing_extensions?" do
    it "returns false if manually_installed?" do
      stub = described_class.from_stub(with_bundler_stub_spec)
      expect(stub.missing_extensions?).to be false
    end

    it "returns true if not manually_installed?" do
      stub = described_class.from_stub(with_bundler_stub_spec)
      stub.installed_by_version = Gem::Version.new(1)
      expect(stub.missing_extensions?).to be true
    end
  end
end
