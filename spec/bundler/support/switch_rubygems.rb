# frozen_string_literal: true

require_relative "rubygems_version_manager"
RubygemsVersionManager.new(ENV["RGV"]).switch

if ENV["BUNDLER_SPEC_IGNORE_DEFAULT_BUNDLER_GEM"]
  module NoBundlerStubs
    def default_stubs(pattern = "*.gemspec")
      super(pattern).reject {|s| s.name == "bundler" }
    end
  end

  Gem::Specification.singleton_class.prepend(NoBundlerStubs)
end
