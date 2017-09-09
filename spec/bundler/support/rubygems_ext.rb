# frozen_string_literal: true
require "rubygems/user_interaction"
require "support/path" unless defined?(Spec::Path)

module Spec
  module Rubygems
    DEPS = begin
      deps = {
        # rack 2.x requires Ruby version >= 2.2.2.
        # artifice doesn't support rack 2.x now.
        "rack" => "< 2",
        # rack-test 0.7.0 dropped 1.8.7 support
        # https://github.com/rack-test/rack-test/issues/193#issuecomment-314230318
        "rack-test" => "< 0.7.0",
        "artifice" => "~> 0.6.0",
        "compact_index" => "~> 0.11.0",
        "sinatra" => "~> 1.4.7",
        # Rake version has to be consistent for tests to pass
        "rake" => "10.0.2",
        # 3.0.0 breaks 1.9.2 specs
        "builder" => "2.1.2",
        "bundler" => "1.12.0",
      }
      # ruby-graphviz is used by the viz tests
      deps["ruby-graphviz"] = nil if RUBY_VERSION >= "1.9.3"
      deps
    end

    def self.setup
      Gem.clear_paths

      ENV["BUNDLE_PATH"] = nil
      ENV["GEM_HOME"] = ENV["GEM_PATH"] = Path.base_system_gems.to_s
      ENV["PATH"] = [Path.bindir, "#{Path.system_gem_path}/bin", ENV["PATH"]].join(File::PATH_SEPARATOR)

      manifest = DEPS.to_a.sort_by(&:first).map {|k, v| "#{k} => #{v}\n" }
      manifest_path = "#{Path.base_system_gems}/manifest.txt"
      # it's OK if there are extra gems
      if !File.exist?(manifest_path) || !(manifest - File.readlines(manifest_path)).empty?
        FileUtils.rm_rf(Path.base_system_gems)
        FileUtils.mkdir_p(Path.base_system_gems)
        puts "installing gems for the tests to use..."
        install_gems(DEPS)
        File.open(manifest_path, "w") {|f| f << manifest.join }
      end

      ENV["HOME"] = Path.home.to_s
      ENV["TMPDIR"] = Path.tmpdir.to_s

      Gem::DefaultUserInteraction.ui = Gem::SilentUI.new
    end

    def self.install_gems(gems)
      reqs, no_reqs = gems.partition {|_, req| !req.nil? && !req.split(" ").empty? }
      reqs = reqs.sort_by {|name, _| name == "rack" ? 0 : 1 } # TODO: remove when we drop ruby 1.8.7 support
      no_reqs.map!(&:first)
      reqs.map! {|name, req| "'#{name}:#{req}'" }
      deps = reqs.concat(no_reqs).join(" ")
      cmd = "#{ENV['BUNDLE_GEM'] || 'gem'} install #{deps} --no-rdoc --no-ri --conservative"
      puts cmd
      system(cmd) || raise("Installing gems #{deps} for the tests to use failed!")
    end
  end
end
