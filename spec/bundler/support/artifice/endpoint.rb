# frozen_string_literal: true
require File.expand_path("../../path.rb", __FILE__)
require Spec::Path.root.join("lib/bundler/deprecate")
include Spec::Path

$LOAD_PATH.unshift(*Dir[Spec::Path.base_system_gems.join("gems/{artifice,rack,tilt,sinatra}-*/lib")].map(&:to_s))
require "artifice"
require "sinatra/base"

class Endpoint < Sinatra::Base
  GEM_REPO = Pathname.new(ENV["BUNDLER_SPEC_GEM_REPO"] || Spec::Path.gem_repo1)
  set :raise_errors, true
  set :show_exceptions, false

  helpers do
    def dependencies_for(gem_names, gem_repo = GEM_REPO)
      return [] if gem_names.nil? || gem_names.empty?

      require "rubygems"
      require "bundler"
      Bundler::Deprecate.skip_during do
        all_specs = %w(specs.4.8 prerelease_specs.4.8).map do |filename|
          Marshal.load(File.open(gem_repo.join(filename)).read)
        end.inject(:+)

        all_specs.map do |name, version, platform|
          spec = load_spec(name, version, platform, gem_repo)
          next unless gem_names.include?(spec.name)
          {
            :name         => spec.name,
            :number       => spec.version.version,
            :platform     => spec.platform.to_s,
            :dependencies => spec.dependencies.select {|dep| dep.type == :runtime }.map do |dep|
              [dep.name, dep.requirement.requirements.map {|a| a.join(" ") }.join(", ")]
            end
          }
        end.compact
      end
    end

    def load_spec(name, version, platform, gem_repo)
      full_name = "#{name}-#{version}"
      full_name += "-#{platform}" if platform != "ruby"
      Marshal.load(Gem.inflate(File.open(gem_repo.join("quick/Marshal.4.8/#{full_name}.gemspec.rz")).read))
    end
  end

  get "/quick/Marshal.4.8/:id" do
    redirect "/fetch/actual/gem/#{params[:id]}"
  end

  get "/fetch/actual/gem/:id" do
    File.read("#{GEM_REPO}/quick/Marshal.4.8/#{params[:id]}")
  end

  get "/gems/:id" do
    File.read("#{GEM_REPO}/gems/#{params[:id]}")
  end

  get "/api/v1/dependencies" do
    Marshal.dump(dependencies_for(params[:gems]))
  end

  get "/specs.4.8.gz" do
    File.read("#{GEM_REPO}/specs.4.8.gz")
  end

  get "/prerelease_specs.4.8.gz" do
    File.read("#{GEM_REPO}/prerelease_specs.4.8.gz")
  end
end

Artifice.activate_with(Endpoint)
