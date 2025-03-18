# frozen_string_literal: true

RSpec.describe "bundle install with groups" do
  describe "installing with no options" do
    before :each do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        group :emo do
          gem "activesupport", "2.3.5"
        end
        gem "thin", :groups => [:emo]
      G
    end

    it "installs gems in the default group" do
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "installs gems in a group block into that group" do
      expect(the_bundle).to include_gems "activesupport 2.3.5"

      load_error_run <<-R, "activesupport", :default
        require 'activesupport'
        puts ACTIVESUPPORT
      R

      expect(err_without_deprecations).to eq("ZOMG LOAD ERROR")
    end

    it "installs gems with inline :groups into those groups" do
      expect(the_bundle).to include_gems "thin 1.0"

      load_error_run <<-R, "thin", :default
        require 'thin'
        puts THIN
      R

      expect(err_without_deprecations).to eq("ZOMG LOAD ERROR")
    end

    it "sets up everything if Bundler.setup is used with no groups" do
      output = run("require 'myrack'; puts MYRACK")
      expect(output).to eq("1.0.0")

      output = run("require 'activesupport'; puts ACTIVESUPPORT")
      expect(output).to eq("2.3.5")

      output = run("require 'thin'; puts THIN")
      expect(output).to eq("1.0")
    end

    it "removes old groups when new groups are set up" do
      load_error_run <<-RUBY, "thin", :emo
        Bundler.setup(:default)
        require 'thin'
        puts THIN
      RUBY

      expect(err_without_deprecations).to eq("ZOMG LOAD ERROR")
    end

    it "sets up old groups when they have previously been removed" do
      output = run <<-RUBY, :emo
        Bundler.setup(:default)
        Bundler.setup(:default, :emo)
        require 'thin'; puts THIN
      RUBY
      expect(output).to eq("1.0")
    end
  end

  describe "without option" do
    describe "with gems assigned to a single group" do
      before :each do
        gemfile <<-G
          source "https://gem.repo1"
          gem "myrack"
          group :emo do
            gem "activesupport", "2.3.5"
          end
          group :debugging, :optional => true do
            gem "thin"
          end
        G
      end

      it "installs gems in the default group" do
        bundle "config set --local without emo"
        bundle :install
        expect(the_bundle).to include_gems "myrack 1.0.0", groups: [:default]
      end

      it "respects global `without` configuration, but does not save it locally" do
        bundle "config set --global without emo"
        bundle :install
        expect(the_bundle).to include_gems "myrack 1.0.0", groups: [:default]
        bundle "config list"
        expect(out).not_to include("Set for your local app (#{bundled_app(".bundle/config")}): [:emo]")
        expect(out).to include("Set for the current user (#{home(".bundle/config")}): [:emo]")
      end

      it "allows running application where groups where configured by a different user", bundler: "< 3" do
        bundle "config set without emo"
        bundle :install
        bundle "exec ruby -e 'puts 42'", env: { "BUNDLE_USER_HOME" => tmp("new_home").to_s }
        expect(out).to include("42")
      end

      it "does not install gems from the excluded group" do
        bundle "config set --local without emo"
        bundle :install
        expect(the_bundle).not_to include_gems "activesupport 2.3.5", groups: [:default]
      end

      it "remembers previous exclusion with `--without`", bundler: "< 3" do
        bundle "install --without emo"
        expect(the_bundle).not_to include_gems "activesupport 2.3.5"
        bundle :install
        expect(the_bundle).not_to include_gems "activesupport 2.3.5"
      end

      it "does not say it installed gems from the excluded group" do
        bundle "config set --local without emo"
        bundle :install
        expect(out).not_to include("activesupport")
      end

      it "allows Bundler.setup for specific groups" do
        bundle "config set --local without emo"
        bundle :install
        run("require 'myrack'; puts MYRACK", :default)
        expect(out).to eq("1.0.0")
      end

      it "does not effect the resolve" do
        gemfile <<-G
          source "https://gem.repo1"
          gem "activesupport"
          group :emo do
            gem "rails", "2.3.2"
          end
        G

        bundle "config set --local without emo"
        bundle :install
        expect(the_bundle).to include_gems "activesupport 2.3.2", groups: [:default]
      end

      it "still works when BUNDLE_WITHOUT is set" do
        ENV["BUNDLE_WITHOUT"] = "emo"

        bundle :install
        expect(out).not_to include("activesupport")

        expect(the_bundle).to include_gems "myrack 1.0.0", groups: [:default]
        expect(the_bundle).not_to include_gems "activesupport 2.3.5", groups: [:default]

        ENV["BUNDLE_WITHOUT"] = nil
      end

      it "clears --without when passed an empty list", bundler: "< 3" do
        bundle "install --without emo"

        bundle "install --without ''"
        expect(the_bundle).to include_gems "activesupport 2.3.5"
      end

      it "doesn't clear without when nothing is passed", bundler: "< 3" do
        bundle "install --without emo"

        bundle :install
        expect(the_bundle).not_to include_gems "activesupport 2.3.5"
      end

      it "does not install gems from the optional group" do
        bundle :install
        expect(the_bundle).not_to include_gems "thin 1.0"
      end

      it "installs gems from the optional group when requested" do
        bundle "config set --local with debugging"
        bundle :install
        expect(the_bundle).to include_gems "thin 1.0"
      end

      it "installs gems from the previously requested group", bundler: "< 3" do
        bundle "install --with debugging"
        expect(the_bundle).to include_gems "thin 1.0"
        bundle :install
        expect(the_bundle).to include_gems "thin 1.0"
      end

      it "installs gems from the optional groups requested with BUNDLE_WITH" do
        ENV["BUNDLE_WITH"] = "debugging"
        bundle :install
        expect(the_bundle).to include_gems "thin 1.0"
        ENV["BUNDLE_WITH"] = nil
      end

      it "clears --with when passed an empty list", bundler: "< 3" do
        bundle "install --with debugging"
        bundle "install --with ''"
        expect(the_bundle).not_to include_gems "thin 1.0"
      end

      it "removes groups from without when passed at --with", bundler: "< 3" do
        bundle "config set --local without emo"
        bundle "install --with emo"
        expect(the_bundle).to include_gems "activesupport 2.3.5"
      end

      it "removes groups from with when passed at --without", bundler: "< 3" do
        bundle "config set --local with debugging"
        bundle "install --without debugging", raise_on_error: false
        expect(the_bundle).not_to include_gem "thin 1.0"
      end

      it "errors out when passing a group to with and without via CLI flags", bundler: "< 3" do
        bundle "install --with emo debugging --without emo", raise_on_error: false
        expect(last_command).to be_failure
        expect(err).to include("The offending groups are: emo")
      end

      it "allows the BUNDLE_WITH setting to override BUNDLE_WITHOUT" do
        ENV["BUNDLE_WITH"] = "debugging"

        bundle :install
        expect(the_bundle).to include_gem "thin 1.0"

        ENV["BUNDLE_WITHOUT"] = "debugging"
        expect(the_bundle).to include_gem "thin 1.0"

        bundle :install
        expect(the_bundle).to include_gem "thin 1.0"
      end

      it "can add and remove a group at the same time", bundler: "< 3" do
        bundle "install --with debugging --without emo"
        expect(the_bundle).to include_gems "thin 1.0"
        expect(the_bundle).not_to include_gems "activesupport 2.3.5"
      end

      it "has no effect when listing a not optional group in with" do
        bundle "config set --local with emo"
        bundle :install
        expect(the_bundle).to include_gems "activesupport 2.3.5"
      end

      it "has no effect when listing an optional group in without" do
        bundle "config set --local without debugging"
        bundle :install
        expect(the_bundle).not_to include_gems "thin 1.0"
      end
    end

    describe "with gems assigned to multiple groups" do
      before :each do
        gemfile <<-G
          source "https://gem.repo1"
          gem "myrack"
          group :emo, :lolercoaster do
            gem "activesupport", "2.3.5"
          end
        G
      end

      it "installs gems in the default group" do
        bundle "config set --local without emo lolercoaster"
        bundle :install
        expect(the_bundle).to include_gems "myrack 1.0.0"
      end

      it "installs the gem if any of its groups are installed" do
        bundle "config set --local without emo"
        bundle :install
        expect(the_bundle).to include_gems "myrack 1.0.0", "activesupport 2.3.5"
      end

      describe "with a gem defined multiple times in different groups" do
        before :each do
          gemfile <<-G
            source "https://gem.repo1"
            gem "myrack"

            group :emo do
              gem "activesupport", "2.3.5"
            end

            group :lolercoaster do
              gem "activesupport", "2.3.5"
            end
          G
        end

        it "installs the gem unless all groups are excluded" do
          bundle "config set --local without emo"
          bundle :install
          expect(the_bundle).to include_gems "activesupport 2.3.5"

          bundle "config set --local without lolercoaster"
          bundle :install
          expect(the_bundle).to include_gems "activesupport 2.3.5"

          bundle "config set --local without emo lolercoaster"
          bundle :install
          expect(the_bundle).not_to include_gems "activesupport 2.3.5"

          bundle "config set --local without 'emo lolercoaster'"
          bundle :install
          expect(the_bundle).not_to include_gems "activesupport 2.3.5"
        end
      end
    end

    describe "nesting groups" do
      before :each do
        gemfile <<-G
          source "https://gem.repo1"
          gem "myrack"
          group :emo do
            group :lolercoaster do
              gem "activesupport", "2.3.5"
            end
          end
        G
      end

      it "installs gems in the default group" do
        bundle "config set --local without emo lolercoaster"
        bundle :install
        expect(the_bundle).to include_gems "myrack 1.0.0"
      end

      it "installs the gem if any of its groups are installed" do
        bundle "config set --local without emo"
        bundle :install
        expect(the_bundle).to include_gems "myrack 1.0.0", "activesupport 2.3.5"
      end
    end
  end

  describe "when loading only the default group" do
    it "should not load all groups" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "activesupport", :groups => :development
      G

      ruby <<-R
        require "bundler"
        Bundler.setup :default
        Bundler.require :default
        puts MYRACK
        begin
          require "activesupport"
        rescue LoadError
          puts "no activesupport"
        end
      R

      expect(out).to include("1.0")
      expect(out).to include("no activesupport")
    end
  end

  describe "when locked and installed with `without` option" do
    before(:each) do
      build_repo2

      system_gems "myrack-0.9.1"

      bundle "config set --local without myrack"
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "myrack"

        group :myrack do
          gem "myrack_middleware"
        end
      G
    end

    it "uses the correct versions even if --without was used on the original" do
      expect(the_bundle).to include_gems "myrack 0.9.1"
      expect(the_bundle).not_to include_gems "myrack_middleware 1.0"
      simulate_new_machine

      bundle :install

      expect(the_bundle).to include_gems "myrack 0.9.1"
      expect(the_bundle).to include_gems "myrack_middleware 1.0"
    end

    it "does not hit the remote a second time" do
      FileUtils.rm_r gem_repo2
      bundle "config set --local without myrack"
      bundle :install, verbose: true
      expect(last_command.stdboth).not_to match(/fetching/i)
    end
  end
end
