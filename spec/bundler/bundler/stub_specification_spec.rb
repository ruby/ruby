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

  describe "#gem_build_complete_path" do
    it "StubSpecification should have equal gem_build_complete_path as Specification" do
      spec_path = File.join(File.dirname(__FILE__), "specifications", "foo.gemspec")
      spec = Gem::Specification.load(spec_path)
      gem_stub = Gem::StubSpecification.new(spec_path, File.dirname(__FILE__),"","")

      stub = described_class.from_stub(gem_stub)
      expect(stub.gem_build_complete_path).to eq spec.gem_build_complete_path
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

    it "returns #{RUBY_ENGINE == "jruby" ? "false" : "true"} if not manually_installed?" do
      stub = described_class.from_stub(with_bundler_stub_spec)
      stub.installed_by_version = Gem::Version.new(1)
      if RUBY_ENGINE == "jruby"
        expect(stub.missing_extensions?).to be false
      else
        expect(stub.missing_extensions?).to be true
      end
    end
  end

  describe "#activated?" do
    it "returns true after activation" do
      stub = described_class.from_stub(with_bundler_stub_spec)

      expect(stub.activated?).to be_falsey
      stub.activated = true
      expect(stub.activated?).to be true
    end

    it "returns true after activation if the underlying stub is a `Gem::StubSpecification`" do
      spec_path = File.join(File.dirname(__FILE__), "specifications", "foo.gemspec")
      gem_stub = Gem::StubSpecification.new(spec_path, File.dirname(__FILE__),"","")
      stub = described_class.from_stub(gem_stub)

      expect(stub.activated?).to be_falsey
      stub.activated = true
      expect(stub.activated?).to be true
    end
  end

  describe "#contains_requirable_file?" do
    let(:base_dir) { Dir.mktmpdir }
    let(:stub) do
      spec_path = File.join(base_dir, "specifications", "bar-1.0.0.gemspec")
      FileUtils.mkdir_p File.dirname(spec_path)
      File.write spec_path, Gem::Specification.new {|s|
        s.name = "bar"
        s.version = "1.0.0"
        s.require_paths = ["lib"]
      }.to_ruby
      FileUtils.mkdir_p File.join(base_dir, "gems", "bar-1.0.0", "lib")
      File.write File.join(base_dir, "gems", "bar-1.0.0", "lib", "bar.rb"), ""

      described_class.from_stub(Gem::StubSpecification.gemspec_stub(spec_path, base_dir, File.join(base_dir, "gems")))
    end

    after { FileUtils.rm_rf base_dir }

    it "answers from the stub without loading the full gemspec" do
      expect(stub).not_to receive(:_remote_specification)

      expect(stub.contains_requirable_file?("bar")).to be true
      expect(stub.contains_requirable_file?("missing")).to be false
    end
  end
end
