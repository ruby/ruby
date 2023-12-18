require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "net-smtp"
end

require "net/smtp"
