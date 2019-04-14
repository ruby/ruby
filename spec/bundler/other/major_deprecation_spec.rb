# frozen_string_literal: true

RSpec.describe "major deprecations" do
  let(:warnings) { err }

  describe "Bundler" do
    before do
      install_gemfile! <<-G
        source "file:#{gem_repo1}"
        gem "rack"
      G
    end

    describe ".clean_env" do
      before do
        source = "Bundler.clean_env"
        bundle "exec ruby -e #{source.dump}"
      end

      it "is deprecated in favor of .unbundled_env", :bundler => "2" do
        expect(deprecations).to include \
          "`Bundler.clean_env` has been deprecated in favor of `Bundler.unbundled_env`. " \
          "If you instead want the environment before bundler was originally loaded, use `Bundler.original_env`"
      end

      pending "is removed and shows a helpful error message about it", :bundler => "3"
    end

    describe ".with_clean_env" do
      before do
        source = "Bundler.with_clean_env {}"
        bundle "exec ruby -e #{source.dump}"
      end

      it "is deprecated in favor of .unbundled_env", :bundler => "2" do
        expect(deprecations).to include(
          "`Bundler.with_clean_env` has been deprecated in favor of `Bundler.with_unbundled_env`. " \
          "If you instead want the environment before bundler was originally loaded, use `Bundler.with_original_env`"
        )
      end

      pending "is removed and shows a helpful error message about it", :bundler => "3"
    end

    describe ".clean_system" do
      before do
        source = "Bundler.clean_system('ls')"
        bundle "exec ruby -e #{source.dump}"
      end

      it "is deprecated in favor of .unbundled_system", :bundler => "2" do
        expect(deprecations).to include(
          "`Bundler.clean_system` has been deprecated in favor of `Bundler.unbundled_system`. " \
          "If you instead want to run the command in the environment before bundler was originally loaded, use `Bundler.original_system`"
        )
      end

      pending "is removed and shows a helpful error message about it", :bundler => "3"
    end

    describe ".clean_exec" do
      before do
        source = "Bundler.clean_exec('ls')"
        bundle "exec ruby -e #{source.dump}"
      end

      it "is deprecated in favor of .unbundled_exec", :bundler => "2" do
        expect(deprecations).to include(
          "`Bundler.clean_exec` has been deprecated in favor of `Bundler.unbundled_exec`. " \
          "If you instead want to exec to a command in the environment before bundler was originally loaded, use `Bundler.original_exec`"
        )
      end

      pending "is removed and shows a helpful error message about it", :bundler => "3"
    end

    describe ".environment" do
      before do
        source = "Bundler.environment"
        bundle "exec ruby -e #{source.dump}"
      end

      it "is deprecated in favor of .load", :bundler => "2" do
        expect(deprecations).to include "Bundler.environment has been removed in favor of Bundler.load"
      end

      pending "is removed and shows a helpful error message about it", :bundler => "3"
    end
  end

  describe "bundle update --quiet" do
    it "does not print any deprecations" do
      bundle :update, :quiet => true
      expect(deprecations).to be_empty
    end
  end

  describe "bundle config" do
    describe "old list interface" do
      before do
        bundle! "config"
      end

      it "warns", :bundler => "2" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config list` instead.")
      end

      pending "fails with a helpful error", :bundler => "3"
    end

    describe "old get interface" do
      before do
        bundle! "config waka"
      end

      it "warns", :bundler => "2" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config get waka` instead.")
      end

      pending "fails with a helpful error", :bundler => "3"
    end

    describe "old set interface" do
      before do
        bundle! "config waka wakapun"
      end

      it "warns", :bundler => "2" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config set waka wakapun` instead.")
      end

      pending "fails with a helpful error", :bundler => "3"
    end

    describe "old set interface with --local" do
      before do
        bundle! "config --local waka wakapun"
      end

      it "warns", :bundler => "2" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config set --local waka wakapun` instead.")
      end

      pending "fails with a helpful error", :bundler => "3"
    end

    describe "old set interface with --global" do
      before do
        bundle! "config --global waka wakapun"
      end

      it "warns", :bundler => "2" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config set --global waka wakapun` instead.")
      end

      pending "fails with a helpful error", :bundler => "3"
    end

    describe "old unset interface" do
      before do
        bundle! "config --delete waka"
      end

      it "warns", :bundler => "2" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config unset waka` instead.")
      end

      pending "fails with a helpful error", :bundler => "3"
    end

    describe "old unset interface with --local" do
      before do
        bundle! "config --delete --local waka"
      end

      it "warns", :bundler => "2" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config unset --local waka` instead.")
      end

      pending "fails with a helpful error", :bundler => "3"
    end

    describe "old unset interface with --global" do
      before do
        bundle! "config --delete --global waka"
      end

      it "warns", :bundler => "2" do
        expect(deprecations).to include("Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle config unset --global waka` instead.")
      end

      pending "fails with a helpful error", :bundler => "3"
    end
  end

  describe "bundle update" do
    before do
      install_gemfile <<-G
        source "file:#{gem_repo1}"
        gem "rack"
      G
    end

    it "warns when no options are given", :bundler => "2" do
      bundle! "update"
      expect(deprecations).to include("Pass --all to `bundle update` to update everything")
    end

    pending "fails with a helpful error when no options are given", :bundler => "3"

    it "does not warn when --all is passed" do
      bundle! "update --all"
      expect(deprecations).to be_empty
    end
  end

  describe "bundle install --binstubs" do
    before do
      install_gemfile <<-G, :binstubs => true
        source "file:#{gem_repo1}"
        gem "rack"
      G
    end

    it "should output a deprecation warning", :bundler => "2" do
      expect(deprecations).to include("The --binstubs option will be removed in favor of `bundle binstubs`")
    end

    pending "fails with a helpful error", :bundler => "3"
  end

  context "bundle install with both gems.rb and Gemfile present" do
    it "should not warn about gems.rb" do
      create_file "gems.rb", <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle :install
      expect(deprecations).to be_empty
    end

    it "should print a proper warning, and use gems.rb" do
      create_file "gems.rb"
      install_gemfile! <<-G
        source "file://#{gem_repo1}"
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
        source "file://#{gem_repo1}"
        gem "rack"
      G
    end

    {
      :clean => true,
      :deployment => true,
      :frozen => true,
      :"no-cache" => true,
      :"no-prune" => true,
      :path => "vendor/bundle",
      :shebang => "ruby27",
      :system => true,
      :without => "development",
      :with => "development",
    }.each do |name, value|
      flag_name = "--#{name}"

      context "with the #{flag_name} flag" do
        before do
          bundle "install" # to create a lockfile, which deployment or frozen need
          bundle "install #{flag_name} #{value}"
        end

        it "should print a deprecation warning", :bundler => "2" do
          expect(deprecations).to include(
            "The `#{flag_name}` flag is deprecated because it relies on " \
            "being remembered accross bundler invokations, which bundler " \
            "will no longer do in future versions. Instead please use " \
            "`bundle config #{name} '#{value}'`, and stop using this flag"
          )
        end

        pending "should fail with a helpful error", :bundler => "3"
      end
    end
  end

  context "bundle install with multiple sources" do
    before do
      install_gemfile <<-G
        source "file://localhost#{gem_repo3}"
        source "file://localhost#{gem_repo1}"
      G
    end

    it "shows a deprecation", :bundler => "2" do
      expect(deprecations).to include(
        "Your Gemfile contains multiple primary sources. " \
        "Using `source` more than once without a block is a security risk, and " \
        "may result in installing unexpected gems. To resolve this warning, use " \
        "a block to indicate which gems should come from the secondary source. " \
        "To upgrade this warning to an error, run `bundle config set " \
        "disable_multisource true`."
      )
    end

    pending "should fail with a helpful error", :bundler => "3"
  end

  context "when Bundler.setup is run in a ruby script" do
    before do
      create_file "gems.rb"
      install_gemfile! <<-G
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
    end

    it "should print a single deprecation warning" do
      expect(warnings).to include(
        "Multiple gemfiles (gems.rb and Gemfile) detected. Make sure you remove Gemfile and Gemfile.lock since bundler is ignoring them in favor of gems.rb and gems.rb.locked."
      )
    end
  end

  context "when `bundler/deployment` is required in a ruby script" do
    before do
      ruby(<<-RUBY)
        require 'bundler/deployment'
      RUBY
    end

    it "should print a capistrano deprecation warning", :bundler => "2" do
      expect(deprecations).to include("Bundler no longer integrates " \
                             "with Capistrano, but Capistrano provides " \
                             "its own integration with Bundler via the " \
                             "capistrano-bundler gem. Use it instead.")
    end

    pending "should fail with a helpful error", :bundler => "3"
  end

  describe Bundler::Dsl do
    let(:msg) do
      <<-EOS
The :github git source is deprecated, and will be removed in the future. Change any "reponame" :github sources to "username/reponame". Add this code to the top of your Gemfile to ensure it continues to work:

    git_source(:github) {|repo_name| "https://github.com/\#{repo_name}.git" }

      EOS
    end

    before do
      @rubygems = double("rubygems")
      allow(Bundler::Source::Rubygems).to receive(:new) { @rubygems }
    end

    context "with github gems" do
      it "warns about the https change if people are opting out" do
        Bundler.settings.temporary "github.https" => false
        expect(Bundler::SharedHelpers).to receive(:major_deprecation).with(3, msg)
        expect(Bundler::SharedHelpers).to receive(:major_deprecation).with(2, "Setting `github.https` to false is deprecated and won't be supported in the future.")
        subject.gem("sparks", :github => "indirect/sparks")
      end

      it "upgrades to https by default", :bundler => "2" do
        expect(Bundler::SharedHelpers).to receive(:major_deprecation).with(3, msg)
        subject.gem("sparks", :github => "indirect/sparks")
        github_uri = "https://github.com/indirect/sparks.git"
        expect(subject.dependencies.first.source.uri).to eq(github_uri)
      end
    end

    context "with bitbucket gems" do
      it "warns about removal" do
        allow(Bundler.ui).to receive(:deprecate)
        msg = <<-EOS
The :bitbucket git source is deprecated, and will be removed in the future. Add this code to the top of your Gemfile to ensure it continues to work:

    git_source(:bitbucket) do |repo_name|
      user_name, repo_name = repo_name.split("/")
      repo_name ||= user_name
      "https://\#{user_name}@bitbucket.org/\#{user_name}/\#{repo_name}.git"
    end

        EOS
        expect(Bundler::SharedHelpers).to receive(:major_deprecation).with(3, msg)
        subject.gem("not-really-a-gem", :bitbucket => "mcorp/flatlab-rails")
      end
    end

    context "with gist gems" do
      it "warns about removal" do
        allow(Bundler.ui).to receive(:deprecate)
        msg = <<-EOS
The :gist git source is deprecated, and will be removed in the future. Add this code to the top of your Gemfile to ensure it continues to work:

    git_source(:gist) {|repo_name| "https://gist.github.com/\#{repo_name}.git" }

        EOS
        expect(Bundler::SharedHelpers).to receive(:major_deprecation).with(3, msg)
        subject.gem("not-really-a-gem", :gist => "1234")
      end
    end
  end

  context "bundle show" do
    before do
      install_gemfile! <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G
    end

    context "without flags" do
      before do
        bundle! :show
      end

      it "prints a deprecation warning recommending `bundle list`", :bundler => "2" do
        expect(deprecations).to include("use `bundle list` instead of `bundle show`")
      end

      pending "fails with a helpful message", :bundler => "3"
    end

    context "with --outdated flag" do
      before do
        bundle! "show --outdated"
      end

      it "prints a deprecation warning informing about its removal", :bundler => "2" do
        expect(deprecations).to include("the `--outdated` flag to `bundle show` was undocumented and will be removed without replacement")
      end

      pending "fails with a helpful message", :bundler => "3"
    end

    context "with --verbose flag" do
      before do
        bundle! "show --verbose"
      end

      it "prints a deprecation warning informing about its removal", :bundler => "2" do
        expect(deprecations).to include("the `--verbose` flag to `bundle show` was undocumented and will be removed without replacement")
      end

      pending "fails with a helpful message", :bundler => "3"
    end

    context "with a gem argument" do
      before do
        bundle! "show rack"
      end

      it "prints a deprecation warning recommending `bundle info`", :bundler => "2" do
        expect(deprecations).to include("use `bundle info rack` instead of `bundle show rack`")
      end
    end

    pending "fails with a helpful message", :bundler => "3"
  end

  context "bundle console" do
    before do
      bundle "console"
    end

    it "prints a deprecation warning", :bundler => "2" do
      expect(deprecations).to include \
        "bundle console will be replaced by `bin/console` generated by `bundle gem <name>`"
    end

    pending "fails with a helpful message", :bundler => "3"
  end

  context "bundle viz" do
    let(:ruby_graphviz) do
      graphviz_glob = base_system_gems.join("cache/ruby-graphviz*")
      Pathname.glob(graphviz_glob).first
    end

    before do
      system_gems ruby_graphviz
      create_file "gems.rb"
      bundle "viz"
    end

    it "prints a deprecation warning", :bundler => "2" do
      expect(deprecations).to include "The `viz` command has been moved to the `bundle-viz` gem, see https://github.com/bundler/bundler-viz"
    end

    pending "fails with a helpful message", :bundler => "3"
  end
end
