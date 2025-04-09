# frozen_string_literal: true

RSpec.describe "bundle lock with git gems" do
  let(:install_gemfile_with_foo_as_a_git_dependency) do
    build_git "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem 'foo', :git => "#{lib_path("foo-1.0")}"
    G
  end

  it "doesn't break right after running lock" do
    install_gemfile_with_foo_as_a_git_dependency

    expect(the_bundle).to include_gems "foo 1.0.0"
  end

  it "doesn't print errors even if running lock after removing the cache" do
    install_gemfile_with_foo_as_a_git_dependency

    FileUtils.rm_r(Dir[default_cache_path("git/foo-1.0-*")].first)

    bundle "lock --verbose"

    expect(err).to be_empty
  end

  it "prints a proper error when changing a locked Gemfile to point to a bad branch" do
    install_gemfile_with_foo_as_a_git_dependency

    gemfile <<-G
      source "https://gem.repo1"
      gem 'foo', :git => "#{lib_path("foo-1.0")}", :branch => "bad"
    G

    bundle "lock --update foo", env: { "LANG" => "en" }, raise_on_error: false

    expect(err).to include("Revision bad does not exist in the repository")
  end

  it "prints a proper error when installing a Gemfile with a locked ref that does not exist" do
    install_gemfile_with_foo_as_a_git_dependency

    lockfile <<~L
      GIT
        remote: #{lib_path("foo-1.0")}
        revision: #{"a" * 40}
        specs:
          foo (1.0)

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "install", raise_on_error: false

    expect(err).to include("Revision #{"a" * 40} does not exist in the repository")
  end

  it "locks a git source to the current ref" do
    install_gemfile_with_foo_as_a_git_dependency

    update_git "foo"
    bundle :install

    run <<-RUBY
      require 'foo'
      puts "WIN" unless defined?(FOO_PREV_REF)
    RUBY

    expect(out).to eq("WIN")
  end

  it "properly clones a git source locked to an out of date ref" do
    install_gemfile_with_foo_as_a_git_dependency

    update_git "foo"

    bundle :install, env: { "BUNDLE_PATH" => "foo" }
    expect(err).to be_empty
  end

  it "properly fetches a git source locked to an unreachable ref" do
    install_gemfile_with_foo_as_a_git_dependency

    # Create a commit and make it unreachable
    git "checkout -b foo ", lib_path("foo-1.0")
    unreachable_sha = update_git("foo").ref_for("HEAD")
    git "checkout main ", lib_path("foo-1.0")
    git "branch -D foo ", lib_path("foo-1.0")

    gemfile <<-G
      source "https://gem.repo1"
      gem 'foo', :git => "#{lib_path("foo-1.0")}"
    G

    lockfile <<-L
      GIT
        remote: #{lib_path("foo-1.0")}
        revision: #{unreachable_sha}
        specs:
          foo (1.0)

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "install"

    expect(err).to be_empty
  end

  it "properly fetches a git source locked to an annotated tag" do
    install_gemfile_with_foo_as_a_git_dependency

    # Create an annotated tag
    git("tag -a v1.0 -m 'Annotated v1.0'", lib_path("foo-1.0"))
    annotated_tag = git("rev-parse v1.0", lib_path("foo-1.0"))

    gemfile <<-G
      source "https://gem.repo1"
      gem 'foo', :git => "#{lib_path("foo-1.0")}"
    G

    lockfile <<-L
      GIT
        remote: #{lib_path("foo-1.0")}
        revision: #{annotated_tag}
        specs:
          foo (1.0)

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "install"

    expect(err).to be_empty
  end

  it "provides correct #full_gem_path" do
    install_gemfile_with_foo_as_a_git_dependency

    run <<-RUBY
      puts Bundler.rubygems.find_name('foo').first.full_gem_path
    RUBY
    expect(out).to eq(bundle("info foo --path"))
  end

  it "does not lock versions that don't exist in the repository when changing a GEM transitive dep to a GIT direct dep" do
    build_repo4 do
      build_gem "activesupport", "8.0.0" do |s|
        s.add_dependency "securerandom"
      end

      build_gem "securerandom", "0.3.1"
    end

    path = lib_path("securerandom")

    build_git "securerandom", "0.3.2", path: path

    lockfile <<~L
      GEM
        remote: https://gem.repo4/
        specs:
          activesupport (8.0.0)
            securerandom
          securerandom (0.3.1)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        activesupport

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    gemfile <<~G
      source "https://gem.repo4"

      gem "activesupport"
      gem "securerandom", git: "#{path}"
    G

    bundle "lock"

    expect(lockfile).to include("securerandom (0.3.2)")
  end
end
