# frozen_string_literal: true

source "https://rubygems.org"

gem "rdoc", "6.2.0" # 6.2.1 is required > Ruby 2.3
gem "test-unit", "~> 3.0"
gem "rake", "~> 13.0"

gem "webrick", "~> 1.6"
gem "parallel_tests", "~> 2.29"
gem "parallel", "1.19.2" # 1.20+ is required > Ruby 2.3
gem "rspec-core", "~> 3.8"
gem "rspec-expectations", "~> 3.8"
gem "rspec-mocks", "~> 3.11.1"
gem "uri", "~> 0.10.1"

group :doc do
  gem "ronn", "~> 0.7.3", :platform => :ruby
end
