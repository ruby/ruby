# frozen_string_literal: true

RSpec.describe "real source plugins" do
  context "with a minimal source plugin" do
    before do
      build_repo2 do
        build_plugin "bundler-source-mpath" do |s|
          s.write "plugins.rb", <<-RUBY
            require "bundler-source-mpath"

            class MPath < Bundler::Plugin::API
              source "mpath"

              attr_reader :path

              def initialize(opts)
                super

                @path = Pathname.new options["uri"]
              end

              def fetch_gemspec_files
                @spec_files ||= begin
                  glob = "{,*,*/*}.gemspec"
                  if installed?
                    search_path = install_path
                  else
                    search_path = path
                  end
                  Dir["\#{search_path.to_s}/\#{glob}"]
                end
              end

              def install(spec, opts)
                mkdir_p(install_path.parent)
                require 'fileutils'
                FileUtils.cp_r(path, install_path)

                spec_path = install_path.join("\#{spec.full_name}.gemspec")
                spec_path.open("wb") {|f| f.write spec.to_ruby }
                spec.loaded_from = spec_path.to_s

                post_install(spec)

                nil
              end
            end
          RUBY
        end # build_plugin
      end

      build_lib "a-path-gem"

      gemfile <<-G
        source "#{file_uri_for(gem_repo2)}" # plugin source
        source "#{lib_path("a-path-gem-1.0")}", :type => :mpath do
          gem "a-path-gem"
        end
      G
    end

    it "installs" do
      bundle "install"

      expect(out).to include("Bundle complete!")

      expect(the_bundle).to include_gems("a-path-gem 1.0")
    end

    it "writes to lock file" do
      bundle "install"

      expect(lockfile).to eq <<~G
        PLUGIN SOURCE
          remote: #{lib_path("a-path-gem-1.0")}
          type: mpath
          specs:
            a-path-gem (1.0)

        GEM
          remote: #{file_uri_for(gem_repo2)}/
          specs:

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          a-path-gem!

        CHECKSUMS
          a-path-gem (1.0)

        BUNDLED WITH
           #{Bundler::VERSION}
      G
    end

    it "provides correct #full_gem_path" do
      bundle "install"
      run <<-RUBY
        puts Bundler.rubygems.find_name('a-path-gem').first.full_gem_path
      RUBY
      expect(out).to eq(bundle("info a-path-gem --path"))
    end

    it "installs the gem executables" do
      build_lib "gem_with_bin" do |s|
        s.executables = ["foo"]
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}" # plugin source
        source "#{lib_path("gem_with_bin-1.0")}", :type => :mpath do
          gem "gem_with_bin"
        end
      G

      bundle "exec foo"
      expect(out).to eq("1.0")
    end

    describe "bundle cache/package" do
      let(:uri_hash) { Digest(:SHA1).hexdigest(lib_path("a-path-gem-1.0").to_s) }
      it "copies repository to vendor cache and uses it" do
        bundle "install"
        bundle "config set cache_all true"
        bundle :cache

        expect(bundled_app("vendor/cache/a-path-gem-1.0-#{uri_hash}")).to exist
        expect(bundled_app("vendor/cache/a-path-gem-1.0-#{uri_hash}/.git")).not_to exist
        expect(bundled_app("vendor/cache/a-path-gem-1.0-#{uri_hash}/.bundlecache")).to be_file

        FileUtils.rm_rf lib_path("a-path-gem-1.0")
        expect(the_bundle).to include_gems("a-path-gem 1.0")
      end

      it "copies repository to vendor cache and uses it even when installed with `path` configured" do
        bundle "config set --local path vendor/bundle"
        bundle :install
        bundle "config set cache_all true"
        bundle :cache

        expect(bundled_app("vendor/cache/a-path-gem-1.0-#{uri_hash}")).to exist

        FileUtils.rm_rf lib_path("a-path-gem-1.0")
        expect(the_bundle).to include_gems("a-path-gem 1.0")
      end

      it "bundler package copies repository to vendor cache" do
        bundle "config set --local path vendor/bundle"
        bundle :install
        bundle "config set cache_all true"
        bundle :cache

        expect(bundled_app("vendor/cache/a-path-gem-1.0-#{uri_hash}")).to exist

        FileUtils.rm_rf lib_path("a-path-gem-1.0")
        expect(the_bundle).to include_gems("a-path-gem 1.0")
      end
    end

    context "with lockfile" do
      before do
        lockfile <<-G
          PLUGIN SOURCE
            remote: #{lib_path("a-path-gem-1.0")}
            type: mpath
            specs:
              a-path-gem (1.0)

          GEM
            remote: #{file_uri_for(gem_repo2)}/
            specs:

          PLATFORMS
            #{generic_local_platform}

          DEPENDENCIES
            a-path-gem!

          BUNDLED WITH
             #{Bundler::VERSION}
        G
      end

      it "installs" do
        bundle "install"

        expect(the_bundle).to include_gems("a-path-gem 1.0")
      end
    end
  end

  context "with a more elaborate source plugin" do
    before do
      build_repo2 do
        build_plugin "bundler-source-gitp" do |s|
          s.write "plugins.rb", <<-RUBY
            require "open3"

            class SPlugin < Bundler::Plugin::API
              source "gitp"

              attr_reader :ref

              def initialize(opts)
                super

                @ref = options["ref"] || options["branch"] || options["tag"] || "main"
                @unlocked = false
              end

              def eql?(other)
                other.is_a?(self.class) && uri == other.uri && ref == other.ref
              end

              alias_method :==, :eql?

              def fetch_gemspec_files
                @spec_files ||= begin
                  glob = "{,*,*/*}.gemspec"
                  if !cached?
                    cache_repo
                  end

                  if installed? && !@unlocked
                    path = install_path
                  else
                    path = cache_path
                  end

                  Dir["\#{path}/\#{glob}"]
                end
              end

              def install(spec, opts)
                mkdir_p(install_path.dirname)
                rm_rf(install_path)
                `git clone --no-checkout --quiet "\#{cache_path}" "\#{install_path}"`
                Open3.capture2e("git reset --hard \#{revision}", :chdir => install_path)

                spec_path = install_path.join("\#{spec.full_name}.gemspec")
                spec_path.open("wb") {|f| f.write spec.to_ruby }
                spec.loaded_from = spec_path.to_s

                post_install(spec)

                nil
              end

              def options_to_lock
                opts = {"revision" => revision}
                opts["ref"] = ref if ref != "main"
                opts
              end

              def unlock!
                @unlocked = true
                @revision = latest_revision
              end

              def app_cache_dirname
                "\#{base_name}-\#{shortref_for_path(revision)}"
              end

            private

              def cache_path
                @cache_path ||= cache_dir.join("gitp", base_name)
              end

              def cache_repo
                `git clone --quiet \#{@options["uri"]} \#{cache_path}`
              end

              def cached?
                File.directory?(cache_path)
              end

              def locked_revision
                options["revision"]
              end

              def revision
                @revision ||= locked_revision || latest_revision
              end

              def latest_revision
                if !cached? || @unlocked
                  rm_rf(cache_path)
                  cache_repo
                end

                output, _status = Open3.capture2e("git rev-parse --verify \#{@ref}", :chdir => cache_path)
                output.strip
              end

              def base_name
                File.basename(uri.sub(%r{^(\w+://)?([^/:]+:)?(//\w*/)?(\w*/)*}, ""), ".git")
              end

              def shortref_for_path(ref)
                ref[0..11]
              end

              def install_path
                @install_path ||= begin
                  git_scope = "\#{base_name}-\#{shortref_for_path(revision)}"

                  gem_install_dir.join(git_scope)
                end
              end

              def installed?
                File.directory?(install_path)
              end
            end
          RUBY
        end
      end

      build_git "ma-gitp-gem"

      gemfile <<-G
        source "#{file_uri_for(gem_repo2)}" # plugin source
        source "#{file_uri_for(lib_path("ma-gitp-gem-1.0"))}", :type => :gitp do
          gem "ma-gitp-gem"
        end
      G
    end

    it "handles the source option" do
      bundle "install"
      expect(out).to include("Bundle complete!")
      expect(the_bundle).to include_gems("ma-gitp-gem 1.0")
    end

    it "writes to lock file" do
      revision = revision_for(lib_path("ma-gitp-gem-1.0"))
      bundle "install"

      expect(lockfile).to eq <<~G
        PLUGIN SOURCE
          remote: #{file_uri_for(lib_path("ma-gitp-gem-1.0"))}
          type: gitp
          revision: #{revision}
          specs:
            ma-gitp-gem (1.0)

        GEM
          remote: #{file_uri_for(gem_repo2)}/
          specs:

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          ma-gitp-gem!

        CHECKSUMS
          ma-gitp-gem (1.0)

        BUNDLED WITH
           #{Bundler::VERSION}
      G
    end

    context "with lockfile" do
      before do
        revision = revision_for(lib_path("ma-gitp-gem-1.0"))
        lockfile <<-G
          PLUGIN SOURCE
            remote: #{file_uri_for(lib_path("ma-gitp-gem-1.0"))}
            type: gitp
            revision: #{revision}
            specs:
              ma-gitp-gem (1.0)

          GEM
            remote: #{file_uri_for(gem_repo2)}/
            specs:

          PLATFORMS
            #{generic_local_platform}

          DEPENDENCIES
            ma-gitp-gem!

          BUNDLED WITH
             #{Bundler::VERSION}
        G
      end

      it "installs" do
        bundle "install"
        expect(the_bundle).to include_gems("ma-gitp-gem 1.0")
      end

      it "uses the locked ref" do
        update_git "ma-gitp-gem"
        bundle "install"

        run <<-RUBY
          require 'ma/gitp/gem'
          puts "WIN" unless defined?(MAGITPGEM_PREV_REF)
        RUBY
        expect(out).to eq("WIN")
      end

      it "updates the deps on bundler update" do
        update_git "ma-gitp-gem"
        bundle "update ma-gitp-gem"

        run <<-RUBY
          require 'ma/gitp/gem'
          puts "WIN" if defined?(MAGITPGEM_PREV_REF)
        RUBY
        expect(out).to eq("WIN")
      end

      it "updates the deps on change in gemfile" do
        update_git "ma-gitp-gem", "1.1", :path => lib_path("ma-gitp-gem-1.0"), :gemspec => true
        gemfile <<-G
          source "#{file_uri_for(gem_repo2)}" # plugin source
          source "#{file_uri_for(lib_path("ma-gitp-gem-1.0"))}", :type => :gitp do
            gem "ma-gitp-gem", "1.1"
          end
        G
        bundle "install"

        expect(the_bundle).to include_gems("ma-gitp-gem 1.1")
      end
    end

    describe "bundle cache with gitp" do
      it "copies repository to vendor cache and uses it" do
        git = build_git "foo"
        ref = git.ref_for("main", 11)

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo2)}" # plugin source
          source  '#{lib_path("foo-1.0")}', :type => :gitp do
            gem "foo"
          end
        G

        bundle "config set cache_all true"
        bundle :cache
        expect(bundled_app("vendor/cache/foo-1.0-#{ref}")).to exist
        expect(bundled_app("vendor/cache/foo-1.0-#{ref}/.git")).not_to exist
        expect(bundled_app("vendor/cache/foo-1.0-#{ref}/.bundlecache")).to be_file

        FileUtils.rm_rf lib_path("foo-1.0")
        expect(the_bundle).to include_gems "foo 1.0"
      end
    end
  end
end
