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
        $:.unshift("#{lib_dir}")
        require "bundler/gem_tasks"
      RAKEFILE
    end

    install_gemfile! <<-G
      source "#{file_uri_for(gem_repo1)}"

      gem "rake"
    G
  end

  it "includes the relevant tasks" do
    with_gem_path_as(Spec::Path.base_system_gems.to_s) do
      sys_exec "#{rake} -T", "RUBYOPT" => "-I#{lib_dir}"
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
    expect(exitstatus).to eq(0) if exitstatus
  end

  it "defines a working `rake install` task" do
    with_gem_path_as(Spec::Path.base_system_gems.to_s) do
      sys_exec "#{rake} install", "RUBYOPT" => "-I#{lib_dir}"
    end

    expect(err).to be_empty

    bundle! "exec rake install"

    expect(err).to be_empty
  end

  it "adds 'pkg' to rake/clean's CLOBBER" do
    with_gem_path_as(Spec::Path.base_system_gems.to_s) do
      sys_exec! %(#{rake} -e 'load "Rakefile"; puts CLOBBER.inspect')
    end
    expect(out).to eq '["pkg"]'
  end
end
