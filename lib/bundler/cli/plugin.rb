# frozen_string_literal: true

require "bundler/vendored_thor"
module Bundler
  class CLI::Plugin < Thor
    desc "install PLUGINS", "Install the plugin from the source"
    long_desc <<-D
      Install plugins either from the rubygems source provided (with --source option) or from a git source provided with (--git option). If no sources are provided, it uses Gem.sources
   D
    method_option "source", :type => :string, :default => nil, :banner =>
      "URL of the RubyGems source to fetch the plugin from"
    method_option "version", :type => :string, :default => nil, :banner =>
      "The version of the plugin to fetch"
    method_option "git", :type => :string, :default => nil, :banner =>
      "URL of the git repo to fetch from"
    method_option "branch", :type => :string, :default => nil, :banner =>
      "The git branch to checkout"
    method_option "ref", :type => :string, :default => nil, :banner =>
      "The git revision to check out"
    def install(*plugins)
      Bundler::Plugin.install(plugins, options)
    end
  end
end
