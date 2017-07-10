require 'bundler/vendor/postit/lib/postit/environment'
require 'bundler/vendor/postit/lib/postit/installer'

environment = BundlerVendoredPostIt::PostIt::Environment.new(ARGV)
version = environment.bundler_version

installer = BundlerVendoredPostIt::PostIt::Installer.new(version)
installer.install!

gem 'bundler', version

require 'bundler/version'
