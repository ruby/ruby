# frozen_string_literal: true

RSpec.describe "global gem caching" do
  before { bundle! "config set global_gem_cache true" }

  describe "using the cross-application user cache" do
    let(:source)  { "http://localgemserver.test" }
    let(:source2) { "http://gemserver.example.org" }

    def source_global_cache(*segments)
      home(".bundle", "cache", "gems", "localgemserver.test.80.dd34752a738ee965a2a4298dc16db6c5", *segments)
    end

    def source2_global_cache(*segments)
      home(".bundle", "cache", "gems", "gemserver.example.org.80.1ae1663619ffe0a3c9d97712f44c705b", *segments)
    end

    it "caches gems into the global cache on download" do
      install_gemfile! <<-G, :artifice => "compact_index"
        source "#{source}"
        gem "rack"
      G

      expect(the_bundle).to include_gems "rack 1.0.0"
      expect(source_global_cache("rack-1.0.0.gem")).to exist
    end

    it "uses globally cached gems if they exist" do
      source_global_cache.mkpath
      FileUtils.cp(gem_repo1("gems/rack-1.0.0.gem"), source_global_cache("rack-1.0.0.gem"))

      install_gemfile! <<-G, :artifice => "compact_index_no_gem"
        source "#{source}"
        gem "rack"
      G

      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    describe "when the same gem from different sources is installed" do
      it "should use the appropriate one from the global cache" do
        install_gemfile! <<-G, :artifice => "compact_index"
          source "#{source}"
          gem "rack"
        G

        FileUtils.rm_r(default_bundle_path)
        expect(the_bundle).not_to include_gems "rack 1.0.0"
        expect(source_global_cache("rack-1.0.0.gem")).to exist
        # rack 1.0.0 is not installed and it is in the global cache

        install_gemfile! <<-G, :artifice => "compact_index"
          source "#{source2}"
          gem "rack", "0.9.1"
        G

        FileUtils.rm_r(default_bundle_path)
        expect(the_bundle).not_to include_gems "rack 0.9.1"
        expect(source2_global_cache("rack-0.9.1.gem")).to exist
        # rack 0.9.1 is not installed and it is in the global cache

        gemfile <<-G
          source "#{source}"
          gem "rack", "1.0.0"
        G

        bundle! :install, :artifice => "compact_index_no_gem"
        # rack 1.0.0 is installed and rack 0.9.1 is not
        expect(the_bundle).to include_gems "rack 1.0.0"
        expect(the_bundle).not_to include_gems "rack 0.9.1"
        FileUtils.rm_r(default_bundle_path)

        gemfile <<-G
          source "#{source2}"
          gem "rack", "0.9.1"
        G

        bundle! :install, :artifice => "compact_index_no_gem"
        # rack 0.9.1 is installed and rack 1.0.0 is not
        expect(the_bundle).to include_gems "rack 0.9.1"
        expect(the_bundle).not_to include_gems "rack 1.0.0"
      end

      it "should not install if the wrong source is provided" do
        gemfile <<-G
          source "#{source}"
          gem "rack"
        G

        bundle! :install, :artifice => "compact_index"
        FileUtils.rm_r(default_bundle_path)
        expect(the_bundle).not_to include_gems "rack 1.0.0"
        expect(source_global_cache("rack-1.0.0.gem")).to exist
        # rack 1.0.0 is not installed and it is in the global cache

        gemfile <<-G
          source "#{source2}"
          gem "rack", "0.9.1"
        G

        bundle! :install, :artifice => "compact_index"
        FileUtils.rm_r(default_bundle_path)
        expect(the_bundle).not_to include_gems "rack 0.9.1"
        expect(source2_global_cache("rack-0.9.1.gem")).to exist
        # rack 0.9.1 is not installed and it is in the global cache

        gemfile <<-G
          source "#{source2}"
          gem "rack", "1.0.0"
        G

        expect(source_global_cache("rack-1.0.0.gem")).to exist
        expect(source2_global_cache("rack-0.9.1.gem")).to exist
        bundle :install, :artifice => "compact_index_no_gem"
        expect(err).to include("Internal Server Error 500")
        # rack 1.0.0 is not installed and rack 0.9.1 is not
        expect(the_bundle).not_to include_gems "rack 1.0.0"
        expect(the_bundle).not_to include_gems "rack 0.9.1"

        gemfile <<-G
          source "#{source}"
          gem "rack", "0.9.1"
        G

        expect(source_global_cache("rack-1.0.0.gem")).to exist
        expect(source2_global_cache("rack-0.9.1.gem")).to exist
        bundle :install, :artifice => "compact_index_no_gem"
        expect(err).to include("Internal Server Error 500")
        # rack 0.9.1 is not installed and rack 1.0.0 is not
        expect(the_bundle).not_to include_gems "rack 0.9.1"
        expect(the_bundle).not_to include_gems "rack 1.0.0"
      end
    end

    describe "when installing gems from a different directory" do
      it "uses the global cache as a source" do
        install_gemfile! <<-G, :artifice => "compact_index"
          source "#{source}"
          gem "rack"
          gem "activesupport"
        G

        # Both gems are installed and in the global cache
        expect(the_bundle).to include_gems "rack 1.0.0"
        expect(the_bundle).to include_gems "activesupport 2.3.5"
        expect(source_global_cache("rack-1.0.0.gem")).to exist
        expect(source_global_cache("activesupport-2.3.5.gem")).to exist
        FileUtils.rm_r(default_bundle_path)
        # Both gems are now only in the global cache
        expect(the_bundle).not_to include_gems "rack 1.0.0"
        expect(the_bundle).not_to include_gems "activesupport 2.3.5"

        install_gemfile! <<-G, :artifice => "compact_index_no_gem"
          source "#{source}"
          gem "rack"
        G

        # rack is installed and both are in the global cache
        expect(the_bundle).to include_gems "rack 1.0.0"
        expect(the_bundle).not_to include_gems "activesupport 2.3.5"
        expect(source_global_cache("rack-1.0.0.gem")).to exist
        expect(source_global_cache("activesupport-2.3.5.gem")).to exist

        Dir.chdir bundled_app2 do
          create_file bundled_app2("gems.rb"), <<-G
            source "#{source}"
            gem "activesupport"
          G

          # Neither gem is installed and both are in the global cache
          expect(the_bundle).not_to include_gems "rack 1.0.0"
          expect(the_bundle).not_to include_gems "activesupport 2.3.5"
          expect(source_global_cache("rack-1.0.0.gem")).to exist
          expect(source_global_cache("activesupport-2.3.5.gem")).to exist

          # Install using the global cache instead of by downloading the .gem
          # from the server
          bundle! :install, :artifice => "compact_index_no_gem"

          # activesupport is installed and both are in the global cache
          expect(the_bundle).not_to include_gems "rack 1.0.0"
          expect(the_bundle).to include_gems "activesupport 2.3.5"
          expect(source_global_cache("rack-1.0.0.gem")).to exist
          expect(source_global_cache("activesupport-2.3.5.gem")).to exist
        end
      end
    end
  end

  describe "extension caching", :ruby_repo do
    it "works" do
      build_git "very_simple_git_binary", &:add_c_extension
      build_lib "very_simple_path_binary", &:add_c_extension
      revision = revision_for(lib_path("very_simple_git_binary-1.0"))[0, 12]

      install_gemfile! <<-G
        source "file:#{gem_repo1}"

        gem "very_simple_binary"
        gem "very_simple_git_binary", :git => "#{lib_path("very_simple_git_binary-1.0")}"
        gem "very_simple_path_binary", :path => "#{lib_path("very_simple_path_binary-1.0")}"
      G

      gem_binary_cache = home(".bundle", "cache", "extensions", specific_local_platform.to_s, Bundler.ruby_scope,
        Digest(:MD5).hexdigest("#{gem_repo1}/"), "very_simple_binary-1.0")
      git_binary_cache = home(".bundle", "cache", "extensions", specific_local_platform.to_s, Bundler.ruby_scope,
        "very_simple_git_binary-1.0-#{revision}", "very_simple_git_binary-1.0")

      cached_extensions = Pathname.glob(home(".bundle", "cache", "extensions", "*", "*", "*", "*", "*")).sort
      expect(cached_extensions).to eq [gem_binary_cache, git_binary_cache].sort

      run! <<-R
        require 'very_simple_binary_c'; puts ::VERY_SIMPLE_BINARY_IN_C
        require 'very_simple_git_binary_c'; puts ::VERY_SIMPLE_GIT_BINARY_IN_C
      R
      expect(out).to eq "VERY_SIMPLE_BINARY_IN_C\nVERY_SIMPLE_GIT_BINARY_IN_C"

      FileUtils.rm Dir[home(".bundle", "cache", "extensions", "**", "*binary_c*")]

      gem_binary_cache.join("very_simple_binary_c.rb").open("w") {|f| f << "puts File.basename(__FILE__)" }
      git_binary_cache.join("very_simple_git_binary_c.rb").open("w") {|f| f << "puts File.basename(__FILE__)" }

      bundle! "config set --local path different_path"
      bundle! :install

      expect(Dir[home(".bundle", "cache", "extensions", "**", "*binary_c*")]).to all(end_with(".rb"))

      run! <<-R
        require 'very_simple_binary_c'
        require 'very_simple_git_binary_c'
      R
      expect(out).to eq "very_simple_binary_c.rb\nvery_simple_git_binary_c.rb"
    end
  end
end
