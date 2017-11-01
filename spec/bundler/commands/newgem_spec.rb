# frozen_string_literal: true

RSpec.describe "bundle gem" do
  def reset!
    super
    global_config "BUNDLE_GEM__MIT" => "false", "BUNDLE_GEM__TEST" => "false", "BUNDLE_GEM__COC" => "false"
  end

  def remove_push_guard(gem_name)
    # Remove exception that prevents public pushes on older RubyGems versions
    if Gem::Version.new(Gem::VERSION) < Gem::Version.new("2.0")
      path = "#{gem_name}/#{gem_name}.gemspec"
      content = File.read(path).sub(/raise "RubyGems 2\.0 or newer.*/, "")
      File.open(path, "w") {|f| f.write(content) }
    end
  end

  def execute_bundle_gem(gem_name, flag = "", to_remove_push_guard = true)
    bundle! "gem #{gem_name} #{flag}"
    remove_push_guard(gem_name) if to_remove_push_guard
    # reset gemspec cache for each test because of commit 3d4163a
    Bundler.clear_gemspec_cache
  end

  def gem_skeleton_assertions(gem_name)
    expect(bundled_app("#{gem_name}/#{gem_name}.gemspec")).to exist
    expect(bundled_app("#{gem_name}/README.md")).to exist
    expect(bundled_app("#{gem_name}/Gemfile")).to exist
    expect(bundled_app("#{gem_name}/Rakefile")).to exist
    expect(bundled_app("#{gem_name}/lib/test/gem.rb")).to exist
    expect(bundled_app("#{gem_name}/lib/test/gem/version.rb")).to exist
  end

  before do
    git_config_content = <<-EOF
    [user]
      name = "Bundler User"
      email = user@example.com
    [github]
      user = bundleuser
    EOF
    @git_config_location = ENV["GIT_CONFIG"]
    path = "#{File.expand_path(tmp, File.dirname(__FILE__))}/test_git_config.txt"
    File.open(path, "w") {|f| f.write(git_config_content) }
    ENV["GIT_CONFIG"] = path
  end

  after do
    FileUtils.rm(ENV["GIT_CONFIG"]) if File.exist?(ENV["GIT_CONFIG"])
    ENV["GIT_CONFIG"] = @git_config_location
  end

  shared_examples_for "git config is present" do
    context "git config user.{name,email} present" do
      it "sets gemspec author to git user.name if available" do
        expect(generated_gem.gemspec.authors.first).to eq("Bundler User")
      end

      it "sets gemspec email to git user.email if available" do
        expect(generated_gem.gemspec.email.first).to eq("user@example.com")
      end
    end
  end

  shared_examples_for "git config is absent" do
    it "sets gemspec author to default message if git user.name is not set or empty" do
      expect(generated_gem.gemspec.authors.first).to eq("TODO: Write your name")
    end

    it "sets gemspec email to default message if git user.email is not set or empty" do
      expect(generated_gem.gemspec.email.first).to eq("TODO: Write your email address")
    end
  end

  shared_examples_for "--mit flag" do
    before do
      execute_bundle_gem(gem_name, "--mit")
    end
    it "generates a gem skeleton with MIT license" do
      gem_skeleton_assertions(gem_name)
      expect(bundled_app("test-gem/LICENSE.txt")).to exist
      skel = Bundler::GemHelper.new(bundled_app(gem_name).to_s)
      expect(skel.gemspec.license).to eq("MIT")
    end
  end

  shared_examples_for "--no-mit flag" do
    before do
      execute_bundle_gem(gem_name, "--no-mit")
    end
    it "generates a gem skeleton without MIT license" do
      gem_skeleton_assertions(gem_name)
      expect(bundled_app("test-gem/LICENSE.txt")).to_not exist
    end
  end

  shared_examples_for "--coc flag" do
    before do
      execute_bundle_gem(gem_name, "--coc", false)
    end
    it "generates a gem skeleton with MIT license" do
      gem_skeleton_assertions(gem_name)
      expect(bundled_app("test-gem/CODE_OF_CONDUCT.md")).to exist
    end

    describe "README additions" do
      it "generates the README with a section for the Code of Conduct" do
        expect(bundled_app("test-gem/README.md").read).to include("## Code of Conduct")
        expect(bundled_app("test-gem/README.md").read).to include("https://github.com/bundleuser/#{gem_name}/blob/master/CODE_OF_CONDUCT.md")
      end
    end
  end

  shared_examples_for "--no-coc flag" do
    before do
      execute_bundle_gem(gem_name, "--no-coc", false)
    end
    it "generates a gem skeleton without Code of Conduct" do
      gem_skeleton_assertions(gem_name)
      expect(bundled_app("test-gem/CODE_OF_CONDUCT.md")).to_not exist
    end

    describe "README additions" do
      it "generates the README without a section for the Code of Conduct" do
        expect(bundled_app("test-gem/README.md").read).not_to include("## Code of Conduct")
        expect(bundled_app("test-gem/README.md").read).not_to include("https://github.com/bundleuser/#{gem_name}/blob/master/CODE_OF_CONDUCT.md")
      end
    end
  end

  context "README.md" do
    let(:gem_name) { "test_gem" }
    let(:generated_gem) { Bundler::GemHelper.new(bundled_app(gem_name).to_s) }

    context "git config github.user present" do
      before do
        execute_bundle_gem(gem_name)
      end

      it "contribute URL set to git username" do
        expect(bundled_app("test_gem/README.md").read).not_to include("[USERNAME]")
        expect(bundled_app("test_gem/README.md").read).to include("github.com/bundleuser")
      end
    end

    context "git config github.user is absent" do
      before do
        sys_exec("git config --unset github.user")
        reset!
        in_app_root
        bundle "gem #{gem_name}"
        remove_push_guard(gem_name)
      end

      it "contribute URL set to [USERNAME]" do
        expect(bundled_app("test_gem/README.md").read).to include("[USERNAME]")
        expect(bundled_app("test_gem/README.md").read).not_to include("github.com/bundleuser")
      end
    end
  end

  it "creates a new git repository" do
    in_app_root
    bundle "gem test_gem"
    expect(bundled_app("test_gem/.git")).to exist
  end

  context "when git is not available" do
    let(:gem_name) { "test_gem" }

    # This spec cannot have `git` available in the test env
    before do
      load_paths = [lib, spec]
      load_path_str = "-I#{load_paths.join(File::PATH_SEPARATOR)}"

      sys_exec "PATH=\"\" #{Gem.ruby} #{load_path_str} #{bindir.join("bundle")} gem #{gem_name}"
    end

    it "creates the gem without the need for git" do
      expect(bundled_app("#{gem_name}/README.md")).to exist
    end

    it "doesn't create a git repo" do
      expect(bundled_app("#{gem_name}/.git")).to_not exist
    end

    it "doesn't create a .gitignore file" do
      expect(bundled_app("#{gem_name}/.gitignore")).to_not exist
    end
  end

  it "generates a valid gemspec" do
    in_app_root
    bundle "gem newgem --bin"

    process_file(bundled_app("newgem", "newgem.gemspec")) do |line|
      # Simulate replacing TODOs with real values
      case line
      when /spec\.metadata\['allowed_push_host'\]/, /spec\.homepage/
        line.gsub(/\=.*$/, "= 'http://example.org'")
      when /spec\.summary/
        line.gsub(/\=.*$/, "= %q{A short summary of my new gem.}")
      when /spec\.description/
        line.gsub(/\=.*$/, "= %q{A longer description of my new gem.}")
      # Remove exception that prevents public pushes on older RubyGems versions
      when /raise "RubyGems 2.0 or newer/
        line.gsub(/.*/, "") if Gem::Version.new(Gem::VERSION) < Gem::Version.new("2.0")
      else
        line
      end
    end

    Dir.chdir(bundled_app("newgem")) do
      system_gems ["rake-10.0.2"], :path => :bundle_path
      bundle! "exec rake build"
    end

    expect(last_command.stdboth).not_to include("ERROR")
  end

  context "gem naming with relative paths" do
    before do
      reset!
      in_app_root
    end

    it "resolves ." do
      create_temporary_dir("tmp")

      bundle "gem ."

      expect(bundled_app("tmp/lib/tmp.rb")).to exist
    end

    it "resolves .." do
      create_temporary_dir("temp/empty_dir")

      bundle "gem .."

      expect(bundled_app("temp/lib/temp.rb")).to exist
    end

    it "resolves relative directory" do
      create_temporary_dir("tmp/empty/tmp")

      bundle "gem ../../empty"

      expect(bundled_app("tmp/empty/lib/empty.rb")).to exist
    end

    def create_temporary_dir(dir)
      FileUtils.mkdir_p(dir)
      Dir.chdir(dir)
    end
  end

  context "gem naming with underscore" do
    let(:gem_name) { "test_gem" }

    before do
      execute_bundle_gem(gem_name)
    end

    let(:generated_gem) { Bundler::GemHelper.new(bundled_app(gem_name).to_s) }

    it "generates a gem skeleton" do
      expect(bundled_app("test_gem/test_gem.gemspec")).to exist
      expect(bundled_app("test_gem/Gemfile")).to exist
      expect(bundled_app("test_gem/Rakefile")).to exist
      expect(bundled_app("test_gem/lib/test_gem.rb")).to exist
      expect(bundled_app("test_gem/lib/test_gem/version.rb")).to exist
      expect(bundled_app("test_gem/.gitignore")).to exist

      expect(bundled_app("test_gem/bin/setup")).to exist
      expect(bundled_app("test_gem/bin/console")).to exist
      expect(bundled_app("test_gem/bin/setup")).to be_executable
      expect(bundled_app("test_gem/bin/console")).to be_executable
    end

    it "starts with version 0.1.0" do
      expect(bundled_app("test_gem/lib/test_gem/version.rb").read).to match(/VERSION = "0.1.0"/)
    end

    it "does not nest constants" do
      expect(bundled_app("test_gem/lib/test_gem/version.rb").read).to match(/module TestGem/)
      expect(bundled_app("test_gem/lib/test_gem.rb").read).to match(/module TestGem/)
    end

    it_should_behave_like "git config is present"

    context "git config user.{name,email} is not set" do
      before do
        `git config --unset user.name`
        `git config --unset user.email`
        reset!
        in_app_root
        bundle "gem #{gem_name}"
        remove_push_guard(gem_name)
      end

      it_should_behave_like "git config is absent"
    end

    it "sets gemspec metadata['allowed_push_host']", :rubygems => "2.0" do
      expect(generated_gem.gemspec.metadata["allowed_push_host"]).
        to match(/mygemserver\.com/)
    end

    it "requires the version file" do
      expect(bundled_app("test_gem/lib/test_gem.rb").read).to match(%r{require "test_gem/version"})
    end

    it "runs rake without problems" do
      system_gems ["rake-10.0.2"]

      rakefile = strip_whitespace <<-RAKEFILE
        task :default do
          puts 'SUCCESS'
        end
      RAKEFILE
      File.open(bundled_app("test_gem/Rakefile"), "w") do |file|
        file.puts rakefile
      end

      Dir.chdir(bundled_app(gem_name)) do
        sys_exec(rake)
        expect(out).to include("SUCCESS")
      end
    end

    context "--exe parameter set" do
      before do
        reset!
        in_app_root
        bundle "gem #{gem_name} --exe"
      end

      it "builds exe skeleton" do
        expect(bundled_app("test_gem/exe/test_gem")).to exist
      end

      it "requires 'test-gem'" do
        expect(bundled_app("test_gem/exe/test_gem").read).to match(/require "test_gem"/)
      end
    end

    context "--bin parameter set" do
      before do
        reset!
        in_app_root
        bundle "gem #{gem_name} --bin"
      end

      it "builds exe skeleton" do
        expect(bundled_app("test_gem/exe/test_gem")).to exist
      end

      it "requires 'test-gem'" do
        expect(bundled_app("test_gem/exe/test_gem").read).to match(/require "test_gem"/)
      end
    end

    context "no --test parameter" do
      before do
        reset!
        in_app_root
        bundle "gem #{gem_name}"
      end

      it "doesn't create any spec/test file" do
        expect(bundled_app("test_gem/.rspec")).to_not exist
        expect(bundled_app("test_gem/spec/test_gem_spec.rb")).to_not exist
        expect(bundled_app("test_gem/spec/spec_helper.rb")).to_not exist
        expect(bundled_app("test_gem/test/test_test_gem.rb")).to_not exist
        expect(bundled_app("test_gem/test/minitest_helper.rb")).to_not exist
      end
    end

    context "--test parameter set to rspec" do
      before do
        reset!
        in_app_root
        bundle "gem #{gem_name} --test=rspec"
      end

      it "builds spec skeleton" do
        expect(bundled_app("test_gem/.rspec")).to exist
        expect(bundled_app("test_gem/spec/test_gem_spec.rb")).to exist
        expect(bundled_app("test_gem/spec/spec_helper.rb")).to exist
      end

      it "depends on a specific version of rspec", :rubygems => ">= 1.8.1" do
        remove_push_guard(gem_name)
        rspec_dep = generated_gem.gemspec.development_dependencies.find {|d| d.name == "rspec" }
        expect(rspec_dep).to be_specific
      end

      it "requires 'test-gem'" do
        expect(bundled_app("test_gem/spec/spec_helper.rb").read).to include(%(require "test_gem"))
      end

      it "creates a default test which fails" do
        expect(bundled_app("test_gem/spec/test_gem_spec.rb").read).to include("expect(false).to eq(true)")
      end
    end

    context "gem.test setting set to rspec" do
      before do
        reset!
        in_app_root
        bundle "config gem.test rspec"
        bundle "gem #{gem_name}"
      end

      it "builds spec skeleton" do
        expect(bundled_app("test_gem/.rspec")).to exist
        expect(bundled_app("test_gem/spec/test_gem_spec.rb")).to exist
        expect(bundled_app("test_gem/spec/spec_helper.rb")).to exist
      end
    end

    context "gem.test setting set to rspec and --test is set to minitest" do
      before do
        reset!
        in_app_root
        bundle "config gem.test rspec"
        bundle "gem #{gem_name} --test=minitest"
      end

      it "builds spec skeleton" do
        expect(bundled_app("test_gem/test/test_gem_test.rb")).to exist
        expect(bundled_app("test_gem/test/test_helper.rb")).to exist
      end
    end

    context "--test parameter set to minitest" do
      before do
        reset!
        in_app_root
        bundle "gem #{gem_name} --test=minitest"
      end

      it "depends on a specific version of minitest", :rubygems => ">= 1.8.1" do
        remove_push_guard(gem_name)
        rspec_dep = generated_gem.gemspec.development_dependencies.find {|d| d.name == "minitest" }
        expect(rspec_dep).to be_specific
      end

      it "builds spec skeleton" do
        expect(bundled_app("test_gem/test/test_gem_test.rb")).to exist
        expect(bundled_app("test_gem/test/test_helper.rb")).to exist
      end

      it "requires 'test-gem'" do
        expect(bundled_app("test_gem/test/test_helper.rb").read).to include(%(require "test_gem"))
      end

      it "requires 'minitest_helper'" do
        expect(bundled_app("test_gem/test/test_gem_test.rb").read).to include(%(require "test_helper"))
      end

      it "creates a default test which fails" do
        expect(bundled_app("test_gem/test/test_gem_test.rb").read).to include("assert false")
      end
    end

    context "gem.test setting set to minitest" do
      before do
        reset!
        in_app_root
        bundle "config gem.test minitest"
        bundle "gem #{gem_name}"
      end

      it "creates a default rake task to run the test suite" do
        rakefile = strip_whitespace <<-RAKEFILE
          require "bundler/gem_tasks"
          require "rake/testtask"

          Rake::TestTask.new(:test) do |t|
            t.libs << "test"
            t.libs << "lib"
            t.test_files = FileList["test/**/*_test.rb"]
          end

          task :default => :test
        RAKEFILE

        expect(bundled_app("test_gem/Rakefile").read).to eq(rakefile)
      end
    end

    context "--test with no arguments" do
      before do
        reset!
        in_app_root
        bundle "gem #{gem_name} --test"
      end

      it "defaults to rspec" do
        expect(bundled_app("test_gem/spec/spec_helper.rb")).to exist
        expect(bundled_app("test_gem/test/minitest_helper.rb")).to_not exist
      end

      it "creates a .travis.yml file to test the library against the current Ruby version on Travis CI" do
        expect(bundled_app("test_gem/.travis.yml").read).to match(/- #{RUBY_VERSION}/)
      end
    end

    context "--edit option" do
      it "opens the generated gemspec in the user's text editor" do
        reset!
        in_app_root
        output = bundle "gem #{gem_name} --edit=echo"
        gemspec_path = File.join(Dir.pwd, gem_name, "#{gem_name}.gemspec")
        expect(output).to include("echo \"#{gemspec_path}\"")
      end
    end
  end

  context "testing --mit and --coc options against bundle config settings" do
    let(:gem_name) { "test-gem" }

    context "with mit option in bundle config settings set to true" do
      before do
        global_config "BUNDLE_GEM__MIT" => "true", "BUNDLE_GEM__TEST" => "false", "BUNDLE_GEM__COC" => "false"
      end
      after { reset! }
      it_behaves_like "--mit flag"
      it_behaves_like "--no-mit flag"
    end

    context "with mit option in bundle config settings set to false" do
      it_behaves_like "--mit flag"
      it_behaves_like "--no-mit flag"
    end

    context "with coc option in bundle config settings set to true" do
      before do
        global_config "BUNDLE_GEM__MIT" => "false", "BUNDLE_GEM__TEST" => "false", "BUNDLE_GEM__COC" => "true"
      end
      after { reset! }
      it_behaves_like "--coc flag"
      it_behaves_like "--no-coc flag"
    end

    context "with coc option in bundle config settings set to false" do
      it_behaves_like "--coc flag"
      it_behaves_like "--no-coc flag"
    end
  end

  context "gem naming with dashed" do
    let(:gem_name) { "test-gem" }

    before do
      execute_bundle_gem(gem_name)
    end

    let(:generated_gem) { Bundler::GemHelper.new(bundled_app(gem_name).to_s) }

    it "generates a gem skeleton" do
      expect(bundled_app("test-gem/test-gem.gemspec")).to exist
      expect(bundled_app("test-gem/Gemfile")).to exist
      expect(bundled_app("test-gem/Rakefile")).to exist
      expect(bundled_app("test-gem/lib/test/gem.rb")).to exist
      expect(bundled_app("test-gem/lib/test/gem/version.rb")).to exist
    end

    it "starts with version 0.1.0" do
      expect(bundled_app("test-gem/lib/test/gem/version.rb").read).to match(/VERSION = "0.1.0"/)
    end

    it "nests constants so they work" do
      expect(bundled_app("test-gem/lib/test/gem/version.rb").read).to match(/module Test\n  module Gem/)
      expect(bundled_app("test-gem/lib/test/gem.rb").read).to match(/module Test\n  module Gem/)
    end

    it_should_behave_like "git config is present"

    context "git config user.{name,email} is not set" do
      before do
        `git config --unset user.name`
        `git config --unset user.email`
        reset!
        in_app_root
        bundle "gem #{gem_name}"
        remove_push_guard(gem_name)
      end

      it_should_behave_like "git config is absent"
    end

    it "requires the version file" do
      expect(bundled_app("test-gem/lib/test/gem.rb").read).to match(%r{require "test/gem/version"})
    end

    it "runs rake without problems" do
      system_gems ["rake-10.0.2"]

      rakefile = strip_whitespace <<-RAKEFILE
        task :default do
          puts 'SUCCESS'
        end
      RAKEFILE
      File.open(bundled_app("test-gem/Rakefile"), "w") do |file|
        file.puts rakefile
      end

      Dir.chdir(bundled_app(gem_name)) do
        sys_exec(rake)
        expect(out).to include("SUCCESS")
      end
    end

    context "--bin parameter set" do
      before do
        reset!
        in_app_root
        bundle "gem #{gem_name} --bin"
      end

      it "builds bin skeleton" do
        expect(bundled_app("test-gem/exe/test-gem")).to exist
      end

      it "requires 'test/gem'" do
        expect(bundled_app("test-gem/exe/test-gem").read).to match(%r{require "test/gem"})
      end
    end

    context "no --test parameter" do
      before do
        reset!
        in_app_root
        bundle "gem #{gem_name}"
      end

      it "doesn't create any spec/test file" do
        expect(bundled_app("test-gem/.rspec")).to_not exist
        expect(bundled_app("test-gem/spec/test/gem_spec.rb")).to_not exist
        expect(bundled_app("test-gem/spec/spec_helper.rb")).to_not exist
        expect(bundled_app("test-gem/test/test_test/gem.rb")).to_not exist
        expect(bundled_app("test-gem/test/minitest_helper.rb")).to_not exist
      end
    end

    context "--test parameter set to rspec" do
      before do
        reset!
        in_app_root
        bundle "gem #{gem_name} --test=rspec"
      end

      it "builds spec skeleton" do
        expect(bundled_app("test-gem/.rspec")).to exist
        expect(bundled_app("test-gem/spec/test/gem_spec.rb")).to exist
        expect(bundled_app("test-gem/spec/spec_helper.rb")).to exist
      end

      it "requires 'test/gem'" do
        expect(bundled_app("test-gem/spec/spec_helper.rb").read).to include(%(require "test/gem"))
      end

      it "creates a default test which fails" do
        expect(bundled_app("test-gem/spec/test/gem_spec.rb").read).to include("expect(false).to eq(true)")
      end

      it "creates a default rake task to run the specs" do
        rakefile = strip_whitespace <<-RAKEFILE
          require "bundler/gem_tasks"
          require "rspec/core/rake_task"

          RSpec::Core::RakeTask.new(:spec)

          task :default => :spec
        RAKEFILE

        expect(bundled_app("test-gem/Rakefile").read).to eq(rakefile)
      end
    end

    context "--test parameter set to minitest" do
      before do
        reset!
        in_app_root
        bundle "gem #{gem_name} --test=minitest"
      end

      it "builds spec skeleton" do
        expect(bundled_app("test-gem/test/test/gem_test.rb")).to exist
        expect(bundled_app("test-gem/test/test_helper.rb")).to exist
      end

      it "requires 'test/gem'" do
        expect(bundled_app("test-gem/test/test_helper.rb").read).to match(%r{require "test/gem"})
      end

      it "requires 'test_helper'" do
        expect(bundled_app("test-gem/test/test/gem_test.rb").read).to match(/require "test_helper"/)
      end

      it "creates a default test which fails" do
        expect(bundled_app("test-gem/test/test/gem_test.rb").read).to match(/assert false/)
      end

      it "creates a default rake task to run the test suite" do
        rakefile = strip_whitespace <<-RAKEFILE
          require "bundler/gem_tasks"
          require "rake/testtask"

          Rake::TestTask.new(:test) do |t|
            t.libs << "test"
            t.libs << "lib"
            t.test_files = FileList["test/**/*_test.rb"]
          end

          task :default => :test
        RAKEFILE

        expect(bundled_app("test-gem/Rakefile").read).to eq(rakefile)
      end
    end

    context "--test with no arguments" do
      before do
        reset!
        in_app_root
        bundle "gem #{gem_name} --test"
      end

      it "defaults to rspec" do
        expect(bundled_app("test-gem/spec/spec_helper.rb")).to exist
        expect(bundled_app("test-gem/test/minitest_helper.rb")).to_not exist
      end
    end

    context "--ext parameter set" do
      before do
        reset!
        in_app_root
        bundle "gem test_gem --ext"
      end

      it "builds ext skeleton" do
        expect(bundled_app("test_gem/ext/test_gem/extconf.rb")).to exist
        expect(bundled_app("test_gem/ext/test_gem/test_gem.h")).to exist
        expect(bundled_app("test_gem/ext/test_gem/test_gem.c")).to exist
      end

      it "includes rake-compiler" do
        expect(bundled_app("test_gem/test_gem.gemspec").read).to include('spec.add_development_dependency "rake-compiler"')
      end

      it "depends on compile task for build" do
        rakefile = strip_whitespace <<-RAKEFILE
          require "bundler/gem_tasks"
          require "rake/extensiontask"

          task :build => :compile

          Rake::ExtensionTask.new("test_gem") do |ext|
            ext.lib_dir = "lib/test_gem"
          end

          task :default => [:clobber, :compile, :spec]
        RAKEFILE

        expect(bundled_app("test_gem/Rakefile").read).to eq(rakefile)
      end
    end
  end

  describe "uncommon gem names" do
    it "can deal with two dashes" do
      bundle "gem a--a"
      Bundler.clear_gemspec_cache

      expect(bundled_app("a--a/a--a.gemspec")).to exist
    end

    it "fails gracefully with a ." do
      bundle "gem foo.gemspec"
      expect(last_command.bundler_err).to end_with("Invalid gem name foo.gemspec -- `Foo.gemspec` is an invalid constant name")
    end

    it "fails gracefully with a ^" do
      bundle "gem ^"
      expect(last_command.bundler_err).to end_with("Invalid gem name ^ -- `^` is an invalid constant name")
    end

    it "fails gracefully with a space" do
      bundle "gem 'foo bar'"
      expect(last_command.bundler_err).to end_with("Invalid gem name foo bar -- `Foo bar` is an invalid constant name")
    end

    it "fails gracefully when multiple names are passed" do
      bundle "gem foo bar baz"
      expect(last_command.bundler_err).to eq(<<-E.strip)
ERROR: "bundle gem" was called with arguments ["foo", "bar", "baz"]
Usage: "bundle gem NAME [OPTIONS]"
      E
    end
  end

  describe "#ensure_safe_gem_name" do
    before do
      bundle "gem #{subject}"
    end
    after do
      Bundler.clear_gemspec_cache
    end

    context "with an existing const name" do
      subject { "gem" }
      it { expect(out).to include("Invalid gem name #{subject}") }
    end

    context "with an existing hyphenated const name" do
      subject { "gem-specification" }
      it { expect(out).to include("Invalid gem name #{subject}") }
    end

    context "starting with an existing const name" do
      subject { "gem-somenewconstantname" }
      it { expect(out).not_to include("Invalid gem name #{subject}") }
    end

    context "ending with an existing const name" do
      subject { "somenewconstantname-gem" }
      it { expect(out).not_to include("Invalid gem name #{subject}") }
    end
  end

  context "on first run" do
    before do
      in_app_root
    end

    it "asks about test framework" do
      global_config "BUNDLE_GEM__MIT" => "false", "BUNDLE_GEM__COC" => "false"

      bundle "gem foobar" do |input, _, _|
        input.puts "rspec"
      end

      expect(bundled_app("foobar/spec/spec_helper.rb")).to exist
      rakefile = strip_whitespace <<-RAKEFILE
        require "bundler/gem_tasks"
        require "rspec/core/rake_task"

        RSpec::Core::RakeTask.new(:spec)

        task :default => :spec
      RAKEFILE

      expect(bundled_app("foobar/Rakefile").read).to eq(rakefile)
      expect(bundled_app("foobar/foobar.gemspec").read).to include('spec.add_development_dependency "rspec"')
    end

    it "asks about MIT license" do
      global_config "BUNDLE_GEM__TEST" => "false", "BUNDLE_GEM__COC" => "false"

      bundle :config

      bundle "gem foobar" do |input, _, _|
        input.puts "yes"
      end

      expect(bundled_app("foobar/LICENSE.txt")).to exist
    end

    it "asks about CoC" do
      global_config "BUNDLE_GEM__MIT" => "false", "BUNDLE_GEM__TEST" => "false"

      bundle "gem foobar" do |input, _, _|
        input.puts "yes"
      end

      expect(bundled_app("foobar/CODE_OF_CONDUCT.md")).to exist
    end
  end

  context "on conflicts with a previously created file" do
    it "should fail gracefully" do
      in_app_root do
        FileUtils.touch("conflict-foobar")
      end
      bundle "gem conflict-foobar"
      expect(last_command.bundler_err).to include("Errno::ENOTDIR")
      expect(exitstatus).to eql(32) if exitstatus
    end
  end

  context "on conflicts with a previously created directory" do
    it "should succeed" do
      in_app_root do
        FileUtils.mkdir_p("conflict-foobar/Gemfile")
      end
      bundle! "gem conflict-foobar"
      expect(last_command.stdout).to include("file_clash  conflict-foobar/Gemfile").
        and include "Initializing git repo in #{bundled_app("conflict-foobar")}"
    end
  end
end
