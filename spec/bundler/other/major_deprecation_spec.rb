# frozen_string_literal: true

RSpec.describe "major deprecations" do
  let(:warnings) { err }

  describe "Bundler" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G
    end

    describe ".clean_env" do
      before do
        source = "Bundler.clean_env"
        bundle "exec ruby -e #{source.dump}", raise_on_error: false
      end

      it "is removed in favor of .unbundled_env and shows a helpful error message about it" do
        expect(err).to include \
          "`Bundler.clean_env` has been removed in favor of `Bundler.unbundled_env`. " \
          "If you instead want the environment before bundler was originally loaded, use `Bundler.original_env`" \
      end
    end

    describe ".with_clean_env" do
      before do
        source = "Bundler.with_clean_env {}"
        bundle "exec ruby -e #{source.dump}", raise_on_error: false
      end

      it "is removed in favor of .unbundled_env and shows a helpful error message about it" do
        expect(err).to include(
          "`Bundler.with_clean_env` has been removed in favor of `Bundler.with_unbundled_env`. " \
          "If you instead want the environment before bundler was originally loaded, use `Bundler.with_original_env`"
        )
      end
    end

    describe ".clean_system" do
      before do
        source = "Bundler.clean_system('ls')"
        bundle "exec ruby -e #{source.dump}", raise_on_error: false
      end

      it "is removed in favor of .unbundled_system and shows a helpful error message about it" do
        expect(err).to include(
          "`Bundler.clean_system` has been removed in favor of `Bundler.unbundled_system`. " \
          "If you instead want to run the command in the environment before bundler was originally loaded, use `Bundler.original_system`" \
        )
      end
    end

    describe ".clean_exec" do
      before do
        source = "Bundler.clean_exec('ls')"
        bundle "exec ruby -e #{source.dump}", raise_on_error: false
      end

      it "is removed in favor of .unbundled_exec and shows a helpful error message about it" do
        expect(err).to include(
          "`Bundler.clean_exec` has been removed in favor of `Bundler.unbundled_exec`. " \
          "If you instead want to exec to a command in the environment before bundler was originally loaded, use `Bundler.original_exec`" \
        )
      end
    end

    describe ".environment" do
      before do
        source = "Bundler.environment"
        bundle "exec ruby -e #{source.dump}", raise_on_error: false
      end

      it "is removed in favor of .load and shows a helpful error message about it" do
        expect(err).to include "Bundler.environment has been removed in favor of Bundler.load"
      end
    end
  end

  describe "bundle exec --no-keep-file-descriptors" do
    before do
      bundle "exec --no-keep-file-descriptors -e 1", raise_on_error: false
    end

    it "is removed and shows a helpful error message about it" do
      expect(err).to include "The `--no-keep-file-descriptors` has been removed. `bundle exec` no longer mess with your file descriptors. Close them in the exec'd script if you need to"
    end
  end

  describe "bundle update --quiet" do
    it "does not print any deprecations" do
      bundle :update, quiet: true, raise_on_error: false
      expect(deprecations).to be_empty
    end
  end

  context "bundle check --path" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "check --path vendor/bundle", raise_on_error: false
    end

    it "fails with a helpful error" do
      expect(err).to include(
        "The `--path` flag has been removed because it relied on being " \
        "remembered across bundler invocations, which bundler no longer " \
        "does. Instead please use `bundle config set path 'vendor/bundle'`, " \
        "and stop using this flag"
      )
    end
  end

  context "bundle check --path=" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "check --path=vendor/bundle", raise_on_error: false
    end

    it "fails with a helpful error" do
      expect(err).to include(
        "The `--path` flag has been removed because it relied on being " \
        "remembered across bundler invocations, which bundler no longer " \
        "does. Instead please use `bundle config set path 'vendor/bundle'`, " \
        "and stop using this flag"
      )
    end
  end

  context "bundle binstubs --path=" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "binstubs myrack --path=binpath", raise_on_error: false
    end

    it "fails with a helpful error" do
      expect(err).to include(
        "The `--path` flag has been removed because it relied on being " \
        "remembered across bundler invocations, which bundler no longer " \
        "does. Instead please use `bundle config set bin 'binpath'`, " \
        "and stop using this flag"
      )
    end
  end

  context "bundle cache --all" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "cache --all --verbose", raise_on_error: false
    end

    it "fails with a helpful error" do
      expect(err).to include(
        "The `--all` flag has been removed because it relied on being " \
        "remembered across bundler invocations, which bundler no longer " \
        "does. Instead please use `bundle config set cache_all true`, " \
        "and stop using this flag"
      )
    end
  end

  context "bundle cache --no-all" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "cache --no-all", raise_on_error: false
    end

    it "fails with a helpful error" do
      expect(err).to include(
        "The `--no-all` flag has been removed because it relied on being " \
        "remembered across bundler invocations, which bundler no longer " \
        "does. Instead please use `bundle config set cache_all false`, " \
        "and stop using this flag"
      )
    end
  end

  context "bundle cache --path" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "cache --path foo", raise_on_error: false
    end

    it "should print a removal error" do
      expect(err).to include(
        "The `--path` flag has been removed because its semantics were unclear. " \
        "Use `bundle config cache_path` to configure the path of your cache of gems, " \
        "and `bundle config path` to configure the path where your gems are installed, " \
        "and stop using this flag"
      )
    end
  end

  context "bundle cache --path=" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "cache --path=foo", raise_on_error: false
    end

    it "should print a deprecation warning" do
      expect(err).to include(
        "The `--path` flag has been removed because its semantics were unclear. " \
        "Use `bundle config cache_path` to configure the path of your cache of gems, " \
        "and `bundle config path` to configure the path where your gems are installed, " \
        "and stop using this flag"
      )
    end
  end

  context "bundle cache --frozen" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "cache --frozen", raise_on_error: false
    end

    it "fails with a helpful error" do
      expect(err).to include(
        "The `--frozen` flag has been removed because it relied on being " \
        "remembered across bundler invocations, which bundler no longer " \
        "does. Instead please use `bundle config set frozen true`, " \
        "and stop using this flag"
      )
    end
  end

  context "bundle cache --no-prune" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "cache --no-prune", raise_on_error: false
    end

    it "fails with a helpful error" do
      expect(err).to include(
        "The `--no-prune` flag has been removed because it relied on being " \
        "remembered across bundler invocations, which bundler no longer " \
        "does. Instead please use `bundle config set no_prune true`, " \
        "and stop using this flag"
      )
    end
  end

  describe "bundle config" do
    describe "old list interface" do
      before do
        bundle "config"
      end

      it "warns", bundler: "4" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config list` instead.")
      end

      pending "fails with a helpful error", bundler: "5"
    end

    describe "old get interface" do
      before do
        bundle "config waka"
      end

      it "warns", bundler: "4" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config get waka` instead.")
      end

      pending "fails with a helpful error", bundler: "5"
    end

    describe "old set interface" do
      before do
        bundle "config waka wakapun"
      end

      it "warns", bundler: "4" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config set waka wakapun` instead.")
      end

      pending "fails with a helpful error", bundler: "5"
    end

    describe "old set interface with --local" do
      before do
        bundle "config --local waka wakapun"
      end

      it "warns", bundler: "4" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config set --local waka wakapun` instead.")
      end

      pending "fails with a helpful error", bundler: "5"
    end

    describe "old set interface with --global" do
      before do
        bundle "config --global waka wakapun"
      end

      it "warns", bundler: "4" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config set --global waka wakapun` instead.")
      end

      pending "fails with a helpful error", bundler: "5"
    end

    describe "old unset interface" do
      before do
        bundle "config --delete waka"
      end

      it "warns", bundler: "4" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config unset waka` instead.")
      end

      pending "fails with a helpful error", bundler: "5"
    end

    describe "old unset interface with --local" do
      before do
        bundle "config --delete --local waka"
      end

      it "warns", bundler: "4" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config unset --local waka` instead.")
      end

      pending "fails with a helpful error", bundler: "5"
    end

    describe "old unset interface with --global" do
      before do
        bundle "config --delete --global waka"
      end

      it "warns", bundler: "4" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config unset --global waka` instead.")
      end

      pending "fails with a helpful error", bundler: "5"
    end
  end

  describe "bundle update" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G
    end

    it "warns when no options are given", bundler: "4" do
      bundle "update"
      expect(deprecations).to include("Pass --all to `bundle update` to update everything")
    end

    pending "fails with a helpful error when no options are given", bundler: "5"

    it "does not warn when --all is passed" do
      bundle "update --all"
      expect(deprecations).to be_empty
    end
  end

  describe "bundle install --binstubs" do
    before do
      install_gemfile <<-G, binstubs: true, raise_on_error: false
        source "https://gem.repo1"
        gem "myrack"
      G
    end

    it "fails with a helpful error" do
      expect(err).to include("The --binstubs option has been removed in favor of `bundle binstubs --all`")
    end
  end

  context "bundle install with both gems.rb and Gemfile present" do
    it "should not warn about gems.rb" do
      gemfile "gems.rb", <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle :install
      expect(deprecations).to be_empty
    end

    it "should print a proper warning, and use gems.rb" do
      gemfile "gems.rb", "source 'https://gem.repo1'"
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      expect(warnings).to include(
        "Multiple gemfiles (gems.rb and Gemfile) detected. Make sure you remove Gemfile and Gemfile.lock since bundler is ignoring them in favor of gems.rb and gems.locked."
      )

      expect(the_bundle).not_to include_gem "myrack 1.0"
    end
  end

  context "bundle install with flags" do
    before do
      bundle "config set --local path vendor/bundle"

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G
    end

    {
      "clean" => ["clean", "true"],
      "deployment" => ["deployment", "true"],
      "frozen" => ["frozen", "true"],
      "no-deployment" => ["deployment", "false"],
      "no-prune" => ["no_prune", "true"],
      "path" => ["path", "'vendor/bundle'"],
      "shebang" => ["shebang", "'ruby27'"],
      "system" => ["path.system", "true"],
      "without" => ["without", "'development'"],
      "with" => ["with", "'development'"],
    }.each do |name, expectations|
      option_name, value = *expectations
      flag_name = "--#{name}"
      args = %w[true false].include?(value) ? flag_name : "#{flag_name} #{value}"

      context "with the #{flag_name} flag" do
        before do
          bundle "install" # to create a lockfile, which deployment or frozen need

          bundle "install #{args}", raise_on_error: false
        end

        it "fails with a helpful error" do
          expect(err).to include(
            "The `#{flag_name}` flag has been removed because it relied on " \
            "being remembered across bundler invocations, which bundler no " \
            "longer does. Instead please use `bundle config set " \
            "#{option_name} #{value}`, and stop using this flag"
          )
        end
      end
    end
  end

  context "bundle install with multiple sources" do
    before do
      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo3"
        source "https://gem.repo1"
      G
    end

    it "fails with a helpful error" do
      expect(err).to include(
        "This Gemfile contains multiple global sources. " \
        "Each source after the first must include a block to indicate which gems " \
        "should come from that source"
      )
    end

    it "doesn't show lockfile deprecations if there's a lockfile" do
      lockfile <<~L
        GEM
          remote: https://gem.repo3/
          remote: https://gem.repo1/
          specs:

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES

        BUNDLED WITH
           #{Bundler::VERSION}
      L
      bundle "install", raise_on_error: false

      expect(err).to include(
        "This Gemfile contains multiple global sources. " \
        "Each source after the first must include a block to indicate which gems " \
        "should come from that source"
      )
      expect(err).not_to include(
        "Your lockfile contains a single rubygems source section with multiple remotes, which is insecure. " \
        "Make sure you run `bundle install` in non frozen mode and commit the result to make your lockfile secure."
      )
      bundle "config set --local frozen true"
      bundle "install", raise_on_error: false

      expect(err).to include(
        "This Gemfile contains multiple global sources. " \
        "Each source after the first must include a block to indicate which gems " \
        "should come from that source"
      )
      expect(err).not_to include(
        "Your lockfile contains a single rubygems source section with multiple remotes, which is insecure. " \
        "Make sure you run `bundle install` in non frozen mode and commit the result to make your lockfile secure."
      )
    end
  end

  context "bundle install with a lockfile with a single rubygems section with multiple remotes" do
    before do
      build_repo3 do
        build_gem "myrack", "0.9.1"
      end

      gemfile <<-G
        source "https://gem.repo1"
        source "https://gem.repo3" do
          gem 'myrack'
        end
      G

      lockfile <<~L
        GEM
          remote: https://gem.repo1/
          remote: https://gem.repo3/
          specs:
            myrack (0.9.1)

        PLATFORMS
          ruby

        DEPENDENCIES
          myrack!

        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end

    it "shows an error" do
      bundle "install", raise_on_error: false

      expect(err).to include("Your lockfile contains a single rubygems source section with multiple remotes, which is insecure. Make sure you run `bundle install` in non frozen mode and commit the result to make your lockfile secure.")
    end
  end

  context "when Bundler.setup is run in a ruby script" do
    before do
      create_file "gems.rb", "source 'https://gem.repo1'"
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :group => :test
      G

      ruby <<-RUBY
        require 'bundler'

        Bundler.setup
        Bundler.setup
      RUBY
    end

    it "should print a single deprecation warning" do
      expect(warnings).to include(
        "Multiple gemfiles (gems.rb and Gemfile) detected. Make sure you remove Gemfile and Gemfile.lock since bundler is ignoring them in favor of gems.rb and gems.locked."
      )
    end
  end

  context "when `bundler/deployment` is required in a ruby script" do
    before do
      ruby <<-RUBY, raise_on_error: false
        require 'bundler/deployment'
      RUBY
    end

    it "should print a capistrano deprecation warning" do
      expect(err).to include("Bundler no longer integrates " \
                             "with Capistrano, but Capistrano provides " \
                             "its own integration with Bundler via the " \
                             "capistrano-bundler gem. Use it instead.")
    end
  end

  context "when `bundler/capistrano` is required in a ruby script" do
    before do
      ruby <<-RUBY, raise_on_error: false
        require 'bundler/capistrano'
      RUBY
    end

    it "fails with a helpful error" do
      expect(err).to include("[REMOVED] The Bundler task for Capistrano. Please use https://github.com/capistrano/bundler")
    end
  end

  context "when `bundler/vlad` is required in a ruby script" do
    before do
      ruby <<-RUBY, raise_on_error: false
        require 'bundler/vlad'
      RUBY
    end

    it "fails with a helpful error" do
      expect(err).to include("[REMOVED] The Bundler task for Vlad")
    end
  end

  context "bundle show" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G
    end

    context "with --outdated flag" do
      before do
        bundle "show --outdated", raise_on_error: false
      end

      it "fails with a helpful message" do
        expect(err).to include("the `--outdated` flag to `bundle show` has been removed in favor of `bundle show --verbose`")
      end
    end
  end

  context "bundle remove" do
    before do
      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G
    end

    context "with --install" do
      it "fails with a helpful message" do
        bundle "remove myrack --install", raise_on_error: false

        expect(err).to include "The `--install` flag has been removed. `bundle install` is triggered by default."
      end
    end
  end

  context "bundle viz" do
    before do
      bundle "viz", raise_on_error: false
    end

    it "fails with a helpful message" do
      expect(err).to include "The `viz` command has been renamed to `graph` and moved to a plugin. See https://github.com/rubygems/bundler-graph"
    end
  end

  context "bundle inject" do
    before do
      bundle "inject", raise_on_error: false
    end

    it "fails with a helpful message" do
      expect(err).to include "The `inject` command has been replaced by the `add` command"
    end
  end

  context "bundle plugin install --local_git" do
    before do
      build_git "foo" do |s|
        s.write "plugins.rb"
      end
    end

    it "fails with a helpful message" do
      bundle "plugin install foo --local_git #{lib_path("foo-1.0")}", raise_on_error: false

      expect(err).to include "--local_git has been removed, use --git"
    end
  end

  describe "removing rubocop" do
    before do
      global_config "BUNDLE_GEM__MIT" => "false", "BUNDLE_GEM__TEST" => "false", "BUNDLE_GEM__COC" => "false",
                    "BUNDLE_GEM__CI" => "false", "BUNDLE_GEM__CHANGELOG" => "false"
    end

    context "bundle gem --rubocop" do
      before do
        bundle "gem my_new_gem --rubocop", raise_on_error: false
      end

      it "prints an error" do
        expect(err).to include \
          "--rubocop has been removed, use --linter=rubocop"
      end
    end

    context "bundle gem --no-rubocop" do
      before do
        bundle "gem my_new_gem --no-rubocop", raise_on_error: false
      end

      it "prints an error" do
        expect(err).to include \
          "--no-rubocop has been removed, use --no-linter"
      end
    end
  end

  context " bundle gem --ext parameter with no value" do
    it "prints error when used before gem name" do
      bundle "gem --ext foo", raise_on_error: false
      expect(err).to include "Extensions can now be generated using C or Rust, so `--ext` with no arguments has been removed. Please select a language, e.g. `--ext=rust` to generate a Rust extension."
    end

    it "prints error when used after gem name" do
      bundle "gem foo --ext", raise_on_error: false
      expect(err).to include "Extensions can now be generated using C or Rust, so `--ext` with no arguments has been removed. Please select a language, e.g. `--ext=rust` to generate a Rust extension."
    end
  end
end
