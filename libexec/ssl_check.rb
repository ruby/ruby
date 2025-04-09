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

uri = URI("https://#{host}")

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

def show_ssl_certs
  puts "", "Below affect only Ruby net/http connections:"
  puts
  t = ENV['SSL_CERT_FILE'] || OpenSSL::X509::DEFAULT_CERT_FILE
  ssl_file = File.exist?(t) ? "✅ exists     #{t}" : "❌ is missing #{t}"
  puts "SSL_CERT_FILE: %s" % ssl_file

  t = ENV['SSL_CERT_DIR']  || OpenSSL::X509::DEFAULT_CERT_DIR
  ssl_dir = Dir.exist?(t)   ? "✅ exists     #{t}" : "❌ is missing #{t}"
  puts "SSL_CERT_DIR:  %s" % ssl_dir
  puts
end

def error_reason(error)
  case error.message
  when /certificate verify failed/
    "certificate verification"
  when /read server hello A/
    "SSL/TLS protocol version mismatch"
  when /tlsv1 alert protocol version/
    "requested TLS version is too old"
  else
    error.message
  end
end

puts "Trying connections to #{uri.to_s}:"
puts
begin
  b_uri = defined?(Bundler::URI) ? Bundler::URI(uri.to_s) : uri
  Bundler::Fetcher.new(Bundler::Source::Rubygems::Remote.new(b_uri)).send(:connection).request(b_uri)
  bundler_status = "✅ success"
rescue => error
  bundler_status = "❌ failed     (#{error_reason(error)})"
end
puts "Bundler:       #{bundler_status}"

begin
  require 'rubygems/remote_fetcher'
  Gem::RemoteFetcher.fetcher.fetch_path(uri)
  rubygems_status = "✅ success"
rescue => error
  rubygems_status = "❌ failed     (#{error_reason(error)})"
end
puts "RubyGems:      #{rubygems_status}"

begin
  # Try to connect using HTTPS
  Net::HTTP.new(uri.host, uri.port).tap do |http|
    http.use_ssl = true
    if tls_version
      if http.respond_to? :min_version=
        vers = tls_version.sub("v", "").to_sym
        http.min_version = vers
        http.max_version = vers
      else
        http.ssl_version = tls_version.to_sym
      end
    end
    http.verify_mode = verify_mode
  end.start

  puts "Ruby net/http: ✅ success"
  puts
rescue => error
  puts "Ruby net/http: ❌ failed"
  puts
  puts "Unfortunately, this Ruby can't connect to #{host}. 😡"

  case error.message
  # Check for certificate errors
  when /certificate verify failed/
    show_ssl_certs
    puts "\nYour Ruby can't connect to #{host} because you are missing the certificate",
         "files OpenSSL needs to verify you are connecting to the genuine #{host} servers.", ""
  # Check for TLS version errors
  when /read server hello A/, /tlsv1 alert protocol version/
    if tls_version == "TLSv1_3"
      puts "\nYour Ruby can't connect to #{host} because #{tls_version} isn't supported yet.\n\n"
    else
      puts "\nYour Ruby can't connect to #{host} because your version of OpenSSL is too old.",
           "You'll need to upgrade your OpenSSL install and/or recompile Ruby to use a newer OpenSSL.", ""
    end
  # OpenSSL doesn't support TLS version specified by argument
  when /unknown SSL method/
    puts "\nYour Ruby can't connect because #{tls_version} isn't supported by your version of OpenSSL.\n\n"
  else
    puts "\nEven worse, we're not sure why. 😕"
    puts
    puts "Here's the full error information:",
         "#{error.class}: #{error.message}",
         "  #{error.backtrace.join("\n  ")}"
    puts
    puts "You might have more luck using Mislav's SSL doctor.rb script. You can get it here:",
         "https://github.com/mislav/ssl-tools/blob/8b3dec4/doctor.rb",
         "Read more about the script and how to use it in this blog post:",
         "https://mislav.net/2013/07/ruby-openssl/", ""
  end
  exit 1
end

guide_url = "http://ruby.to/ssl-check-failed"
if bundler_status =~ /success/ && rubygems_status =~ /success/
  # Whoa, it seems like it's working!
  puts "Hooray! This Ruby can connect to #{host}.",
       "You are all set to use Bundler and RubyGems.  👌", ""
elsif rubygems_status !~ /success/
  puts "It looks like Ruby and Bundler can connect to #{host}, but RubyGems itself",
       "cannot. You can likely solve this by manually downloading and installing a",
       "RubyGems update. Visit #{guide_url} for instructions on how to manually upgrade RubyGems. 💎"
elsif bundler_status !~ /success/
  puts "Although your Ruby installation and RubyGems can both connect to #{host},",
       "Bundler is having trouble. The most likely way to fix this is to upgrade",
       "Bundler by running `gem install bundler`. Run this script again after doing",
       "that to make sure everything is all set. If you're still having trouble,",
       "check out the troubleshooting guide at #{guide_url} 📦"
else
  puts "For some reason, your Ruby installation can connect to #{host}, but neither",
       "RubyGems nor Bundler can. The most likely fix is to manually upgrade RubyGems by",
       "following the instructions at #{guide_url}. After you've done that, run `gem install",
       "bundler` to upgrade Bundler, and then run this script again to make sure everything worked. ❣️"
end

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
