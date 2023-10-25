# frozen_string_literal: true

RSpec.describe "github source", :realworld => true do
  it "properly fetches PRs" do
    install_gemfile <<-G
      source "https://rubygems.org"

      gem "reline", github: "https://github.com/ruby/reline/pull/488"
    G
  end
end
