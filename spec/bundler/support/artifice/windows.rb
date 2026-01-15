# frozen_string_literal: true

require_relative "../path"

$LOAD_PATH.unshift(*Spec::Path.sinatra_dependency_paths)

require "sinatra/base"

class Windows < Sinatra::Base
  set :raise_errors, true
  set :show_exceptions, false

  helpers do
    def default_gem_repo
      Pathname.new(ENV["BUNDLER_SPEC_GEM_REPO"] || Spec::Path.gem_repo1)
    end
  end

  files = ["specs.4.8.gz",
           "prerelease_specs.4.8.gz",
           "quick/Marshal.4.8/rcov-1.0-mswin32.gemspec.rz",
           "gems/rcov-1.0-mswin32.gem"]

  files.each do |file|
    get "/#{file}" do
      File.binread default_gem_repo.join(file)
    end
  end

  get "/gems/rcov-1.0-x86-mswin32.gem" do
    halt 404
  end

  get "/api/v1/dependencies" do
    halt 404
  end

  get "/versions" do
    halt 500
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(Windows)
