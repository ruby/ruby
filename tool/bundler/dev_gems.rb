# frozen_string_literal: true

source "https://rubygems.org"

gem "test-unit", "~> 3.0"
gem "rake", "~> 13.1"
gem "rb_sys"

gem "webrick", "~> 1.6"
gem "turbo_tests", "~> 2.1"
gem "parallel_tests", "< 3.9.0"
gem "parallel", "~> 1.19"
gem "rspec-core", "~> 3.12"
gem "rspec-expectations", "~> 3.12"
gem "rspec-mocks", "~> 3.12"
gem "uri", "~> 0.12.0"

group :doc do
  gem "nronn", "~> 0.11.1", platform: :ruby
end
