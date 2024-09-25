require "bundler"
Bundler::Definition.no_lock = true

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "bigdecimal"
end

require "bigdecimal/util"
