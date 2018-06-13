# frozen_string_literal: true

require "bundler/installer/parallel_installer"

RSpec.describe Bundler::ParallelInstaller do
  let(:installer) { instance_double("Installer") }
  let(:all_specs) { [] }
  let(:size) { 1 }
  let(:standalone) { false }
  let(:force) { false }

  subject { described_class.new(installer, all_specs, size, standalone, force) }

  context "when dependencies that are not on the overall installation list are the only ones not installed" do
    let(:all_specs) do
      [
        build_spec("alpha", "1.0") {|s| s.runtime "a", "1" },
      ].flatten
    end

    it "prints a warning" do
      expect(Bundler.ui).to receive(:warn).with(<<-W.strip)
Your lockfile was created by an old Bundler that left some things out.
You can fix this by adding the missing gems to your Gemfile, running bundle install, and then removing the gems from your Gemfile.
The missing gems are:
* a depended upon by alpha
      W
      subject.check_for_corrupt_lockfile
    end

    context "when size > 1" do
      let(:size) { 500 }

      it "prints a warning and sets size to 1" do
        expect(Bundler.ui).to receive(:warn).with(<<-W.strip)
Your lockfile was created by an old Bundler that left some things out.
Because of the missing DEPENDENCIES, we can only install gems one at a time, instead of installing 500 at a time.
You can fix this by adding the missing gems to your Gemfile, running bundle install, and then removing the gems from your Gemfile.
The missing gems are:
* a depended upon by alpha
        W
        subject.check_for_corrupt_lockfile
        expect(subject.size).to eq(1)
      end
    end
  end
end
