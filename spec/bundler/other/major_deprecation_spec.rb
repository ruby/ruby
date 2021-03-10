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
      create_file "gems.rb"
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      expect(warnings).to include(
        "Multiple gemfiles (gems.rb and Gemfile) detected. Make sure you remove Gemfile and Gemfile.lock since bundler is ignoring them in favor of gems.rb and gems.rb.locked."
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

    pending "fails with a helpful error", :bundler => "3"
  end

  context "bundle install with a lockfile with a single rubygems section with multiple remotes" do
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
    end

    it "shows a deprecation", :bundler => "< 3" do
      bundle "install"

      expect(deprecations).to include("Your lockfile contains a single rubygems source section with multiple remotes, which is insecure. You should run `bundle update` or generate your lockfile from scratch.")
    end

    pending "fails with a helpful error", :bundler => "3"
  end

  context "when Bundler.setup is run in a ruby script" do
    before do
      create_file "gems.rb"
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", :group => :test
      G

      ruby <<-RUBY
        require '#{lib_dir}/bundler'

        Bundler.setup
        Bundler.setup
      RUBY
    end

    it "should print a single deprecation warning" do
      expect(warnings).to include(
        "Multiple gemfiles (gems.rb and Gemfile) detected. Make sure you remove Gemfile and Gemfile.lock since bundler is ignoring them in favor of gems.rb and gems.rb.locked."
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

  describe Bundler::Dsl do
    before do
      @rubygems = double("rubygems")
      allow(Bundler::Source::Rubygems).to receive(:new) { @rubygems }
    end

    context "with github gems" do
      it "does not warn about removal", :bundler => "< 3" do
        expect(Bundler.ui).not_to receive(:warn)
        subject.gem("sparks", :github => "indirect/sparks")
        github_uri = "https://github.com/indirect/sparks.git"
        expect(subject.dependencies.first.source.uri).to eq(github_uri)
      end

      it "warns about removal", :bundler => "3" do
        msg = <<-EOS
The :github git source is deprecated, and will be removed in the future. Change any "reponame" :github sources to "username/reponame". Add this code to the top of your Gemfile to ensure it continues to work:

    git_source(:github) {|repo_name| "https://github.com/\#{repo_name}.git" }

        EOS
        expect(Bundler.ui).to receive(:warn).with("[DEPRECATED] #{msg}")
        subject.gem("sparks", :github => "indirect/sparks")
        github_uri = "https://github.com/indirect/sparks.git"
        expect(subject.dependencies.first.source.uri).to eq(github_uri)
      end
    end

    context "with bitbucket gems" do
      it "does not warn about removal", :bundler => "< 3" do
        expect(Bundler.ui).not_to receive(:warn)
        subject.gem("not-really-a-gem", :bitbucket => "mcorp/flatlab-rails")
      end

      it "warns about removal", :bundler => "3" do
        msg = <<-EOS
The :bitbucket git source is deprecated, and will be removed in the future. Add this code to the top of your Gemfile to ensure it continues to work:

    git_source(:bitbucket) do |repo_name|
      user_name, repo_name = repo_name.split("/")
      repo_name ||= user_name
      "https://\#{user_name}@bitbucket.org/\#{user_name}/\#{repo_name}.git"
    end

        EOS
        expect(Bundler.ui).to receive(:warn).with("[DEPRECATED] #{msg}")
        subject.gem("not-really-a-gem", :bitbucket => "mcorp/flatlab-rails")
      end
    end

    context "with gist gems" do
      it "does not warn about removal", :bundler => "< 3" do
        expect(Bundler.ui).not_to receive(:warn)
        subject.gem("not-really-a-gem", :gist => "1234")
      end

      it "warns about removal", :bundler => "3" do
        msg = <<-EOS
The :gist git source is deprecated, and will be removed in the future. Add this code to the top of your Gemfile to ensure it continues to work:

    git_source(:gist) {|repo_name| "https://gist.github.com/\#{repo_name}.git" }

        EOS
        expect(Bundler.ui).to receive(:warn).with("[DEPRECATED] #{msg}")
        subject.gem("not-really-a-gem", :gist => "1234")
      end
    end
  end

  context "bundle show" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G
    end

    context "without flags" do
      before do
        bundle :show
      end

      it "prints a deprecation warning recommending `bundle list`", :bundler => "< 3" do
        expect(deprecations).to include("use `bundle list` instead of `bundle show`")
      end

      pending "fails with a helpful message", :bundler => "3"
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

    context "with --verbose flag" do
      before do
        bundle "show --verbose"
      end

      it "prints a deprecation warning informing about its removal", :bundler => "< 3" do
        expect(deprecations).to include("the `--verbose` flag to `bundle show` was undocumented and will be removed without replacement")
      end

      pending "fails with a helpful message", :bundler => "3"
    end

    context "with a gem argument" do
      before do
        bundle "show rack"
      end

      it "prints a deprecation warning recommending `bundle info`", :bundler => "< 3" do
        expect(deprecations).to include("use `bundle info rack` instead of `bundle show rack`")
      end

      pending "fails with a helpful message", :bundler => "3"
    end

    context "with the --paths option" do
      before do
        bundle "show --paths"
      end

      it "prints a deprecation warning recommending `bundle list`", :bundler => "< 3" do
        expect(deprecations).to include("use `bundle list` instead of `bundle show --paths`")
      end

      pending "fails with a helpful message", :bundler => "3"
    end

    context "with a gem argument and the --paths option" do
      before do
        bundle "show rack --paths"
      end

      it "prints deprecation warning recommending `bundle info`", :bundler => "< 3" do
        expect(deprecations).to include("use `bundle info rack --path` instead of `bundle show rack --paths`")
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
      create_file "gems.rb"
      bundle "viz"
    end

    it "prints a deprecation warning", :bundler => "< 3" do
      expect(deprecations).to include "The `viz` command has been moved to the `bundle-viz` gem, see https://github.com/bundler/bundler-viz"
    end

    pending "fails with a helpful message", :bundler => "3"
  end
end
