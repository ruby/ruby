# frozen_string_literal: true

RSpec.describe Bundler::Dependency do
  let(:options) do
    {}
  end
  let(:dependency) do
    described_class.new(
      "test_gem",
      "1.0.0",
      options
    )
  end

  describe "to_lock" do
    it "returns formatted string" do
      expect(dependency.to_lock).to eq("  test_gem (= 1.0.0)")
    end

    it "matches format of Gem::Dependency#to_lock" do
      gem_dependency = Gem::Dependency.new("test_gem", "1.0.0")
      expect(dependency.to_lock).to eq(gem_dependency.to_lock)
    end

    context "when source is passed" do
      let(:options) do
        {
          "source" => Bundler::Source::Git.new({}),
        }
      end

      it "returns formatted string with exclamation mark" do
        expect(dependency.to_lock).to eq("  test_gem (= 1.0.0)!")
      end
    end
  end

  it "is on the current platform" do
    engine = Gem.win_platform? ? "windows" : RUBY_ENGINE

    dep = described_class.new(
      "test_gem",
      "1.0.0",
      { "platforms" => "#{engine}_#{RbConfig::CONFIG["MAJOR"]}#{RbConfig::CONFIG["MINOR"]}" },
    )

    expect(dep.current_platform?).to be_truthy
  end
end
