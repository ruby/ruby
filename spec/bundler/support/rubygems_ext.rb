# frozen_string_literal: true

require_relative "path"

module Spec
  module Rubygems
    DEV_DEPS = {
      "automatiek" => "~> 0.3.0",
      "parallel_tests" => "~> 2.29",
      "rake" => "~> 12.0",
      "ronn" => "~> 0.7.3",
      "rspec" => "~> 3.8",
      "rubocop" => "= 0.77.0",
      "rubocop-performance" => "= 1.5.1",
    }.freeze

    DEPS = {
      "rack" => "~> 2.0",
      "rack-test" => "~> 1.1",
      "artifice" => "~> 0.6.0",
      "compact_index" => "~> 0.11.0",
      "sinatra" => "~> 2.0",
      # Rake version has to be consistent for tests to pass
      "rake" => "12.3.2",
      "builder" => "~> 3.2",
      # ruby-graphviz is used by the viz tests
      "ruby-graphviz" => ">= 0.a",
    }.freeze

    extend self

    def dev_setup
      deps = DEV_DEPS

      # JRuby can't build ronn, so we skip that
      deps.delete("ronn") if RUBY_ENGINE == "jruby"

      install_gems(deps)
    end

    def gem_load(gem_name, bin_container)
      require_relative "rubygems_version_manager"
      RubygemsVersionManager.new(ENV["RGV"]).switch

      gem_load_and_activate(gem_name, bin_container)
    end

    def gem_require(gem_name)
      gem_activate(gem_name)
      require gem_name
    end

    def setup
      require "fileutils"

      Gem.clear_paths

      ENV["BUNDLE_PATH"] = nil
      ENV["GEM_HOME"] = ENV["GEM_PATH"] = Path.base_system_gems.to_s
      ENV["PATH"] = [Path.bindir, Path.system_gem_path.join("bin"), ENV["PATH"]].join(File::PATH_SEPARATOR)

      manifest = DEPS.to_a.sort_by(&:first).map {|k, v| "#{k} => #{v}\n" }
      manifest_path = Path.base_system_gems.join("manifest.txt")
      # it's OK if there are extra gems
      if !manifest_path.file? || !(manifest - manifest_path.readlines).empty?
        FileUtils.rm_rf(Path.base_system_gems)
        FileUtils.mkdir_p(Path.base_system_gems)
        puts "installing gems for the tests to use..."
        install_gems(DEPS)
        manifest_path.open("wb") {|f| f << manifest.join }
      end

      FileUtils.mkdir_p(Path.home)
      FileUtils.mkdir_p(Path.tmpdir)

      ENV["HOME"] = Path.home.to_s
      ENV["TMPDIR"] = Path.tmpdir.to_s

      require "rubygems/user_interaction"
      Gem::DefaultUserInteraction.ui = Gem::SilentUI.new
    end

  private

    def gem_load_and_activate(gem_name, bin_container)
      gem_activate(gem_name)
      load Gem.bin_path(gem_name, bin_container)
    rescue Gem::LoadError => e
      abort "We couln't activate #{gem_name} (#{e.requirement}). Run `gem install #{gem_name}:'#{e.requirement}'`"
    end

    def gem_activate(gem_name)
      gem_requirement = DEV_DEPS[gem_name]
      gem gem_name, gem_requirement
    end

    def install_gems(gems)
      reqs, no_reqs = gems.partition {|_, req| !req.nil? && !req.split(" ").empty? }
      no_reqs.map!(&:first)
      reqs.map! {|name, req| "'#{name}:#{req}'" }
      deps = reqs.concat(no_reqs).join(" ")
      gem = ENV["GEM_COMMAND"] || "#{Gem.ruby} -S gem --backtrace"
      cmd = "#{gem} install #{deps} --no-document --conservative"
      system(cmd) || raise("Installing gems #{deps} for the tests to use failed!")
    end
  end
end
