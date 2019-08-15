# frozen_string_literal: true

RSpec.describe "bundle add" do
  before :each do
    build_repo2 do
      build_gem "foo", "1.1"
      build_gem "foo", "2.0"
      build_gem "baz", "1.2.3"
      build_gem "bar", "0.12.3"
      build_gem "cat", "0.12.3.pre"
      build_gem "dog", "1.1.3.pre"
    end

    build_git "foo", "2.0"

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"
      gem "weakling", "~> 0.0.1"
    G
  end

  context "when no gems are specified" do
    it "shows error" do
      bundle "add"

      expect(err).to include("Please specify gems to add")
    end
  end

  describe "without version specified" do
    it "version requirement becomes ~> major.minor.patch when resolved version is < 1.0" do
      bundle "add 'bar'"
      expect(bundled_app("Gemfile").read).to match(/gem "bar", "~> 0.12.3"/)
      expect(the_bundle).to include_gems "bar 0.12.3"
    end

    it "version requirement becomes ~> major.minor when resolved version is > 1.0" do
      bundle "add 'baz'"
      expect(bundled_app("Gemfile").read).to match(/gem "baz", "~> 1.2"/)
      expect(the_bundle).to include_gems "baz 1.2.3"
    end

    it "version requirement becomes ~> major.minor.patch.pre when resolved version is < 1.0" do
      bundle "add 'cat'"
      expect(bundled_app("Gemfile").read).to match(/gem "cat", "~> 0.12.3.pre"/)
      expect(the_bundle).to include_gems "cat 0.12.3.pre"
    end

    it "version requirement becomes ~> major.minor.pre when resolved version is > 1.0.pre" do
      bundle "add 'dog'"
      expect(bundled_app("Gemfile").read).to match(/gem "dog", "~> 1.1.pre"/)
      expect(the_bundle).to include_gems "dog 1.1.3.pre"
    end
  end

  describe "with --version" do
    it "adds dependency of specified version and runs install" do
      bundle "add 'foo' --version='~> 1.0'"
      expect(bundled_app("Gemfile").read).to match(/gem "foo", "~> 1.0"/)
      expect(the_bundle).to include_gems "foo 1.1"
    end

    it "adds multiple version constraints when specified" do
      requirements = ["< 3.0", "> 1.0"]
      bundle "add 'foo' --version='#{requirements.join(", ")}'"
      expect(bundled_app("Gemfile").read).to match(/gem "foo", #{Gem::Requirement.new(requirements).as_list.map(&:dump).join(', ')}/)
      expect(the_bundle).to include_gems "foo 2.0"
    end
  end

  describe "with --group" do
    it "adds dependency for the specified group" do
      bundle "add 'foo' --group='development'"
      expect(bundled_app("Gemfile").read).to match(/gem "foo", "~> 2.0", :group => :development/)
      expect(the_bundle).to include_gems "foo 2.0"
    end

    it "adds dependency to more than one group" do
      bundle "add 'foo' --group='development, test'"
      expect(bundled_app("Gemfile").read).to match(/gem "foo", "~> 2.0", :groups => \[:development, :test\]/)
      expect(the_bundle).to include_gems "foo 2.0"
    end
  end

  describe "with --source" do
    it "adds dependency with specified source" do
      bundle "add 'foo' --source='#{file_uri_for(gem_repo2)}'"

      expect(bundled_app("Gemfile").read).to match(/gem "foo", "~> 2.0", :source => "#{file_uri_for(gem_repo2)}"/)
      expect(the_bundle).to include_gems "foo 2.0"
    end
  end

  describe "with --git" do
    it "adds dependency with specified github source" do
      bundle "add foo --git=#{lib_path("foo-2.0")}"

      expect(bundled_app("Gemfile").read).to match(/gem "foo", "~> 2.0", :git => "#{lib_path("foo-2.0")}"/)
      expect(the_bundle).to include_gems "foo 2.0"
    end
  end

  describe "with --git and --branch" do
    before do
      update_git "foo", "2.0", :branch => "test"
    end

    it "adds dependency with specified github source and branch" do
      bundle "add foo --git=#{lib_path("foo-2.0")} --branch=test"

      expect(bundled_app("Gemfile").read).to match(/gem "foo", "~> 2.0", :git => "#{lib_path("foo-2.0")}", :branch => "test"/)
      expect(the_bundle).to include_gems "foo 2.0"
    end
  end

  describe "with --skip-install" do
    it "adds gem to Gemfile but is not installed" do
      bundle "add foo --skip-install --version=2.0"

      expect(bundled_app("Gemfile").read).to match(/gem "foo", "= 2.0"/)
      expect(the_bundle).to_not include_gems "foo 2.0"
    end
  end

  it "using combination of short form options works like long form" do
    bundle "add 'foo' -s='#{file_uri_for(gem_repo2)}' -g='development' -v='~>1.0'"
    expect(bundled_app("Gemfile").read).to include %(gem "foo", "~> 1.0", :group => :development, :source => "#{file_uri_for(gem_repo2)}")
    expect(the_bundle).to include_gems "foo 1.1"
  end

  it "shows error message when version is not formatted correctly" do
    bundle "add 'foo' -v='~>1 . 0'"
    expect(err).to match("Invalid gem requirement pattern '~>1 . 0'")
  end

  it "shows error message when gem cannot be found" do
    bundle "config set force_ruby_platform true"
    bundle "add 'werk_it'"
    expect(err).to match("Could not find gem 'werk_it' in")

    bundle "add 'werk_it' -s='#{file_uri_for(gem_repo2)}'"
    expect(err).to match("Could not find gem 'werk_it' in rubygems repository")
  end

  it "shows error message when source cannot be reached" do
    bundle "add 'baz' --source='http://badhostasdf'"
    expect(err).to include("Could not reach host badhostasdf. Check your network connection and try again.")

    bundle "add 'baz' --source='file://does/not/exist'"
    expect(err).to include("Could not fetch specs from file://does/not/exist/")
  end

  describe "with --optimistic" do
    it "adds optimistic version" do
      bundle! "add 'foo' --optimistic"
      expect(bundled_app("Gemfile").read).to include %(gem "foo", ">= 2.0")
      expect(the_bundle).to include_gems "foo 2.0"
    end
  end

  describe "with --strict option" do
    it "adds strict version" do
      bundle! "add 'foo' --strict"
      expect(bundled_app("Gemfile").read).to include %(gem "foo", "= 2.0")
      expect(the_bundle).to include_gems "foo 2.0"
    end
  end

  describe "with no option" do
    it "adds pessimistic version" do
      bundle! "add 'foo'"
      expect(bundled_app("Gemfile").read).to include %(gem "foo", "~> 2.0")
      expect(the_bundle).to include_gems "foo 2.0"
    end
  end

  describe "with --optimistic and --strict" do
    it "throws error" do
      bundle "add 'foo' --strict --optimistic"

      expect(err).to include("You can not specify `--strict` and `--optimistic` at the same time")
    end
  end

  context "multiple gems" do
    it "adds multiple gems to gemfile" do
      bundle! "add bar baz"

      expect(bundled_app("Gemfile").read).to match(/gem "bar", "~> 0.12.3"/)
      expect(bundled_app("Gemfile").read).to match(/gem "baz", "~> 1.2"/)
    end

    it "throws error if any of the specified gems are present in the gemfile with different version" do
      bundle "add weakling bar"

      expect(err).to include("You cannot specify the same gem twice with different version requirements")
      expect(err).to include("You specified: weakling (~> 0.0.1) and weakling (>= 0).")
    end
  end

  describe "when a gem is added which is already specified in Gemfile with version" do
    it "shows an error when added with different version requirement" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rack", "1.0"
      G

      bundle "add 'rack' --version=1.1"

      expect(err).to include("You cannot specify the same gem twice with different version requirements")
      expect(err).to include("If you want to update the gem version, run `bundle update rack`. You may also need to change the version requirement specified in the Gemfile if it's too restrictive")
    end

    it "shows error when added without version requirements" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rack", "1.0"
      G

      bundle "add 'rack'"

      expect(err).to include("Gem already added.")
      expect(err).to include("You cannot specify the same gem twice with different version requirements")
      expect(err).not_to include("If you want to update the gem version, run `bundle update rack`. You may also need to change the version requirement specified in the Gemfile if it's too restrictive")
    end
  end

  describe "when a gem is added which is already specified in Gemfile without version" do
    it "shows an error when added with different version requirement" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rack"
      G

      bundle "add 'rack' --version=1.1"

      expect(err).to include("You cannot specify the same gem twice with different version requirements")
      expect(err).to include("If you want to update the gem version, run `bundle update rack`.")
      expect(err).not_to include("You may also need to change the version requirement specified in the Gemfile if it's too restrictive")
    end
  end
end
