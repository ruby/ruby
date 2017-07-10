require 'bundler/vendor/postit/lib/postit/environment'
require 'bundler/vendor/postit/lib/postit/installer'
require 'bundler/vendor/postit/lib/postit/parser'
require 'bundler/vendor/postit/lib/postit/version'
require 'rubygems'

module BundlerVendoredPostIt::PostIt
  def self.setup
    load File.expand_path('../postit/setup.rb', __FILE__)
  end

  def self.bundler_version
    defined?(Bundler::VERSION) && Bundler::VERSION
  end
end
