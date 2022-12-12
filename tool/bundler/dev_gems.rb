# frozen_string_literal: true

source "https://rubygems.org"

gem "test-unit", "~> 3.0"
gem "rake", "~> 13.0"

gem "webrick", "~> 1.6"
gem "parallel_tests", "~> 2.29"
gem "parallel", "~> 1.19"
gem "rspec-core", "~> 3.12"
gem "rspec-expectations", "~> 3.12"
gem "rspec-mocks", "~> 3.12"
gem "uri", "~> 0.12.0"

group :doc do
  gem "ronn", "~> 0.7.3", :platform => :ruby
end
