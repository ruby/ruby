# frozen_string_literal: true

require "bundler/cli"
require "bundler/cli/open"

RSpec.describe Bundler::CLI::Open do
  subject { described_class.new({}, "rack") }

  describe "#editor_command" do
    it "takes an editor path that names an existing file as a single word on Windows" do
      editor = File.join(Dir.mktmpdir, "editor.exe")
      FileUtils.touch editor
      allow(Gem).to receive(:win_platform?).and_return(true)

      expect(subject.editor_command(editor)).to eq([editor])
    end

    it "keeps backslashes in a quoted path" do
      expect(subject.editor_command('"C:\Program Files\Microsoft VS Code\Code.exe" -w')).
        to eq(['C:\Program Files\Microsoft VS Code\Code.exe', "-w"])
    end

    it "splits an editor with arguments" do
      expect(subject.editor_command("code -w")).to eq(["code", "-w"])
    end

    it "splits an existing path on POSIX" do
      dir = Dir.mktmpdir
      FileUtils.mkdir_p File.join(dir, "editor dir")
      editor = File.join(dir, "editor dir", "editor")
      FileUtils.touch editor
      allow(Gem).to receive(:win_platform?).and_return(false)

      expect(subject.editor_command(editor)).to eq(editor.split(" "))
    end
  end
end
