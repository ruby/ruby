# frozen_string_literal: true

RSpec.describe "bundle install with gems on multiple sources" do
  # repo1 is built automatically before all of the specs run
  # it contains rack-obama 1.0.0 and rack 0.9.1 & 1.0.0 amongst other gems

  context "without source affinity" do
    before do
      # Oh no! Someone evil is trying to hijack rack :(
      # need this to be broken to check for correct source ordering
      build_repo gem_repo3 do
        build_gem "rack", repo3_rack_version do |s|
          s.write "lib/rack.rb", "RACK = 'FAIL'"
        end
      end
    end

    context "with multiple toplevel sources" do
      let(:repo3_rack_version) { "1.0.0" }

      before do
        gemfile <<-G
          source "#{file_uri_for(gem_repo3)}"
          source "#{file_uri_for(gem_repo1)}"
          gem "rack-obama"
          gem "rack"
        G
      end

      it "warns about ambiguous gems, but installs anyway, prioritizing sources last to first", :bundler => "2" do
        bundle :install

        expect(err).to include("Warning: the gem 'rack' was found in multiple sources.")
        expect(err).to include("Installed from: #{file_uri_for(gem_repo1)}")
        expect(the_bundle).to include_gems("rack-obama 1.0.0", "rack 1.0.0", :source => "remote1")
      end

      it "fails", :bundler => "3" do
        bundle :instal, :raise_on_error => false
        expect(err).to include("Each source after the first must include a block")
        expect(exitstatus).to eq(4)
      end
    end

    context "when different versions of the same gem are in multiple sources" do
      let(:repo3_rack_version) { "1.2" }

      before do
        gemfile <<-G
          source "#{file_uri_for(gem_repo3)}"
          source "#{file_uri_for(gem_repo1)}"
          gem "rack-obama"
          gem "rack", "1.0.0" # force it to install the working version in repo1
        G
      end

      it "warns about ambiguous gems, but installs anyway", :bundler => "2" do
        bundle :install
        expect(err).to include("Warning: the gem 'rack' was found in multiple sources.")
        expect(err).to include("Installed from: #{file_uri_for(gem_repo1)}")
        expect(the_bundle).to include_gems("rack-obama 1.0.0", "rack 1.0.0", :source => "remote1")
      end

      it "fails", :bundler => "3" do
        bundle :install, :raise_on_error => false
        expect(err).to include("Each source after the first must include a block")
        expect(exitstatus).to eq(4)
      end
    end
  end

  context "with source affinity" do
    context "with sources given by a block" do
      before do
        # Oh no! Someone evil is trying to hijack rack :(
        # need this to be broken to check for correct source ordering
        build_repo gem_repo3 do
          build_gem "rack", "1.0.0" do |s|
            s.write "lib/rack.rb", "RACK = 'FAIL'"
          end

          build_gem "rack-obama" do |s|
            s.add_dependency "rack"
          end
        end

        gemfile <<-G
          source "#{file_uri_for(gem_repo3)}"
          source "#{file_uri_for(gem_repo1)}" do
            gem "thin" # comes first to test name sorting
            gem "rack"
          end
          gem "rack-obama" # shoud come from repo3!
        G
      end

      it "installs the gems without any warning" do
        bundle :install
        expect(out).not_to include("Warning")
        expect(the_bundle).to include_gems("rack-obama 1.0.0")
        expect(the_bundle).to include_gems("rack 1.0.0", :source => "remote1")
      end

      it "can cache and deploy" do
        bundle :cache

        expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
        expect(bundled_app("vendor/cache/rack-obama-1.0.gem")).to exist

        bundle "config --local deployment true"
        bundle :install

        expect(the_bundle).to include_gems("rack-obama 1.0.0", "rack 1.0.0")
      end
    end

    context "with sources set by an option" do
      before do
        # Oh no! Someone evil is trying to hijack rack :(
        # need this to be broken to check for correct source ordering
        build_repo gem_repo3 do
          build_gem "rack", "1.0.0" do |s|
            s.write "lib/rack.rb", "RACK = 'FAIL'"
          end

          build_gem "rack-obama" do |s|
            s.add_dependency "rack"
          end
        end

        gemfile <<-G
          source "#{file_uri_for(gem_repo3)}"
          gem "rack-obama" # should come from repo3!
          gem "rack", :source => "#{file_uri_for(gem_repo1)}"
        G
      end

      it "installs the gems without any warning" do
        bundle :install
        expect(out).not_to include("Warning")
        expect(the_bundle).to include_gems("rack-obama 1.0.0", "rack 1.0.0")
      end
    end

    context "when a pinned gem has an indirect dependency" do
      before do
        build_repo gem_repo3 do
          build_gem "depends_on_rack", "1.0.1" do |s|
            s.add_dependency "rack"
          end
        end
      end

      context "when the indirect dependency is in the pinned source" do
        before do
          # we need a working rack gem in repo3
          update_repo gem_repo3 do
            build_gem "rack", "1.0.0"
          end

          gemfile <<-G
            source "#{file_uri_for(gem_repo2)}"
            source "#{file_uri_for(gem_repo3)}" do
              gem "depends_on_rack"
            end
          G
        end

        context "and not in any other sources" do
          before do
            build_repo(gem_repo2) {}
          end

          it "installs from the same source without any warning" do
            bundle :install
            expect(out).not_to include("Warning")
            expect(the_bundle).to include_gems("depends_on_rack 1.0.1", "rack 1.0.0")
          end
        end

        context "and in another source" do
          before do
            # need this to be broken to check for correct source ordering
            build_repo gem_repo2 do
              build_gem "rack", "1.0.0" do |s|
                s.write "lib/rack.rb", "RACK = 'FAIL'"
              end
            end
          end

          context "when disable_multisource is set" do
            before do
              bundle "config set disable_multisource true"
            end

            it "installs from the same source without any warning" do
              bundle :install

              expect(out).not_to include("Warning: the gem 'rack' was found in multiple sources.")
              expect(err).not_to include("Warning: the gem 'rack' was found in multiple sources.")
              expect(the_bundle).to include_gems("depends_on_rack 1.0.1", "rack 1.0.0")

              # when there is already a lock file, and the gems are missing, so try again
              system_gems []
              bundle :install

              expect(out).not_to include("Warning: the gem 'rack' was found in multiple sources.")
              expect(err).not_to include("Warning: the gem 'rack' was found in multiple sources.")
              expect(the_bundle).to include_gems("depends_on_rack 1.0.1", "rack 1.0.0")
            end
          end
        end
      end

      context "when the indirect dependency is in a different source" do
        before do
          # In these tests, we need a working rack gem in repo2 and not repo3
          build_repo gem_repo2 do
            build_gem "rack", "1.0.0"
          end
        end

        context "and not in any other sources" do
          before do
            gemfile <<-G
              source "#{file_uri_for(gem_repo2)}"
              source "#{file_uri_for(gem_repo3)}" do
                gem "depends_on_rack"
              end
            G
          end

          it "installs from the other source without any warning" do
            bundle :install
            expect(out).not_to include("Warning")
            expect(the_bundle).to include_gems("depends_on_rack 1.0.1", "rack 1.0.0")
          end
        end

        context "and in yet another source" do
          before do
            gemfile <<-G
              source "#{file_uri_for(gem_repo1)}"
              source "#{file_uri_for(gem_repo2)}"
              source "#{file_uri_for(gem_repo3)}" do
                gem "depends_on_rack"
              end
            G
          end

          it "installs from the other source and warns about ambiguous gems", :bundler => "2" do
            bundle :install
            expect(err).to include("Warning: the gem 'rack' was found in multiple sources.")
            expect(err).to include("Installed from: #{file_uri_for(gem_repo2)}")
            expect(the_bundle).to include_gems("depends_on_rack 1.0.1", "rack 1.0.0")
          end

          it "fails", :bundler => "3" do
            bundle :install, :raise_on_error => false
            expect(err).to include("Each source after the first must include a block")
            expect(exitstatus).to eq(4)
          end
        end

        context "and only the dependency is pinned" do
          before do
            # need this to be broken to check for correct source ordering
            build_repo gem_repo2 do
              build_gem "rack", "1.0.0" do |s|
                s.write "lib/rack.rb", "RACK = 'FAIL'"
              end
            end

            gemfile <<-G
              source "#{file_uri_for(gem_repo3)}" # contains depends_on_rack
              source "#{file_uri_for(gem_repo2)}" # contains broken rack

              gem "depends_on_rack" # installed from gem_repo3
              gem "rack", :source => "#{file_uri_for(gem_repo1)}"
            G
          end

          it "installs the dependency from the pinned source without warning", :bundler => "2" do
            bundle :install

            expect(err).not_to include("Warning: the gem 'rack' was found in multiple sources.")
            expect(the_bundle).to include_gems("depends_on_rack 1.0.1", "rack 1.0.0")

            # In https://github.com/rubygems/bundler/issues/3585 this failed
            # when there is already a lock file, and the gems are missing, so try again
            system_gems []
            bundle :install

            expect(err).not_to include("Warning: the gem 'rack' was found in multiple sources.")
            expect(the_bundle).to include_gems("depends_on_rack 1.0.1", "rack 1.0.0")
          end

          it "fails", :bundler => "3" do
            bundle :install, :raise_on_error => false
            expect(err).to include("Each source after the first must include a block")
            expect(exitstatus).to eq(4)
          end
        end
      end
    end

    context "when a top-level gem has an indirect dependency" do
      context "when disable_multisource is set" do
        before do
          bundle "config set disable_multisource true"
        end

        before do
          build_repo gem_repo2 do
            build_gem "depends_on_rack", "1.0.1" do |s|
              s.add_dependency "rack"
            end
          end

          build_repo gem_repo3 do
            build_gem "unrelated_gem", "1.0.0"
          end

          gemfile <<-G
            source "#{file_uri_for(gem_repo2)}"

            gem "depends_on_rack"

            source "#{file_uri_for(gem_repo3)}" do
              gem "unrelated_gem"
            end
          G
        end

        context "and the dependency is only in the top-level source" do
          before do
            update_repo gem_repo2 do
              build_gem "rack", "1.0.0"
            end
          end

          it "installs all gems without warning" do
            bundle :install
            expect(err).not_to include("Warning")
            expect(the_bundle).to include_gems("depends_on_rack 1.0.1", "rack 1.0.0", "unrelated_gem 1.0.0")
          end
        end

        context "and the dependency is only in a pinned source" do
          before do
            update_repo gem_repo3 do
              build_gem "rack", "1.0.0" do |s|
                s.write "lib/rack.rb", "RACK = 'FAIL'"
              end
            end
          end

          it "does not find the dependency" do
            bundle :install, :raise_on_error => false
            expect(err).to include("Could not find gem 'rack', which is required by gem 'depends_on_rack', in any of the relevant sources")
          end
        end

        context "and the dependency is in both the top-level and a pinned source" do
          before do
            update_repo gem_repo2 do
              build_gem "rack", "1.0.0"
            end

            update_repo gem_repo3 do
              build_gem "rack", "1.0.0" do |s|
                s.write "lib/rack.rb", "RACK = 'FAIL'"
              end
            end
          end

          it "installs the dependency from the top-level source without warning" do
            bundle :install
            expect(err).not_to include("Warning")
            expect(the_bundle).to include_gems("depends_on_rack 1.0.1", "rack 1.0.0", "unrelated_gem 1.0.0")
          end
        end
      end
    end

    context "with a gem that is only found in the wrong source" do
      before do
        build_repo gem_repo3 do
          build_gem "not_in_repo1", "1.0.0"
        end

        gemfile <<-G
          source "#{file_uri_for(gem_repo3)}"
          gem "not_in_repo1", :source => "#{file_uri_for(gem_repo1)}"
        G
      end

      it "does not install the gem" do
        bundle :install, :raise_on_error => false
        expect(err).to include("Could not find gem 'not_in_repo1'")
      end
    end

    context "with an existing lockfile" do
      before do
        system_gems "rack-0.9.1", "rack-1.0.0", :path => default_bundle_path

        lockfile <<-L
          GEM
            remote: #{file_uri_for(gem_repo1)}
            remote: #{file_uri_for(gem_repo3)}
            specs:
              rack (0.9.1)

          PLATFORMS
            ruby

          DEPENDENCIES
            rack!
        L

        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          source "#{file_uri_for(gem_repo3)}" do
            gem 'rack'
          end
        G
      end

      # Reproduction of https://github.com/rubygems/bundler/issues/3298
      it "does not unlock the installed gem on exec" do
        expect(the_bundle).to include_gems("rack 0.9.1")
      end
    end

    context "with a path gem in the same Gemfile" do
      before do
        build_lib "foo"

        gemfile <<-G
          gem "rack", :source => "#{file_uri_for(gem_repo1)}"
          gem "foo", :path => "#{lib_path("foo-1.0")}"
        G
      end

      it "does not unlock the non-path gem after install" do
        bundle :install

        bundle %(exec ruby -e 'puts "OK"')

        expect(out).to include("OK")
      end
    end
  end

  context "when an older version of the same gem also ships with Ruby" do
    before do
      system_gems "rack-0.9.1"

      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack" # shoud come from repo1!
      G
    end

    it "installs the gems without any warning" do
      bundle :install
      expect(err).not_to include("Warning")
      expect(the_bundle).to include_gems("rack 1.0.0")
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
        source '#{file_uri_for(gem_repo1)}'
        gem 'rack'
        gem 'foo', '~> 0.1', :source => '#{file_uri_for(gem_repo4)}'
        gem 'bar', '~> 0.1', :source => '#{file_uri_for(gem_repo4)}'
      G

      bundle "config --local path ../gems/system"
      bundle :install

      # And then we add some new versions...
      update_repo4 do
        build_gem "foo", "0.2"
        build_gem "bar", "0.3"
      end
    end

    it "allows them to be unlocked separately" do
      # And install this gemfile, updating only foo.
      install_gemfile <<-G
        source '#{file_uri_for(gem_repo1)}'
        gem 'rack'
        gem 'foo', '~> 0.2', :source => '#{file_uri_for(gem_repo4)}'
        gem 'bar', '~> 0.1', :source => '#{file_uri_for(gem_repo4)}'
      G

      # It should update foo to 0.2, but not the (locked) bar 0.1
      expect(the_bundle).to include_gems("foo 0.2", "bar 0.1")
    end
  end

  context "re-resolving" do
    context "when there is a mix of sources in the gemfile" do
      before do
        build_repo3
        build_lib "path1"
        build_lib "path2"
        build_git "git1"
        build_git "git2"

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "rails"

          source "#{file_uri_for(gem_repo3)}" do
            gem "rack"
          end

          gem "path1", :path => "#{lib_path("path1-1.0")}"
          gem "path2", :path => "#{lib_path("path2-1.0")}"
          gem "git1",  :git  => "#{lib_path("git1-1.0")}"
          gem "git2",  :git  => "#{lib_path("git2-1.0")}"
        G
      end

      it "does not re-resolve" do
        bundle :install, :verbose => true
        expect(out).to include("using resolution from the lockfile")
        expect(out).not_to include("re-resolving dependencies")
      end
    end
  end

  context "when a gem is installed to system gems" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G
    end

    context "and the gemfile changes" do
      it "is still able to find that gem from remote sources" do
        source_uri = file_uri_for(gem_repo1)
        second_uri = file_uri_for(gem_repo4)

        build_repo4 do
          build_gem "rack", "2.0.1.1.forked"
          build_gem "thor", "0.19.1.1.forked"
        end

        # When this gemfile is installed...
        install_gemfile <<-G
          source "#{source_uri}"

          source "#{second_uri}" do
            gem "rack", "2.0.1.1.forked"
            gem "thor"
          end
          gem "rack-obama"
        G

        # Then we change the Gemfile by adding a version to thor
        gemfile <<-G
          source "#{source_uri}"

          source "#{second_uri}" do
            gem "rack", "2.0.1.1.forked"
            gem "thor", "0.19.1.1.forked"
          end
          gem "rack-obama"
        G

        # But we should still be able to find rack 2.0.1.1.forked and install it
        bundle :install
      end
    end
  end

  describe "source changed to one containing a higher version of a dependency" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        gem "rack"
      G

      build_repo2 do
        build_gem "bar"
      end

      build_lib("gemspec_test", :path => tmp.join("gemspec_test")) do |s|
        s.add_dependency "bar", "=1.0.0"
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rack"
        gemspec :path => "#{tmp.join("gemspec_test")}"
      G
    end

    it "keeps the old version", :bundler => "2" do
      expect(the_bundle).to include_gems("rack 1.0.0")
    end

    it "installs the higher version in the new repo", :bundler => "3" do
      expect(the_bundle).to include_gems("rack 1.2")
    end
  end

  context "when a gem is available from multiple ambiguous sources", :bundler => "3" do
    it "raises, suggesting a source block" do
      build_repo4 do
        build_gem "depends_on_rack" do |s|
          s.add_dependency "rack"
        end
        build_gem "rack"
      end

      install_gemfile <<-G, :raise_on_error => false
        source "#{file_uri_for(gem_repo4)}"
        source "#{file_uri_for(gem_repo1)}" do
          gem "thin"
        end
        gem "depends_on_rack"
      G
      expect(last_command).to be_failure
      expect(err).to eq strip_whitespace(<<-EOS).strip
        The gem 'rack' was found in multiple relevant sources.
          * rubygems repository #{file_uri_for(gem_repo1)}/ or installed locally
          * rubygems repository #{file_uri_for(gem_repo4)}/ or installed locally
        You must add this gem to the source block for the source you wish it to be installed from.
      EOS
      expect(the_bundle).not_to be_locked
    end
  end
end
