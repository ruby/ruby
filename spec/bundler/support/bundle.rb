# frozen_string_literal: true

require "rubygems"
require_relative "path"
bundler_gemspec = Spec::Path.loaded_gemspec
bundler_gemspec.instance_variable_set(:@full_gem_path, Spec::Path.source_root)
bundler_gemspec.activate if bundler_gemspec.respond_to?(:activate)
load File.expand_path("bundle", Spec::Path.bindir)
