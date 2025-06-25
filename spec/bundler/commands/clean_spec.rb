# frozen_string_literal: true

RSpec.describe "bundle clean" do
  def should_have_gems(*gems)
    gems.each do |g|
      expect(vendored_gems("gems/#{g}")).to exist
      expect(vendored_gems("specifications/#{g}.gemspec")).to exist
      expect(vendored_gems("cache/#{g}.gem")).to exist
    end
  end

  def should_not_have_gems(*gems)
    gems.each do |g|
      expect(vendored_gems("gems/#{g}")).not_to exist
      expect(vendored_gems("specifications/#{g}.gemspec")).not_to exist
      expect(vendored_gems("cache/#{g}.gem")).not_to exist
    end
  end

  it "removes unused gems that are different" do
    gemfile <<-G
      source "https://gem.repo1"

      gem "thin"
      gem "foo"
    G

    bundle "config set path vendor/bundle"
    bundle "config set clean false"
    bundle "install"

    gemfile <<-G
      source "https://gem.repo1"

      gem "thin"
    G
    bundle "install"

    bundle :clean

    expect(out).to include("Removing foo (1.0)")

    should_have_gems "thin-1.0", "myrack-1.0.0"
    should_not_have_gems "foo-1.0"

    expect(vendored_gems("bin/myrackup")).to exist
  end

  it "removes old version of gem if unused" do
    gemfile <<-G
      source "https://gem.repo1"

      gem "myrack", "0.9.1"
      gem "foo"
    G

    bundle "config set path vendor/bundle"
    bundle "config set clean false"
    bundle "install"

    gemfile <<-G
      source "https://gem.repo1"

      gem "myrack", "1.0.0"
      gem "foo"
    G
    bundle "install"

    bundle :clean

    expect(out).to include("Removing myrack (0.9.1)")

    should_have_gems "foo-1.0", "myrack-1.0.0"
    should_not_have_gems "myrack-0.9.1"

    expect(vendored_gems("bin/myrackup")).to exist
  end

  it "removes new version of gem if unused" do
    gemfile <<-G
      source "https://gem.repo1"

      gem "myrack", "1.0.0"
      gem "foo"
    G

    bundle "config set path vendor/bundle"
    bundle "config set clean false"
    bundle "install"

    gemfile <<-G
      source "https://gem.repo1"

      gem "myrack", "0.9.1"
      gem "foo"
    G
    bundle "update myrack"

    bundle :clean

    expect(out).to include("Removing myrack (1.0.0)")

    should_have_gems "foo-1.0", "myrack-0.9.1"
    should_not_have_gems "myrack-1.0.0"

    expect(vendored_gems("bin/myrackup")).to exist
  end

  it "removes gems in bundle without groups" do
    gemfile <<-G
      source "https://gem.repo1"

      gem "foo"

      group :test_group do
        gem "myrack", "1.0.0"
      end
    G

    bundle "config set path vendor/bundle"
    bundle "install"
    bundle "config set without test_group"
    bundle "install"
    bundle :clean

    expect(out).to include("Removing myrack (1.0.0)")

    should_have_gems "foo-1.0"
    should_not_have_gems "myrack-1.0.0"

    expect(vendored_gems("bin/myrackup")).to_not exist
  end

  it "does not remove cached git dir if it's being used" do
    build_git "foo"
    revision = revision_for(lib_path("foo-1.0"))
    git_path = lib_path("foo-1.0")

    gemfile <<-G
      source "https://gem.repo1"

      gem "myrack", "1.0.0"
      git "#{git_path}", :ref => "#{revision}" do
        gem "foo"
      end
    G

    bundle "config set path vendor/bundle"
    bundle "install"

    bundle :clean

    digest = Digest(:SHA1).hexdigest(git_path.to_s)
    cache_path = Bundler.feature_flag.global_gem_cache? ? home(".bundle/cache/git/foo-1.0-#{digest}") : vendored_gems("cache/bundler/git/foo-1.0-#{digest}")
    expect(cache_path).to exist
  end

  it "removes unused git gems" do
    build_git "foo", path: lib_path("foo")
    git_path = lib_path("foo")
    revision = revision_for(git_path)

    gemfile <<-G
      source "https://gem.repo1"

      gem "myrack", "1.0.0"
      git "#{git_path}", :ref => "#{revision}" do
        gem "foo"
      end
    G

    bundle "config set path vendor/bundle"
    bundle "install"

    gemfile <<-G
      source "https://gem.repo1"

      gem "myrack", "1.0.0"
    G
    bundle "install"

    bundle :clean

    expect(out).to include("Removing foo (#{revision[0..11]})")

    expect(vendored_gems("gems/myrack-1.0.0")).to exist
    expect(vendored_gems("bundler/gems/foo-#{revision[0..11]}")).not_to exist
    digest = Digest(:SHA1).hexdigest(git_path.to_s)
    expect(vendored_gems("cache/bundler/git/foo-#{digest}")).not_to exist

    expect(vendored_gems("specifications/myrack-1.0.0.gemspec")).to exist

    expect(vendored_gems("bin/myrackup")).to exist
  end

  it "keeps used git gems even if installed to a symlinked location" do
    build_git "foo", path: lib_path("foo")
    git_path = lib_path("foo")
    revision = revision_for(git_path)

    gemfile <<-G
      source "https://gem.repo1"

      gem "myrack", "1.0.0"
      git "#{git_path}", :ref => "#{revision}" do
        gem "foo"
      end
    G

    FileUtils.mkdir_p(bundled_app("real-path"))
    File.symlink(bundled_app("real-path"), bundled_app("symlink-path"))

    bundle "config set path #{bundled_app("symlink-path")}"
    bundle "install"

    bundle :clean

    expect(out).not_to include("Removing foo (#{revision[0..11]})")

    expect(bundled_app("symlink-path/#{Bundler.ruby_scope}/bundler/gems/foo-#{revision[0..11]}")).to exist
  end

  it "removes old git gems" do
    build_git "foo-bar", path: lib_path("foo-bar")
    revision = revision_for(lib_path("foo-bar"))

    gemfile <<-G
      source "https://gem.repo1"

      gem "myrack", "1.0.0"
      git "#{lib_path("foo-bar")}" do
        gem "foo-bar"
      end
    G

    bundle "config set path vendor/bundle"
    bundle "install"

    update_git "foo-bar", path: lib_path("foo-bar")
    revision2 = revision_for(lib_path("foo-bar"))

    bundle "update", all: true
    bundle :clean

    expect(out).to include("Removing foo-bar (#{revision[0..11]})")

    expect(vendored_gems("gems/myrack-1.0.0")).to exist
    expect(vendored_gems("bundler/gems/foo-bar-#{revision[0..11]}")).not_to exist
    expect(vendored_gems("bundler/gems/foo-bar-#{revision2[0..11]}")).to exist

    expect(vendored_gems("specifications/myrack-1.0.0.gemspec")).to exist

    expect(vendored_gems("bin/myrackup")).to exist
  end

  it "does not remove nested gems in a git repo" do
    build_lib "activesupport", "3.0", path: lib_path("rails/activesupport")
    build_git "rails", "3.0", path: lib_path("rails") do |s|
      s.add_dependency "activesupport", "= 3.0"
    end
    revision = revision_for(lib_path("rails"))

    gemfile <<-G
      source "https://gem.repo1"
      gem "activesupport", :git => "#{lib_path("rails")}", :ref => '#{revision}'
    G

    bundle "config set path vendor/bundle"
    bundle "install"
    bundle :clean
    expect(out).to include("")

    expect(vendored_gems("bundler/gems/rails-#{revision[0..11]}")).to exist
  end

  it "does not remove git sources that are in without groups" do
    build_git "foo", path: lib_path("foo")
    git_path = lib_path("foo")
    revision = revision_for(git_path)

    gemfile <<-G
      source "https://gem.repo1"

      gem "myrack", "1.0.0"
      group :test do
        git "#{git_path}", :ref => "#{revision}" do
          gem "foo"
        end
      end
    G
    bundle "config set path vendor/bundle"
    bundle "config set without test"
    bundle "install"

    bundle :clean

    expect(out).to include("")
    expect(vendored_gems("bundler/gems/foo-#{revision[0..11]}")).to exist
    digest = Digest(:SHA1).hexdigest(git_path.to_s)
    expect(vendored_gems("cache/bundler/git/foo-#{digest}")).to_not exist
  end

  it "does not blow up when using without groups" do
    gemfile <<-G
      source "https://gem.repo1"

      gem "myrack"

      group :development do
        gem "foo"
      end
    G

    bundle "config set path vendor/bundle"
    bundle "config set without development"
    bundle "install"

    bundle :clean
  end

  it "displays an error when used without --path" do
    bundle "config set path.system true"
    install_gemfile <<-G
      source "https://gem.repo1"

      gem "myrack", "1.0.0"
    G

    bundle :clean, raise_on_error: false

    expect(exitstatus).to eq(15)
    expect(err).to include("--force")
  end

  # handling bundle clean upgrade path from the pre's
  it "removes .gem/.gemspec file even if there's no corresponding gem dir" do
    gemfile <<-G
      source "https://gem.repo1"

      gem "thin"
      gem "foo"
    G

    bundle "config set path vendor/bundle"
    bundle "install"

    gemfile <<-G
      source "https://gem.repo1"

      gem "foo"
    G
    bundle "install"

    FileUtils.rm(vendored_gems("bin/myrackup"))
    FileUtils.rm_r(vendored_gems("gems/thin-1.0"))
    FileUtils.rm_r(vendored_gems("gems/myrack-1.0.0"))

    bundle :clean

    should_not_have_gems "thin-1.0", "myrack-1.0"
    should_have_gems "foo-1.0"

    expect(vendored_gems("bin/myrackup")).not_to exist
  end

  it "does not call clean automatically when using system gems" do
    bundle "config set path.system true"

    install_gemfile <<-G
      source "https://gem.repo1"

      gem "thin"
      gem "myrack"
    G

    install_gemfile <<-G
      source "https://gem.repo1"

      gem "myrack"
    G

    gem_command :list
    expect(out).to include("myrack (1.0.0)").and include("thin (1.0)")
  end

  it "--clean should override the bundle setting on install" do
    gemfile <<-G
      source "https://gem.repo1"

      gem "thin"
      gem "myrack"
    G
    bundle "config set path vendor/bundle"
    bundle "config set clean false"
    bundle "install --clean true"

    gemfile <<-G
      source "https://gem.repo1"

      gem "myrack"
    G
    bundle "install"

    should_have_gems "myrack-1.0.0"
    should_not_have_gems "thin-1.0"
  end

  it "--clean should override the bundle setting on update" do
    build_repo2

    gemfile <<-G
      source "https://gem.repo2"

      gem "foo"
    G
    bundle "config set path vendor/bundle"
    bundle "config set clean false"
    bundle "install --clean true"

    update_repo2 do
      build_gem "foo", "1.0.1"
    end

    bundle "update", all: true

    should_have_gems "foo-1.0.1"
    should_not_have_gems "foo-1.0"
  end

  it "automatically cleans when path has not been set", bundler: "4" do
    build_repo2

    install_gemfile <<-G
      source "https://gem.repo2"

      gem "foo"
    G

    update_repo2 do
      build_gem "foo", "1.0.1"
    end

    bundle "update", all: true

    files = Pathname.glob(bundled_app(".bundle", Bundler.ruby_scope, "*", "*"))
    files.map! {|f| f.to_s.sub(bundled_app(".bundle", Bundler.ruby_scope).to_s, "") }
    expect(files.sort).to eq %w[
      /cache/foo-1.0.1.gem
      /gems/foo-1.0.1
      /specifications/foo-1.0.1.gemspec
    ]
  end

  it "does not clean automatically on --path" do
    gemfile <<-G
      source "https://gem.repo1"

      gem "thin"
      gem "myrack"
    G
    bundle "config set path vendor/bundle"
    bundle "install"

    gemfile <<-G
      source "https://gem.repo1"

      gem "myrack"
    G
    bundle "install"

    should_have_gems "myrack-1.0.0", "thin-1.0"
  end

  it "does not clean on bundle update with --path" do
    build_repo2

    gemfile <<-G
      source "https://gem.repo2"

      gem "foo"
    G
    bundle "config set path vendor/bundle"
    bundle "install"

    update_repo2 do
      build_gem "foo", "1.0.1"
    end

    bundle :update, all: true
    should_have_gems "foo-1.0", "foo-1.0.1"
  end

  it "does not clean on bundle update when using --system" do
    bundle "config set path.system true"

    build_repo2

    gemfile <<-G
      source "https://gem.repo2"

      gem "foo"
    G
    bundle "install"

    update_repo2 do
      build_gem "foo", "1.0.1"
    end
    bundle :update, all: true

    gem_command :list
    expect(out).to include("foo (1.0.1, 1.0)")
  end

  it "cleans system gems when --force is used" do
    bundle "config set path.system true"

    gemfile <<-G
      source "https://gem.repo1"

      gem "foo"
      gem "myrack"
    G
    bundle :install

    gemfile <<-G
      source "https://gem.repo1"

      gem "myrack"
    G
    bundle :install
    bundle "clean --force"

    expect(out).to include("Removing foo (1.0)")
    gem_command :list
    expect(out).not_to include("foo (1.0)")
    expect(out).to include("myrack (1.0.0)")
  end

  describe "when missing permissions", :permissions do
    before { ENV["BUNDLE_PATH__SYSTEM"] = "true" }
    let(:system_cache_path) { system_gem_path("cache") }
    after do
      FileUtils.chmod(0o755, system_cache_path)
    end
    it "returns a helpful error message" do
      gemfile <<-G
        source "https://gem.repo1"

        gem "foo"
        gem "myrack"
      G
      bundle :install

      gemfile <<-G
        source "https://gem.repo1"

        gem "myrack"
      G
      bundle :install

      FileUtils.chmod(0o500, system_cache_path)

      bundle :clean, force: true, raise_on_error: false

      expect(err).to include(system_gem_path.to_s)
      expect(err).to include("grant write permissions")

      gem_command :list
      expect(out).to include("foo (1.0)")
      expect(out).to include("myrack (1.0.0)")
    end
  end

  it "cleans git gems with a 7 length git revision" do
    build_git "foo"
    revision = revision_for(lib_path("foo-1.0"))

    gemfile <<-G
      source "https://gem.repo1"

      gem "foo", :git => "#{lib_path("foo-1.0")}"
    G

    bundle "config set path vendor/bundle"
    bundle "install"

    # mimic 7 length git revisions in Gemfile.lock
    gemfile_lock = File.read(bundled_app_lock).split("\n")
    gemfile_lock.each_with_index do |line, index|
      gemfile_lock[index] = line[0..(11 + 7)] if line.include?("  revision:")
    end
    lockfile(bundled_app_lock, gemfile_lock.join("\n"))

    bundle "config set path vendor/bundle"
    bundle "install"

    bundle :clean

    expect(out).not_to include("Removing foo (1.0 #{revision[0..6]})")

    expect(vendored_gems("bundler/gems/foo-1.0-#{revision[0..6]}")).to exist
  end

  it "when using --force on system gems, it doesn't remove binaries" do
    bundle "config set path.system true"

    build_repo2 do
      build_gem "bindir" do |s|
        s.bindir = "exe"
        s.executables = "foo"
      end
    end

    gemfile <<-G
      source "https://gem.repo2"

      gem "bindir"
    G
    bundle :install

    bundle "clean --force"

    sys_exec "foo"

    expect(out).to eq("1.0")
  end

  it "when using --force, it doesn't remove default gem binaries", :realworld do
    default_irb_version = ruby "gem 'irb', '< 999999'; require 'irb'; puts IRB::VERSION", raise_on_error: false
    skip "irb isn't a default gem" if default_irb_version.empty?

    # simulate executable for default gem
    build_gem "irb", default_irb_version, to_system: true, default: true do |s|
      s.executables = "irb"
    end

    realworld_system_gems "tsort --version 0.1.0", "pathname --version 0.1.0", "set --version 1.0.1"

    install_gemfile <<-G
      source "https://gem.repo2"
    G

    bundle "clean --force", env: { "BUNDLER_GEM_DEFAULT_DIR" => system_gem_path.to_s }

    expect(out).not_to include("Removing irb")
  end

  it "doesn't blow up on path gems without a .gemspec" do
    relative_path = "vendor/private_gems/bar-1.0"
    absolute_path = bundled_app(relative_path)
    FileUtils.mkdir_p("#{absolute_path}/lib/bar")
    File.open("#{absolute_path}/lib/bar/bar.rb", "wb") do |file|
      file.puts "module Bar; end"
    end

    gemfile <<-G
      source "https://gem.repo1"

      gem "foo"
      gem "bar", "1.0", :path => "#{relative_path}"
    G

    bundle "config set path vendor/bundle"
    bundle "install"
    bundle :clean
  end

  it "doesn't remove gems in dry-run mode with path set" do
    gemfile <<-G
      source "https://gem.repo1"

      gem "thin"
      gem "foo"
    G

    bundle "config set path vendor/bundle"
    bundle "config set clean false"
    bundle "install"

    gemfile <<-G
      source "https://gem.repo1"

      gem "thin"
    G

    bundle :install

    bundle "clean --dry-run"

    expect(out).not_to include("Removing foo (1.0)")
    expect(out).to include("Would have removed foo (1.0)")

    should_have_gems "thin-1.0", "myrack-1.0.0", "foo-1.0"

    expect(vendored_gems("bin/myrackup")).to exist
  end

  it "doesn't remove gems in dry-run mode with no path set" do
    gemfile <<-G
      source "https://gem.repo1"

      gem "thin"
      gem "foo"
    G

    bundle "config set path vendor/bundle"
    bundle "config set clean false"
    bundle "install"

    gemfile <<-G
      source "https://gem.repo1"

      gem "thin"
    G

    bundle :install

    bundle "clean --dry-run"

    expect(out).not_to include("Removing foo (1.0)")
    expect(out).to include("Would have removed foo (1.0)")

    should_have_gems "thin-1.0", "myrack-1.0.0", "foo-1.0"

    expect(vendored_gems("bin/myrackup")).to exist
  end

  it "doesn't store dry run as a config setting" do
    gemfile <<-G
      source "https://gem.repo1"

      gem "thin"
      gem "foo"
    G

    bundle "config set path vendor/bundle"
    bundle "config set clean false"
    bundle "install"
    bundle "config set dry_run false"

    gemfile <<-G
      source "https://gem.repo1"

      gem "thin"
    G

    bundle :install

    bundle "clean"

    expect(out).to include("Removing foo (1.0)")
    expect(out).not_to include("Would have removed foo (1.0)")

    should_have_gems "thin-1.0", "myrack-1.0.0"
    should_not_have_gems "foo-1.0"

    expect(vendored_gems("bin/myrackup")).to exist
  end

  it "performs an automatic bundle install" do
    gemfile <<-G
      source "https://gem.repo1"

      gem "thin"
      gem "foo"
    G

    bundle "config set path vendor/bundle"
    bundle "config set clean false"
    bundle "install"

    gemfile <<-G
      source "https://gem.repo1"

      gem "thin"
      gem "weakling"
    G

    bundle "config set auto_install 1"
    bundle :clean
    expect(out).to include("Installing weakling 0.0.3")
    should_have_gems "thin-1.0", "myrack-1.0.0", "weakling-0.0.3"
    should_not_have_gems "foo-1.0"
  end

  it "doesn't remove extensions artifacts from bundled git gems after clean" do
    build_git "very_simple_git_binary", &:add_c_extension

    revision = revision_for(lib_path("very_simple_git_binary-1.0"))

    gemfile <<-G
      source "https://gem.repo1"

      gem "very_simple_git_binary", :git => "#{lib_path("very_simple_git_binary-1.0")}", :ref => "#{revision}"
    G

    bundle "config set path vendor/bundle"
    bundle "install"
    expect(vendored_gems("bundler/gems/extensions")).to exist
    expect(vendored_gems("bundler/gems/very_simple_git_binary-1.0-#{revision[0..11]}")).to exist

    bundle :clean
    expect(out).to be_empty

    expect(vendored_gems("bundler/gems/extensions")).to exist
    expect(vendored_gems("bundler/gems/very_simple_git_binary-1.0-#{revision[0..11]}")).to exist
  end

  it "removes extension directories" do
    gemfile <<-G
      source "https://gem.repo1"

      gem "thin"
      gem "very_simple_binary"
      gem "simple_binary"
    G

    bundle "config set path vendor/bundle"
    bundle "install"

    very_simple_binary_extensions_dir =
      Pathname.glob("#{vendored_gems}/extensions/*/*/very_simple_binary-1.0").first

    simple_binary_extensions_dir =
      Pathname.glob("#{vendored_gems}/extensions/*/*/simple_binary-1.0").first

    expect(very_simple_binary_extensions_dir).to exist
    expect(simple_binary_extensions_dir).to exist

    gemfile <<-G
      source "https://gem.repo1"

      gem "thin"
      gem "simple_binary"
    G

    bundle "install"
    bundle :clean
    expect(out).to eq("Removing very_simple_binary (1.0)")

    expect(very_simple_binary_extensions_dir).not_to exist
    expect(simple_binary_extensions_dir).to exist
  end

  it "removes git extension directories" do
    build_git "very_simple_git_binary", &:add_c_extension

    revision = revision_for(lib_path("very_simple_git_binary-1.0"))
    short_revision = revision[0..11]

    gemfile <<-G
      source "https://gem.repo1"

      gem "thin"
      gem "very_simple_git_binary", :git => "#{lib_path("very_simple_git_binary-1.0")}", :ref => "#{revision}"
    G

    bundle "config set path vendor/bundle"
    bundle "install"

    very_simple_binary_extensions_dir =
      Pathname.glob("#{vendored_gems}/bundler/gems/extensions/*/*/very_simple_git_binary-1.0-#{short_revision}").first

    expect(very_simple_binary_extensions_dir).to exist

    gemfile <<-G
      source "https://gem.repo1"
      gem "very_simple_git_binary", :git => "#{lib_path("very_simple_git_binary-1.0")}", :ref => "#{revision}"
    G

    bundle "install"
    bundle :clean
    expect(out).to include("Removing thin (1.0)")
    expect(very_simple_binary_extensions_dir).to exist

    gemfile <<-G
      source "https://gem.repo1"
    G

    bundle "install"
    bundle :clean
    expect(out).to eq("Removing very_simple_git_binary-1.0 (#{short_revision})")

    expect(very_simple_binary_extensions_dir).not_to exist
  end

  it "keeps git extension directories when excluded by group" do
    build_git "very_simple_git_binary", &:add_c_extension

    revision = revision_for(lib_path("very_simple_git_binary-1.0"))
    short_revision = revision[0..11]

    gemfile <<-G
      source "https://gem.repo1"

      group :development do
        gem "very_simple_git_binary", :git => "#{lib_path("very_simple_git_binary-1.0")}", :ref => "#{revision}"
      end
    G

    bundle :lock
    bundle "config set without development"
    bundle "config set path vendor/bundle"
    bundle "install", verbose: true
    bundle :clean

    very_simple_binary_extensions_dir =
      Pathname.glob("#{vendored_gems}/bundler/gems/extensions/*/*/very_simple_git_binary-1.0-#{short_revision}").first

    expect(very_simple_binary_extensions_dir).to be_nil
  end
end
