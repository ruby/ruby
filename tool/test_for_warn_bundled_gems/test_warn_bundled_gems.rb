require "bundler"
Bundler::Definition.no_lock = true

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
end

Object.send(:remove_const, :Bundler)

require "mutex_m"
require "rss"
