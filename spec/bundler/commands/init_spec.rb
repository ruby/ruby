# frozen_string_literal: true
require "spec_helper"

describe "bundle init" do
  it "generates a Gemfile" do
    bundle :init
    expect(bundled_app("Gemfile")).to exist
  end

  it "does not change existing Gemfiles" do
    gemfile <<-G
      gem "rails"
    G

    expect do
      bundle :init
    end.not_to change { File.read(bundled_app("Gemfile")) }
  end

  it "should generate from an existing gemspec" do
    spec_file = tmp.join("test.gemspec")
    File.open(spec_file, "w") do |file|
      file << <<-S
        Gem::Specification.new do |s|
        s.name = 'test'
        s.add_dependency 'rack', '= 1.0.1'
        s.add_development_dependency 'rspec', '1.2'
        end
      S
    end

    bundle :init, :gemspec => spec_file

    gemfile = bundled_app("Gemfile").read
    expect(gemfile).to match(%r{source 'https://rubygems.org'})
    expect(gemfile.scan(/gem "rack", "= 1.0.1"/).size).to eq(1)
    expect(gemfile.scan(/gem "rspec", "= 1.2"/).size).to eq(1)
    expect(gemfile.scan(/group :development/).size).to eq(1)
  end
end
