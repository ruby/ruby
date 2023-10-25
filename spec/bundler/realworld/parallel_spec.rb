# frozen_string_literal: true

RSpec.describe "parallel", :realworld => true do
  it "installs" do
    gemfile <<-G
      source "https://rubygems.org"
      gem 'activesupport', '~> 3.2.13'
      gem 'faker', '~> 1.1.2'
      gem 'i18n', '~> 0.6.0' # Because 0.7+ requires Ruby 1.9.3+
    G

    bundle :install, :jobs => 4, :env => { "DEBUG" => "1" }

    expect(out).to match(/[1-3]: /)

    bundle "info activesupport --path"
    expect(out).to match(/activesupport/)

    bundle "info faker --path"
    expect(out).to match(/faker/)
  end

  it "updates" do
    install_gemfile <<-G
      source "https://rubygems.org"
      gem 'activesupport', '3.2.12'
      gem 'faker', '~> 1.1.2'
    G

    gemfile <<-G
      source "https://rubygems.org"
      gem 'activesupport', '~> 3.2.12'
      gem 'faker', '~> 1.1.2'
      gem 'i18n', '~> 0.6.0' # Because 0.7+ requires Ruby 1.9.3+
    G

    bundle :update, :jobs => 4, :env => { "DEBUG" => "1" }, :all => true

    expect(out).to match(/[1-3]: /)

    bundle "info activesupport --path"
    expect(out).to match(/activesupport-3\.2\.\d+/)

    bundle "info faker --path"
    expect(out).to match(/faker/)
  end

  it "works with --standalone" do
    gemfile <<-G
      source "https://rubygems.org"
      gem "diff-lcs"
    G

    bundle :install, :standalone => true, :jobs => 4

    ruby <<-RUBY
      $:.unshift File.expand_path("bundle")
      require "bundler/setup"

      require "diff/lcs"
      puts Diff::LCS
    RUBY

    expect(out).to eq("Diff::LCS")
  end
end
