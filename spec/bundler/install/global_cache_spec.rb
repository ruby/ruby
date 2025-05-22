# frozen_string_literal: true

RSpec.describe "global gem caching" do
  before { bundle "config set global_gem_cache true" }

  describe "using the cross-application user cache" do
    let(:source)  { "http://localgemserver.test" }
    let(:source2) { "http://gemserver.example.org" }

    def cache_base
      home(".bundle", "cache", "gems")
    end

    def source_global_cache(*segments)
      cache_base.join("localgemserver.test.80.dd34752a738ee965a2a4298dc16db6c5", *segments)
    end

    def source2_global_cache(*segments)
      cache_base.join("gemserver.example.org.80.1ae1663619ffe0a3c9d97712f44c705b", *segments)
    end

    it "caches gems into the global cache on download" do
      install_gemfile <<-G, artifice: "compact_index"
        source "#{source}"
        gem "myrack"
      G

      expect(the_bundle).to include_gems "myrack 1.0.0"
      expect(source_global_cache("myrack-1.0.0.gem")).to exist
    end

    it "uses globally cached gems if they exist" do
      source_global_cache.mkpath
      FileUtils.cp(gem_repo1("gems/myrack-1.0.0.gem"), source_global_cache("myrack-1.0.0.gem"))

      install_gemfile <<-G, artifice: "compact_index_no_gem"
        source "#{source}"
        gem "myrack"
      G

      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "shows a proper error message if a cached gem is corrupted" do
      source_global_cache.mkpath
      FileUtils.touch(source_global_cache("myrack-1.0.0.gem"))

      install_gemfile <<-G, artifice: "compact_index_no_gem", raise_on_error: false
        source "#{source}"
        gem "myrack"
      G

      expect(err).to include("Gem::Package::FormatError: package metadata is missing in #{source_global_cache("myrack-1.0.0.gem")}")
    end

    it "uses a shorter path for the cache to not hit filesystem limits" do
      install_gemfile <<-G, artifice: "compact_index", verbose: true
        source "http://#{"a" * 255}.test"
        gem "myrack"
      G

      expect(the_bundle).to include_gems "myrack 1.0.0"
      source_segment = "a" * 222 + ".a3cb26de2edfce9f509a65c611d99c4b"
      source_cache = cache_base.join(source_segment)
      cached_gem = source_cache.join("myrack-1.0.0.gem")
      expect(cached_gem).to exist
    ensure
      # We cleanup dummy files created by this spec manually because due to a
      # Ruby on Windows bug, `FileUtils.rm_rf` (run in our global after hook)
      # cannot traverse directories with such long names. So we delete
      # everything explicitly to workaround the bug. An alternative workaround
      # would be to shell out to `rm -rf`. That also works fine, but I went with
      # the more verbose and explicit approach. This whole ensure block can be
      # removed once/if https://bugs.ruby-lang.org/issues/21177 is fixed, and
      # once the fix propagates to all supported rubies.
      File.delete cached_gem
      Dir.rmdir source_cache

      File.delete compact_index_cache_path.join(source_segment, "info", "myrack")
      Dir.rmdir compact_index_cache_path.join(source_segment, "info")
      File.delete compact_index_cache_path.join(source_segment, "info-etags", "myrack-92f3313ce5721296f14445c3a6b9c073")
      Dir.rmdir compact_index_cache_path.join(source_segment, "info-etags")
      Dir.rmdir compact_index_cache_path.join(source_segment, "info-special-characters")
      File.delete compact_index_cache_path.join(source_segment, "versions")
      File.delete compact_index_cache_path.join(source_segment, "versions.etag")
      Dir.rmdir compact_index_cache_path.join(source_segment)
    end

    describe "when the same gem from different sources is installed" do
      it "should use the appropriate one from the global cache" do
        bundle "config path.system true"

        install_gemfile <<-G, artifice: "compact_index"
          source "#{source}"
          gem "myrack"
        G

        pristine_system_gems :bundler
        expect(the_bundle).not_to include_gems "myrack 1.0.0"
        expect(source_global_cache("myrack-1.0.0.gem")).to exist
        # myrack 1.0.0 is not installed and it is in the global cache

        install_gemfile <<-G, artifice: "compact_index"
          source "#{source2}"
          gem "myrack", "0.9.1"
        G

        pristine_system_gems :bundler
        expect(the_bundle).not_to include_gems "myrack 0.9.1"
        expect(source2_global_cache("myrack-0.9.1.gem")).to exist
        # myrack 0.9.1 is not installed and it is in the global cache

        gemfile <<-G
          source "#{source}"
          gem "myrack", "1.0.0"
        G

        bundle :install, artifice: "compact_index_no_gem"
        # myrack 1.0.0 is installed and myrack 0.9.1 is not
        expect(the_bundle).to include_gems "myrack 1.0.0"
        expect(the_bundle).not_to include_gems "myrack 0.9.1"
        pristine_system_gems :bundler

        gemfile <<-G
          source "#{source2}"
          gem "myrack", "0.9.1"
        G

        bundle :install, artifice: "compact_index_no_gem"
        # myrack 0.9.1 is installed and myrack 1.0.0 is not
        expect(the_bundle).to include_gems "myrack 0.9.1"
        expect(the_bundle).not_to include_gems "myrack 1.0.0"
      end

      it "should not install if the wrong source is provided" do
        bundle "config path.system true"

        gemfile <<-G
          source "#{source}"
          gem "myrack"
        G

        bundle :install, artifice: "compact_index"
        pristine_system_gems :bundler
        expect(the_bundle).not_to include_gems "myrack 1.0.0"
        expect(source_global_cache("myrack-1.0.0.gem")).to exist
        # myrack 1.0.0 is not installed and it is in the global cache

        gemfile <<-G
          source "#{source2}"
          gem "myrack", "0.9.1"
        G

        bundle :install, artifice: "compact_index"
        pristine_system_gems :bundler
        expect(the_bundle).not_to include_gems "myrack 0.9.1"
        expect(source2_global_cache("myrack-0.9.1.gem")).to exist
        # myrack 0.9.1 is not installed and it is in the global cache

        gemfile <<-G
          source "#{source2}"
          gem "myrack", "1.0.0"
        G

        expect(source_global_cache("myrack-1.0.0.gem")).to exist
        expect(source2_global_cache("myrack-0.9.1.gem")).to exist
        bundle :install, artifice: "compact_index_no_gem", raise_on_error: false
        expect(err).to include("Internal Server Error 500")
        expect(err).not_to include("ERROR REPORT TEMPLATE")

        # myrack 1.0.0 is not installed and myrack 0.9.1 is not
        expect(the_bundle).not_to include_gems "myrack 1.0.0"
        expect(the_bundle).not_to include_gems "myrack 0.9.1"

        gemfile <<-G
          source "#{source}"
          gem "myrack", "0.9.1"
        G

        expect(source_global_cache("myrack-1.0.0.gem")).to exist
        expect(source2_global_cache("myrack-0.9.1.gem")).to exist
        bundle :install, artifice: "compact_index_no_gem", raise_on_error: false
        expect(err).to include("Internal Server Error 500")
        expect(err).not_to include("ERROR REPORT TEMPLATE")

        # myrack 0.9.1 is not installed and myrack 1.0.0 is not
        expect(the_bundle).not_to include_gems "myrack 0.9.1"
        expect(the_bundle).not_to include_gems "myrack 1.0.0"
      end
    end

    describe "when installing gems from a different directory" do
      it "uses the global cache as a source" do
        bundle "config path.system true"

        install_gemfile <<-G, artifice: "compact_index"
          source "#{source}"
          gem "myrack"
          gem "activesupport"
        G

        # Both gems are installed and in the global cache
        expect(the_bundle).to include_gems "myrack 1.0.0"
        expect(the_bundle).to include_gems "activesupport 2.3.5"
        expect(source_global_cache("myrack-1.0.0.gem")).to exist
        expect(source_global_cache("activesupport-2.3.5.gem")).to exist
        pristine_system_gems :bundler
        # Both gems are now only in the global cache
        expect(the_bundle).not_to include_gems "myrack 1.0.0"
        expect(the_bundle).not_to include_gems "activesupport 2.3.5"

        install_gemfile <<-G, artifice: "compact_index_no_gem"
          source "#{source}"
          gem "myrack"
        G

        # myrack is installed and both are in the global cache
        expect(the_bundle).to include_gems "myrack 1.0.0"
        expect(the_bundle).not_to include_gems "activesupport 2.3.5"
        expect(source_global_cache("myrack-1.0.0.gem")).to exist
        expect(source_global_cache("activesupport-2.3.5.gem")).to exist

        create_file bundled_app2("gems.rb"), <<-G
          source "#{source}"
          gem "activesupport"
        G

        # Neither gem is installed and both are in the global cache
        expect(the_bundle).not_to include_gems "myrack 1.0.0", dir: bundled_app2
        expect(the_bundle).not_to include_gems "activesupport 2.3.5", dir: bundled_app2
        expect(source_global_cache("myrack-1.0.0.gem")).to exist
        expect(source_global_cache("activesupport-2.3.5.gem")).to exist

        # Install using the global cache instead of by downloading the .gem
        # from the server
        bundle :install, artifice: "compact_index_no_gem", dir: bundled_app2

        # activesupport is installed and both are in the global cache
        expect(the_bundle).not_to include_gems "myrack 1.0.0", dir: bundled_app2
        expect(the_bundle).to include_gems "activesupport 2.3.5", dir: bundled_app2

        expect(source_global_cache("myrack-1.0.0.gem")).to exist
        expect(source_global_cache("activesupport-2.3.5.gem")).to exist
      end
    end
  end

  describe "extension caching" do
    it "works" do
      skip "gets incorrect ref in path" if Gem.win_platform?
      skip "fails for unknown reason when run by ruby-core" if ruby_core?

      build_git "very_simple_git_binary", &:add_c_extension
      build_lib "very_simple_path_binary", &:add_c_extension
      revision = revision_for(lib_path("very_simple_git_binary-1.0"))[0, 12]

      install_gemfile <<-G
        source "https://gem.repo1"

        gem "very_simple_binary"
        gem "very_simple_git_binary", :git => "#{lib_path("very_simple_git_binary-1.0")}"
        gem "very_simple_path_binary", :path => "#{lib_path("very_simple_path_binary-1.0")}"
      G

      gem_binary_cache = home(".bundle", "cache", "extensions", local_platform.to_s, Bundler.ruby_scope,
        "gem.repo1.443.#{Digest(:MD5).hexdigest("gem.repo1.443./")}", "very_simple_binary-1.0")
      git_binary_cache = home(".bundle", "cache", "extensions", local_platform.to_s, Bundler.ruby_scope,
        "very_simple_git_binary-1.0-#{revision}", "very_simple_git_binary-1.0")

      cached_extensions = Pathname.glob(home(".bundle", "cache", "extensions", "*", "*", "*", "*", "*")).sort
      expect(cached_extensions).to eq [gem_binary_cache, git_binary_cache].sort

      run <<-R
        require 'very_simple_binary_c'; puts ::VERY_SIMPLE_BINARY_IN_C
        require 'very_simple_git_binary_c'; puts ::VERY_SIMPLE_GIT_BINARY_IN_C
      R
      expect(out).to eq "VERY_SIMPLE_BINARY_IN_C\nVERY_SIMPLE_GIT_BINARY_IN_C"

      FileUtils.rm_r Dir[home(".bundle", "cache", "extensions", "**", "*binary_c*")]

      gem_binary_cache.join("very_simple_binary_c.rb").open("w") {|f| f << "puts File.basename(__FILE__)" }
      git_binary_cache.join("very_simple_git_binary_c.rb").open("w") {|f| f << "puts File.basename(__FILE__)" }

      bundle "config set --local path different_path"
      bundle :install

      expect(Dir[home(".bundle", "cache", "extensions", "**", "*binary_c*")]).to all(end_with(".rb"))

      run <<-R
        require 'very_simple_binary_c'
        require 'very_simple_git_binary_c'
      R
      expect(out).to eq "very_simple_binary_c.rb\nvery_simple_git_binary_c.rb"
    end
  end
end
