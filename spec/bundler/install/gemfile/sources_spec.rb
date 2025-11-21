# frozen_string_literal: true

RSpec.describe "bundle install with gems on multiple sources" do
  # repo1 is built automatically before all of the specs run
  # it contains myrack-obama 1.0.0 and myrack 0.9.1 & 1.0.0 amongst other gems

  context "with source affinity" do
    context "with sources given by a block" do
      before do
        # Oh no! Someone evil is trying to hijack myrack :(
        # need this to be broken to check for correct source ordering
        build_repo3 do
          build_gem "myrack", "1.0.0" do |s|
            s.write "lib/myrack.rb", "MYRACK = 'FAIL'"
          end

          build_gem "myrack-obama" do |s|
            s.add_dependency "myrack"
          end
        end

        gemfile <<-G
          source "https://gem.repo3"
          source "https://gem.repo1" do
            gem "thin" # comes first to test name sorting
            gem "myrack"
          end
          gem "myrack-obama" # should come from repo3!
        G
      end

      it "installs the gems without any warning" do
        bundle :install, artifice: "compact_index"
        expect(err).not_to include("Warning")
        expect(the_bundle).to include_gems("myrack-obama 1.0.0")
        expect(the_bundle).to include_gems("myrack 1.0.0", source: "remote1")
      end

      it "can cache and deploy" do
        bundle :cache, artifice: "compact_index"

        expect(bundled_app("vendor/cache/myrack-1.0.0.gem")).to exist
        expect(bundled_app("vendor/cache/myrack-obama-1.0.gem")).to exist

        bundle "config set --local deployment true"
        bundle :install, artifice: "compact_index"

        expect(the_bundle).to include_gems("myrack-obama 1.0.0", "myrack 1.0.0")
      end
    end

    context "with sources set by an option" do
      before do
        # Oh no! Someone evil is trying to hijack myrack :(
        # need this to be broken to check for correct source ordering
        build_repo3 do
          build_gem "myrack", "1.0.0" do |s|
            s.write "lib/myrack.rb", "MYRACK = 'FAIL'"
          end

          build_gem "myrack-obama" do |s|
            s.add_dependency "myrack"
          end
        end

        install_gemfile <<-G, artifice: "compact_index"
          source "https://gem.repo3"
          gem "myrack-obama" # should come from repo3!
          gem "myrack", :source => "https://gem.repo1"
        G
      end

      it "installs the gems without any warning" do
        expect(err).not_to include("Warning")
        expect(the_bundle).to include_gems("myrack-obama 1.0.0", "myrack 1.0.0")
      end
    end

    context "when a pinned gem has an indirect dependency in the pinned source" do
      before do
        build_repo3 do
          build_gem "depends_on_myrack", "1.0.1" do |s|
            s.add_dependency "myrack"
          end
        end

        # we need a working myrack gem in repo3
        update_repo gem_repo3 do
          build_gem "myrack", "1.0.0"
        end

        gemfile <<-G
          source "https://gem.repo2"
          source "https://gem.repo3" do
            gem "depends_on_myrack"
          end
        G
      end

      context "and not in any other sources" do
        before do
          build_repo(gem_repo2) {}
        end

        it "installs from the same source without any warning" do
          bundle :install, artifice: "compact_index"
          expect(err).not_to include("Warning")
          expect(the_bundle).to include_gems("depends_on_myrack 1.0.1", "myrack 1.0.0", source: "remote3")
        end
      end

      context "and in another source" do
        before do
          # need this to be broken to check for correct source ordering
          build_repo gem_repo2 do
            build_gem "myrack", "1.0.0" do |s|
              s.write "lib/myrack.rb", "MYRACK = 'FAIL'"
            end
          end
        end

        it "installs from the same source without any warning" do
          bundle :install, artifice: "compact_index"

          expect(err).not_to include("Warning: the gem 'myrack' was found in multiple sources.")
          expect(the_bundle).to include_gems("depends_on_myrack 1.0.1", "myrack 1.0.0", source: "remote3")

          # In https://github.com/bundler/bundler/issues/3585 this failed
          # when there is already a lockfile, and the gems are missing, so try again
          system_gems []
          bundle :install, artifice: "compact_index"

          expect(err).not_to include("Warning: the gem 'myrack' was found in multiple sources.")
          expect(the_bundle).to include_gems("depends_on_myrack 1.0.1", "myrack 1.0.0", source: "remote3")
        end
      end
    end

    context "when a pinned gem has an indirect dependency in a different source" do
      before do
        # In these tests, we need a working myrack gem in repo2 and not repo3

        build_repo3 do
          build_gem "depends_on_myrack", "1.0.1" do |s|
            s.add_dependency "myrack"
          end
        end

        build_repo gem_repo2 do
          build_gem "myrack", "1.0.0"
        end
      end

      context "and not in any other sources" do
        before do
          install_gemfile <<-G, artifice: "compact_index"
            source "https://gem.repo2"
            source "https://gem.repo3" do
              gem "depends_on_myrack"
            end
          G
        end

        it "installs from the other source without any warning" do
          expect(err).not_to include("Warning")
          expect(the_bundle).to include_gems("depends_on_myrack 1.0.1", "myrack 1.0.0")
        end
      end
    end

    context "when a top-level gem can only be found in an scoped source" do
      before do
        build_repo2

        build_repo3 do
          build_gem "private_gem_1", "1.0.0"
          build_gem "private_gem_2", "1.0.0"
        end

        gemfile <<-G
          source "https://gem.repo2"

          gem "private_gem_1"

          source "https://gem.repo3" do
            gem "private_gem_2"
          end
        G
      end

      it "fails" do
        bundle :install, artifice: "compact_index", raise_on_error: false
        expect(err).to include("Could not find gem 'private_gem_1' in rubygems repository https://gem.repo2/ or installed locally.")
      end
    end

    context "when a top-level gem has an indirect dependency" do
      before do
        build_repo gem_repo2 do
          build_gem "depends_on_myrack", "1.0.1" do |s|
            s.add_dependency "myrack"
          end
        end

        build_repo3 do
          build_gem "unrelated_gem", "1.0.0"
        end

        gemfile <<-G
          source "https://gem.repo2"

          gem "depends_on_myrack"

          source "https://gem.repo3" do
            gem "unrelated_gem"
          end
        G
      end

      context "and the dependency is only in the top-level source" do
        before do
          update_repo gem_repo2 do
            build_gem "myrack", "1.0.0"
          end
        end

        it "installs the dependency from the top-level source without warning" do
          bundle :install, artifice: "compact_index"
          expect(err).not_to include("Warning")
          expect(the_bundle).to include_gems("depends_on_myrack 1.0.1", "myrack 1.0.0", "unrelated_gem 1.0.0")
          expect(the_bundle).to include_gems("depends_on_myrack 1.0.1", "myrack 1.0.0", source: "remote2")
          expect(the_bundle).to include_gems("unrelated_gem 1.0.0", source: "remote3")
        end
      end

      context "and the dependency is only in a pinned source" do
        before do
          update_repo gem_repo3 do
            build_gem "myrack", "1.0.0" do |s|
              s.write "lib/myrack.rb", "MYRACK = 'FAIL'"
            end
          end
        end

        it "does not find the dependency" do
          bundle :install, artifice: "compact_index", raise_on_error: false
          expect(err).to end_with <<~E.strip
            Could not find compatible versions

            Because every version of depends_on_myrack depends on myrack >= 0
              and myrack >= 0 could not be found in rubygems repository https://gem.repo2/ or installed locally,
              depends_on_myrack cannot be used.
            So, because Gemfile depends on depends_on_myrack >= 0,
              version solving has failed.
          E
        end
      end

      context "and the dependency is in both the top-level and a pinned source" do
        before do
          update_repo gem_repo2 do
            build_gem "myrack", "1.0.0"
          end

          update_repo gem_repo3 do
            build_gem "myrack", "1.0.0" do |s|
              s.write "lib/myrack.rb", "MYRACK = 'FAIL'"
            end
          end
        end

        it "installs the dependency from the top-level source without warning" do
          bundle :install, artifice: "compact_index"
          expect(err).not_to include("Warning")
          expect(run("require 'myrack'; puts MYRACK")).to eq("1.0.0")
          expect(the_bundle).to include_gems("depends_on_myrack 1.0.1", "myrack 1.0.0", "unrelated_gem 1.0.0")
          expect(the_bundle).to include_gems("depends_on_myrack 1.0.1", "myrack 1.0.0", source: "remote2")
          expect(the_bundle).to include_gems("unrelated_gem 1.0.0", source: "remote3")
        end
      end
    end

    context "when a scoped gem has a deeply nested indirect dependency" do
      before do
        build_repo3 do
          build_gem "depends_on_depends_on_myrack", "1.0.1" do |s|
            s.add_dependency "depends_on_myrack"
          end

          build_gem "depends_on_myrack", "1.0.1" do |s|
            s.add_dependency "myrack"
          end
        end

        gemfile <<-G
          source "https://gem.repo2"

          source "https://gem.repo3" do
            gem "depends_on_depends_on_myrack"
          end
        G
      end

      context "and the dependency is only in the top-level source" do
        before do
          update_repo gem_repo2 do
            build_gem "myrack", "1.0.0"
          end
        end

        it "installs the dependency from the top-level source" do
          bundle :install, artifice: "compact_index"
          expect(the_bundle).to include_gems("depends_on_depends_on_myrack 1.0.1", "depends_on_myrack 1.0.1", "myrack 1.0.0")
          expect(the_bundle).to include_gems("myrack 1.0.0", source: "remote2")
          expect(the_bundle).to include_gems("depends_on_depends_on_myrack 1.0.1", "depends_on_myrack 1.0.1", source: "remote3")
        end
      end

      context "and the dependency is only in a pinned source" do
        before do
          build_repo2

          update_repo gem_repo3 do
            build_gem "myrack", "1.0.0"
          end
        end

        it "installs the dependency from the pinned source" do
          bundle :install, artifice: "compact_index"
          expect(the_bundle).to include_gems("depends_on_depends_on_myrack 1.0.1", "depends_on_myrack 1.0.1", "myrack 1.0.0", source: "remote3")
        end
      end

      context "and the dependency is in both the top-level and a pinned source" do
        before do
          update_repo gem_repo2 do
            build_gem "myrack", "1.0.0" do |s|
              s.write "lib/myrack.rb", "MYRACK = 'FAIL'"
            end
          end

          update_repo gem_repo3 do
            build_gem "myrack", "1.0.0"
          end
        end

        it "installs the dependency from the pinned source without warning" do
          bundle :install, artifice: "compact_index"
          expect(the_bundle).to include_gems("depends_on_depends_on_myrack 1.0.1", "depends_on_myrack 1.0.1", "myrack 1.0.0", source: "remote3")
        end
      end
    end

    context "when a top-level gem has an indirect dependency present in the default source, but with a different version from the one resolved" do
      before do
        build_lib "activesupport", "7.0.0.alpha", path: lib_path("rails/activesupport")
        build_lib "rails", "7.0.0.alpha", path: lib_path("rails") do |s|
          s.add_dependency "activesupport", "= 7.0.0.alpha"
        end

        build_repo gem_repo2 do
          build_gem "activesupport", "6.1.2"

          build_gem "webpacker", "5.2.1" do |s|
            s.add_dependency "activesupport", ">= 5.2"
          end
        end

        gemfile <<-G
          source "https://gem.repo2"

          gemspec :path => "#{lib_path("rails")}"

          gem "webpacker", "~> 5.0"
        G
      end

      it "installs all gems without warning" do
        bundle :install, artifice: "compact_index"
        expect(err).not_to include("Warning")
        expect(the_bundle).to include_gems("activesupport 7.0.0.alpha", "rails 7.0.0.alpha")
        expect(the_bundle).to include_gems("activesupport 7.0.0.alpha", source: "path@#{lib_path("rails/activesupport")}")
        expect(the_bundle).to include_gems("rails 7.0.0.alpha", source: "path@#{lib_path("rails")}")
      end
    end

    context "when a pinned gem has an indirect dependency with more than one level of indirection in the default source " do
      before do
        build_repo3 do
          build_gem "handsoap", "0.2.5.5" do |s|
            s.add_dependency "nokogiri", ">= 1.2.3"
          end
        end

        update_repo gem_repo2 do
          build_gem "nokogiri", "1.11.1" do |s|
            s.add_dependency "racca", "~> 1.4"
          end

          build_gem "racca", "1.5.2"
        end

        gemfile <<-G
          source "https://gem.repo2"

          source "https://gem.repo3" do
            gem "handsoap"
          end

          gem "nokogiri"
        G
      end

      it "installs from the default source without any warnings or errors and generates a proper lockfile" do
        checksums = checksums_section_when_enabled do |c|
          c.checksum gem_repo3, "handsoap", "0.2.5.5"
          c.checksum gem_repo2, "nokogiri", "1.11.1"
          c.checksum gem_repo2, "racca", "1.5.2"
        end

        expected_lockfile = <<~L
          GEM
            remote: https://gem.repo2/
            specs:
              nokogiri (1.11.1)
                racca (~> 1.4)
              racca (1.5.2)

          GEM
            remote: https://gem.repo3/
            specs:
              handsoap (0.2.5.5)
                nokogiri (>= 1.2.3)

          PLATFORMS
            #{lockfile_platforms}

          DEPENDENCIES
            handsoap!
            nokogiri
          #{checksums}
          BUNDLED WITH
            #{Bundler::VERSION}
        L

        bundle "install --verbose", artifice: "compact_index"
        expect(err).not_to include("Warning")
        expect(the_bundle).to include_gems("handsoap 0.2.5.5", "nokogiri 1.11.1", "racca 1.5.2")
        expect(the_bundle).to include_gems("handsoap 0.2.5.5", source: "remote3")
        expect(the_bundle).to include_gems("nokogiri 1.11.1", "racca 1.5.2", source: "remote2")
        expect(lockfile).to eq(expected_lockfile)

        # Even if the gems are already installed
        FileUtils.rm bundled_app_lock
        bundle "install --verbose", artifice: "compact_index"
        expect(err).not_to include("Warning")
        expect(the_bundle).to include_gems("handsoap 0.2.5.5", "nokogiri 1.11.1", "racca 1.5.2")
        expect(the_bundle).to include_gems("handsoap 0.2.5.5", source: "remote3")
        expect(the_bundle).to include_gems("nokogiri 1.11.1", "racca 1.5.2", source: "remote2")
        expect(lockfile).to eq(expected_lockfile)
      end
    end

    context "with a gem that is only found in the wrong source" do
      before do
        build_repo3 do
          build_gem "not_in_repo1", "1.0.0"
        end

        install_gemfile <<-G, artifice: "compact_index", raise_on_error: false
          source "https://gem.repo3"
          gem "not_in_repo1", :source => "https://gem.repo1"
        G
      end

      it "does not install the gem" do
        expect(err).to include("Could not find gem 'not_in_repo1'")
      end
    end

    context "with an existing lockfile" do
      before do
        system_gems "myrack-0.9.1", "myrack-1.0.0", path: default_bundle_path

        lockfile <<-L
          GEM
            remote: https://gem.repo1
            specs:

          GEM
            remote: https://gem.repo3
            specs:
              myrack (0.9.1)

          PLATFORMS
            #{lockfile_platforms}

          DEPENDENCIES
            myrack!
        L

        gemfile <<-G
          source "https://gem.repo1"
          source "https://gem.repo3" do
            gem 'myrack'
          end
        G
      end

      # Reproduction of https://github.com/rubygems/bundler/issues/3298
      it "does not unlock the installed gem on exec" do
        expect(the_bundle).to include_gems("myrack 0.9.1")
      end
    end

    context "with a path gem in the same Gemfile" do
      before do
        build_lib "foo"

        gemfile <<-G
          source "https://gem.repo1"
          gem "myrack", :source => "https://gem.repo1"
          gem "foo", :path => "#{lib_path("foo-1.0")}"
        G
      end

      it "does not unlock the non-path gem after install" do
        bundle :install, artifice: "compact_index"

        bundle %(exec ruby -e 'puts "OK"')

        expect(out).to include("OK")
      end
    end
  end

  context "when an older version of the same gem also ships with Ruby" do
    before do
      system_gems "myrack-0.9.1"

      install_gemfile <<-G, artifice: "compact_index"
        source "https://gem.repo1"
        gem "myrack" # should come from repo1!
      G
    end

    it "installs the gems without any warning" do
      expect(err).not_to include("Warning")
      expect(the_bundle).to include_gems("myrack 1.0.0")
    end
  end

  context "when a single source contains multiple locked gems" do
    before do
      # With these gems,
      build_repo4 do
        build_gem "foo", "0.1"
        build_gem "bar", "0.1"
      end

      # Installing this gemfile...
      gemfile <<-G
        source 'https://gem.repo1'
        gem 'myrack'
        gem 'foo', '~> 0.1', :source => 'https://gem.repo4'
        gem 'bar', '~> 0.1', :source => 'https://gem.repo4'
      G

      bundle "config set --local path ../gems/system"
      bundle :install, artifice: "compact_index"

      # And then we add some new versions...
      build_repo4 do
        build_gem "foo", "0.2"
        build_gem "bar", "0.3"
      end
    end

    it "allows them to be unlocked separately" do
      # And install this gemfile, updating only foo.
      install_gemfile <<-G, artifice: "compact_index"
        source 'https://gem.repo1'
        gem 'myrack'
        gem 'foo', '~> 0.2', :source => 'https://gem.repo4'
        gem 'bar', '~> 0.1', :source => 'https://gem.repo4'
      G

      # It should update foo to 0.2, but not the (locked) bar 0.1
      expect(the_bundle).to include_gems("foo 0.2", "bar 0.1")
    end
  end

  context "re-resolving" do
    context "when there is a mix of sources in the gemfile" do
      before do
        build_repo3 do
          build_gem "myrack"
        end

        build_lib "path1"
        build_lib "path2"
        build_git "git1"
        build_git "git2"

        install_gemfile <<-G, artifice: "compact_index"
          source "https://gem.repo1"
          gem "rails"

          source "https://gem.repo3" do
            gem "myrack"
          end

          gem "path1", :path => "#{lib_path("path1-1.0")}"
          gem "path2", :path => "#{lib_path("path2-1.0")}"
          gem "git1",  :git  => "#{lib_path("git1-1.0")}"
          gem "git2",  :git  => "#{lib_path("git2-1.0")}"
        G
      end

      it "does not re-resolve" do
        bundle :install, artifice: "compact_index", verbose: true
        expect(out).to include("using resolution from the lockfile")
        expect(out).not_to include("re-resolving dependencies")
      end
    end
  end

  context "when a gem is installed to system gems" do
    before do
      install_gemfile <<-G, artifice: "compact_index"
        source "https://gem.repo1"
        gem "myrack"
      G
    end

    context "and the gemfile changes" do
      it "is still able to find that gem from remote sources" do
        build_repo4 do
          build_gem "myrack", "2.0.1.1.forked"
          build_gem "thor", "0.19.1.1.forked"
        end

        # When this gemfile is installed...
        install_gemfile <<-G, artifice: "compact_index"
          source "https://gem.repo1"

          source "https://gem.repo4" do
            gem "myrack", "2.0.1.1.forked"
            gem "thor"
          end
          gem "myrack-obama"
        G

        # Then we change the Gemfile by adding a version to thor
        gemfile <<-G
          source "https://gem.repo1"

          source "https://gem.repo4" do
            gem "myrack", "2.0.1.1.forked"
            gem "thor", "0.19.1.1.forked"
          end
          gem "myrack-obama"
        G

        # But we should still be able to find myrack 2.0.1.1.forked and install it
        bundle :install, artifice: "compact_index"
      end
    end
  end

  describe "source changed to one containing a higher version of a dependency" do
    before do
      install_gemfile <<-G, artifice: "compact_index"
        source "https://gem.repo1"

        gem "myrack"
      G

      build_repo2 do
        build_gem "myrack", "1.2" do |s|
          s.executables = "myrackup"
        end

        build_gem "bar"
      end

      build_lib("gemspec_test", path: tmp("gemspec_test")) do |s|
        s.add_dependency "bar", "=1.0.0"
      end

      install_gemfile <<-G, artifice: "compact_index"
        source "https://gem.repo2"
        gem "myrack"
        gemspec :path => "#{tmp("gemspec_test")}"
      G
    end

    it "conservatively installs the existing locked version" do
      expect(the_bundle).to include_gems("myrack 1.0.0")
    end
  end

  context "when Gemfile overrides a gemspec development dependency to change the default source" do
    before do
      build_repo4 do
        build_gem "bar"
      end

      build_lib("gemspec_test", path: tmp("gemspec_test")) do |s|
        s.add_development_dependency "bar"
      end

      install_gemfile <<-G, artifice: "compact_index"
        source "https://gem.repo1"

        source "https://gem.repo4" do
          gem "bar"
        end

        gemspec :path => "#{tmp("gemspec_test")}"
      G
    end

    it "does not print warnings" do
      expect(err).to be_empty
    end
  end

  it "doesn't update version when a gem uses a source block but a higher version from another source is already installed locally" do
    build_repo2 do
      build_gem "example", "0.1.0"
    end

    build_repo4 do
      build_gem "example", "1.0.2"
    end

    install_gemfile <<-G, artifice: "compact_index"
      source "https://gem.repo4"

      gem "example", :source => "https://gem.repo2"
    G

    bundle "info example"
    expect(out).to include("example (0.1.0)")

    system_gems "example-1.0.2", path: default_bundle_path, gem_repo: gem_repo4

    bundle "update example --verbose", artifice: "compact_index"
    expect(out).not_to include("Using example 1.0.2")
    expect(out).to include("Using example 0.1.0")
  end

  it "fails immediately with a helpful error when a rubygems source does not exist and bundler/setup is required" do
    gemfile <<-G
      source "https://gem.repo1"

      source "https://gem.repo4" do
        gem "example"
      end
    G

    ruby <<~R, raise_on_error: false
      require 'bundler/setup'
    R

    expect(last_command).to be_failure
    expect(err).to include("Could not find gem 'example' in locally installed gems.")
  end

  it "fails immediately with a helpful error when a non retriable network error happens while resolving sources" do
    gemfile <<-G
      source "https://gem.repo1"

      source "https://gem.repo4" do
        gem "example"
      end
    G

    bundle "install", artifice: nil, raise_on_error: false

    expect(last_command).to be_failure
    expect(err).to include("Could not reach host gem.repo4. Check your network connection and try again.")
  end

  context "when an indirect dependency is available from multiple ambiguous sources" do
    it "raises, suggesting a source block" do
      build_repo4 do
        build_gem "depends_on_myrack" do |s|
          s.add_dependency "myrack"
        end
        build_gem "myrack"
      end

      install_gemfile <<-G, artifice: "compact_index_extra_api", raise_on_error: false
        source "https://global.source"

        source "https://scoped.source/extra" do
          gem "depends_on_myrack"
        end

        source "https://scoped.source" do
          gem "thin"
        end
      G
      expect(last_command).to be_failure
      expect(err).to eq <<~EOS.strip
        The gem 'myrack' was found in multiple relevant sources.
          * rubygems repository https://scoped.source/
          * rubygems repository https://scoped.source/extra/
        You must add this gem to the source block for the source you wish it to be installed from.
      EOS
      expect(the_bundle).not_to be_locked
    end
  end

  context "when default source includes old gems with nil required_ruby_version" do
    before do
      build_repo2 do
        build_gem "ruport", "1.7.0.3" do |s|
          s.add_dependency "pdf-writer", "1.1.8"
        end
      end

      build_repo gem_repo4 do
        build_gem "pdf-writer", "1.1.8"
      end

      path = "#{gem_repo4}/#{Gem::MARSHAL_SPEC_DIR}/pdf-writer-1.1.8.gemspec.rz"
      spec = Marshal.load(Bundler.rubygems.inflate(File.binread(path)))
      spec.instance_variable_set(:@required_ruby_version, nil)
      File.open(path, "wb") do |f|
        f.write Gem.deflate(Marshal.dump(spec))
      end

      gemfile <<~G
        source "https://gem.repo4"

        gem "ruport", "= 1.7.0.3", :source => "https://gem.repo4/extra"
      G
    end

    it "handles that fine" do
      bundle "install", artifice: "compact_index_extra"

      checksums = checksums_section_when_enabled do |c|
        c.checksum gem_repo4, "pdf-writer", "1.1.8"
        c.checksum gem_repo2, "ruport", "1.7.0.3"
      end

      expect(lockfile).to eq <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            pdf-writer (1.1.8)

        GEM
          remote: https://gem.repo4/extra/
          specs:
            ruport (1.7.0.3)
              pdf-writer (= 1.1.8)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          ruport (= 1.7.0.3)!
        #{checksums}
        BUNDLED WITH
          #{Bundler::VERSION}
      L
    end
  end

  context "when default source includes old gems with nil required_rubygems_version" do
    before do
      build_repo2 do
        build_gem "ruport", "1.7.0.3" do |s|
          s.add_dependency "pdf-writer", "1.1.8"
        end
      end

      build_repo gem_repo4 do
        build_gem "pdf-writer", "1.1.8"
      end

      path = "#{gem_repo4}/#{Gem::MARSHAL_SPEC_DIR}/pdf-writer-1.1.8.gemspec.rz"
      spec = Marshal.load(Bundler.rubygems.inflate(File.binread(path)))
      spec.instance_variable_set(:@required_rubygems_version, nil)
      File.open(path, "wb") do |f|
        f.write Gem.deflate(Marshal.dump(spec))
      end

      gemfile <<~G
        source "https://gem.repo4"

        gem "ruport", "= 1.7.0.3", :source => "https://gem.repo4/extra"
      G
    end

    it "handles that fine" do
      bundle "install", artifice: "compact_index_extra"

      checksums = checksums_section_when_enabled do |c|
        c.checksum gem_repo4, "pdf-writer", "1.1.8"
        c.checksum gem_repo2, "ruport", "1.7.0.3"
      end

      expect(lockfile).to eq <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            pdf-writer (1.1.8)

        GEM
          remote: https://gem.repo4/extra/
          specs:
            ruport (1.7.0.3)
              pdf-writer (= 1.1.8)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          ruport (= 1.7.0.3)!
        #{checksums}
        BUNDLED WITH
          #{Bundler::VERSION}
      L
    end
  end

  context "when default source uses the old API and includes old gems with nil required_rubygems_version" do
    before do
      build_repo4 do
        build_gem "pdf-writer", "1.1.8"
      end

      path = "#{gem_repo4}/#{Gem::MARSHAL_SPEC_DIR}/pdf-writer-1.1.8.gemspec.rz"
      spec = Marshal.load(Bundler.rubygems.inflate(File.binread(path)))
      spec.instance_variable_set(:@required_rubygems_version, nil)
      File.open(path, "wb") do |f|
        f.write Gem.deflate(Marshal.dump(spec))
      end

      gemfile <<~G
        source "https://gem.repo4"

        gem "pdf-writer", "= 1.1.8"
      G
    end

    it "handles that fine" do
      bundle "install --verbose", artifice: "endpoint"

      checksums = checksums_section_when_enabled do |c|
        c.checksum gem_repo4, "pdf-writer", "1.1.8"
      end

      expect(lockfile).to eq <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            pdf-writer (1.1.8)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          pdf-writer (= 1.1.8)
        #{checksums}
        BUNDLED WITH
          #{Bundler::VERSION}
      L
    end
  end

  context "when mistakenly adding a top level gem already depended on and cached under the wrong source" do
    before do
      build_repo4 do
        build_gem "some_private_gem", "0.1.0" do |s|
          s.add_dependency "example", "~> 1.0"
        end
      end

      build_repo2 do
        build_gem "example", "1.0.0"
      end

      install_gemfile <<~G, artifice: "compact_index"
        source "https://gem.repo2"

        source "https://gem.repo4" do
          gem "some_private_gem"
        end
      G

      gemfile <<~G
        source "https://gem.repo2"

        source "https://gem.repo4" do
          gem "some_private_gem"
          gem "example" # MISTAKE, example is not available at gem.repo4
        end
      G
    end

    it "shows a proper error message and does not generate a corrupted lockfile" do
      expect do
        bundle :install, artifice: "compact_index", raise_on_error: false, env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
      end.not_to change { lockfile }

      expect(err).to include("Could not find gem 'example' in rubygems repository https://gem.repo4/")
    end
  end

  context "when a gem has versions in two sources, but only the locked one has updates" do
    let(:original_lockfile) do
      <<~L
        GEM
          remote: https://main.source/
          specs:
            activesupport (1.0)
              bigdecimal
            bigdecimal (1.0.0)

        GEM
          remote: https://main.source/extra/
          specs:
            foo (1.0)
              bigdecimal

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          activesupport
          foo!

        BUNDLED WITH
          #{Bundler::VERSION}
      L
    end

    before do
      build_repo3 do
        build_gem "activesupport" do |s|
          s.add_dependency "bigdecimal"
        end

        build_gem "bigdecimal", "1.0.0"
        build_gem "bigdecimal", "3.3.1"
      end

      build_repo4 do
        build_gem "foo" do |s|
          s.add_dependency "bigdecimal"
        end

        build_gem "bigdecimal", "1.0.0"
      end

      gemfile <<~G
        source "https://main.source"

        gem "activesupport"

        source "https://main.source/extra" do
          gem "foo"
        end
      G

      lockfile original_lockfile
    end

    it "properly upgrades the lockfile when updating that specific gem" do
      bundle "update bigdecimal --conservative", artifice: "compact_index_extra_api", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo3.to_s }

      expect(lockfile).to eq original_lockfile.gsub("bigdecimal (1.0.0)", "bigdecimal (3.3.1)")
    end
  end
end
