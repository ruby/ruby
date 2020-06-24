# frozen_string_literal: true

RSpec.describe "require 'bundler/gem_tasks'" do
  before :each do
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
      source "#{file_uri_for(gem_repo1)}"

      gem "rake"
    G
  end

  it "includes the relevant tasks" do
    with_gem_path_as(base_system_gems.to_s) do
      sys_exec "#{rake} -T", :env => { "GEM_HOME" => system_gem_path.to_s }
    end

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
    with_gem_path_as(base_system_gems.to_s) do
      sys_exec "#{rake} install", :env => { "GEM_HOME" => system_gem_path.to_s }
    end

    expect(err).to be_empty

    bundle "exec rake install"

    expect(err).to be_empty
  end

  context "rake build when path has spaces", :ruby_repo do
    before do
      spaced_bundled_app = tmp.join("bundled app")
      FileUtils.cp_r bundled_app, spaced_bundled_app
      bundle "exec rake build", :dir => spaced_bundled_app
    end

    it "still runs successfully" do
      expect(err).to be_empty
    end
  end

  context "bundle path configured locally" do
    before do
      bundle "config set path vendor/bundle"
    end

    it "works", :ruby_repo do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        gem "rake"
      G

      bundle "exec rake -T"

      expect(err).to be_empty
    end
  end

  it "adds 'pkg' to rake/clean's CLOBBER" do
    with_gem_path_as(base_system_gems.to_s) do
      sys_exec %(#{rake} -e 'load "Rakefile"; puts CLOBBER.inspect'), :env => { "GEM_HOME" => system_gem_path.to_s }
    end
    expect(out).to eq '["pkg"]'
  end
end
