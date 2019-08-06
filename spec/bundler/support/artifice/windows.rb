# frozen_string_literal: true

require File.expand_path("../../path.rb", __FILE__)
include Spec::Path

$LOAD_PATH.unshift(*Dir[Spec::Path.base_system_gems.join("gems/{artifice,mustermann,rack,tilt,sinatra}-*/lib")].map(&:to_s))

require "artifice"
require "sinatra/base"

Artifice.deactivate

class Windows < Sinatra::Base
  set :raise_errors, true
  set :show_exceptions, false

  helpers do
    def gem_repo
      Pathname.new(ENV["BUNDLER_SPEC_GEM_REPO"] || Spec::Path.gem_repo1)
    end
  end

  files = ["specs.4.8.gz",
           "prerelease_specs.4.8.gz",
           "quick/Marshal.4.8/rcov-1.0-mswin32.gemspec.rz",
           "gems/rcov-1.0-mswin32.gem"]

  files.each do |file|
    get "/#{file}" do
      File.read gem_repo.join(file)
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

Artifice.activate_with(Windows)
