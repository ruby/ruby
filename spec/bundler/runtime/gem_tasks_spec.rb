# frozen_string_literal: true

RSpec.describe "require 'bundler/gem_tasks'" do
  let(:define_local_gem_using_gem_tasks) do
    bundled_app("foo.gemspec").open("w") do |f|
      f.write <<-GEMSPEC
        Gem::Specification.new do |s|
          s.name = "foo"
          s.version = "1.0"
          s.summary = "dummy"
          s.author = "Perry Mason"
        end
      GEMSPEC
    end

    bundled_app("Rakefile").open("w") do |f|
      f.write <<-RAKEFILE
        require "bundler/gem_tasks"
      RAKEFILE
    end

    install_gemfile <<-G
      source "https://gem.repo1"

      gem "rake"
    G
  end

  let(:define_local_gem_with_extensions_using_gem_tasks_and_gemspec_dsl) do
    bundled_app("foo.gemspec").open("w") do |f|
      f.write <<-GEMSPEC
        Gem::Specification.new do |s|
          s.name = "foo"
          s.version = "1.0"
          s.summary = "dummy"
          s.author = "Perry Mason"
          s.extensions = "ext/extconf.rb"
        end
      GEMSPEC
    end

    bundled_app("Rakefile").open("w") do |f|
      f.write <<-RAKEFILE
        require "bundler/gem_tasks"
      RAKEFILE
    end

    Dir.mkdir bundled_app("ext")

    bundled_app("ext/extconf.rb").open("w") do |f|
      f.write <<-EXTCONF
        require "mkmf"
        File.write("Makefile", dummy_makefile($srcdir).join)
      EXTCONF
    end

    install_gemfile <<-G
      source "https://gem.repo1"

      gemspec

      gem "rake"
    G
  end

  it "includes the relevant tasks" do
    define_local_gem_using_gem_tasks

    in_bundled_app "rake -T"

    expect(err).to be_empty
    expected_tasks = [
      "rake build",
      "rake clean",
      "rake clobber",
      "rake install",
      "rake release[remote]",
    ]
    tasks = out.lines.to_a.map {|s| s.split("#").first.strip }
    expect(tasks & expected_tasks).to eq(expected_tasks)
  end

  it "defines a working `rake install` task", :ruby_repo do
    define_local_gem_using_gem_tasks

    in_bundled_app "rake install"

    expect(err).to be_empty

    bundle "exec rake install"

    expect(err).to be_empty
  end

  it "defines a working `rake install` task for local gems with extensions", :ruby_repo do
    define_local_gem_with_extensions_using_gem_tasks_and_gemspec_dsl

    bundle "exec rake install"

    expect(err).to be_empty
  end

  context "rake build when path has spaces", :ruby_repo do
    before do
      define_local_gem_using_gem_tasks

      spaced_bundled_app = tmp("bundled app")
      FileUtils.cp_r bundled_app, spaced_bundled_app
      bundle "exec rake build", dir: spaced_bundled_app
    end

    it "still runs successfully" do
      expect(err).to be_empty
    end
  end

  context "rake build when path has brackets", :ruby_repo do
    before do
      define_local_gem_using_gem_tasks

      bracketed_bundled_app = tmp("bundled[app")
      FileUtils.cp_r bundled_app, bracketed_bundled_app
      bundle "exec rake build", dir: bracketed_bundled_app
    end

    it "still runs successfully" do
      expect(err).to be_empty
    end
  end

  context "bundle path configured locally" do
    before do
      define_local_gem_using_gem_tasks

      bundle "config set path vendor/bundle"
    end

    it "works", :ruby_repo do
      install_gemfile <<-G
        source "https://gem.repo1"

        gem "rake"
      G

      bundle "exec rake -T"

      expect(err).to be_empty
    end
  end

  it "adds 'pkg' to rake/clean's CLOBBER" do
    define_local_gem_using_gem_tasks

    in_bundled_app %(rake -e 'load "Rakefile"; puts CLOBBER.inspect')

    expect(out).to eq '["pkg"]'
  end
end
