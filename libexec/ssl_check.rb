#!/usr/bin/env ruby
# Encoding: utf-8

require 'uri'
require 'net/http'

begin
  # Some versions of Ruby need this require to do HTTPS
  require 'net/https'
  # Try for RubyGems version
  require 'rubygems'
  # Try for Bundler version
  require 'bundler'
  require 'bundler/vendor/uri/lib/uri'
rescue LoadError
end

if defined?(RUBY_DESCRIPTION)
  ruby_version = RUBY_DESCRIPTION
else
  ruby_version = RUBY_VERSION.dup
  ruby_version << "p#{RUBY_PATCHLEVEL}" if defined?(RUBY_PATCHLEVEL)
  ruby_version << " (#{RUBY_RELEASE_DATE} revision #{RUBY_REVISION})"
  ruby_version << " [#{RUBY_PLATFORM}]"
end

puts "", "Here's your Ruby and OpenSSL environment:"
puts
puts "Ruby:          %s" % ruby_version
puts "RubyGems:      %s" % Gem::VERSION if defined?(Gem::VERSION)
puts "Bundler:       %s" % Bundler::VERSION if defined?(Bundler::VERSION)

def tls12_supported?
  ctx = OpenSSL::SSL::SSLContext.new
  if ctx.methods.include?(:min_version=)
    ctx.min_version = ctx.max_version = OpenSSL::SSL::TLS1_2_VERSION
    true
  else
    OpenSSL::SSL::SSLContext::METHODS.include?(:TLSv1_2)
  end
rescue
end

# We were able to connect, but perhaps this Ruby will have trouble when we require TLSv1.2
unless tls12_supported?
  puts "\nWARNING: Although your Ruby can connect to #{host} today, your OpenSSL is very old! 👴",
         "WARNING: You will need to upgrade OpenSSL to use #{host}."
  exit 1
end

exit 0
