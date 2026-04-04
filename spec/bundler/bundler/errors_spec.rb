# frozen_string_literal: true

RSpec.describe Bundler::IncorrectLockfileDependencies do
  describe "#message" do
    let(:spec) do
      double("LazySpecification", full_name: "rubocop-1.82.0")
    end

    context "without dependency details" do
      subject { described_class.new(spec) }

      it "provides a basic error message" do
        expect(subject.message).to include("Bundler found incorrect dependencies in the lockfile for rubocop-1.82.0")
        expect(subject.message).to include("Please run `bundle install` to regenerate the lockfile.")
      end
    end

    context "with dependency details" do
      let(:actual_dependencies) do
        [
          Gem::Dependency.new("json", [">= 2.3", "< 4.0"]),
          Gem::Dependency.new("parallel", ["~> 1.10"]),
          Gem::Dependency.new("parser", [">= 3.3.0.2"]),
        ]
      end

      let(:lockfile_dependencies) do
        [
          Gem::Dependency.new("json", [">= 2.3", "< 3.0"]),
          Gem::Dependency.new("parallel", ["~> 1.10"]),
          Gem::Dependency.new("parser", [">= 3.2.0.0"]),
        ]
      end

      subject { described_class.new(spec, actual_dependencies, lockfile_dependencies) }

      it "shows only mismatched dependencies" do
        message = subject.message

        expect(message).to include("json: gemspec specifies")
        expect(message).to include("parser: gemspec specifies")
        expect(message).not_to include("parallel")
      end
    end

    context "when gemspec has dependencies but lockfile has none" do
      let(:actual_dependencies) do
        [
          Gem::Dependency.new("myrack-test", ["~> 1.0"]),
        ]
      end

      let(:lockfile_dependencies) { [] }

      subject { described_class.new(spec, actual_dependencies, lockfile_dependencies) }

      it "shows the dependency as not in lockfile" do
        message = subject.message

        expect(message).to include("myrack-test: gemspec specifies ~> 1.0, not in lockfile")
      end
    end

    context "when gemspec has no dependencies but lockfile has some" do
      let(:actual_dependencies) { [] }

      let(:lockfile_dependencies) do
        [
          Gem::Dependency.new("unexpected", ["~> 1.0"]),
        ]
      end

      subject { described_class.new(spec, actual_dependencies, lockfile_dependencies) }

      it "shows the dependency as not in gemspec" do
        message = subject.message

        expect(message).to include("unexpected: not in gemspec, lockfile has ~> 1.0")
      end
    end
  end

  describe "#status_code" do
    let(:spec) { double("LazySpecification", full_name: "test-1.0.0") }
    subject { described_class.new(spec) }

    it "returns 41" do
      expect(subject.status_code).to eq(41)
    end
  end
end
