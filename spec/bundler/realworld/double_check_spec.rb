# frozen_string_literal: true

RSpec.describe "double checking sources", :realworld => true do
  if RUBY_VERSION >= "2.2" # rails 5.x and rack 2.x only supports >= Ruby 2.2.
    it "finds already-installed gems" do
      create_file("rails.gemspec", <<-RUBY)
        Gem::Specification.new do |s|
          s.name        = "rails"
          s.version     = "5.1.4"
          s.summary     = ""
          s.description = ""
          s.author      = ""
          s.add_dependency "actionpack", "5.1.4"
        end
      RUBY

      create_file("actionpack.gemspec", <<-RUBY)
        Gem::Specification.new do |s|
          s.name        = "actionpack"
          s.version     = "5.1.4"
          s.summary     = ""
          s.description = ""
          s.author      = ""
          s.add_dependency "rack", "~> 2.0.0"
        end
      RUBY

      cmd = <<-RUBY
        require "bundler"
        require #{File.expand_path("../../support/artifice/vcr.rb", __FILE__).dump}
        require "bundler/inline"
        gemfile(true) do
          source "https://rubygems.org"
          gem "rails", path: "."
        end
      RUBY

      ruby! cmd
      ruby! cmd
    end
  end
end
