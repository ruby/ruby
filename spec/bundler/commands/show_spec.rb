# frozen_string_literal: true

RSpec.describe "bundle show", :bundler => "< 2", :ruby => ">= 2.0" do
  context "with a standard Gemfile" do
    before :each do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rails"
      G
    end

    it "creates a Gemfile.lock if one did not exist" do
      FileUtils.rm("Gemfile.lock")

      bundle "show"

      expect(bundled_app("Gemfile.lock")).to exist
    end

    it "creates a Gemfile.lock when invoked with a gem name" do
      FileUtils.rm("Gemfile.lock")

      bundle "show rails"

      expect(bundled_app("Gemfile.lock")).to exist
    end

    it "prints path if gem exists in bundle" do
      bundle "show rails"
      expect(out).to eq(default_bundle_path("gems", "rails-2.3.2").to_s)
    end

    context "when show command deprecation is enabled" do
      before { bundle "config major_deprecations yes" }

      it "prints path if gem exists in bundle" do
        bundle "show rails"
        expect(out).to eq(
          "[DEPRECATED FOR 2.0] use `bundle info rails` instead of `bundle show rails`\n" +
          default_bundle_path("gems", "rails-2.3.2").to_s
        )
      end

      it "prints the path to the running bundler" do
        bundle "show bundler"
        expect(out).to eq(
          "[DEPRECATED FOR 2.0] use `bundle info bundler` instead of `bundle show bundler`\n" +
          root.to_s
        )
      end

      it "prints path if gem exists in bundle (with --paths option)" do
        bundle "show rails --paths"
        expect(out).to eq(
          "[DEPRECATED FOR 2.0] use `bundle info rails --path` instead of `bundle show rails --paths`\n" +
          default_bundle_path("gems", "rails-2.3.2").to_s
        )
      end

      it "prints path of all gems in bundle sorted by name" do
        bundle "show --paths"

        expect(out).to include(default_bundle_path("gems", "rake-10.0.2").to_s)
        expect(out).to include(default_bundle_path("gems", "rails-2.3.2").to_s)

        out_lines = out.split("\n")
        expect(out_lines[0]).to eq("[DEPRECATED FOR 2.0] use `bundle list` instead of `bundle show --paths`")

        # Gem names are the last component of their path.
        gem_list = out_lines[1..-1].map {|p| p.split("/").last }
        expect(gem_list).to eq(gem_list.sort)
      end
    end

    it "prints path if gem exists in bundle (with --paths option)" do
      bundle "show rails --paths"
      expect(out).to eq(default_bundle_path("gems", "rails-2.3.2").to_s)
    end

    it "warns if path no longer exists on disk" do
      FileUtils.rm_rf(default_bundle_path("gems", "rails-2.3.2"))

      bundle "show rails"

      expect(out).to match(/has been deleted/i).
        and include(default_bundle_path("gems", "rails-2.3.2").to_s)
    end

    it "prints the path to the running bundler" do
      bundle "show bundler"
      expect(out).to eq(root.to_s)
    end

    it "complains if gem not in bundle" do
      bundle "show missing"
      expect(out).to match(/could not find gem 'missing'/i)
    end

    it "prints path of all gems in bundle sorted by name" do
      bundle "show --paths"

      expect(out).to include(default_bundle_path("gems", "rake-10.0.2").to_s)
      expect(out).to include(default_bundle_path("gems", "rails-2.3.2").to_s)

      # Gem names are the last component of their path.
      gem_list = out.split.map {|p| p.split("/").last }
      expect(gem_list).to eq(gem_list.sort)
    end

    it "prints summary of gems" do
      bundle "show --verbose"

      loaded_bundler_spec = Bundler.load.specs["bundler"]
      expected = if !loaded_bundler_spec.empty?
        loaded_bundler_spec[0].homepage
      else
        "No website available."
      end

      expect(out).to include("* actionmailer (2.3.2)")
      expect(out).to include("\tSummary:  This is just a fake gem for testing")
      expect(out).to include("\tHomepage: #{expected}")
      expect(out).to include("\tStatus:   Up to date")
    end
  end

  context "with a git repo in the Gemfile" do
    before :each do
      @git = build_git "foo", "1.0"
    end

    it "prints out git info" do
      install_gemfile <<-G
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G
      expect(the_bundle).to include_gems "foo 1.0"

      bundle :show
      expect(out).to include("foo (1.0 #{@git.ref_for("master", 6)}")
    end

    it "prints out branch names other than master" do
      update_git "foo", :branch => "omg" do |s|
        s.write "lib/foo.rb", "FOO = '1.0.omg'"
      end
      @revision = revision_for(lib_path("foo-1.0"))[0...6]

      install_gemfile <<-G
        gem "foo", :git => "#{lib_path("foo-1.0")}", :branch => "omg"
      G
      expect(the_bundle).to include_gems "foo 1.0.omg"

      bundle :show
      expect(out).to include("foo (1.0 #{@git.ref_for("omg", 6)}")
    end

    it "doesn't print the branch when tied to a ref" do
      sha = revision_for(lib_path("foo-1.0"))
      install_gemfile <<-G
        gem "foo", :git => "#{lib_path("foo-1.0")}", :ref => "#{sha}"
      G

      bundle :show
      expect(out).to include("foo (1.0 #{sha[0..6]})")
    end

    it "handles when a version is a '-' prerelease", :rubygems => "2.1" do
      @git = build_git("foo", "1.0.0-beta.1", :path => lib_path("foo"))
      install_gemfile <<-G
        gem "foo", "1.0.0-beta.1", :git => "#{lib_path("foo")}"
      G
      expect(the_bundle).to include_gems "foo 1.0.0.pre.beta.1"

      bundle! :show
      expect(out).to include("foo (1.0.0.pre.beta.1")
    end
  end

  context "in a fresh gem in a blank git repo" do
    before :each do
      build_git "foo", :path => lib_path("foo")
      in_app_root_custom lib_path("foo")
      File.open("Gemfile", "w") {|f| f.puts "gemspec" }
      sys_exec "rm -rf .git && git init"
    end

    it "does not output git errors" do
      bundle :show
      expect(err).to lack_errors
    end
  end

  it "performs an automatic bundle install" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "foo"
    G

    bundle "config auto_install 1"
    bundle :show
    expect(out).to include("Installing foo 1.0")
  end

  context "with an invalid regexp for gem name" do
    it "does not find the gem" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rails"
      G

      invalid_regexp = "[]"

      bundle "show #{invalid_regexp}"
      expect(out).to include("Could not find gem '#{invalid_regexp}'.")
    end
  end

  context "--outdated option" do
    # Regression test for https://github.com/bundler/bundler/issues/5375
    before do
      build_repo2
    end

    it "doesn't update gems to newer versions" do
      install_gemfile! <<-G
        source "file://#{gem_repo2}"
        gem "rails"
      G

      expect(the_bundle).to include_gem("rails 2.3.2")

      update_repo2 do
        build_gem "rails", "3.0.0" do |s|
          s.executables = "rails"
        end
      end

      bundle! "show --outdated"

      bundle! "install"
      expect(the_bundle).to include_gem("rails 2.3.2")
    end
  end
end
