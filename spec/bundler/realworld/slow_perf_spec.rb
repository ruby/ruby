# frozen_string_literal: true

require "spec_helper"

RSpec.describe "bundle install with complex dependencies", :realworld => true do
  it "resolves quickly" do
    start_time = Time.now

    install_gemfile <<-G
      source 'https://rubygems.org'

      gem "actionmailer"
      gem "mongoid", ">= 0.10.2"
    G

    duration = Time.now - start_time

    expect(duration.to_f).to be < 120 # seconds
  end
end
