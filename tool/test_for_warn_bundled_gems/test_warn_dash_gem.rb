require "bundler"
Bundler::Definition.no_lock = true

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
end

require "net/smtp"
