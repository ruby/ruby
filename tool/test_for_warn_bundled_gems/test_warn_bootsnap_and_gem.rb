require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "bootsnap", require: false
  gem "childprocess", "5.0.0", require: false # Has undeclared logger dependency
end

ENV["BOOTSNAP_CACHE_DIR"] ||= "tmp/cache/bootsnap"
require "bootsnap/setup"
require "childprocess"
