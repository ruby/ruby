require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "bootsnap", require: false
end

require 'bootsnap'
Bootsnap.setup(cache_dir: 'tmp/cache')

require 'csv'
