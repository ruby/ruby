# frozen_string_literal: true
require "spec_helper"

RSpec.describe "major deprecations" do
  let(:warnings) { out } # change to err in 2.0

  context "in a .99 version" do
    before do
      simulate_bundler_version "1.99.1"
      bundle "config --delete major_deprecations"
    end

    it "prints major deprecations without being configured" do
      ruby <<-R
        require "bundler"
        Bundler::SharedHelpers.major_deprecation(Bundler::VERSION)
      R

      expect(warnings).to have_major_deprecation("1.99.1")
    end
  end

  before do
    bundle "config major_deprecations true"

    install_gemfile <<-G
      source "file:#{gem_repo1}"
      ruby #{RUBY_VERSION.dump}
      gem "rack"
    G
  end

  describe "bundle_ruby", :ruby_repo do
    it "prints a deprecation" do
      bundle_ruby
      out.gsub! "\nruby #{RUBY_VERSION}", ""
      expect(warnings).to have_major_deprecation "the bundle_ruby executable has been removed in favor of `bundle platform --ruby`"
    end
  end

  describe "Bundler" do
    describe ".clean_env" do
      it "is deprecated in favor of .original_env" do
        source = "Bundler.clean_env"
        bundle "exec ruby -e #{source.dump}"
        expect(warnings).to have_major_deprecation "`Bundler.clean_env` has weird edge cases, use `.original_env` instead"
      end
    end

    describe ".environment" do
      it "is deprecated in favor of .load" do
        source = "Bundler.environment"
        bundle "exec ruby -e #{source.dump}"
        expect(warnings).to have_major_deprecation "Bundler.environment has been removed in favor of Bundler.load"
      end
    end

    shared_examples_for "environmental deprecations" do |trigger|
      describe "ruby version", :ruby => "< 2.0" do
        it "requires a newer ruby version" do
          instance_eval(&trigger)
          expect(warnings).to have_major_deprecation "Bundler will only support ruby >= 2.0, you are running #{RUBY_VERSION}"
        end
      end

      describe "rubygems version", :rubygems => "< 2.0" do
        it "requires a newer rubygems version" do
          instance_eval(&trigger)
          expect(warnings).to have_major_deprecation "Bundler will only support rubygems >= 2.0, you are running #{Gem::VERSION}"
        end
      end
    end

    describe "-rbundler/setup" do
      it_behaves_like "environmental deprecations", proc { ruby "require 'bundler/setup'" }
    end

    describe "Bundler.setup" do
      it_behaves_like "environmental deprecations", proc { ruby "require 'bundler'; Bundler.setup" }
    end

    describe "bundle check" do
      it_behaves_like "environmental deprecations", proc { bundle :check }
    end

    describe "bundle update --quiet" do
      it "does not print any deprecations" do
        bundle :update, :quiet => true
        expect(warnings).not_to have_major_deprecation
      end
    end

    describe "bundle install --binstubs" do
      it "should output a deprecation warning" do
        gemfile <<-G
          gem 'rack'
        G

        bundle :install, :binstubs => true
        expect(warnings).to have_major_deprecation a_string_including("The --binstubs option will be removed")
      end
    end
  end

  context "when bundle is run" do
    it "should not warn about gems.rb" do
      create_file "gems.rb", <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle :install
      expect(err).not_to have_major_deprecation
      expect(out).not_to have_major_deprecation
    end

    it "should print a Gemfile deprecation warning" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      expect(warnings).to have_major_deprecation("gems.rb and gems.locked will be preferred to Gemfile and Gemfile.lock.")
    end

    context "with flags" do
      it "should print a deprecation warning about autoremembering flags" do
        install_gemfile <<-G, :path => "vendor/bundle"
          source "file://#{gem_repo1}"
          gem "rack"
        G

        expect(warnings).to have_major_deprecation a_string_including(
          "flags passed to commands will no longer be automatically remembered."
        )
      end
    end
  end

  context "when Bundler.setup is run in a ruby script" do
    it "should print a single deprecation warning" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :group => :test
      G

      ruby <<-RUBY
        require 'rubygems'
        require 'bundler'
        require 'bundler/vendored_thor'

        Bundler.ui = Bundler::UI::Shell.new
        Bundler.setup
        Bundler.setup
      RUBY

      expect(warnings).to have_major_deprecation("gems.rb and gems.locked will be preferred to Gemfile and Gemfile.lock.")
    end
  end

  context "when `bundler/deployment` is required in a ruby script" do
    it "should print a capistrano deprecation warning" do
      ruby(<<-RUBY)
        require 'bundler/deployment'
      RUBY

      expect(warnings).to have_major_deprecation("Bundler no longer integrates " \
                             "with Capistrano, but Capistrano provides " \
                             "its own integration with Bundler via the " \
                             "capistrano-bundler gem. Use it instead.")
    end
  end

  describe Bundler::Dsl do
    before do
      @rubygems = double("rubygems")
      allow(Bundler::Source::Rubygems).to receive(:new) { @rubygems }
    end

    context "with github gems" do
      it "warns about the https change" do
        msg = "The :github option uses the git: protocol, which is not secure. " \
        "Bundler 2.0 will use the https: protocol, which is secure. Enable this change now by " \
        "running `bundle config github.https true`."
        expect(Bundler::SharedHelpers).to receive(:major_deprecation).with(msg)
        subject.gem("sparks", :github => "indirect/sparks")
      end

      it "upgrades to https on request" do
        Bundler.settings["github.https"] = true
        subject.gem("sparks", :github => "indirect/sparks")
        expect(Bundler::SharedHelpers).to receive(:major_deprecation).never
        github_uri = "https://github.com/indirect/sparks.git"
        expect(subject.dependencies.first.source.uri).to eq(github_uri)
      end
    end

    context "with bitbucket gems" do
      it "warns about removal" do
        allow(Bundler.ui).to receive(:deprecate)
        msg = "The :bitbucket git source is deprecated, and will be removed " \
          "in Bundler 2.0. Add this code to your Gemfile to ensure it " \
          "continues to work:\n    git_source(:bitbucket) do |repo_name|\n  " \
          "    \"https://\#{user_name}@bitbucket.org/\#{user_name}/\#{repo_name}" \
          ".git\"\n    end\n"
        expect(Bundler::SharedHelpers).to receive(:major_deprecation).with(msg)
        subject.gem("not-really-a-gem", :bitbucket => "mcorp/flatlab-rails")
      end
    end

    context "with gist gems" do
      it "warns about removal" do
        allow(Bundler.ui).to receive(:deprecate)
        msg = "The :gist git source is deprecated, and will be removed " \
          "in Bundler 2.0. Add this code to your Gemfile to ensure it " \
          "continues to work:\n    git_source(:gist) do |repo_name|\n  " \
          "    \"https://gist.github.com/\#{repo_name}.git\"\n" \
          "    end\n"
        expect(Bundler::SharedHelpers).to receive(:major_deprecation).with(msg)
        subject.gem("not-really-a-gem", :gist => "1234")
      end
    end
  end

  context "bundle list" do
    it "prints a deprecation warning" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle :list

      out.gsub!(/gems included.*?\[DEPRECATED/im, "[DEPRECATED")

      expect(warnings).to have_major_deprecation("use `bundle show` instead of `bundle list`")
    end
  end

  context "bundle console" do
    it "prints a deprecation warning" do
      bundle "console"

      expect(warnings).to have_major_deprecation \
        "bundle console will be replaced by `bin/console` generated by `bundle gem <name>`"
    end
  end
end
