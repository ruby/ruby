# frozen_string_literal: true

require "bundler/vendored_fileutils"

RSpec.describe "bundle pristine", :ruby_repo do
  before :each do
    build_lib "baz", :path => bundled_app do |s|
      s.version = "1.0.0"
      s.add_development_dependency "baz-dev", "=1.0.0"
    end

    build_repo2 do
      build_gem "weakling"
      build_gem "baz-dev", "1.0.0"
      build_gem "very_simple_binary", &:add_c_extension
      build_git "foo", :path => lib_path("foo")
      build_git "git_with_ext", :path => lib_path("git_with_ext"), &:add_c_extension
      build_lib "bar", :path => lib_path("bar")
    end

    install_gemfile! <<-G
      source "#{file_uri_for(gem_repo2)}"
      gem "weakling"
      gem "very_simple_binary"
      gem "foo", :git => "#{lib_path("foo")}"
      gem "git_with_ext", :git => "#{lib_path("git_with_ext")}"
      gem "bar", :path => "#{lib_path("bar")}"

      gemspec
    G
  end

  context "when sourced from RubyGems" do
    it "reverts using cached .gem file" do
      spec = Bundler.definition.specs["weakling"].first
      changes_txt = Pathname.new(spec.full_gem_path).join("lib/changes.txt")

      FileUtils.touch(changes_txt)
      expect(changes_txt).to be_file

      bundle "pristine"
      expect(changes_txt).to_not be_file
    end

    it "does not delete the bundler gem" do
      system_gems :bundler
      bundle! "install"
      bundle! "pristine", :system_bundler => true
      bundle! "-v", :system_bundler => true

      expected = if Bundler::VERSION < "3.0"
        "Bundler version"
      else
        Bundler::VERSION
      end

      expect(out).to start_with(expected)
    end
  end

  context "when sourced from git repo" do
    it "reverts by resetting to current revision`" do
      spec = Bundler.definition.specs["foo"].first
      changed_file = Pathname.new(spec.full_gem_path).join("lib/foo.rb")
      diff = "#Pristine spec changes"

      File.open(changed_file, "a") {|f| f.puts diff }
      expect(File.read(changed_file)).to include(diff)

      bundle! "pristine"
      expect(File.read(changed_file)).to_not include(diff)
    end

    it "removes added files" do
      spec = Bundler.definition.specs["foo"].first
      changes_txt = Pathname.new(spec.full_gem_path).join("lib/changes.txt")

      FileUtils.touch(changes_txt)
      expect(changes_txt).to be_file

      bundle! "pristine"
      expect(changes_txt).not_to be_file
    end
  end

  context "when sourced from gemspec" do
    it "displays warning and ignores changes when sourced from gemspec" do
      spec = Bundler.definition.specs["baz"].first
      changed_file = Pathname.new(spec.full_gem_path).join("lib/baz.rb")
      diff = "#Pristine spec changes"

      File.open(changed_file, "a") {|f| f.puts diff }
      expect(File.read(changed_file)).to include(diff)

      bundle "pristine"
      expect(File.read(changed_file)).to include(diff)
      expect(err).to include("Cannot pristine #{spec.name} (#{spec.version}#{spec.git_version}). Gem is sourced from local path.")
    end

    it "reinstall gemspec dependency" do
      spec = Bundler.definition.specs["baz-dev"].first
      changed_file = Pathname.new(spec.full_gem_path).join("lib/baz/dev.rb")
      diff = "#Pristine spec changes"

      File.open(changed_file, "a") {|f| f.puts "#Pristine spec changes" }
      expect(File.read(changed_file)).to include(diff)

      bundle "pristine"
      expect(File.read(changed_file)).to_not include(diff)
    end
  end

  context "when sourced from path" do
    it "displays warning and ignores changes when sourced from local path" do
      spec = Bundler.definition.specs["bar"].first
      changes_txt = Pathname.new(spec.full_gem_path).join("lib/changes.txt")
      FileUtils.touch(changes_txt)
      expect(changes_txt).to be_file
      bundle "pristine"
      expect(err).to include("Cannot pristine #{spec.name} (#{spec.version}#{spec.git_version}). Gem is sourced from local path.")
      expect(changes_txt).to be_file
    end
  end

  context "when passing a list of gems to pristine" do
    it "resets them" do
      foo = Bundler.definition.specs["foo"].first
      foo_changes_txt = Pathname.new(foo.full_gem_path).join("lib/changes.txt")
      FileUtils.touch(foo_changes_txt)
      expect(foo_changes_txt).to be_file

      bar = Bundler.definition.specs["bar"].first
      bar_changes_txt = Pathname.new(bar.full_gem_path).join("lib/changes.txt")
      FileUtils.touch(bar_changes_txt)
      expect(bar_changes_txt).to be_file

      weakling = Bundler.definition.specs["weakling"].first
      weakling_changes_txt = Pathname.new(weakling.full_gem_path).join("lib/changes.txt")
      FileUtils.touch(weakling_changes_txt)
      expect(weakling_changes_txt).to be_file

      bundle! "pristine foo bar weakling"

      expect(err).to include("Cannot pristine bar (1.0). Gem is sourced from local path.")
      expect(out).to include("Installing weakling 1.0")

      expect(weakling_changes_txt).not_to be_file
      expect(foo_changes_txt).not_to be_file
      expect(bar_changes_txt).to be_file
    end

    it "raises when one of them is not in the lockfile" do
      bundle "pristine abcabcabc"
      expect(err).to include("Could not find gem 'abcabcabc'.")
    end
  end

  context "when a build config exists for one of the gems" do
    let(:very_simple_binary) { Bundler.definition.specs["very_simple_binary"].first }
    let(:c_ext_dir)          { Pathname.new(very_simple_binary.full_gem_path).join("ext") }
    let(:build_opt)          { "--with-ext-lib=#{c_ext_dir}" }
    before { bundle "config set build.very_simple_binary -- #{build_opt}" }

    # This just verifies that the generated Makefile from the c_ext gem makes
    # use of the build_args from the bundle config
    it "applies the config when installing the gem" do
      bundle! "pristine"

      makefile_contents = File.read(c_ext_dir.join("Makefile").to_s)
      expect(makefile_contents).to match(/libpath =.*#{c_ext_dir}/)
      expect(makefile_contents).to match(/LIBPATH =.*-L#{c_ext_dir}/)
    end
  end

  context "when a build config exists for a git sourced gem" do
    let(:git_with_ext) { Bundler.definition.specs["git_with_ext"].first }
    let(:c_ext_dir)          { Pathname.new(git_with_ext.full_gem_path).join("ext") }
    let(:build_opt)          { "--with-ext-lib=#{c_ext_dir}" }
    before { bundle "config set build.git_with_ext -- #{build_opt}" }

    # This just verifies that the generated Makefile from the c_ext gem makes
    # use of the build_args from the bundle config
    it "applies the config when installing the gem" do
      bundle! "pristine"

      makefile_contents = File.read(c_ext_dir.join("Makefile").to_s)
      expect(makefile_contents).to match(/libpath =.*#{c_ext_dir}/)
      expect(makefile_contents).to match(/LIBPATH =.*-L#{c_ext_dir}/)
    end
  end
end
