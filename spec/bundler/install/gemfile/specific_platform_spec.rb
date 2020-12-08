# frozen_string_literal: true

RSpec.describe "bundle install with specific platforms" do
  let(:google_protobuf) { <<-G }
    source "#{file_uri_for(gem_repo2)}"
    gem "google-protobuf"
  G

  context "when on a darwin machine" do
    before { simulate_platform "x86_64-darwin-15" }

    it "locks to both the specific darwin platform and ruby" do
      setup_multiplatform_gem
      install_gemfile(google_protobuf)
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      expect(the_bundle.locked_gems.platforms).to eq([pl("ruby"), pl("x86_64-darwin-15")])
      expect(the_bundle).to include_gem("google-protobuf 3.0.0.alpha.5.0.5.1 universal-darwin")
      expect(the_bundle.locked_gems.specs.map(&:full_name)).to eq(%w[
        google-protobuf-3.0.0.alpha.5.0.5.1
        google-protobuf-3.0.0.alpha.5.0.5.1-universal-darwin
      ])
    end

    it "caches both the universal-darwin and ruby gems when --all-platforms is passed and properly picks them up on further bundler invocations" do
      setup_multiplatform_gem
      gemfile(google_protobuf)
      bundle "cache --all-platforms"
      expect([cached_gem("google-protobuf-3.0.0.alpha.5.0.5.1"), cached_gem("google-protobuf-3.0.0.alpha.5.0.5.1-universal-darwin")]).
        to all(exist)

      bundle "install --verbose"
      expect(err).to be_empty
    end

    it "caches both the universal-darwin and ruby gems when cache_all_platforms is configured and properly picks them up on further bundler invocations" do
      setup_multiplatform_gem
      gemfile(google_protobuf)
      bundle "config set --local cache_all_platforms true"
      bundle "cache"
      expect([cached_gem("google-protobuf-3.0.0.alpha.5.0.5.1"), cached_gem("google-protobuf-3.0.0.alpha.5.0.5.1-universal-darwin")]).
        to all(exist)

      bundle "install --verbose"
      expect(err).to be_empty
    end

    it "caches multiplatform git gems with a single gemspec when --all-platforms is passed" do
      git = build_git "pg_array_parser", "1.0"

      gemfile <<-G
        gem "pg_array_parser", :git => "#{lib_path("pg_array_parser-1.0")}"
      G

      lockfile <<-L
        GIT
          remote: #{lib_path("pg_array_parser-1.0")}
          revision: #{git.ref_for("master")}
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

      expect(the_bundle.locked_gems.platforms).to eq([pl("ruby"), pl("x86_64-darwin-15")])
      expect(the_bundle).to include_gems("facter 2.4.6 universal-darwin", "CFPropertyList 1.0")
      expect(the_bundle.locked_gems.specs.map(&:full_name)).to eq(["CFPropertyList-1.0",
                                                                   "facter-2.4.6",
                                                                   "facter-2.4.6-universal-darwin"])
    end

    context "when adding a platform via lock --add_platform" do
      before do
        allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      end

      it "adds the foreign platform" do
        setup_multiplatform_gem
        install_gemfile(google_protobuf)
        bundle "lock --add-platform=#{x64_mingw}"

        expect(the_bundle.locked_gems.platforms).to eq([rb, x64_mingw, pl("x86_64-darwin-15")])
        expect(the_bundle.locked_gems.specs.map(&:full_name)).to eq(%w[
          google-protobuf-3.0.0.alpha.5.0.5.1
          google-protobuf-3.0.0.alpha.5.0.5.1-universal-darwin
          google-protobuf-3.0.0.alpha.5.0.5.1-x64-mingw32
        ])
      end

      it "falls back on plain ruby when that version doesnt have a platform-specific gem" do
        setup_multiplatform_gem
        install_gemfile(google_protobuf)
        bundle "lock --add-platform=#{java}"

        expect(the_bundle.locked_gems.platforms).to eq([java, rb, pl("x86_64-darwin-15")])
        expect(the_bundle.locked_gems.specs.map(&:full_name)).to eq(%w[
          google-protobuf-3.0.0.alpha.5.0.5.1
          google-protobuf-3.0.0.alpha.5.0.5.1-universal-darwin
        ])
      end
    end
  end

  private

  def setup_multiplatform_gem
    build_repo2 do
      build_gem("google-protobuf", "3.0.0.alpha.5.0.5.1")
      build_gem("google-protobuf", "3.0.0.alpha.5.0.5.1") {|s| s.platform = "x86_64-linux" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.5.1") {|s| s.platform = "x86-mingw32" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.5.1") {|s| s.platform = "x86-linux" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.5.1") {|s| s.platform = "x64-mingw32" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.5.1") {|s| s.platform = "universal-darwin" }

      build_gem("google-protobuf", "3.0.0.alpha.5.0.5") {|s| s.platform = "x86_64-linux" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.5") {|s| s.platform = "x86-linux" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.5") {|s| s.platform = "x64-mingw32" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.5") {|s| s.platform = "x86-mingw32" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.5")

      build_gem("google-protobuf", "3.0.0.alpha.5.0.4") {|s| s.platform = "universal-darwin" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.4") {|s| s.platform = "x86_64-linux" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.4") {|s| s.platform = "x86-mingw32" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.4") {|s| s.platform = "x86-linux" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.4") {|s| s.platform = "x64-mingw32" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.4")

      build_gem("google-protobuf", "3.0.0.alpha.5.0.3")
      build_gem("google-protobuf", "3.0.0.alpha.5.0.3") {|s| s.platform = "x86_64-linux" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.3") {|s| s.platform = "x86-mingw32" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.3") {|s| s.platform = "x86-linux" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.3") {|s| s.platform = "x64-mingw32" }
      build_gem("google-protobuf", "3.0.0.alpha.5.0.3") {|s| s.platform = "universal-darwin" }

      build_gem("google-protobuf", "3.0.0.alpha.4.0")
      build_gem("google-protobuf", "3.0.0.alpha.3.1.pre")
      build_gem("google-protobuf", "3.0.0.alpha.3")
      build_gem("google-protobuf", "3.0.0.alpha.2.0")
      build_gem("google-protobuf", "3.0.0.alpha.1.1")
      build_gem("google-protobuf", "3.0.0.alpha.1.0")
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
end
