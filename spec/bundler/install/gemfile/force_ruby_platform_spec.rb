# frozen_string_literal: true

RSpec.describe "bundle install with force_ruby_platform DSL option", :jruby do
  context "when no transitive deps" do
    before do
      build_repo4 do
        # Build a gem with platform specific versions
        build_gem("platform_specific") do |s|
          s.write "lib/platform_specific.rb", "PLATFORM_SPECIFIC = '1.0.0 RUBY'"
        end

        build_gem("platform_specific") do |s|
          s.platform = Bundler.local_platform
          s.write "lib/platform_specific.rb", "PLATFORM_SPECIFIC = '1.0.0 #{Bundler.local_platform}'"
        end

        # Build the exact same gem with a different name to compare using vs not using the option
        build_gem("platform_specific_forced") do |s|
          s.write "lib/platform_specific_forced.rb", "PLATFORM_SPECIFIC_FORCED = '1.0.0 RUBY'"
        end

        build_gem("platform_specific_forced") do |s|
          s.platform = Bundler.local_platform
          s.write "lib/platform_specific_forced.rb", "PLATFORM_SPECIFIC_FORCED = '1.0.0 #{Bundler.local_platform}'"
        end
      end
    end

    it "pulls the pure ruby variant of the given gem" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"

        gem "platform_specific_forced", :force_ruby_platform => true
        gem "platform_specific"
      G

      expect(the_bundle).to include_gems "platform_specific_forced 1.0.0 RUBY"
      expect(the_bundle).to include_gems "platform_specific 1.0.0 #{Bundler.local_platform}"
    end

    it "still respects a global `force_ruby_platform` config" do
      install_gemfile <<-G, :env => { "BUNDLE_FORCE_RUBY_PLATFORM" => "true" }
        source "#{file_uri_for(gem_repo4)}"

        gem "platform_specific_forced", :force_ruby_platform => true
        gem "platform_specific"
      G

      expect(the_bundle).to include_gems "platform_specific_forced 1.0.0 RUBY"
      expect(the_bundle).to include_gems "platform_specific 1.0.0 RUBY"
    end
  end

  context "when also a transitive dependency" do
    before do
      build_repo4 do
        build_gem("depends_on_platform_specific") {|s| s.add_runtime_dependency "platform_specific" }

        build_gem("platform_specific") do |s|
          s.write "lib/platform_specific.rb", "PLATFORM_SPECIFIC = '1.0.0 RUBY'"
        end

        build_gem("platform_specific") do |s|
          s.platform = Bundler.local_platform
          s.write "lib/platform_specific.rb", "PLATFORM_SPECIFIC = '1.0.0 #{Bundler.local_platform}'"
        end
      end
    end

    it "still pulls the ruby variant" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"

        gem "depends_on_platform_specific"
        gem "platform_specific", :force_ruby_platform => true
      G

      expect(the_bundle).to include_gems "platform_specific 1.0.0 RUBY"
    end
  end

  context "with transitive dependencies with platform specific versions" do
    before do
      build_repo4 do
        build_gem("depends_on_platform_specific") do |s|
          s.add_runtime_dependency "platform_specific"
          s.write "lib/depends_on_platform_specific.rb", "DEPENDS_ON_PLATFORM_SPECIFIC = '1.0.0 RUBY'"
        end

        build_gem("depends_on_platform_specific") do |s|
          s.add_runtime_dependency "platform_specific"
          s.platform = Bundler.local_platform
          s.write "lib/depends_on_platform_specific.rb", "DEPENDS_ON_PLATFORM_SPECIFIC = '1.0.0 #{Bundler.local_platform}'"
        end

        build_gem("platform_specific") do |s|
          s.write "lib/platform_specific.rb", "PLATFORM_SPECIFIC = '1.0.0 RUBY'"
        end

        build_gem("platform_specific") do |s|
          s.platform = Bundler.local_platform
          s.write "lib/platform_specific.rb", "PLATFORM_SPECIFIC = '1.0.0 #{Bundler.local_platform}'"
        end
      end
    end

    it "ignores ruby variants for the transitive dependencies" do
      install_gemfile <<-G, :env => { "DEBUG_RESOLVER" => "true" }
        source "#{file_uri_for(gem_repo4)}"

        gem "depends_on_platform_specific", :force_ruby_platform => true
      G

      expect(the_bundle).to include_gems "depends_on_platform_specific 1.0.0 RUBY"
      expect(the_bundle).to include_gems "platform_specific 1.0.0 #{Bundler.local_platform}"
    end

    it "reinstalls the ruby variant when a platform specific variant is already installed, the lockile has only RUBY platform, and :force_ruby_platform is used in the Gemfile" do
      lockfile <<-L
        GEM
          remote: #{file_uri_for(gem_repo4)}
          specs:
            platform_specific (1.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          platform_specific

        BUNDLED WITH
            #{Bundler::VERSION}
      L

      system_gems "platform_specific-1.0-#{Gem::Platform.local}", :path => default_bundle_path

      install_gemfile <<-G, :env => { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }, :artifice => "compact_index"
        source "#{file_uri_for(gem_repo4)}"

        gem "platform_specific", :force_ruby_platform => true
      G

      expect(the_bundle).to include_gems "platform_specific 1.0.0 RUBY"
    end
  end
end
