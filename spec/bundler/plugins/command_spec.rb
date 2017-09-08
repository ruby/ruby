# frozen_string_literal: true
require "spec_helper"

RSpec.describe "command plugins" do
  before do
    build_repo2 do
      build_plugin "command-mah" do |s|
        s.write "plugins.rb", <<-RUBY
          module Mah
            class Plugin < Bundler::Plugin::API
              command "mahcommand" # declares the command

              def exec(command, args)
                puts "MahHello"
              end
            end
          end
        RUBY
      end
    end

    bundle "plugin install command-mah --source file://#{gem_repo2}"
  end

  it "executes without arguments" do
    expect(out).to include("Installed plugin command-mah")

    bundle "mahcommand"
    expect(out).to eq("MahHello")
  end

  it "accepts the arguments" do
    build_repo2 do
      build_plugin "the-echoer" do |s|
        s.write "plugins.rb", <<-RUBY
          module Resonance
            class Echoer
              # Another method to declare the command
              Bundler::Plugin::API.command "echo", self

              def exec(command, args)
                puts "You gave me \#{args.join(", ")}"
              end
            end
          end
        RUBY
      end
    end

    bundle "plugin install the-echoer --source file://#{gem_repo2}"
    expect(out).to include("Installed plugin the-echoer")

    bundle "echo tacos tofu lasange", "no-color" => false
    expect(out).to eq("You gave me tacos, tofu, lasange")
  end

  it "raises error on redeclaration of command" do
    build_repo2 do
      build_plugin "copycat" do |s|
        s.write "plugins.rb", <<-RUBY
          module CopyCat
            class Cheater < Bundler::Plugin::API
              command "mahcommand", self

              def exec(command, args)
              end
            end
          end
        RUBY
      end
    end

    bundle "plugin install copycat --source file://#{gem_repo2}"

    expect(out).not_to include("Installed plugin copycat")

    expect(out).to include("Failed to install plugin")

    expect(out).to include("Command(s) `mahcommand` declared by copycat are already registered.")
  end
end
