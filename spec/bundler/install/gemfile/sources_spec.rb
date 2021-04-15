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

      it "warns about ambiguous gems, but installs anyway, prioritizing sources last to first", :bundler => "< 3" do
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

      it "warns about ambiguous gems, but installs anyway", :bundler => "< 3" do
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
        expect(err).not_to include("Warning")
        expect(the_bundle).to include_gems("rack-obama 1.0.0")
        expect(the_bundle).to include_gems("rack 1.0.0", :source => "remote1")
      end

      it "can cache and deploy" do
        bundle :cache

        expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
        expect(bundled_app("vendor/cache/rack-obama-1.0.gem")).to exist

        bundle "config set --local deployment true"
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

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo3)}"
          gem "rack-obama" # should come from repo3!
          gem "rack", :source => "#{file_uri_for(gem_repo1)}"
        G
      end

      it "installs the gems without any warning" do
        expect(err).not_to include("Warning")
        expect(the_bundle).to include_gems("rack-obama 1.0.0", "rack 1.0.0")
      end
    end

    context "when a pinned gem has an indirect dependency in the pinned source" do
      before do
        build_repo gem_repo3 do
          build_gem "depends_on_rack", "1.0.1" do |s|
            s.add_dependency "rack"
          end
        end

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
          expect(err).not_to include("Warning")
          expect(the_bundle).to include_gems("depends_on_rack 1.0.1", "rack 1.0.0", :source => "remote3")
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

        it "installs from the same source without any warning" do
          bundle :install

          expect(err).not_to include("Warning: the gem 'rack' was found in multiple sources.")
          expect(the_bundle).to include_gems("depends_on_rack 1.0.1", "rack 1.0.0", :source => "remote3")

          # In https://github.com/bundler/bundler/issues/3585 this failed
          # when there is already a lock file, and the gems are missing, so try again
          system_gems []
          bundle :install

          expect(err).not_to include("Warning: the gem 'rack' was found in multiple sources.")
          expect(the_bundle).to include_gems("depends_on_rack 1.0.1", "rack 1.0.0", :source => "remote3")
        end
      end
    end

    context "when a pinned gem has an indirect dependency in a different source" do
      before do
        # In these tests, we need a working rack gem in repo2 and not repo3

        build_repo gem_repo3 do
          build_gem "depends_on_rack", "1.0.1" do |s|
            s.add_dependency "rack"
          end
        end

        build_repo gem_repo2 do
          build_gem "rack", "1.0.0"
        end
      end

      context "and not in any other sources" do
        before do
          install_gemfile <<-G
            source "#{file_uri_for(gem_repo2)}"
            source "#{file_uri_for(gem_repo3)}" do
              gem "depends_on_rack"
            end
          G
        end

        it "installs from the other source without any warning" do
          expect(err).not_to include("Warning")
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

        it "installs from the other source and warns about ambiguous gems", :bundler => "< 3" do
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

        it "installs the dependency from the pinned source without warning", :bundler => "< 3" do
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

    context "when a top-level gem can only be found in an scoped source" do
      before do
        build_repo2

        build_repo gem_repo3 do
          build_gem "private_gem_1", "1.0.0"
          build_gem "private_gem_2", "1.0.0"
        end

        gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"

          gem "private_gem_1"

          source "#{file_uri_for(gem_repo3)}" do
            gem "private_gem_2"
          end
        G
      end

      it "fails" do
        bundle :install, :raise_on_error => false
        expect(err).to include("Could not find gem 'private_gem_1' in rubygems repository #{file_uri_for(gem_repo2)}/ or installed locally.")
        expect(err).to include("The source does not contain any versions of 'private_gem_1'")
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

      context "when the lockfile has aggregated rubygems sources and newer versions of dependencies are available" do
        before do
          build_repo gem_repo2 do
            build_gem "activesupport", "6.0.3.4" do |s|
              s.add_dependency "concurrent-ruby", "~> 1.0", ">= 1.0.2"
              s.add_dependency "i18n", ">= 0.7", "< 2"
              s.add_dependency "minitest", "~> 5.1"
              s.add_dependency "tzinfo", "~> 1.1"
              s.add_dependency "zeitwerk", "~> 2.2", ">= 2.2.2"
            end

            build_gem "activesupport", "6.1.2.1" do |s|
              s.add_dependency "concurrent-ruby", "~> 1.0", ">= 1.0.2"
              s.add_dependency "i18n", ">= 1.6", "< 2"
              s.add_dependency "minitest", ">= 5.1"
              s.add_dependency "tzinfo", "~> 2.0"
              s.add_dependency "zeitwerk", "~> 2.3"
            end

            build_gem "concurrent-ruby", "1.1.8"
            build_gem "concurrent-ruby", "1.1.9"
            build_gem "connection_pool", "2.2.3"

            build_gem "i18n", "1.8.9" do |s|
              s.add_dependency "concurrent-ruby", "~> 1.0"
            end

            build_gem "minitest", "5.14.3"
            build_gem "rack", "2.2.3"
            build_gem "redis", "4.2.5"

            build_gem "sidekiq", "6.1.3" do |s|
              s.add_dependency "connection_pool", ">= 2.2.2"
              s.add_dependency "rack", "~> 2.0"
              s.add_dependency "redis", ">= 4.2.0"
            end

            build_gem "thread_safe", "0.3.6"

            build_gem "tzinfo", "1.2.9" do |s|
              s.add_dependency "thread_safe", "~> 0.1"
            end

            build_gem "tzinfo", "2.0.4" do |s|
              s.add_dependency "concurrent-ruby", "~> 1.0"
            end

            build_gem "zeitwerk", "2.4.2"
          end

          build_repo gem_repo3 do
            build_gem "sidekiq-pro", "5.2.1" do |s|
              s.add_dependency "connection_pool", ">= 2.2.3"
              s.add_dependency "sidekiq", ">= 6.1.0"
            end
          end

          gemfile <<-G
            # frozen_string_literal: true

            source "#{file_uri_for(gem_repo2)}"

            gem "activesupport"

            source "#{file_uri_for(gem_repo3)}" do
              gem "sidekiq-pro"
            end
          G

          lockfile <<~L
            GEM
              remote: #{file_uri_for(gem_repo2)}/
              remote: #{file_uri_for(gem_repo3)}/
              specs:
                activesupport (6.0.3.4)
                  concurrent-ruby (~> 1.0, >= 1.0.2)
                  i18n (>= 0.7, < 2)
                  minitest (~> 5.1)
                  tzinfo (~> 1.1)
                  zeitwerk (~> 2.2, >= 2.2.2)
                concurrent-ruby (1.1.8)
                connection_pool (2.2.3)
                i18n (1.8.9)
                  concurrent-ruby (~> 1.0)
                minitest (5.14.3)
                rack (2.2.3)
                redis (4.2.5)
                sidekiq (6.1.3)
                  connection_pool (>= 2.2.2)
                  rack (~> 2.0)
                  redis (>= 4.2.0)
                sidekiq-pro (5.2.1)
                  connection_pool (>= 2.2.3)
                  sidekiq (>= 6.1.0)
                thread_safe (0.3.6)
                tzinfo (1.2.9)
                  thread_safe (~> 0.1)
                zeitwerk (2.4.2)

            PLATFORMS
              #{specific_local_platform}

            DEPENDENCIES
              activesupport
              sidekiq-pro!

            BUNDLED WITH
               #{Bundler::VERSION}
          L
        end

        it "does not install newer versions or generate lockfile changes when running bundle install, and warns", :bundler => "< 3" do
          initial_lockfile = lockfile

          bundle :install

          expect(err).to include("Your lockfile contains a single rubygems source section with multiple remotes, which is insecure.")

          expect(the_bundle).to include_gems("activesupport 6.0.3.4")
          expect(the_bundle).not_to include_gems("activesupport 6.1.2.1")
          expect(the_bundle).to include_gems("tzinfo 1.2.9")
          expect(the_bundle).not_to include_gems("tzinfo 2.0.4")
          expect(the_bundle).to include_gems("concurrent-ruby 1.1.8")
          expect(the_bundle).not_to include_gems("concurrent-ruby 1.1.9")

          expect(lockfile).to eq(initial_lockfile)
        end

        it "fails when running bundle install", :bundler => "3" do
          initial_lockfile = lockfile

          bundle :install, :raise_on_error => false

          expect(err).to include("Your lockfile contains a single rubygems source section with multiple remotes, which is insecure.")

          expect(lockfile).to eq(initial_lockfile)
        end

        it "splits sections and upgrades gems when running bundle update, and doesn't warn" do
          bundle "update --all"
          expect(err).to be_empty

          expect(the_bundle).not_to include_gems("activesupport 6.0.3.4")
          expect(the_bundle).to include_gems("activesupport 6.1.2.1")
          expect(the_bundle).not_to include_gems("tzinfo 1.2.9")
          expect(the_bundle).to include_gems("tzinfo 2.0.4")
          expect(the_bundle).not_to include_gems("concurrent-ruby 1.1.8")
          expect(the_bundle).to include_gems("concurrent-ruby 1.1.9")

          expect(lockfile).to eq <<~L
            GEM
              remote: #{file_uri_for(gem_repo2)}/
              specs:
                activesupport (6.1.2.1)
                  concurrent-ruby (~> 1.0, >= 1.0.2)
                  i18n (>= 1.6, < 2)
                  minitest (>= 5.1)
                  tzinfo (~> 2.0)
                  zeitwerk (~> 2.3)
                concurrent-ruby (1.1.9)
                connection_pool (2.2.3)
                i18n (1.8.9)
                  concurrent-ruby (~> 1.0)
                minitest (5.14.3)
                rack (2.2.3)
                redis (4.2.5)
                sidekiq (6.1.3)
                  connection_pool (>= 2.2.2)
                  rack (~> 2.0)
                  redis (>= 4.2.0)
                tzinfo (2.0.4)
                  concurrent-ruby (~> 1.0)
                zeitwerk (2.4.2)

            GEM
              remote: #{file_uri_for(gem_repo3)}/
              specs:
                sidekiq-pro (5.2.1)
                  connection_pool (>= 2.2.3)
                  sidekiq (>= 6.1.0)

            PLATFORMS
              #{specific_local_platform}

            DEPENDENCIES
              activesupport
              sidekiq-pro!

            BUNDLED WITH
               #{Bundler::VERSION}
          L
        end

        it "it keeps the currrent lockfile format and upgrades the requested gem when running bundle update with an argument, and warns", :bundler => "< 3" do
          bundle "update concurrent-ruby"
          expect(err).to include("Your lockfile contains a single rubygems source section with multiple remotes, which is insecure.")

          expect(the_bundle).to include_gems("activesupport 6.0.3.4")
          expect(the_bundle).not_to include_gems("activesupport 6.1.2.1")
          expect(the_bundle).to include_gems("tzinfo 1.2.9")
          expect(the_bundle).not_to include_gems("tzinfo 2.0.4")
          expect(the_bundle).to include_gems("concurrent-ruby 1.1.9")
          expect(the_bundle).not_to include_gems("concurrent-ruby 1.1.8")

          expect(lockfile).to eq <<~L
            GEM
              remote: #{file_uri_for(gem_repo2)}/
              remote: #{file_uri_for(gem_repo3)}/
              specs:
                activesupport (6.0.3.4)
                  concurrent-ruby (~> 1.0, >= 1.0.2)
                  i18n (>= 0.7, < 2)
                  minitest (~> 5.1)
                  tzinfo (~> 1.1)
                  zeitwerk (~> 2.2, >= 2.2.2)
                concurrent-ruby (1.1.9)
                connection_pool (2.2.3)
                i18n (1.8.9)
                  concurrent-ruby (~> 1.0)
                minitest (5.14.3)
                rack (2.2.3)
                redis (4.2.5)
                sidekiq (6.1.3)
                  connection_pool (>= 2.2.2)
                  rack (~> 2.0)
                  redis (>= 4.2.0)
                sidekiq-pro (5.2.1)
                  connection_pool (>= 2.2.3)
                  sidekiq (>= 6.1.0)
                thread_safe (0.3.6)
                tzinfo (1.2.9)
                  thread_safe (~> 0.1)
                zeitwerk (2.4.2)

            PLATFORMS
              #{specific_local_platform}

            DEPENDENCIES
              activesupport
              sidekiq-pro!

            BUNDLED WITH
               #{Bundler::VERSION}
          L
        end

        it "fails when running bundle update with an argument", :bundler => "3" do
          initial_lockfile = lockfile

          bundle "update concurrent-ruby", :raise_on_error => false

          expect(err).to include("Your lockfile contains a single rubygems source section with multiple remotes, which is insecure.")

          expect(lockfile).to eq(initial_lockfile)
        end
      end
    end

    context "when a top-level gem has an indirect dependency present in the default source, but with a different version from the one resolved", :bundler => "< 3" do
      before do
        build_lib "activesupport", "7.0.0.alpha", :path => lib_path("rails/activesupport")
        build_lib "rails", "7.0.0.alpha", :path => lib_path("rails") do |s|
          s.add_dependency "activesupport", "= 7.0.0.alpha"
        end

        build_repo gem_repo2 do
          build_gem "activesupport", "6.1.2"

          build_gem "webpacker", "5.2.1" do |s|
            s.add_dependency "activesupport", ">= 5.2"
          end
        end

        gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"

          gemspec :path => "#{lib_path("rails")}"

          gem "webpacker", "~> 5.0"
        G
      end

      it "installs all gems without warning" do
        bundle :install
        expect(err).not_to include("Warning")
        expect(the_bundle).to include_gems("activesupport 7.0.0.alpha", "rails 7.0.0.alpha")
        expect(the_bundle).to include_gems("activesupport 7.0.0.alpha", :source => "path@#{lib_path("rails/activesupport")}")
        expect(the_bundle).to include_gems("rails 7.0.0.alpha", :source => "path@#{lib_path("rails")}")
      end
    end

    context "when a pinned gem has an indirect dependency with more than one level of indirection in the default source " do
      before do
        build_repo gem_repo3 do
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
          source "#{file_uri_for(gem_repo2)}"

          source "#{file_uri_for(gem_repo3)}" do
            gem "handsoap"
          end

          gem "nokogiri"
        G
      end

      it "installs from the default source without any warnings or errors and generates a proper lockfile" do
        expected_lockfile = <<~L
          GEM
            remote: #{file_uri_for(gem_repo2)}/
            specs:
              nokogiri (1.11.1)
                racca (~> 1.4)
              racca (1.5.2)

          GEM
            remote: #{file_uri_for(gem_repo3)}/
            specs:
              handsoap (0.2.5.5)
                nokogiri (>= 1.2.3)

          PLATFORMS
            #{specific_local_platform}

          DEPENDENCIES
            handsoap!
            nokogiri

          BUNDLED WITH
             #{Bundler::VERSION}
        L

        bundle "install --verbose"
        expect(err).not_to include("Warning")
        expect(the_bundle).to include_gems("handsoap 0.2.5.5", "nokogiri 1.11.1", "racca 1.5.2")
        expect(the_bundle).to include_gems("handsoap 0.2.5.5", :source => "remote3")
        expect(the_bundle).to include_gems("nokogiri 1.11.1", "racca 1.5.2", :source => "remote2")
        expect(lockfile).to eq(expected_lockfile)

        # Even if the gems are already installed
        FileUtils.rm bundled_app_lock
        bundle "install --verbose"
        expect(err).not_to include("Warning")
        expect(the_bundle).to include_gems("handsoap 0.2.5.5", "nokogiri 1.11.1", "racca 1.5.2")
        expect(the_bundle).to include_gems("handsoap 0.2.5.5", :source => "remote3")
        expect(the_bundle).to include_gems("nokogiri 1.11.1", "racca 1.5.2", :source => "remote2")
        expect(lockfile).to eq(expected_lockfile)
      end
    end

    context "with a gem that is only found in the wrong source" do
      before do
        build_repo gem_repo3 do
          build_gem "not_in_repo1", "1.0.0"
        end

        install_gemfile <<-G, :raise_on_error => false
          source "#{file_uri_for(gem_repo3)}"
          gem "not_in_repo1", :source => "#{file_uri_for(gem_repo1)}"
        G
      end

      it "does not install the gem" do
        expect(err).to include("Could not find gem 'not_in_repo1'")
      end
    end

    context "with an existing lockfile" do
      before do
        system_gems "rack-0.9.1", "rack-1.0.0", :path => default_bundle_path

        lockfile <<-L
          GEM
            remote: #{file_uri_for(gem_repo1)}
            specs:

          GEM
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

    context "with a lockfile with aggregated rubygems sources" do
      let(:aggregate_gem_section_lockfile) do
        <<~L
          GEM
            remote: #{file_uri_for(gem_repo1)}/
            remote: #{file_uri_for(gem_repo3)}/
            specs:
              rack (0.9.1)

          PLATFORMS
            #{specific_local_platform}

          DEPENDENCIES
            rack!

          BUNDLED WITH
             #{Bundler::VERSION}
        L
      end

      let(:split_gem_section_lockfile) do
        <<~L
          GEM
            remote: #{file_uri_for(gem_repo1)}/
            specs:

          GEM
            remote: #{file_uri_for(gem_repo3)}/
            specs:
              rack (0.9.1)

          PLATFORMS
            #{specific_local_platform}

          DEPENDENCIES
            rack!

          BUNDLED WITH
             #{Bundler::VERSION}
        L
      end

      before do
        build_repo gem_repo3 do
          build_gem "rack", "0.9.1"
        end

        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          source "#{file_uri_for(gem_repo3)}" do
            gem 'rack'
          end
        G

        lockfile aggregate_gem_section_lockfile
      end

      it "installs the existing lockfile but prints a warning", :bundler => "< 3" do
        bundle "config set --local deployment true"

        bundle "install"

        expect(lockfile).to eq(aggregate_gem_section_lockfile)
        expect(err).to include("Your lockfile contains a single rubygems source section with multiple remotes, which is insecure.")
        expect(the_bundle).to include_gems("rack 0.9.1", :source => "remote3")
      end

      it "refuses to install the existing lockfile and prints an error", :bundler => "3" do
        bundle "config set --local deployment true"

        bundle "install", :raise_on_error =>false

        expect(lockfile).to eq(aggregate_gem_section_lockfile)
        expect(err).to include("Your lockfile contains a single rubygems source section with multiple remotes, which is insecure.")
        expect(out).to be_empty
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

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack" # shoud come from repo1!
      G
    end

    it "installs the gems without any warning" do
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

      bundle "config set --local path ../gems/system"
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
        build_gem "rack", "1.2" do |s|
          s.executables = "rackup"
        end

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

    it "installs the higher version in the new repo" do
      expect(the_bundle).to include_gems("rack 1.2")
    end
  end

  it "doesn't update version when a gem uses a source block but a higher version from another source is already installed locally" do
    build_repo2 do
      build_gem "example", "0.1.0"
    end

    build_repo4 do
      build_gem "example", "1.0.2"
    end

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo4)}"

      gem "example", :source => "#{file_uri_for(gem_repo2)}"
    G

    bundle "info example"
    expect(out).to include("example (0.1.0)")

    system_gems "example-1.0.2", :path => default_bundle_path, :gem_repo => gem_repo4

    bundle "update example --verbose"
    expect(out).not_to include("Using example 1.0.2")
    expect(out).to include("Using example 0.1.0")
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
