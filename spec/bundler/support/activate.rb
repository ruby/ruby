# frozen_string_literal: true

require "rubygems"
Gem.instance_variable_set(:@ruby, ENV["RUBY"]) if ENV["RUBY"]

require_relative "path"
bundler_gemspec = Spec::Path.loaded_gemspec
bundler_gemspec.instance_variable_set(:@full_gem_path, Spec::Path.source_root.to_s)
bundler_gemspec.activate if bundler_gemspec.respond_to?(:activate)
