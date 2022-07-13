# frozen_string_literal: true

require "bundler/vendored_fileutils"

RSpec.describe "bundle pristine" do
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

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"
      gem "weakling"
      gem "very_simple_binary"
      gem "foo", :git => "#{lib_path("foo")}", :branch => "master"
      gem "git_with_ext", :git => "#{lib_path("git_with_ext")}"
      gem "bar", :path => "#{lib_path("bar")}"

      gemspec
    G

    allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
  end

  context "when sourced from RubyGems" do
    it "reverts using cached .gem file" do
      spec = find_spec("weakling")
      changes_txt = Pathname.new(spec.full_gem_path).join("lib/changes.txt")

      FileUtils.touch(changes_txt)
      expect(changes_txt).to be_file

      bundle "pristine"
      expect(changes_txt).to_not be_file
    end

    it "does not delete the bundler gem" do
      bundle "install"
      bundle "pristine"
      bundle "-v"

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
      spec = find_spec("foo")
      changed_file = Pathname.new(spec.full_gem_path).join("lib/foo.rb")
      diff = "#Pristine spec changes"

      File.open(changed_file, "a") {|f| f.puts diff }
      expect(File.read(changed_file)).to include(diff)

      bundle "pristine"
      expect(File.read(changed_file)).to_not include(diff)
    end

    it "removes added files" do
      spec = find_spec("foo")
      changes_txt = Pathname.new(spec.full_gem_path).join("lib/changes.txt")

      FileUtils.touch(changes_txt)
      expect(changes_txt).to be_file

      bundle "pristine"
      expect(changes_txt).not_to be_file
    end

    it "displays warning and ignores changes when a local config exists" do
      spec = find_spec("foo")
      bundle "config set local.#{spec.name} #{lib_path(spec.name)}"

      changes_txt = Pathname.new(spec.full_gem_path).join("lib/changes.txt")
      FileUtils.touch(changes_txt)
      expect(changes_txt).to be_file

      bundle "pristine"
      expect(changes_txt).to be_file
      expect(err).to include("Cannot pristine #{spec.name} (#{spec.version}#{spec.git_version}). Gem is locally overridden.")
    end
  end

  context "when sourced from gemspec" do
    it "displays warning and ignores changes when sourced from gemspec" do
      spec = find_spec("baz")
      changed_file = Pathname.new(spec.full_gem_path).join("lib/baz.rb")
      diff = "#Pristine spec changes"

      File.open(changed_file, "a") {|f| f.puts diff }
      expect(File.read(changed_file)).to include(diff)

      bundle "pristine"
      expect(File.read(changed_file)).to include(diff)
      expect(err).to include("Cannot pristine #{spec.name} (#{spec.version}#{spec.git_version}). Gem is sourced from local path.")
    end

    it "reinstall gemspec dependency" do
      spec = find_spec("baz-dev")
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
      spec = find_spec("bar")
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
      foo = find_spec("foo")
      foo_changes_txt = Pathname.new(foo.full_gem_path).join("lib/changes.txt")
      FileUtils.touch(foo_changes_txt)
      expect(foo_changes_txt).to be_file

      bar = find_spec("bar")
      bar_changes_txt = Pathname.new(bar.full_gem_path).join("lib/changes.txt")
      FileUtils.touch(bar_changes_txt)
      expect(bar_changes_txt).to be_file

      weakling = find_spec("weakling")
      weakling_changes_txt = Pathname.new(weakling.full_gem_path).join("lib/changes.txt")
      FileUtils.touch(weakling_changes_txt)
      expect(weakling_changes_txt).to be_file

      bundle "pristine foo bar weakling"

      expect(err).to include("Cannot pristine bar (1.0). Gem is sourced from local path.")
      expect(out).to include("Installing weakling 1.0")

      expect(weakling_changes_txt).not_to be_file
      expect(foo_changes_txt).not_to be_file
      expect(bar_changes_txt).to be_file
    end

    it "raises when one of them is not in the lockfile" do
      bundle "pristine abcabcabc", :raise_on_error => false
      expect(err).to include("Could not find gem 'abcabcabc'.")
    end
  end

  context "when a build config exists for one of the gems" do
    let(:very_simple_binary) { find_spec("very_simple_binary") }
    let(:c_ext_dir)          { Pathname.new(very_simple_binary.full_gem_path).join("ext") }
    let(:build_opt)          { "--with-ext-lib=#{c_ext_dir}" }
    before { bundle "config set build.very_simple_binary -- #{build_opt}" }

    # This just verifies that the generated Makefile from the c_ext gem makes
    # use of the build_args from the bundle config
    it "applies the config when installing the gem" do
      bundle "pristine"

      makefile_contents = File.read(c_ext_dir.join("Makefile").to_s)
      expect(makefile_contents).to match(/libpath =.*#{c_ext_dir}/)
      expect(makefile_contents).to match(/LIBPATH =.*-L#{c_ext_dir}/)
    end
  end

  context "when a build config exists for a git sourced gem" do
    let(:git_with_ext) { find_spec("git_with_ext") }
    let(:c_ext_dir)          { Pathname.new(git_with_ext.full_gem_path).join("ext") }
    let(:build_opt)          { "--with-ext-lib=#{c_ext_dir}" }
    before { bundle "config set build.git_with_ext -- #{build_opt}" }

    # This just verifies that the generated Makefile from the c_ext gem makes
    # use of the build_args from the bundle config
    it "applies the config when installing the gem" do
      bundle "pristine"

      makefile_contents = File.read(c_ext_dir.join("Makefile").to_s)
      expect(makefile_contents).to match(/libpath =.*#{c_ext_dir}/)
      expect(makefile_contents).to match(/LIBPATH =.*-L#{c_ext_dir}/)
    end
  end

  context "when BUNDLE_GEMFILE doesn't exist" do
    before do
      bundle "pristine", :env => { "BUNDLE_GEMFILE" => "does/not/exist" }, :raise_on_error => false
    end

    it "shows a meaningful error" do
      expect(err).to eq("#{bundled_app("does/not/exist")} not found")
    end
  end

  def find_spec(name)
    without_env_side_effects do
      Bundler.definition.specs[name].first
    end
  end
end
