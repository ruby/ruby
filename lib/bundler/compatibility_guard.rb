# frozen_string_literal: false

require "bundler/version"

if Bundler::VERSION.split(".").first.to_i >= 2
  if Gem::Version.new(Object::RUBY_VERSION.dup) < Gem::Version.new("2.3")
    abort "Bundler 2 requires Ruby 2.3 or later. Either install bundler 1 or update to a supported Ruby version."
  end
end
