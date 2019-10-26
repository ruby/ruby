require_relative '../../../spec_helper'
require 'rubygems'

describe "Gem.bin_path" do
  before :each do
    @bundle_gemfile = ENV['BUNDLE_GEMFILE']
    ENV['BUNDLE_GEMFILE'] = tmp("no-gemfile")
  end

  after :each do
    ENV['BUNDLE_GEMFILE'] = @bundle_gemfile
  end

  platform_is_not :windows do
    it "finds executables of default gems, which are the only files shipped for default gems" do
      # For instance, Gem.bin_path("bundler", "bundle") is used by rails new

      if Gem.respond_to? :default_specifications_dir
        default_specifications_dir = Gem.default_specifications_dir
      else
        default_specifications_dir = Gem::Specification.default_specifications_dir
      end

      skip "Could not find the default gemspecs" unless Dir.exist?(default_specifications_dir)

      Gem::Specification.each_spec([default_specifications_dir]) do |spec|
        spec.executables.each do |exe|
          path = Gem.bin_path(spec.name, exe)
          File.should.exist?(path)
        end
      end
    end
  end
end
