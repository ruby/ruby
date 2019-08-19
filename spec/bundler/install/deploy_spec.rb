# frozen_string_literal: true

RSpec.describe "install with --deployment or --frozen" do
  before do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G
  end

  context "with CLI flags", :bundler => "< 3" do
    it "fails without a lockfile and says that --deployment requires a lock" do
      bundle "install --deployment"
      expect(out).to include("The --deployment flag requires a Gemfile.lock")
    end

    it "fails without a lockfile and says that --frozen requires a lock" do
      bundle "install --frozen"
      expect(out).to include("The --frozen flag requires a Gemfile.lock")
    end

    it "disallows --deployment --system" do
      bundle "install --deployment --system"
      expect(out).to include("You have specified both --deployment")
      expect(out).to include("Please choose only one option")
      expect(exitstatus).to eq(15) if exitstatus
    end

    it "disallows --deployment --path --system" do
      bundle "install --deployment --path . --system"
      expect(out).to include("You have specified both --path")
      expect(out).to include("as well as --system")
      expect(out).to include("Please choose only one option")
      expect(exitstatus).to eq(15) if exitstatus
    end

    it "works after you try to deploy without a lock" do
      bundle "install --deployment"
      bundle! :install
      expect(the_bundle).to include_gems "rack 1.0"
    end
  end

  it "still works if you are not in the app directory and specify --gemfile" do
    bundle "install"
    Dir.chdir tmp do
      simulate_new_machine
      bundle! :install,
        forgotten_command_line_options(:gemfile => "#{tmp}/bundled_app/Gemfile",
                                       :deployment => true,
                                       :path => "vendor/bundle")
    end
    expect(the_bundle).to include_gems "rack 1.0"
  end

  it "works if you exclude a group with a git gem" do
    build_git "foo"
    gemfile <<-G
      group :test do
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      end
    G
    bundle :install
    bundle! :install, forgotten_command_line_options(:deployment => true, :without => "test")
  end

  it "works when you bundle exec bundle", :ruby_repo do
    bundle :install
    bundle "install --deployment"
    bundle! "exec bundle check"
  end

  it "works when using path gems from the same path and the version is specified" do
    build_lib "foo", :path => lib_path("nested/foo")
    build_lib "bar", :path => lib_path("nested/bar")
    gemfile <<-G
      gem "foo", "1.0", :path => "#{lib_path("nested")}"
      gem "bar", :path => "#{lib_path("nested")}"
    G

    bundle! :install
    bundle! :install, forgotten_command_line_options(:deployment => true)
  end

  it "works when there are credentials in the source URL" do
    install_gemfile(<<-G, :artifice => "endpoint_strict_basic_authentication", :quiet => true)
      source "http://user:pass@localgemserver.test/"

      gem "rack-obama", ">= 1.0"
    G

    bundle! :install, forgotten_command_line_options(:deployment => true).merge(:artifice => "endpoint_strict_basic_authentication")
  end

  it "works with sources given by a block" do
    install_gemfile! <<-G
      source "file://#{gem_repo1}" do
        gem "rack"
      end
    G

    bundle! :install, forgotten_command_line_options(:deployment => true)

    expect(the_bundle).to include_gems "rack 1.0"
  end

  describe "with an existing lockfile" do
    before do
      bundle "install"
    end

    it "works with the --deployment flag if you didn't change anything", :bundler => "< 3" do
      bundle! "install --deployment"
    end

    it "works with the --frozen flag if you didn't change anything", :bundler => "< 3" do
      bundle! "install --frozen"
    end

    it "works with BUNDLE_FROZEN if you didn't change anything" do
      bundle! :install, :env => { "BUNDLE_FROZEN" => "true" }
    end

    it "explodes with the --deployment flag if you make a change and don't check in the lockfile" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
        gem "rack-obama"
      G

      bundle :install, forgotten_command_line_options(:deployment => true)
      expect(out).to include("deployment mode")
      expect(out).to include("You have added to the Gemfile")
      expect(out).to include("* rack-obama")
      expect(out).not_to include("You have deleted from the Gemfile")
      expect(out).not_to include("You have changed in the Gemfile")
    end

    it "works if a path gem is missing but is in a without group" do
      build_lib "path_gem"
      install_gemfile! <<-G
        source "file://#{gem_repo1}"
        gem "rake"
        gem "path_gem", :path => "#{lib_path("path_gem-1.0")}", :group => :development
      G
      expect(the_bundle).to include_gems "path_gem 1.0"
      FileUtils.rm_r lib_path("path_gem-1.0")

      bundle! :install, forgotten_command_line_options(:path => ".bundle", :without => "development", :deployment => true).merge(:env => { :DEBUG => "1" })
      run! "puts :WIN"
      expect(out).to eq("WIN")
    end

    it "explodes if a path gem is missing" do
      build_lib "path_gem"
      install_gemfile! <<-G
        source "file://#{gem_repo1}"
        gem "rake"
        gem "path_gem", :path => "#{lib_path("path_gem-1.0")}", :group => :development
      G
      expect(the_bundle).to include_gems "path_gem 1.0"
      FileUtils.rm_r lib_path("path_gem-1.0")

      bundle :install, forgotten_command_line_options(:path => ".bundle", :deployment => true)
      expect(out).to include("The path `#{lib_path("path_gem-1.0")}` does not exist.")
    end

    it "can have --frozen set via an environment variable", :bundler => "< 3" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
        gem "rack-obama"
      G

      ENV["BUNDLE_FROZEN"] = "1"
      bundle "install"
      expect(out).to include("deployment mode")
      expect(out).to include("You have added to the Gemfile")
      expect(out).to include("* rack-obama")
      expect(out).not_to include("You have deleted from the Gemfile")
      expect(out).not_to include("You have changed in the Gemfile")
    end

    it "can have --deployment set via an environment variable" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
        gem "rack-obama"
      G

      ENV["BUNDLE_DEPLOYMENT"] = "true"
      bundle "install"
      expect(out).to include("deployment mode")
      expect(out).to include("You have added to the Gemfile")
      expect(out).to include("* rack-obama")
      expect(out).not_to include("You have deleted from the Gemfile")
      expect(out).not_to include("You have changed in the Gemfile")
    end

    it "can have --frozen set to false via an environment variable" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
        gem "rack-obama"
      G

      ENV["BUNDLE_FROZEN"] = "false"
      ENV["BUNDLE_DEPLOYMENT"] = "false"
      bundle "install"
      expect(out).not_to include("deployment mode")
      expect(out).not_to include("You have added to the Gemfile")
      expect(out).not_to include("* rack-obama")
    end

    it "explodes with the --frozen flag if you make a change and don't check in the lockfile", :bundler => "< 2" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
        gem "rack-obama", "1.1"
      G

      bundle :install, forgotten_command_line_options(:frozen => true)
      expect(out).to include("deployment mode")
      expect(out).to include("You have added to the Gemfile")
      expect(out).to include("* rack-obama (= 1.1)")
      expect(out).not_to include("You have deleted from the Gemfile")
      expect(out).not_to include("You have changed in the Gemfile")
    end

    it "explodes if you remove a gem and don't check in the lockfile" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "activesupport"
      G

      bundle :install, forgotten_command_line_options(:deployment => true)
      expect(out).to include("deployment mode")
      expect(out).to include("You have added to the Gemfile:\n* activesupport\n\n")
      expect(out).to include("You have deleted from the Gemfile:\n* rack")
      expect(out).not_to include("You have changed in the Gemfile")
    end

    it "explodes if you add a source" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "git://hubz.com"
      G

      bundle :install, forgotten_command_line_options(:deployment => true)
      expect(out).to include("deployment mode")
      expect(out).to include("You have added to the Gemfile:\n* source: git://hubz.com (at master)")
      expect(out).not_to include("You have changed in the Gemfile")
    end

    it "explodes if you unpin a source" do
      build_git "rack"

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-1.0")}"
      G

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle :install, forgotten_command_line_options(:deployment => true)
      expect(out).to include("deployment mode")
      expect(out).to include("You have deleted from the Gemfile:\n* source: #{lib_path("rack-1.0")} (at master@#{revision_for(lib_path("rack-1.0"))[0..6]}")
      expect(out).not_to include("You have added to the Gemfile")
      expect(out).not_to include("You have changed in the Gemfile")
    end

    it "explodes if you unpin a source, leaving it pinned somewhere else" do
      build_lib "foo", :path => lib_path("rack/foo")
      build_git "rack", :path => lib_path("rack")

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack")}"
        gem "foo", :git => "#{lib_path("rack")}"
      G

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
        gem "foo", :git => "#{lib_path("rack")}"
      G

      bundle :install, forgotten_command_line_options(:deployment => true)
      expect(out).to include("deployment mode")
      expect(out).to include("You have changed in the Gemfile:\n* rack from `no specified source` to `#{lib_path("rack")} (at master@#{revision_for(lib_path("rack"))[0..6]})`")
      expect(out).not_to include("You have added to the Gemfile")
      expect(out).not_to include("You have deleted from the Gemfile")
    end

    context "when replacing a host with the same host with credentials" do
      let(:success_message) do
        if Bundler.bundler_major_version < 3
          "Could not reach host localgemserver.test"
        else
          "Bundle complete!"
        end
      end

      before do
        install_gemfile <<-G
        source "http://user_name:password@localgemserver.test/"
        gem "rack"
        G

        lockfile <<-G
        GEM
          remote: http://localgemserver.test/
          specs:
            rack (1.0.0)

        PLATFORMS
          #{local}

        DEPENDENCIES
          rack
        G
      end

      it "prevents the replace by default" do
        bundle :install, forgotten_command_line_options(:deployment => true)

        expect(out).to match(/The list of sources changed/)
      end

      context "when allow_deployment_source_credential_changes is true" do
        before { bundle! "config allow_deployment_source_credential_changes true" }

        it "allows the replace" do
          bundle :install, forgotten_command_line_options(:deployment => true)

          expect(out).to match(/#{success_message}/)
        end
      end

      context "when allow_deployment_source_credential_changes is false" do
        before { bundle! "config allow_deployment_source_credential_changes false" }

        it "prevents the replace" do
          bundle :install, forgotten_command_line_options(:deployment => true)

          expect(out).to match(/The list of sources changed/)
        end
      end

      context "when BUNDLE_ALLOW_DEPLOYMENT_SOURCE_CREDENTIAL_CHANGES env var is true" do
        before { ENV["BUNDLE_ALLOW_DEPLOYMENT_SOURCE_CREDENTIAL_CHANGES"] = "true" }

        it "allows the replace" do
          bundle :install, forgotten_command_line_options(:deployment => true)

          expect(out).to match(/#{success_message}/)
        end
      end

      context "when BUNDLE_ALLOW_DEPLOYMENT_SOURCE_CREDENTIAL_CHANGES env var is false" do
        before { ENV["BUNDLE_ALLOW_DEPLOYMENT_SOURCE_CREDENTIAL_CHANGES"] = "false" }

        it "prevents the replace" do
          bundle :install, forgotten_command_line_options(:deployment => true)

          expect(out).to match(/The list of sources changed/)
        end
      end
    end

    it "remembers that the bundle is frozen at runtime" do
      bundle! :lock

      bundle! "config deployment true"

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", "1.0.0"
        gem "rack-obama"
      G

      expect(the_bundle).not_to include_gems "rack 1.0.0"
      expect(err).to include strip_whitespace(<<-E).strip
The dependencies in your gemfile changed

You have added to the Gemfile:
* rack (= 1.0.0)
* rack-obama

You have deleted from the Gemfile:
* rack
      E
    end
  end

  context "with path in Gemfile and packed" do
    it "works fine after bundle package and bundle install --local" do
      build_lib "foo", :path => lib_path("foo")
      install_gemfile! <<-G
        gem "foo", :path => "#{lib_path("foo")}"
      G

      bundle! :install
      expect(the_bundle).to include_gems "foo 1.0"
      bundle! :package, forgotten_command_line_options([:all, :cache_all] => true)
      expect(bundled_app("vendor/cache/foo")).to be_directory

      bundle! "install --local"
      expect(out).to include("Updating files in vendor/cache")

      simulate_new_machine
      bundle! "install --verbose", forgotten_command_line_options(:deployment => true)
      expect(out).not_to include("You are trying to install in deployment mode after changing your Gemfile")
      expect(out).not_to include("You have added to the Gemfile")
      expect(out).not_to include("You have deleted from the Gemfile")
      expect(out).to include("vendor/cache/foo")
      expect(the_bundle).to include_gems "foo 1.0"
    end
  end
end
