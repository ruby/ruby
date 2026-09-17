# frozen_string_literal: true

require "bundler/cli"
require "bundler/cli/exec"

RSpec.describe Bundler::CLI::Exec do
  subject(:command) { described_class.new(options, ["script"]) }

  let(:options) { double("options", keep_file_descriptors?: false) }

  before do
    allow(Bundler.current_ruby).to receive(:jruby?).and_return(false)
    allow(Bundler::SharedHelpers).to receive(:set_bundle_environment)
    allow(Bundler).to receive(:settings).and_return({ disable_exec_load: true })
  end

  def expect_exec_path(path, expected_path)
    allow(Bundler).to receive(:which).with("script").and_return(path)
    expect(command).to receive(:kernel_exec).with(expected_path, kind_of(Hash))
    command.run
  end

  it "preserves explicit relative paths using the primary path separator" do
    path = ".#{File::SEPARATOR}script"
    expect_exec_path(path, path)
  end

  it "preserves parent-relative paths using the primary path separator" do
    path = "..#{File::SEPARATOR}script"
    expect_exec_path(path, path)
  end

  it "preserves explicit relative paths using the alternative path separator" do
    stub_const("File::ALT_SEPARATOR", "\\")

    expect_exec_path(".\\script", ".\\script")
  end

  it "preserves parent-relative paths using the alternative path separator" do
    stub_const("File::ALT_SEPARATOR", "\\")

    expect_exec_path("..\\script", "..\\script")
  end

  it "prepends the primary path separator to other relative paths" do
    expect_exec_path(".script", ".#{File::SEPARATOR}.script")
  end

  it "treats a backslash as part of a filename when it is not a path separator" do
    stub_const("File::ALT_SEPARATOR", nil)

    expect_exec_path(".\\script", ".#{File::SEPARATOR}.\\script")
  end
end
