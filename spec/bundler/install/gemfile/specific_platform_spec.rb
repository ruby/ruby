# frozen_string_literal: true

RSpec.describe "bundle install with specific platforms" do
  let(:google_protobuf) { <<-G }
    source "#{file_uri_for(gem_repo2)}"
    gem "google-protobuf"
  G

  context "when on a darwin machine" do
    before { simulate_platform "x86_64-darwin-15" }

    it "locks to the specific darwin platform" do
      setup_multiplatform_gem
      install_gemfile(google_protobuf)
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      expect(the_bundle.locked_gems.platforms).to eq([pl("x86_64-darwin-15")])
      expect(the_bundle).to include_gem("google-protobuf 3.0.0.alpha.5.0.5.1 universal-darwin")
      expect(the_bundle.locked_gems.specs.map(&:full_name)).to eq(%w[
        google-protobuf-3.0.0.alpha.5.0.5.1-universal-darwin
      ])
    end

    it "understands that a non-platform specific gem in a old lockfile doesn't necessarily mean installing the non-specific variant" do
      setup_multiplatform_gem

      system_gems "bundler-2.1.4"

      # Consistent location to install and look for gems
      bundle "config set --local path vendor/bundle", :env => { "BUNDLER_VERSION" => "2.1.4" }

      install_gemfile(google_protobuf, :env => { "BUNDLER_VERSION" => "2.1.4" })

      # simulate lockfile created with old bundler, which only locks for ruby platform
      lockfile <<-L
        GEM
          remote: #{file_uri_for(gem_repo2)}/
          specs:
            google-protobuf (3.0.0.alpha.5.0.5.1)

        PLATFORMS
          ruby

        DEPENDENCIES
          google-protobuf

        BUNDLED WITH
           2.1.4
      L

      # force strict usage of the lock file by setting frozen mode
      bundle "config set --local frozen true", :env => { "BUNDLER_VERSION" => "2.1.4" }

      # make sure the platform that got actually installed with the old bundler is used
      expect(the_bundle).to include_gem("google-protobuf 3.0.0.alpha.5.0.5.1 universal-darwin")
    end

    it "understands that a non-platform specific gem in a new lockfile locked only to RUBY doesn't necessarily mean installing the non-specific variant" do
      setup_multiplatform_gem

      system_gems "bundler-2.1.4"

      # Consistent location to install and look for gems
      bundle "config set --local path vendor/bundle", :env => { "BUNDLER_VERSION" => "2.1.4" }

      gemfile google_protobuf

      # simulate lockfile created with old bundler, which only locks for ruby platform
      lockfile <<-L
        GEM
          remote: #{file_uri_for(gem_repo2)}/
          specs:
            google-protobuf (3.0.0.alpha.4.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          google-protobuf

        BUNDLED WITH
           2.1.4
      L

      bundle "update", :env => { "BUNDLER_VERSION" => Bundler::VERSION }

      # make sure the platform that the platform specific dependency is used, since we're only locked to ruby
      expect(the_bundle).to include_gem("google-protobuf 3.0.0.alpha.5.0.5.1 universal-darwin")

      # make sure we're still only locked to ruby
      expect(lockfile).to eq <<~L
        GEM
          remote: #{file_uri_for(gem_repo2)}/
          specs:
            google-protobuf (3.0.0.alpha.5.0.5.1)

        PLATFORMS
          ruby

        DEPENDENCIES
          google-protobuf

        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end

    context "when running on a legacy lockfile locked only to RUBY" do
      around do |example|
        build_repo4 do
          build_gem "nokogiri", "1.3.10"
          build_gem "nokogiri", "1.3.10" do |s|
            s.platform = "arm64-darwin"
            s.required_ruby_version = "< #{Gem.ruby_version}"
          end

          build_gem "bundler", "2.1.4"
        end

        gemfile <<~G
        source "#{file_uri_for(gem_repo4)}"

        gem "nokogiri"
        G

        lockfile <<-L
        GEM
          remote: #{file_uri_for(gem_repo4)}/
          specs:
            nokogiri (1.3.10)

        PLATFORMS
          ruby

        DEPENDENCIES
          nokogiri

        RUBY VERSION
          2.5.3p105

        BUNDLED WITH
           2.1.4
        L

        simulate_platform "arm64-darwin-22", &example
      end

      it "still installs the generic RUBY variant if necessary" do
        bundle "update --bundler", :artifice => "compact_index", :env => { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
      end

      it "still installs the generic RUBY variant if necessary, even in frozen mode" do
        bundle "update --bundler", :artifice => "compact_index", :env => { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s, "BUNDLE_FROZEN" => "true" }
      end
    end

    it "doesn't discard previously installed platform specific gem and fall back to ruby on subsequent bundles" do
      build_repo2 do
        build_gem("libv8", "8.4.255.0")
        build_gem("libv8", "8.4.255.0") {|s| s.platform = "universal-darwin" }

        build_gem("mini_racer", "1.0.0") do |s|
          s.add_runtime_dependency "libv8"
        end
      end

      system_gems "bundler-2.1.4"

      # Consistent location to install and look for gems
      bundle "config set --local path vendor/bundle", :env => { "BUNDLER_VERSION" => "2.1.4" }

      gemfile <<-G
        source "https://localgemserver.test"
        gem "libv8"
      G

      # simulate lockfile created with old bundler, which only locks for ruby platform
      lockfile <<-L
        GEM
          remote: https://localgemserver.test/
          specs:
            libv8 (8.4.255.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          libv8

        BUNDLED WITH
           2.1.4
      L

      bundle "install --verbose", :artifice => "compact_index", :env => { "BUNDLER_VERSION" => "2.1.4", "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
      expect(out).to include("Installing libv8 8.4.255.0 (universal-darwin)")

      bundle "add mini_racer --verbose", :artifice => "compact_index", :env => { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
      expect(out).to include("Using libv8 8.4.255.0 (universal-darwin)")
    end

    it "chooses platform specific gems even when resolving upon materialization and the API returns more specific plaforms first" do
      build_repo4 do
        build_gem("grpc", "1.50.0")
        build_gem("grpc", "1.50.0") {|s| s.platform = "universal-darwin" }
      end

      gemfile <<-G
        source "https://localgemserver.test"
        gem "grpc"
      G

      # simulate lockfile created with old bundler, which only locks for ruby platform
      lockfile <<-L
        GEM
          remote: https://localgemserver.test/
          specs:
            grpc (1.50.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          grpc

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "install --verbose", :artifice => "compact_index_precompiled_before", :env => { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
      expect(out).to include("Installing grpc 1.50.0 (universal-darwin)")
    end

    it "caches the universal-darwin gem when --all-platforms is passed and properly picks it up on further bundler invocations" do
      setup_multiplatform_gem
      gemfile(google_protobuf)
      bundle "cache --all-platforms"
      expect(cached_gem("google-protobuf-3.0.0.alpha.5.0.5.1-universal-darwin")).to exist

      bundle "install --verbose"
      expect(err).to be_empty
    end

    it "caches the universal-darwin gem when cache_all_platforms is configured and properly picks it up on further bundler invocations" do
      setup_multiplatform_gem
      gemfile(google_protobuf)
      bundle "config set --local cache_all_platforms true"
      bundle "cache"
      expect(cached_gem("google-protobuf-3.0.0.alpha.5.0.5.1-universal-darwin")).to exist

      bundle "install --verbose"
      expect(err).to be_empty
    end

    it "caches multiplatform git gems with a single gemspec when --all-platforms is passed" do
      git = build_git "pg_array_parser", "1.0"

      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "pg_array_parser", :git => "#{lib_path("pg_array_parser-1.0")}"
      G

      lockfile <<-L
        GIT
          remote: #{lib_path("pg_array_parser-1.0")}
          revision: #{git.ref_for("main")}
          specs:
            pg_array_parser (1.0-java)
            pg_array_parser (1.0)

        GEM
          specs:

        PLATFORMS
          java
          #{lockfile_platforms}

        DEPENDENCIES
          pg_array_parser!

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "config set --local cache_all true"
      bundle "cache --all-platforms"

      expect(err).to be_empty
    end

    it "uses the platform-specific gem with extra dependencies" do
      setup_multiplatform_gem_with_different_dependencies_per_platform
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "facter"
      G
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)

      expect(the_bundle.locked_gems.platforms).to eq([pl("x86_64-darwin-15")])
      expect(the_bundle).to include_gems("facter 2.4.6 universal-darwin", "CFPropertyList 1.0")
      expect(the_bundle.locked_gems.specs.map(&:full_name)).to eq(["CFPropertyList-1.0",
                                                                   "facter-2.4.6-universal-darwin"])
    end

    context "when adding a platform via lock --add_platform" do
      before do
        allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      end

      it "adds the foreign platform" do
        setup_multiplatform_gem
        install_gemfile(google_protobuf)
        bundle "lock --add-platform=#{x64_mingw32}"

        expect(the_bundle.locked_gems.platforms).to eq([x64_mingw32, pl("x86_64-darwin-15")])
        expect(the_bundle.locked_gems.specs.map(&:full_name)).to eq(%w[
          google-protobuf-3.0.0.alpha.5.0.5.1-universal-darwin
          google-protobuf-3.0.0.alpha.5.0.5.1-x64-mingw32
        ])
      end

      it "falls back on plain ruby when that version doesnt have a platform-specific gem" do
        setup_multiplatform_gem
        install_gemfile(google_protobuf)
        bundle "lock --add-platform=#{java}"

        expect(the_bundle.locked_gems.platforms).to eq([java, pl("x86_64-darwin-15")])
        expect(the_bundle.locked_gems.specs.map(&:full_name)).to eq(%w[
          google-protobuf-3.0.0.alpha.5.0.5.1
          google-protobuf-3.0.0.alpha.5.0.5.1-universal-darwin
        ])
      end
    end
  end

  it "installs sorbet-static, which does not provide a pure ruby variant, just fine", :truffleruby do
    skip "does not apply to Windows" if Gem.win_platform?

    build_repo2 do
      build_gem("sorbet-static", "0.5.6403") {|s| s.platform = Bundler.local_platform }
    end

    gemfile <<~G
      source "#{file_uri_for(gem_repo2)}"

      gem "sorbet-static", "0.5.6403"
    G

    lockfile <<~L
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          sorbet-static (0.5.6403-#{Bundler.local_platform})

      PLATFORMS
        ruby

      DEPENDENCIES
        sorbet-static (= 0.5.6403)

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "install --verbose"
  end

  it "does not resolve if the current platform does not match any of available platform specific variants for a top level dependency" do
    build_repo4 do
      build_gem("sorbet-static", "0.5.6433") {|s| s.platform = "x86_64-linux" }
      build_gem("sorbet-static", "0.5.6433") {|s| s.platform = "universal-darwin-20" }
    end

    gemfile <<~G
      source "#{file_uri_for(gem_repo4)}"

      gem "sorbet-static", "0.5.6433"
    G

    error_message = <<~ERROR.strip
      Could not find gem 'sorbet-static (= 0.5.6433)' with platform 'arm64-darwin-21' in rubygems repository #{file_uri_for(gem_repo4)}/ or installed locally.

      The source contains the following gems matching 'sorbet-static (= 0.5.6433)':
        * sorbet-static-0.5.6433-universal-darwin-20
        * sorbet-static-0.5.6433-x86_64-linux
    ERROR

    simulate_platform "arm64-darwin-21" do
      bundle "lock", :raise_on_error => false
    end

    expect(err).to include(error_message).once

    # Make sure it doesn't print error twice in verbose mode

    simulate_platform "arm64-darwin-21" do
      bundle "lock --verbose", :raise_on_error => false
    end

    expect(err).to include(error_message).once
  end

  it "does not resolve if the current platform does not match any of available platform specific variants for a transitive dependency" do
    build_repo4 do
      build_gem("sorbet", "0.5.6433") {|s| s.add_dependency "sorbet-static", "= 0.5.6433" }
      build_gem("sorbet-static", "0.5.6433") {|s| s.platform = "x86_64-linux" }
      build_gem("sorbet-static", "0.5.6433") {|s| s.platform = "universal-darwin-20" }
    end

    gemfile <<~G
      source "#{file_uri_for(gem_repo4)}"

      gem "sorbet", "0.5.6433"
    G

    error_message = <<~ERROR.strip
      Could not find gem 'sorbet-static (= 0.5.6433)' with platform 'arm64-darwin-21', which is required by gem 'sorbet (= 0.5.6433)', in rubygems repository #{file_uri_for(gem_repo4)}/ or installed locally.

      The source contains the following gems matching 'sorbet-static (= 0.5.6433)':
        * sorbet-static-0.5.6433-universal-darwin-20
        * sorbet-static-0.5.6433-x86_64-linux
    ERROR

    simulate_platform "arm64-darwin-21" do
      bundle "lock", :raise_on_error => false
    end

    expect(err).to include(error_message).once

    # Make sure it doesn't print error twice in verbose mode

    simulate_platform "arm64-darwin-21" do
      bundle "lock --verbose", :raise_on_error => false
    end

    expect(err).to include(error_message).once
  end

  it "does not generate a lockfile if RUBY platform is forced and some gem has no RUBY variant available" do
    build_repo4 do
      build_gem("sorbet-static", "0.5.9889") {|s| s.platform = Gem::Platform.local }
    end

    gemfile <<~G
      source "#{file_uri_for(gem_repo4)}"

      gem "sorbet-static", "0.5.9889"
    G

    bundle "lock", :raise_on_error => false, :env => { "BUNDLE_FORCE_RUBY_PLATFORM" => "true" }

    expect(err).to include <<~ERROR.rstrip
      Could not find gem 'sorbet-static (= 0.5.9889)' with platform 'ruby' in rubygems repository #{file_uri_for(gem_repo4)}/ or installed locally.

      The source contains the following gems matching 'sorbet-static (= 0.5.9889)':
        * sorbet-static-0.5.9889-#{Gem::Platform.local}
    ERROR
  end

  it "automatically fixes the lockfile if RUBY platform is locked and some gem has no RUBY variant available" do
    build_repo4 do
      build_gem("sorbet-static-and-runtime", "0.5.10160") do |s|
        s.add_runtime_dependency "sorbet", "= 0.5.10160"
        s.add_runtime_dependency "sorbet-runtime", "= 0.5.10160"
      end

      build_gem("sorbet", "0.5.10160") do |s|
        s.add_runtime_dependency "sorbet-static", "= 0.5.10160"
      end

      build_gem("sorbet-runtime", "0.5.10160")

      build_gem("sorbet-static", "0.5.10160") do |s|
        s.platform = Gem::Platform.local
      end
    end

    gemfile <<~G
      source "#{file_uri_for(gem_repo4)}"

      gem "sorbet-static-and-runtime"
    G

    lockfile <<~L
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          sorbet (0.5.10160)
            sorbet-static (= 0.5.10160)
          sorbet-runtime (0.5.10160)
          sorbet-static (0.5.10160-#{Gem::Platform.local})
          sorbet-static-and-runtime (0.5.10160)
            sorbet (= 0.5.10160)
            sorbet-runtime (= 0.5.10160)

      PLATFORMS
        #{lockfile_platforms_for([specific_local_platform, "ruby"])}

      DEPENDENCIES
        sorbet-static-and-runtime

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "update"

    expect(lockfile).to eq <<~L
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          sorbet (0.5.10160)
            sorbet-static (= 0.5.10160)
          sorbet-runtime (0.5.10160)
          sorbet-static (0.5.10160-#{Gem::Platform.local})
          sorbet-static-and-runtime (0.5.10160)
            sorbet (= 0.5.10160)
            sorbet-runtime (= 0.5.10160)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        sorbet-static-and-runtime

      BUNDLED WITH
         #{Bundler::VERSION}
    L
  end

  it "automatically fixes the lockfile if only RUBY platform is locked and some gem has no RUBY variant available" do
    build_repo4 do
      build_gem("sorbet-static-and-runtime", "0.5.10160") do |s|
        s.add_runtime_dependency "sorbet", "= 0.5.10160"
        s.add_runtime_dependency "sorbet-runtime", "= 0.5.10160"
      end

      build_gem("sorbet", "0.5.10160") do |s|
        s.add_runtime_dependency "sorbet-static", "= 0.5.10160"
      end

      build_gem("sorbet-runtime", "0.5.10160")

      build_gem("sorbet-static", "0.5.10160") do |s|
        s.platform = Gem::Platform.local
      end
    end

    gemfile <<~G
      source "#{file_uri_for(gem_repo4)}"

      gem "sorbet-static-and-runtime"
    G

    lockfile <<~L
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          sorbet (0.5.10160)
            sorbet-static (= 0.5.10160)
          sorbet-runtime (0.5.10160)
          sorbet-static (0.5.10160-#{Gem::Platform.local})
          sorbet-static-and-runtime (0.5.10160)
            sorbet (= 0.5.10160)
            sorbet-runtime (= 0.5.10160)

      PLATFORMS
        ruby

      DEPENDENCIES
        sorbet-static-and-runtime

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "update"

    expect(lockfile).to eq <<~L
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          sorbet (0.5.10160)
            sorbet-static (= 0.5.10160)
          sorbet-runtime (0.5.10160)
          sorbet-static (0.5.10160-#{Gem::Platform.local})
          sorbet-static-and-runtime (0.5.10160)
            sorbet (= 0.5.10160)
            sorbet-runtime (= 0.5.10160)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        sorbet-static-and-runtime

      BUNDLED WITH
         #{Bundler::VERSION}
    L
  end

  it "does not remove ruby if gems for other platforms, and not present in the lockfile, exist in the Gemfile" do
    build_repo4 do
      build_gem "nokogiri", "1.13.8"
      build_gem "nokogiri", "1.13.8" do |s|
        s.platform = Gem::Platform.local
      end
    end

    gemfile <<~G
      source "#{file_uri_for(gem_repo4)}"

      gem "nokogiri"

      gem "tzinfo", "~> 1.2", platform: :#{not_local_tag}
    G

    original_lockfile = <<~L
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          nokogiri (1.13.8)
          nokogiri (1.13.8-#{Gem::Platform.local})

      PLATFORMS
        #{lockfile_platforms_for([specific_local_platform, "ruby"])}

      DEPENDENCIES
        nokogiri
        tzinfo (~> 1.2)

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    lockfile original_lockfile

    bundle "lock --update"

    expect(lockfile).to eq(original_lockfile)
  end

  it "can fallback to a source gem when platform gems are incompatible with current ruby version" do
    setup_multiplatform_gem_with_source_gem

    source = file_uri_for(gem_repo2)

    gemfile <<~G
      source "#{source}"

      gem "my-precompiled-gem"
    G

    # simulate lockfile which includes both a precompiled gem with:
    # - Gem the current platform (with imcompatible ruby version)
    # - A source gem with compatible ruby version
    lockfile <<-L
      GEM
        remote: #{source}/
        specs:
          my-precompiled-gem (3.0.0)
          my-precompiled-gem (3.0.0-#{Bundler.local_platform})

      PLATFORMS
        ruby
        #{Bundler.local_platform}

      DEPENDENCIES
        my-precompiled-gem

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle :install
  end

  private

  def setup_multiplatform_gem
    build_repo2 do
      build_gem("google-protobuf", "3.0.0.alpha.5.0.5.1")
      build_gem("google-protobuf", "3.0.0.alpha.5.0.5.1") {|s| s.platform = "x86_64-linux" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.5.1") {|s| s.platform = "x64-mingw32" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.5.1") {|s| s.platform = "universal-darwin" }

      build_gem("google-protobuf", "3.0.0.alpha.5.0.5") {|s| s.platform = "x86_64-linux" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.5") {|s| s.platform = "x64-mingw32" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.5")

      build_gem("google-protobuf", "3.0.0.alpha.5.0.4") {|s| s.platform = "universal-darwin" }

      build_gem("google-protobuf", "3.0.0.alpha.4.0")
      build_gem("google-protobuf", "3.0.0.alpha.3.1.pre")
    end
  end

  def setup_multiplatform_gem_with_different_dependencies_per_platform
    build_repo2 do
      build_gem("facter", "2.4.6")
      build_gem("facter", "2.4.6") do |s|
        s.platform = "universal-darwin"
        s.add_runtime_dependency "CFPropertyList"
      end
      build_gem("CFPropertyList")
    end
  end

  def setup_multiplatform_gem_with_source_gem
    build_repo2 do
      build_gem("my-precompiled-gem", "3.0.0")
      build_gem("my-precompiled-gem", "3.0.0") do |s|
        s.platform = Bundler.local_platform

        # purposely unresolvable
        s.required_ruby_version = ">= 1000.0.0"
      end
    end
  end
end
