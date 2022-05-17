# frozen_string_literal: true

RSpec.describe "major deprecations" do
  let(:warnings) { err }

  describe "Bundler" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G
    end

    describe ".clean_env" do
      before do
        source = "Bundler.clean_env"
        bundle "exec ruby -e #{source.dump}"
      end

      it "is deprecated in favor of .unbundled_env", :bundler => "< 3" do
        expect(deprecations).to include \
          "`Bundler.clean_env` has been deprecated in favor of `Bundler.unbundled_env`. " \
          "If you instead want the environment before bundler was originally loaded, use `Bundler.original_env` " \
          "(called at -e:1)"
      end

      pending "is removed and shows a helpful error message about it", :bundler => "3"
    end

    describe ".with_clean_env" do
      before do
        source = "Bundler.with_clean_env {}"
        bundle "exec ruby -e #{source.dump}"
      end

      it "is deprecated in favor of .unbundled_env", :bundler => "< 3" do
        expect(deprecations).to include(
          "`Bundler.with_clean_env` has been deprecated in favor of `Bundler.with_unbundled_env`. " \
          "If you instead want the environment before bundler was originally loaded, use `Bundler.with_original_env` " \
          "(called at -e:1)"
        )
      end

      pending "is removed and shows a helpful error message about it", :bundler => "3"
    end

    describe ".clean_system" do
      before do
        source = "Bundler.clean_system('ls')"
        bundle "exec ruby -e #{source.dump}"
      end

      it "is deprecated in favor of .unbundled_system", :bundler => "< 3" do
        expect(deprecations).to include(
          "`Bundler.clean_system` has been deprecated in favor of `Bundler.unbundled_system`. " \
          "If you instead want to run the command in the environment before bundler was originally loaded, use `Bundler.original_system` " \
          "(called at -e:1)"
        )
      end

      pending "is removed and shows a helpful error message about it", :bundler => "3"
    end

    describe ".clean_exec" do
      before do
        source = "Bundler.clean_exec('ls')"
        bundle "exec ruby -e #{source.dump}"
      end

      it "is deprecated in favor of .unbundled_exec", :bundler => "< 3" do
        expect(deprecations).to include(
          "`Bundler.clean_exec` has been deprecated in favor of `Bundler.unbundled_exec`. " \
          "If you instead want to exec to a command in the environment before bundler was originally loaded, use `Bundler.original_exec` " \
          "(called at -e:1)"
        )
      end

      pending "is removed and shows a helpful error message about it", :bundler => "3"
    end

    describe ".environment" do
      before do
        source = "Bundler.environment"
        bundle "exec ruby -e #{source.dump}"
      end

      it "is deprecated in favor of .load", :bundler => "< 3" do
        expect(deprecations).to include "Bundler.environment has been removed in favor of Bundler.load (called at -e:1)"
      end

      pending "is removed and shows a helpful error message about it", :bundler => "3"
    end
  end

  describe "bundle exec --no-keep-file-descriptors" do
    before do
      bundle "exec --no-keep-file-descriptors -e 1", :raise_on_error => false
    end

    it "is deprecated", :bundler => "< 3" do
      expect(deprecations).to include "The `--no-keep-file-descriptors` has been deprecated. `bundle exec` no longer mess with your file descriptors. Close them in the exec'd script if you need to"
    end

    pending "is removed and shows a helpful error message about it", :bundler => "3"
  end

  describe "bundle update --quiet" do
    it "does not print any deprecations" do
      bundle :update, :quiet => true, :raise_on_error => false
      expect(deprecations).to be_empty
    end
  end

  context "bundle check --path" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      bundle "check --path vendor/bundle", :raise_on_error => false
    end

    it "should print a deprecation warning", :bundler => "< 3" do
      expect(deprecations).to include(
        "The `--path` flag is deprecated because it relies on being " \
        "remembered across bundler invocations, which bundler will no " \
        "longer do in future versions. Instead please use `bundle config set --local " \
        "path 'vendor/bundle'`, and stop using this flag"
      )
    end

    pending "fails with a helpful error", :bundler => "3"
  end

  context "bundle check --path=" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      bundle "check --path=vendor/bundle", :raise_on_error => false
    end

    it "should print a deprecation warning", :bundler => "< 3" do
      expect(deprecations).to include(
        "The `--path` flag is deprecated because it relies on being " \
        "remembered across bundler invocations, which bundler will no " \
        "longer do in future versions. Instead please use `bundle config set --local " \
        "path 'vendor/bundle'`, and stop using this flag"
      )
    end

    pending "fails with a helpful error", :bundler => "3"
  end

  context "bundle cache --all" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      bundle "cache --all", :raise_on_error => false
    end

    it "should print a deprecation warning", :bundler => "< 3" do
      expect(deprecations).to include(
        "The `--all` flag is deprecated because it relies on being " \
        "remembered across bundler invocations, which bundler will no " \
        "longer do in future versions. Instead please use `bundle config set " \
        "cache_all true`, and stop using this flag"
      )
    end

    pending "fails with a helpful error", :bundler => "3"
  end

  context "bundle cache --path" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      bundle "cache --path foo", :raise_on_error => false
    end

    it "should print a deprecation warning", :bundler => "< 3" do
      expect(deprecations).to include(
        "The `--path` flag is deprecated because its semantics are unclear. " \
        "Use `bundle config cache_path` to configure the path of your cache of gems, " \
        "and `bundle config path` to configure the path where your gems are installed, " \
        "and stop using this flag"
      )
    end

    pending "fails with a helpful error", :bundler => "3"
  end

  describe "bundle config" do
    describe "old list interface" do
      before do
        bundle "config"
      end

      it "warns", :bundler => "3" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config list` instead.")
      end

      pending "fails with a helpful error", :bundler => "3"
    end

    describe "old get interface" do
      before do
        bundle "config waka"
      end

      it "warns", :bundler => "3" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config get waka` instead.")
      end

      pending "fails with a helpful error", :bundler => "3"
    end

    describe "old set interface" do
      before do
        bundle "config waka wakapun"
      end

      it "warns", :bundler => "3" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config set waka wakapun` instead.")
      end

      pending "fails with a helpful error", :bundler => "3"
    end

    describe "old set interface with --local" do
      before do
        bundle "config --local waka wakapun"
      end

      it "warns", :bundler => "3" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config set --local waka wakapun` instead.")
      end

      pending "fails with a helpful error", :bundler => "3"
    end

    describe "old set interface with --global" do
      before do
        bundle "config --global waka wakapun"
      end

      it "warns", :bundler => "3" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config set --global waka wakapun` instead.")
      end

      pending "fails with a helpful error", :bundler => "3"
    end

    describe "old unset interface" do
      before do
        bundle "config --delete waka"
      end

      it "warns", :bundler => "3" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config unset waka` instead.")
      end

      pending "fails with a helpful error", :bundler => "3"
    end

    describe "old unset interface with --local" do
      before do
        bundle "config --delete --local waka"
      end

      it "warns", :bundler => "3" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config unset --local waka` instead.")
      end

      pending "fails with a helpful error", :bundler => "3"
    end

    describe "old unset interface with --global" do
      before do
        bundle "config --delete --global waka"
      end

      it "warns", :bundler => "3" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config unset --global waka` instead.")
      end

      pending "fails with a helpful error", :bundler => "3"
    end
  end

  describe "bundle update" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G
    end

    it "warns when no options are given", :bundler => "3" do
      bundle "update"
      expect(deprecations).to include("Pass --all to `bundle update` to update everything")
    end

    pending "fails with a helpful error when no options are given", :bundler => "3"

    it "does not warn when --all is passed" do
      bundle "update --all"
      expect(deprecations).to be_empty
    end
  end

  describe "bundle install --binstubs" do
    before do
      install_gemfile <<-G, :binstubs => true
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G
    end

    it "should output a deprecation warning", :bundler => "< 3" do
      expect(deprecations).to include("The --binstubs option will be removed in favor of `bundle binstubs --all`")
    end

    pending "fails with a helpful error", :bundler => "3"
  end

  context "bundle install with both gems.rb and Gemfile present" do
    it "should not warn about gems.rb" do
      create_file "gems.rb", <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      bundle :install
      expect(deprecations).to be_empty
    end

    it "should print a proper warning, and use gems.rb" do
      create_file "gems.rb", "source \"#{file_uri_for(gem_repo1)}\""
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      expect(warnings).to include(
        "Multiple gemfiles (gems.rb and Gemfile) detected. Make sure you remove Gemfile and Gemfile.lock since bundler is ignoring them in favor of gems.rb and gems.locked."
      )

      expect(the_bundle).not_to include_gem "rack 1.0"
    end
  end

  context "bundle install with flags" do
    before do
      bundle "config set --local path vendor/bundle"

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G
    end

    {
      "clean" => ["clean", true],
      "deployment" => ["deployment", true],
      "frozen" => ["frozen", true],
      "no-deployment" => ["deployment", false],
      "no-prune" => ["no_prune", true],
      "path" => ["path", "vendor/bundle"],
      "shebang" => ["shebang", "ruby27"],
      "system" => ["system", true],
      "without" => ["without", "development"],
      "with" => ["with", "development"],
    }.each do |name, expectations|
      option_name, value = *expectations
      flag_name = "--#{name}"

      context "with the #{flag_name} flag" do
        before do
          bundle "install" # to create a lockfile, which deployment or frozen need
          bundle "install #{flag_name} #{value}"
        end

        it "should print a deprecation warning", :bundler => "< 3" do
          expect(deprecations).to include(
            "The `#{flag_name}` flag is deprecated because it relies on " \
            "being remembered across bundler invocations, which bundler " \
            "will no longer do in future versions. Instead please use " \
            "`bundle config set --local #{option_name} '#{value}'`, and stop using this flag"
          )
        end

        pending "fails with a helpful error", :bundler => "3"
      end
    end
  end

  context "bundle install with multiple sources" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo3)}"
        source "#{file_uri_for(gem_repo1)}"
      G
    end

    it "shows a deprecation", :bundler => "< 3" do
      expect(deprecations).to include(
        "Your Gemfile contains multiple primary sources. " \
        "Using `source` more than once without a block is a security risk, and " \
        "may result in installing unexpected gems. To resolve this warning, use " \
        "a block to indicate which gems should come from the secondary source."
      )
    end

    it "doesn't show lockfile deprecations if there's a lockfile", :bundler => "< 3" do
      bundle "install"

      expect(deprecations).to include(
        "Your Gemfile contains multiple primary sources. " \
        "Using `source` more than once without a block is a security risk, and " \
        "may result in installing unexpected gems. To resolve this warning, use " \
        "a block to indicate which gems should come from the secondary source."
      )
      expect(deprecations).not_to include(
        "Your lockfile contains a single rubygems source section with multiple remotes, which is insecure. " \
        "Make sure you run `bundle install` in non frozen mode and commit the result to make your lockfile secure."
      )
      bundle "config set --local frozen true"
      bundle "install"

      expect(deprecations).to include(
        "Your Gemfile contains multiple primary sources. " \
        "Using `source` more than once without a block is a security risk, and " \
        "may result in installing unexpected gems. To resolve this warning, use " \
        "a block to indicate which gems should come from the secondary source."
      )
      expect(deprecations).not_to include(
        "Your lockfile contains a single rubygems source section with multiple remotes, which is insecure. " \
        "Make sure you run `bundle install` in non frozen mode and commit the result to make your lockfile secure."
      )
    end

    pending "fails with a helpful error", :bundler => "3"
  end

  context "bundle install in frozen mode with a lockfile with a single rubygems section with multiple remotes" do
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

      lockfile <<~L
        GEM
          remote: #{file_uri_for(gem_repo1)}/
          remote: #{file_uri_for(gem_repo3)}/
          specs:
            rack (0.9.1)

        PLATFORMS
          ruby

        DEPENDENCIES
          rack!

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "config set --local frozen true"
    end

    it "shows a deprecation", :bundler => "< 3" do
      bundle "install"

      expect(deprecations).to include("Your lockfile contains a single rubygems source section with multiple remotes, which is insecure. Make sure you run `bundle install` in non frozen mode and commit the result to make your lockfile secure.")
    end

    pending "fails with a helpful error", :bundler => "3"
  end

  context "when Bundler.setup is run in a ruby script" do
    before do
      create_file "gems.rb", "source \"#{file_uri_for(gem_repo1)}\""
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", :group => :test
      G

      ruby <<-RUBY
        require '#{entrypoint}'

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
      ruby(<<-RUBY, :env => env_for_missing_prerelease_default_gem_activation)
        require 'bundler/deployment'
      RUBY
    end

    it "should print a capistrano deprecation warning", :bundler => "< 3" do
      expect(deprecations).to include("Bundler no longer integrates " \
                             "with Capistrano, but Capistrano provides " \
                             "its own integration with Bundler via the " \
                             "capistrano-bundler gem. Use it instead.")
    end

    pending "fails with a helpful error", :bundler => "3"
  end

  context "bundle show" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G
    end

    context "with --outdated flag" do
      before do
        bundle "show --outdated"
      end

      it "prints a deprecation warning informing about its removal", :bundler => "< 3" do
        expect(deprecations).to include("the `--outdated` flag to `bundle show` was undocumented and will be removed without replacement")
      end

      pending "fails with a helpful message", :bundler => "3"
    end
  end

  context "bundle remove" do
    before do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G
    end

    context "with --install" do
      it "shows a deprecation warning", :bundler => "< 3" do
        bundle "remove rack --install"

        expect(err).to include "[DEPRECATED] The `--install` flag has been deprecated. `bundle install` is triggered by default."
      end

      pending "fails with a helpful message", :bundler => "3"
    end
  end

  context "bundle console" do
    before do
      bundle "console", :raise_on_error => false
    end

    it "prints a deprecation warning", :bundler => "< 3" do
      expect(deprecations).to include \
        "bundle console will be replaced by `bin/console` generated by `bundle gem <name>`"
    end

    pending "fails with a helpful message", :bundler => "3"
  end

  context "bundle viz" do
    before do
      graphviz_version = RUBY_VERSION >= "2.4" ? "1.2.5" : "1.2.4"
      realworld_system_gems "ruby-graphviz --version #{graphviz_version}"
      create_file "gems.rb", "source \"#{file_uri_for(gem_repo1)}\""
      bundle "viz"
    end

    it "prints a deprecation warning", :bundler => "< 3" do
      expect(deprecations).to include "The `viz` command has been renamed to `graph` and moved to a plugin. See https://github.com/rubygems/bundler-graph"
    end

    pending "fails with a helpful message", :bundler => "3"
  end

  describe "deprecating rubocop", :readline do
    context "bundle gem --rubocop" do
      before do
        bundle "gem my_new_gem --rubocop", :raise_on_error => false
      end

      it "prints a deprecation warning", :bundler => "< 3" do
        expect(deprecations).to include \
          "--rubocop is deprecated, use --linter=rubocop"
      end
    end

    context "bundle gem --no-rubocop" do
      before do
        bundle "gem my_new_gem --no-rubocop", :raise_on_error => false
      end

      it "prints a deprecation warning", :bundler => "< 3" do
        expect(deprecations).to include \
          "--no-rubocop is deprecated, use --linter"
      end
    end

    context "bundle gem with gem.rubocop set to true" do
      before do
        bundle "gem my_new_gem", :env => { "BUNDLE_GEM__RUBOCOP" => "true" }, :raise_on_error => false
      end

      it "prints a deprecation warning", :bundler => "< 3" do
        expect(deprecations).to include \
          "config gem.rubocop is deprecated; we've updated your config to use gem.linter instead"
      end
    end

    context "bundle gem with gem.rubocop set to false" do
      before do
        bundle "gem my_new_gem", :env => { "BUNDLE_GEM__RUBOCOP" => "false" }, :raise_on_error => false
      end

      it "prints a deprecation warning", :bundler => "< 3" do
        expect(deprecations).to include \
          "config gem.rubocop is deprecated; we've updated your config to use gem.linter instead"
      end
    end
  end
end
