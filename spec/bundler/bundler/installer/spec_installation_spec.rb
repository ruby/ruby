# frozen_string_literal: true

require "bundler/installer/parallel_installer"

RSpec.describe Bundler::ParallelInstaller::SpecInstallation do
  let!(:dep) do
    a_spec = Object.new
    def a_spec.name
      "I like tests"
    end

    def a_spec.full_name
      "I really like tests"
    end
    a_spec
  end

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
    context "when all dependencies are installed" do
      it "returns true" do
        dependencies = []
        dependencies << instance_double("SpecInstallation", spec: "alpha", name: "alpha", installed?: true, all_dependencies: [], type: :production)
        dependencies << instance_double("SpecInstallation", spec: "beta", name: "beta", installed?: true, all_dependencies: [], type: :production)
        all_specs = dependencies + [instance_double("SpecInstallation", spec: "gamma", name: "gamma", installed?: false, all_dependencies: [], type: :production)]
        spec = described_class.new(dep)
        allow(spec).to receive(:all_dependencies).and_return(dependencies)
        installed_specs = all_specs.select(&:installed?).map {|s| [s.name, true] }.to_h
        expect(spec.dependencies_installed?(installed_specs)).to be_truthy
      end
    end

    context "when all dependencies are not installed" do
      it "returns false" do
        dependencies = []
        dependencies << instance_double("SpecInstallation", spec: "alpha", name: "alpha", installed?: false, all_dependencies: [], type: :production)
        dependencies << instance_double("SpecInstallation", spec: "beta", name: "beta", installed?: true, all_dependencies: [], type: :production)
        all_specs = dependencies + [instance_double("SpecInstallation", spec: "gamma", name: "gamma", installed?: false, all_dependencies: [], type: :production)]
        spec = described_class.new(dep)
        allow(spec).to receive(:all_dependencies).and_return(dependencies)
        installed_specs = all_specs.select(&:installed?).map {|s| [s.name, true] }.to_h
        expect(spec.dependencies_installed?(installed_specs)).to be_falsey
      end
    end
  end
end
