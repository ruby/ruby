# frozen_string_literal: true

require_relative "../../path"

$LOAD_PATH.unshift(*Dir[Spec::Path.base_system_gem_path.join("gems/{mustermann,rack,tilt,sinatra,ruby2_keywords,base64}-*/lib")].map(&:to_s))

require "sinatra/base"

ALL_REQUESTS = [] # rubocop:disable Style/MutableConstant
ALL_REQUESTS_MUTEX = Thread::Mutex.new

at_exit do
  if expected = ENV["BUNDLER_SPEC_ALL_REQUESTS"]
    expected = expected.split("\n").sort
    actual = ALL_REQUESTS.sort

    unless expected == actual
      raise "Unexpected requests!\nExpected:\n\t#{expected.join("\n\t")}\n\nActual:\n\t#{actual.join("\n\t")}"
    end
  end
end

class Endpoint < Sinatra::Base
  def self.all_requests
    @all_requests ||= []
  end

  set :raise_errors, true
  set :show_exceptions, false
  set :host_authorization, permitted_hosts: [".example.org", ".local", ".repo", ".repo1", ".repo2", ".repo3", ".repo4", ".rubygems.org", ".security", ".source", ".test", "127.0.0.1"]

  def call!(*)
    super.tap do
      ALL_REQUESTS_MUTEX.synchronize do
        ALL_REQUESTS << @request.url
      end
    end
  end

  helpers do
    include Spec::Path

    def default_gem_repo
      if ENV["BUNDLER_SPEC_GEM_REPO"]
        Pathname.new(ENV["BUNDLER_SPEC_GEM_REPO"])
      else
        case request.host
        when "gem.repo1"
          Spec::Path.gem_repo1
        when "gem.repo2"
          Spec::Path.gem_repo2
        when "gem.repo3"
          Spec::Path.gem_repo3
        when "gem.repo4"
          Spec::Path.gem_repo4
        else
          Spec::Path.gem_repo1
        end
      end
    end

    def dependencies_for(gem_names, gem_repo = default_gem_repo)
      return [] if gem_names.nil? || gem_names.empty?

      all_specs = %w[specs.4.8 prerelease_specs.4.8].map do |filename|
        Marshal.load(File.binread(gem_repo.join(filename)))
      end.inject(:+)

      all_specs.filter_map do |name, version, platform|
        spec = load_spec(name, version, platform, gem_repo)
        next unless gem_names.include?(spec.name)
        {
          name: spec.name,
          number: spec.version.version,
          platform: spec.platform.to_s,
          dependencies: spec.runtime_dependencies.map do |dep|
            [dep.name, dep.requirement.requirements.map {|a| a.join(" ") }.join(", ")]
          end,
        }
      end
    end

    def load_spec(name, version, platform, gem_repo)
      full_name = "#{name}-#{version}"
      full_name += "-#{platform}" if platform != "ruby"
      Marshal.load(Bundler.rubygems.inflate(File.binread(gem_repo.join("quick/Marshal.4.8/#{full_name}.gemspec.rz"))))
    end
  end

  get "/quick/Marshal.4.8/:id" do
    redirect "/fetch/actual/gem/#{params[:id]}"
  end

  get "/fetch/actual/gem/:id" do
    File.binread("#{default_gem_repo}/quick/Marshal.4.8/#{params[:id]}")
  end

  get "/gems/:id" do
    File.binread("#{default_gem_repo}/gems/#{params[:id]}")
  end

  get "/api/v1/dependencies" do
    Marshal.dump(dependencies_for(params[:gems]))
  end

  get "/specs.4.8.gz" do
    File.binread("#{default_gem_repo}/specs.4.8.gz")
  end

  get "/prerelease_specs.4.8.gz" do
    File.binread("#{default_gem_repo}/prerelease_specs.4.8.gz")
  end
end
