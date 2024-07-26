# frozen_string_literal: true

RSpec.describe "bundle open" do
  context "when opening a regular gem" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rails"
      G
    end

    it "opens the gem with BUNDLER_EDITOR as highest priority" do
      bundle "open rails", env: { "EDITOR" => "echo editor", "VISUAL" => "echo visual", "BUNDLER_EDITOR" => "echo bundler_editor" }
      expect(out).to include("bundler_editor #{default_bundle_path("gems", "rails-2.3.2")}")
    end

    it "opens the gem with VISUAL as 2nd highest priority" do
      bundle "open rails", env: { "EDITOR" => "echo editor", "VISUAL" => "echo visual", "BUNDLER_EDITOR" => "" }
      expect(out).to include("visual #{default_bundle_path("gems", "rails-2.3.2")}")
    end

    it "opens the gem with EDITOR as 3rd highest priority" do
      bundle "open rails", env: { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }
      expect(out).to include("editor #{default_bundle_path("gems", "rails-2.3.2")}")
    end

    it "complains if no EDITOR is set" do
      bundle "open rails", env: { "EDITOR" => "", "VISUAL" => "", "BUNDLER_EDITOR" => "" }
      expect(out).to eq("To open a bundled gem, set $EDITOR or $BUNDLER_EDITOR")
    end

    it "complains if gem not in bundle" do
      bundle "open missing", env: { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }, raise_on_error: false
      expect(err).to match(/could not find gem 'missing'/i)
    end

    it "does not blow up if the gem to open does not have a Gemfile" do
      git = build_git "foo"
      ref = git.ref_for("main", 11)

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'foo', :git => "#{lib_path("foo-1.0")}"
      G

      bundle "open foo", env: { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }
      expect(out).to include("editor #{default_bundle_path("bundler", "gems", "foo-1.0-#{ref}")}")
    end

    it "suggests alternatives for similar-sounding gems" do
      bundle "open Rails", env: { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }, raise_on_error: false
      expect(err).to match(/did you mean rails\?/i)
    end

    it "opens the gem with short words" do
      bundle "open rec", env: { "EDITOR" => "echo editor", "VISUAL" => "echo visual", "BUNDLER_EDITOR" => "echo bundler_editor" }

      expect(out).to include("bundler_editor #{default_bundle_path("gems", "activerecord-2.3.2")}")
    end

    it "opens subpath of the gem" do
      bundle "open activerecord --path lib/activerecord", env: { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }
      expect(out).to include("editor #{default_bundle_path("gems", "activerecord-2.3.2")}/lib/activerecord")
    end

    it "opens subpath file of the gem" do
      bundle "open activerecord --path lib/version.rb", env: { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }
      expect(out).to include("editor #{default_bundle_path("gems", "activerecord-2.3.2")}/lib/version.rb")
    end

    it "opens deep subpath of the gem" do
      bundle "open activerecord --path lib/active_record", env: { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }
      expect(out).to include("editor #{default_bundle_path("gems", "activerecord-2.3.2")}/lib/active_record")
    end

    it "requires value for --path arg" do
      bundle "open activerecord --path", env: { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }, raise_on_error: false
      expect(err).to eq "Cannot specify `--path` option without a value"
    end

    it "suggests alternatives for similar-sounding gems when using subpath" do
      bundle "open Rails --path README.md", env: { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }, raise_on_error: false
      expect(err).to match(/did you mean rails\?/i)
    end

    it "suggests alternatives for similar-sounding gems when using deep subpath" do
      bundle "open Rails --path some/path/here", env: { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }, raise_on_error: false
      expect(err).to match(/did you mean rails\?/i)
    end

    it "opens subpath of the short worded gem" do
      bundle "open rec --path CHANGELOG.md", env: { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }
      expect(out).to include("editor #{default_bundle_path("gems", "activerecord-2.3.2")}/CHANGELOG.md")
    end

    it "opens deep subpath of the short worded gem" do
      bundle "open rec --path lib/activerecord", env: { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }
      expect(out).to include("editor #{default_bundle_path("gems", "activerecord-2.3.2")}/lib/activerecord")
    end

    it "opens subpath of the selected matching gem", :readline do
      env = { "EDITOR" => "echo editor", "VISUAL" => "echo visual", "BUNDLER_EDITOR" => "echo bundler_editor" }
      bundle "open active --path CHANGELOG.md", env: env do |input, _, _|
        input.puts "2"
      end

      expect(out).to include("bundler_editor #{default_bundle_path("gems", "activerecord-2.3.2").join("CHANGELOG.md")}")
    end

    it "opens deep subpath of the selected matching gem", :readline do
      env = { "EDITOR" => "echo editor", "VISUAL" => "echo visual", "BUNDLER_EDITOR" => "echo bundler_editor" }
      bundle "open active --path lib/activerecord/version.rb", env: env do |input, _, _|
        input.puts "2"
      end

      expect(out).to include("bundler_editor #{default_bundle_path("gems", "activerecord-2.3.2").join("lib", "activerecord", "version.rb")}")
    end

    it "select the gem from many match gems", :readline do
      env = { "EDITOR" => "echo editor", "VISUAL" => "echo visual", "BUNDLER_EDITOR" => "echo bundler_editor" }
      bundle "open active", env: env do |input, _, _|
        input.puts "2"
      end

      expect(out).to include("bundler_editor #{default_bundle_path("gems", "activerecord-2.3.2")}")
    end

    it "allows selecting exit from many match gems", :readline do
      env = { "EDITOR" => "echo editor", "VISUAL" => "echo visual", "BUNDLER_EDITOR" => "echo bundler_editor" }
      bundle "open active", env: env do |input, _, _|
        input.puts "0"
      end
    end

    it "performs an automatic bundle install" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rails"
        gem "foo"
      G

      bundle "config set auto_install 1"
      bundle "open rails", env: { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }
      expect(out).to include("Installing foo 1.0")
    end

    it "opens the editor with a clean env" do
      bundle "open", env: { "EDITOR" => "sh -c 'env'", "VISUAL" => "", "BUNDLER_EDITOR" => "" }, raise_on_error: false
      expect(out).not_to include("BUNDLE_GEMFILE=")
    end
  end

  context "when opening a default gem" do
    let(:default_gems) do
      ruby(<<-RUBY).split("\n")
        if Gem::Specification.is_a?(Enumerable)
          puts Gem::Specification.select(&:default_gem?).map(&:name)
        end
      RUBY
    end

    before do
      skip "No default gems available on this test run" if default_gems.empty?

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
      G
    end

    it "throws proper error when trying to open default gem" do
      bundle "open json", env: { "EDITOR" => "echo editor", "VISUAL" => "echo visual", "BUNDLER_EDITOR" => "echo bundler_editor" }
      expect(out).to include("Unable to open json because it's a default gem, so the directory it would normally be installed to does not exist.")
    end
  end
end
