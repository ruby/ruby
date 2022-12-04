# frozen_string_literal: true

RSpec.describe "bundle help" do
  it "uses man when available" do
    with_fake_man do
      bundle "help gemfile"
    end
    expect(out).to eq(%(["#{man_dir}/gemfile.5"]))
  end

  it "prefixes bundle commands with bundle- when finding the man files" do
    with_fake_man do
      bundle "help install"
    end
    expect(out).to eq(%(["#{man_dir}/bundle-install.1"]))
  end

  it "simply outputs the human readable file when there is no man on the path" do
    with_path_as("") do
      bundle "help install"
    end
    expect(out).to match(/bundle-install/)
  end

  it "still outputs the old help for commands that do not have man pages yet" do
    bundle "help fund"
    expect(out).to include("Lists information about gems seeking funding assistance")
  end

  it "looks for a binary and executes it with --help option if it's named bundler-<task>" do
    skip "Could not find command testtasks, probably because not a windows friendly executable" if Gem.win_platform?

    File.open(tmp("bundler-testtasks"), "w", 0o755) do |f|
      f.puts "#!/usr/bin/env ruby\nputs ARGV.join(' ')\n"
    end

    with_path_added(tmp) do
      bundle "help testtasks"
    end

    expect(out).to eq("--help")
  end

  it "is called when the --help flag is used after the command" do
    with_fake_man do
      bundle "install --help"
    end
    expect(out).to eq(%(["#{man_dir}/bundle-install.1"]))
  end

  it "is called when the --help flag is used before the command" do
    with_fake_man do
      bundle "--help install"
    end
    expect(out).to eq(%(["#{man_dir}/bundle-install.1"]))
  end

  it "is called when the -h flag is used before the command" do
    with_fake_man do
      bundle "-h install"
    end
    expect(out).to eq(%(["#{man_dir}/bundle-install.1"]))
  end

  it "is called when the -h flag is used after the command" do
    with_fake_man do
      bundle "install -h"
    end
    expect(out).to eq(%(["#{man_dir}/bundle-install.1"]))
  end

  it "has helpful output when using --help flag for a non-existent command" do
    with_fake_man do
      bundle "instill -h", :raise_on_error => false
    end
    expect(err).to include('Could not find command "instill".')
  end

  it "is called when only using the --help flag" do
    with_fake_man do
      bundle "--help"
    end
    expect(out).to eq(%(["#{man_dir}/bundle.1"]))

    with_fake_man do
      bundle "-h"
    end
    expect(out).to eq(%(["#{man_dir}/bundle.1"]))
  end
end
