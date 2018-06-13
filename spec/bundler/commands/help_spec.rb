# frozen_string_literal: true

RSpec.describe "bundle help" do
  # RubyGems 1.4+ no longer load gem plugins so this test is no longer needed
  it "complains if older versions of bundler are installed", :rubygems => "< 1.4" do
    system_gems "bundler-0.8.1"

    bundle "help"
    expect(err).to include("older than 0.9")
    expect(err).to include("running `gem cleanup bundler`.")
  end

  it "uses mann when available", :ruby_repo do
    with_fake_man do
      bundle "help gemfile"
    end
    expect(out).to eq(%(["#{root}/man/gemfile.5"]))
  end

  it "prefixes bundle commands with bundle- when finding the groff files", :ruby_repo do
    with_fake_man do
      bundle "help install"
    end
    expect(out).to eq(%(["#{root}/man/bundle-install.1"]))
  end

  it "simply outputs the txt file when there is no man on the path", :ruby_repo do
    with_path_as("") do
      bundle "help install"
    end
    expect(out).to match(/BUNDLE-INSTALL/)
  end

  it "still outputs the old help for commands that do not have man pages yet" do
    bundle "help version"
    expect(out).to include("Prints the bundler's version information")
  end

  it "looks for a binary and executes it with --help option if it's named bundler-<task>" do
    File.open(tmp("bundler-testtasks"), "w", 0o755) do |f|
      f.puts "#!/usr/bin/env ruby\nputs ARGV.join(' ')\n"
    end

    with_path_added(tmp) do
      bundle "help testtasks"
    end

    expect(exitstatus).to be_zero if exitstatus
    expect(out).to eq("--help")
  end

  it "is called when the --help flag is used after the command", :ruby_repo do
    with_fake_man do
      bundle "install --help"
    end
    expect(out).to eq(%(["#{root}/man/bundle-install.1"]))
  end

  it "is called when the --help flag is used before the command", :ruby_repo do
    with_fake_man do
      bundle "--help install"
    end
    expect(out).to eq(%(["#{root}/man/bundle-install.1"]))
  end

  it "is called when the -h flag is used before the command", :ruby_repo do
    with_fake_man do
      bundle "-h install"
    end
    expect(out).to eq(%(["#{root}/man/bundle-install.1"]))
  end

  it "is called when the -h flag is used after the command", :ruby_repo do
    with_fake_man do
      bundle "install -h"
    end
    expect(out).to eq(%(["#{root}/man/bundle-install.1"]))
  end

  it "has helpful output when using --help flag for a non-existent command" do
    with_fake_man do
      bundle "instill -h"
    end
    expect(out).to include('Could not find command "instill".')
  end

  it "is called when only using the --help flag", :ruby_repo do
    with_fake_man do
      bundle "--help"
    end
    expect(out).to eq(%(["#{root}/man/bundle.1"]))

    with_fake_man do
      bundle "-h"
    end
    expect(out).to eq(%(["#{root}/man/bundle.1"]))
  end
end
