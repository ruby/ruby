# frozen_string_literal: true

source "https://rubygems.org"

gem "rack", "~> 2.0"
gem "webrick", "1.7.0"
gem "rack-test", "~> 1.1"
gem "artifice", "~> 0.6.0"
gem "compact_index", "~> 0.13.0"
gem "sinatra", "~> 2.0"
# for Ruby 2.6. bundler/spec/install/gemfile/sources_spec.rb is failed with sinatra-2.0.8.1 and tilt-2.2.0.
gem "tilt", "~> 2.0.11"
gem "rake", "13.0.1"
gem "builder", "~> 3.2"
