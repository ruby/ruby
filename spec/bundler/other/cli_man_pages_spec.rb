# frozen_string_literal: true

RSpec.describe "bundle commands" do
  it "expects all commands to have a man page" do
    Bundler::CLI.all_commands.each_key do |command_name|
      next if command_name == "cli_help"

      expect(man_page(command_name)).to exist
    end
  end

  private

  def man_page(command_name)
    source_root.join("lib/bundler/man/bundle-#{command_name}.1.ronn")
  end
end
