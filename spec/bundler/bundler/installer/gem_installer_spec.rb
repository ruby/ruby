# frozen_string_literal: true

require "bundler/installer/gem_installer"

RSpec.describe Bundler::GemInstaller do
  let(:installer) { instance_double("Installer") }
  let(:spec_source) { instance_double("SpecSource") }
  let(:spec) { instance_double("Specification", :name => "dummy", :version => "0.0.1", :loaded_from => "dummy", :source => spec_source) }

  subject { described_class.new(spec, installer) }

  context "spec_settings is nil" do
    it "invokes install method with empty build_args" do
      allow(spec_source).to receive(:install).with(spec, :force => false, :ensure_builtin_gems_cached => false, :build_args => [])
      subject.install_from_spec
    end
  end

  context "spec_settings is build option" do
    it "invokes install method with build_args" do
      allow(Bundler.settings).to receive(:[]).with(:bin)
      allow(Bundler.settings).to receive(:[]).with(:inline)
      allow(Bundler.settings).to receive(:[]).with(:forget_cli_options)
      allow(Bundler.settings).to receive(:[]).with("build.dummy").and_return("--with-dummy-config=dummy")
      expect(spec_source).to receive(:install).with(spec, :force => false, :ensure_builtin_gems_cached => false, :build_args => ["--with-dummy-config=dummy"])
      subject.install_from_spec
    end
  end

  context "spec_settings is build option with spaces" do
    it "invokes install method with build_args" do
      allow(Bundler.settings).to receive(:[]).with(:bin)
      allow(Bundler.settings).to receive(:[]).with(:inline)
      allow(Bundler.settings).to receive(:[]).with(:forget_cli_options)
      allow(Bundler.settings).to receive(:[]).with("build.dummy").and_return("--with-dummy-config=dummy --with-another-dummy-config")
      expect(spec_source).to receive(:install).with(spec, :force => false, :ensure_builtin_gems_cached => false, :build_args => ["--with-dummy-config=dummy", "--with-another-dummy-config"])
      subject.install_from_spec
    end
  end
end
