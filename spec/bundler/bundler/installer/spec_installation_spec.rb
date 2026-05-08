# frozen_string_literal: true

require "bundler/installer/parallel_installer"

RSpec.describe Bundler::ParallelInstaller::SpecInstallation do
  def build_spec(name, extensions: [])
    spec = Object.new
    spec.define_singleton_method(:name) { name }
    spec.define_singleton_method(:full_name) { "#{name}-1.0" }
    spec.define_singleton_method(:extensions) { extensions }
    spec.define_singleton_method(:dependencies) { [] }
    spec
  end

  let!(:dep) { build_spec("I like tests") }

  describe "#ready_to_enqueue?" do
    context "when in enqueued state" do
      it "is falsey" do
        spec = described_class.new(dep)
        spec.state = :enqueued
        expect(spec.ready_to_enqueue?).to be_falsey
      end
    end

    context "when in installed state" do
      it "returns falsey" do
        spec = described_class.new(dep)
        spec.state = :installed
        expect(spec.ready_to_enqueue?).to be_falsey
      end
    end

    it "returns truthy" do
      spec = described_class.new(dep)
      expect(spec.ready_to_enqueue?).to be_truthy
    end
  end

  describe "#dependencies_installed?" do
    it "returns true when all dependencies are installed" do
      alpha = described_class.new(build_spec("alpha"))
      alpha.dependencies = []

      beta = described_class.new(build_spec("beta"))
      beta.dependencies = [alpha]

      gamma = described_class.new(build_spec("gamma"))
      gamma.dependencies = [beta]

      expect(gamma.dependencies_installed?({})).to be_falsey
      expect(gamma.dependencies_installed?({ "beta" => true })).to be_falsey
      expect(gamma.dependencies_installed?({ "alpha" => true, "beta" => true })).to be_truthy
    end
  end

  describe "#ready_to_install?" do
    context "when spec has no extensions" do
      it "returns true regardless of dependencies" do
        beta = described_class.new(build_spec("beta"))
        beta.dependencies = []

        spec = described_class.new(dep)
        spec.state = :downloaded
        spec.dependencies = [beta]

        expect(spec.ready_to_install?({})).to be_truthy
      end
    end

    context "when spec has extensions" do
      it "returns true when all dependencies are installed" do
        alpha = described_class.new(build_spec("alpha"))
        alpha.dependencies = []

        beta = described_class.new(build_spec("beta"))
        beta.dependencies = [alpha]

        gamma = described_class.new(build_spec("gamma", extensions: ["ext/Rakefile"]))
        gamma.state = :downloaded
        gamma.dependencies = [beta]

        expect(gamma.ready_to_install?({})).to be_falsey
        expect(gamma.ready_to_install?({ "beta" => true })).to be_falsey
        expect(gamma.ready_to_install?({ "alpha" => true, "beta" => true })).to be_truthy
      end
    end
  end
end
