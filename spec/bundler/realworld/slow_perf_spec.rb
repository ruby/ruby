# frozen_string_literal: true

require "spec_helper"

RSpec.describe "bundle install with complex dependencies", :realworld => true do
  it "resolves quickly" do
    gemfile <<-G
      source 'https://rubygems.org'

      gem "actionmailer"
      gem "mongoid", ">= 0.10.2"
    G

    expect { bundle "lock" }.to take_less_than(18) # seconds
  end

  it "resolves quickly (case 2)" do
    gemfile <<-G
      source "https://rubygems.org"

      gem 'metasploit-erd'
      gem 'rails-erd'
      gem 'yard'

      gem 'coveralls'
      gem 'rails'
      gem 'simplecov'
      gem 'rspec-rails'
    G

    expect { bundle "lock" }.to take_less_than(18) # seconds
  end
end
