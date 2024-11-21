# frozen_string_literal: true

RSpec.describe "bundle commands" do
  it "expects all commands to have a man page" do
    command_names =
      Dir["#{source_root}/lib/bundler/cli/*.rb"].
        grep_v(/common.rb/).
        map {|file_path| File.basename(file_path, ".rb") }

    command_names.each do |command_name|
      man_page = source_root.join("lib/bundler/man/bundle-#{command_name}.1.ronn")
      expect(man_page).to exist
    end
  end
end
