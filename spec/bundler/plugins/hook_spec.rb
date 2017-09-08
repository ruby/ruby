# frozen_string_literal: true
require "spec_helper"

RSpec.describe "hook plugins" do
  before do
    build_repo2 do
      build_plugin "before-install-plugin" do |s|
        s.write "plugins.rb", <<-RUBY
          Bundler::Plugin::API.hook "before-install-all" do |deps|
            puts "gems to be installed \#{deps.map(&:name).join(", ")}"
          end
        RUBY
      end
    end

    bundle "plugin install before-install-plugin --source file://#{gem_repo2}"
  end

  it "runs after a rubygem is installed" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rake"
      gem "rack"
    G

    expect(out).to include "gems to be installed rake, rack"
  end
end
