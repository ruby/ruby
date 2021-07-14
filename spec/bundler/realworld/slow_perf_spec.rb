# frozen_string_literal: true

require "spec_helper"

RSpec.describe "bundle install with complex dependencies", :realworld => true do
  it "resolves quickly" do
    gemfile <<-G
      source 'https://rubygems.org'

      gem "actionmailer"
      gem "mongoid", ">= 0.10.2"
    G

    start_time = Time.now

    bundle "lock"

    duration = Time.now - start_time

    expect(duration.to_f).to be < 12 # seconds
  end
end
