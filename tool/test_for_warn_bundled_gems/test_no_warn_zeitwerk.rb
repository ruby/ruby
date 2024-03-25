require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "zeitwerk", require: false
end

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem(warn_on_extra_files: false)
loader.setup

require 'csv'
