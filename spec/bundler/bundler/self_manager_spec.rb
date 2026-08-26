# frozen_string_literal: true

RSpec.describe Bundler::SelfManager do
  describe "#restart_with" do
    # When the running Ruby lives under a path containing whitespace, Gem.ruby
    # returns a quoted string. That quoting must not leak into the argv passed
    # to Kernel.exec, or the interpreter can't be found and the auto-switch to
    # the locked bundler version fails to spawn.
    it "does not embed quotes in the ruby executable when Gem.ruby is quoted" do
      manager = described_class.new

      allow(Gem).to receive(:ruby).and_return('"/path with space/bin/ruby"')

      # Force the branch that prepends Gem.ruby to the command.
      allow(File).to receive(:executable?).and_return(false)
      allow(Bundler).to receive(:with_original_env).and_yield

      captured = nil
      allow(Kernel).to receive(:exec) do |_env, *cmd|
        captured = cmd
      end

      manager.send(:restart_with, Gem::Version.new("1.0.0"))

      expect(captured.first).to eq("/path with space/bin/ruby")
      expect(captured.first).not_to include('"')
    end
  end
end
