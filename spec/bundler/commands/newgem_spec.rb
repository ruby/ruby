# frozen_string_literal: true

RSpec.describe "bundle gem" do
  def gem_skeleton_assertions
    expect(bundled_app("#{gem_name}/#{gem_name}.gemspec")).to exist
    expect(bundled_app("#{gem_name}/README.md")).to exist
    expect(bundled_app("#{gem_name}/Gemfile")).to exist
    expect(bundled_app("#{gem_name}/Rakefile")).to exist
    expect(bundled_app("#{gem_name}/lib/#{require_path}.rb")).to exist
    expect(bundled_app("#{gem_name}/lib/#{require_path}/version.rb")).to exist
  end

  let(:generated_gemspec) { Bundler.load_gemspec_uncached(bundled_app(gem_name).join("#{gem_name}.gemspec")) }

  let(:gem_name) { "mygem" }

  let(:require_path) { "mygem" }

  before do
    global_config "BUNDLE_GEM__MIT" => "false", "BUNDLE_GEM__TEST" => "false", "BUNDLE_GEM__COC" => "false"
    git_config_content = <<-EOF
    [user]
      name = "Bundler User"
      email = user@example.com
    [github]
      user = bundleuser
    EOF
    @git_config_location = ENV["GIT_CONFIG"]
    path = "#{tmp}/test_git_config.txt"
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
        expect(generated_gemspec.authors.first).to eq("Bundler User")
      end

      it "sets gemspec email to git user.email if available" do
        expect(generated_gemspec.email.first).to eq("user@example.com")
      end
    end
  end

  shared_examples_for "git config is absent" do
    it "sets gemspec author to default message if git user.name is not set or empty" do
      expect(generated_gemspec.authors.first).to eq("TODO: Write your name")
    end

    it "sets gemspec email to default message if git user.email is not set or empty" do
      expect(generated_gemspec.email.first).to eq("TODO: Write your email address")
    end
  end

  describe "git repo initialization" do
    shared_examples_for "a gem with an initial git repo" do
      before do
        bundle! "gem #{gem_name} #{flags}"
      end

      it "generates a gem skeleton with a .git folder" do
        gem_skeleton_assertions
        expect(bundled_app("#{gem_name}/.git")).to exist
      end
    end

    context "when using the default" do
      it_behaves_like "a gem with an initial git repo" do
        let(:flags) { "" }
      end
    end

    context "when explicitly passing --git" do
      it_behaves_like "a gem with an initial git repo" do
        let(:flags) { "--git" }
      end
    end

    context "when passing --no-git" do
      before do
        bundle! "gem #{gem_name} --no-git"
      end
      it "generates a gem skeleton without a .git folder" do
        gem_skeleton_assertions
        expect(bundled_app("#{gem_name}/.git")).not_to exist
      end
    end
  end

  shared_examples_for "--mit flag" do
    before do
      bundle! "gem #{gem_name} --mit"
    end
    it "generates a gem skeleton with MIT license" do
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/LICENSE.txt")).to exist
      expect(generated_gemspec.license).to eq("MIT")
    end
  end

  shared_examples_for "--no-mit flag" do
    before do
      bundle! "gem #{gem_name} --no-mit"
    end
    it "generates a gem skeleton without MIT license" do
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/LICENSE.txt")).to_not exist
    end
  end

  shared_examples_for "--coc flag" do
    before do
      bundle! "gem #{gem_name} --coc"
    end
    it "generates a gem skeleton with MIT license" do
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/CODE_OF_CONDUCT.md")).to exist
    end

    describe "README additions" do
      it "generates the README with a section for the Code of Conduct" do
        expect(bundled_app("#{gem_name}/README.md").read).to include("## Code of Conduct")
        expect(bundled_app("#{gem_name}/README.md").read).to include("https://github.com/bundleuser/#{gem_name}/blob/master/CODE_OF_CONDUCT.md")
      end
    end
  end

  shared_examples_for "--no-coc flag" do
    before do
      bundle! "gem #{gem_name} --no-coc"
    end
    it "generates a gem skeleton without Code of Conduct" do
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/CODE_OF_CONDUCT.md")).to_not exist
    end

    describe "README additions" do
      it "generates the README without a section for the Code of Conduct" do
        expect(bundled_app("#{gem_name}/README.md").read).not_to include("## Code of Conduct")
        expect(bundled_app("#{gem_name}/README.md").read).not_to include("https://github.com/bundleuser/#{gem_name}/blob/master/CODE_OF_CONDUCT.md")
      end
    end
  end

  context "README.md" do
    context "git config github.user present" do
      before do
        bundle! "gem #{gem_name}"
      end

      it "contribute URL set to git username" do
        expect(bundled_app("#{gem_name}/README.md").read).not_to include("[USERNAME]")
        expect(bundled_app("#{gem_name}/README.md").read).to include("github.com/bundleuser")
      end
    end

    context "git config github.user is absent" do
      before do
        sys_exec("git config --unset github.user")
        bundle "gem #{gem_name}"
      end

      it "contribute URL set to [USERNAME]" do
        expect(bundled_app("#{gem_name}/README.md").read).to include("[USERNAME]")
        expect(bundled_app("#{gem_name}/README.md").read).not_to include("github.com/bundleuser")
      end
    end
  end

  it "creates a new git repository" do
    bundle "gem #{gem_name}"
    expect(bundled_app("#{gem_name}/.git")).to exist
  end

  context "when git is not available" do
    # This spec cannot have `git` available in the test env
    before do
      load_paths = [lib_dir, spec_dir]
      load_path_str = "-I#{load_paths.join(File::PATH_SEPARATOR)}"

      sys_exec "#{Gem.ruby} #{load_path_str} #{bindir.join("bundle")} gem #{gem_name}", "PATH" => ""
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
    bundle! "gem newgem --bin"

    prepare_gemspec(bundled_app("newgem", "newgem.gemspec"))

    Dir.chdir(bundled_app("newgem")) do
      gems = ["rake-12.3.2"]
      system_gems gems, :path => :bundle_path
      bundle! "exec rake build"
    end

    expect(last_command.stdboth).not_to include("ERROR")
  end

  context "gem naming with relative paths" do
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

  shared_examples_for "generating a gem" do
    it "generates a gem skeleton" do
      bundle! "gem #{gem_name}"

      expect(bundled_app("#{gem_name}/#{gem_name}.gemspec")).to exist
      expect(bundled_app("#{gem_name}/Gemfile")).to exist
      expect(bundled_app("#{gem_name}/Rakefile")).to exist
      expect(bundled_app("#{gem_name}/lib/#{require_path}.rb")).to exist
      expect(bundled_app("#{gem_name}/lib/#{require_path}/version.rb")).to exist
      expect(bundled_app("#{gem_name}/.gitignore")).to exist

      expect(bundled_app("#{gem_name}/bin/setup")).to exist
      expect(bundled_app("#{gem_name}/bin/console")).to exist
      expect(bundled_app("#{gem_name}/bin/setup")).to be_executable
      expect(bundled_app("#{gem_name}/bin/console")).to be_executable
    end

    it "starts with version 0.1.0" do
      bundle! "gem #{gem_name}"

      expect(bundled_app("#{gem_name}/lib/#{require_path}/version.rb").read).to match(/VERSION = "0.1.0"/)
    end

    context "git config user.{name,email} is set" do
      before do
        bundle! "gem #{gem_name}"
      end

      it_should_behave_like "git config is present"
    end

    context "git config user.{name,email} is not set" do
      before do
        `git config --unset user.name`
        `git config --unset user.email`
        bundle "gem #{gem_name}"
      end

      it_should_behave_like "git config is absent"
    end

    it "sets gemspec metadata['allowed_push_host']" do
      bundle! "gem #{gem_name}"

      expect(generated_gemspec.metadata["allowed_push_host"]).
        to match(/mygemserver\.com/)
    end

    it "sets a minimum ruby version" do
      bundle! "gem #{gem_name}"

      bundler_gemspec = Bundler::GemHelper.new(gemspec_dir).gemspec

      expect(bundler_gemspec.required_ruby_version).to eq(generated_gemspec.required_ruby_version)
    end

    it "requires the version file" do
      bundle! "gem #{gem_name}"

      expect(bundled_app("#{gem_name}/lib/#{require_path}.rb").read).to match(%r{require "#{require_path}/version"})
    end

    it "creates a base error class" do
      bundle! "gem #{gem_name}"

      expect(bundled_app("#{gem_name}/lib/#{require_path}.rb").read).to match(/class Error < StandardError; end$/)
    end

    it "runs rake without problems" do
      bundle! "gem #{gem_name}"

      system_gems ["rake-12.3.2"]

      rakefile = strip_whitespace <<-RAKEFILE
        task :default do
          puts 'SUCCESS'
        end
      RAKEFILE
      File.open(bundled_app("#{gem_name}/Rakefile"), "w") do |file|
        file.puts rakefile
      end

      Dir.chdir(bundled_app(gem_name)) do
        sys_exec(rake)
        expect(out).to include("SUCCESS")
      end
    end

    context "--exe parameter set" do
      before do
        bundle "gem #{gem_name} --exe"
      end

      it "builds exe skeleton" do
        expect(bundled_app("#{gem_name}/exe/#{gem_name}")).to exist
      end

      it "requires the main file" do
        expect(bundled_app("#{gem_name}/exe/#{gem_name}").read).to match(/require "#{require_path}"/)
      end
    end

    context "--bin parameter set" do
      before do
        bundle "gem #{gem_name} --bin"
      end

      it "builds exe skeleton" do
        expect(bundled_app("#{gem_name}/exe/#{gem_name}")).to exist
      end

      it "requires the main file" do
        expect(bundled_app("#{gem_name}/exe/#{gem_name}").read).to match(/require "#{require_path}"/)
      end
    end

    context "no --test parameter" do
      before do
        bundle "gem #{gem_name}"
      end

      it "doesn't create any spec/test file" do
        expect(bundled_app("#{gem_name}/.rspec")).to_not exist
        expect(bundled_app("#{gem_name}/spec/#{require_path}_spec.rb")).to_not exist
        expect(bundled_app("#{gem_name}/spec/spec_helper.rb")).to_not exist
        expect(bundled_app("#{gem_name}/test/#{require_path}.rb")).to_not exist
        expect(bundled_app("#{gem_name}/test/minitest_helper.rb")).to_not exist
      end
    end

    context "--test parameter set to rspec" do
      before do
        bundle "gem #{gem_name} --test=rspec"
      end

      it "builds spec skeleton" do
        expect(bundled_app("#{gem_name}/.rspec")).to exist
        expect(bundled_app("#{gem_name}/spec/#{require_path}_spec.rb")).to exist
        expect(bundled_app("#{gem_name}/spec/spec_helper.rb")).to exist
      end

      it "depends on a specific version of rspec in generated Gemfile" do
        Dir.chdir(bundled_app(gem_name)) do
          builder = Bundler::Dsl.new
          builder.eval_gemfile(bundled_app("#{gem_name}/Gemfile"))
          builder.dependencies
          rspec_dep = builder.dependencies.find {|d| d.name == "rspec" }
          expect(rspec_dep).to be_specific
        end
      end

      it "requires the main file" do
        expect(bundled_app("#{gem_name}/spec/spec_helper.rb").read).to include(%(require "#{require_path}"))
      end

      it "creates a default test which fails" do
        expect(bundled_app("#{gem_name}/spec/#{require_path}_spec.rb").read).to include("expect(false).to eq(true)")
      end
    end

    context "gem.test setting set to rspec" do
      before do
        bundle "config set gem.test rspec"
        bundle "gem #{gem_name}"
      end

      it "builds spec skeleton" do
        expect(bundled_app("#{gem_name}/.rspec")).to exist
        expect(bundled_app("#{gem_name}/spec/#{require_path}_spec.rb")).to exist
        expect(bundled_app("#{gem_name}/spec/spec_helper.rb")).to exist
      end
    end

    context "gem.test setting set to rspec and --test is set to minitest" do
      before do
        bundle "config set gem.test rspec"
        bundle "gem #{gem_name} --test=minitest"
      end

      it "builds spec skeleton" do
        expect(bundled_app("#{gem_name}/test/#{require_path}_test.rb")).to exist
        expect(bundled_app("#{gem_name}/test/test_helper.rb")).to exist
      end
    end

    context "--test parameter set to minitest" do
      before do
        bundle "gem #{gem_name} --test=minitest"
      end

      it "depends on a specific version of minitest" do
        Dir.chdir(bundled_app(gem_name)) do
          builder = Bundler::Dsl.new
          builder.eval_gemfile(bundled_app("#{gem_name}/Gemfile"))
          builder.dependencies
          minitest_dep = builder.dependencies.find {|d| d.name == "minitest" }
          expect(minitest_dep).to be_specific
        end
      end

      it "builds spec skeleton" do
        expect(bundled_app("#{gem_name}/test/#{require_path}_test.rb")).to exist
        expect(bundled_app("#{gem_name}/test/test_helper.rb")).to exist
      end

      it "requires the main file" do
        expect(bundled_app("#{gem_name}/test/test_helper.rb").read).to include(%(require "#{require_path}"))
      end

      it "requires 'minitest_helper'" do
        expect(bundled_app("#{gem_name}/test/#{require_path}_test.rb").read).to include(%(require "test_helper"))
      end

      it "creates a default test which fails" do
        expect(bundled_app("#{gem_name}/test/#{require_path}_test.rb").read).to include("assert false")
      end
    end

    context "gem.test setting set to minitest" do
      before do
        bundle "config set gem.test minitest"
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

        expect(bundled_app("#{gem_name}/Rakefile").read).to eq(rakefile)
      end
    end

    context "--test with no arguments" do
      before do
        bundle "gem #{gem_name} --test"
      end

      it "defaults to rspec" do
        expect(bundled_app("#{gem_name}/spec/spec_helper.rb")).to exist
        expect(bundled_app("#{gem_name}/test/minitest_helper.rb")).to_not exist
      end

      it "creates a .travis.yml file to test the library against the current Ruby version on Travis CI" do
        expect(bundled_app("#{gem_name}/.travis.yml").read).to match(/- #{RUBY_VERSION}/)
      end
    end

    context "--edit option" do
      it "opens the generated gemspec in the user's text editor" do
        output = bundle "gem #{gem_name} --edit=echo"
        gemspec_path = File.join(Dir.pwd, gem_name, "#{gem_name}.gemspec")
        expect(output).to include("echo \"#{gemspec_path}\"")
      end
    end
  end

  context "testing --mit and --coc options against bundle config settings" do
    let(:gem_name) { "test-gem" }

    let(:require_path) { "test/gem" }

    context "with mit option in bundle config settings set to true" do
      before do
        global_config "BUNDLE_GEM__MIT" => "true", "BUNDLE_GEM__TEST" => "false", "BUNDLE_GEM__COC" => "false"
      end
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
      it_behaves_like "--coc flag"
      it_behaves_like "--no-coc flag"
    end

    context "with coc option in bundle config settings set to false" do
      it_behaves_like "--coc flag"
      it_behaves_like "--no-coc flag"
    end
  end

  context "gem naming with underscore" do
    let(:gem_name) { "test_gem" }

    let(:require_path) { "test_gem" }

    let(:flags) { nil }

    before do
      bundle! ["gem", gem_name, flags].compact.join(" ")
    end

    it "does not nest constants" do
      expect(bundled_app("#{gem_name}/lib/#{require_path}/version.rb").read).to match(/module TestGem/)
      expect(bundled_app("#{gem_name}/lib/#{require_path}.rb").read).to match(/module TestGem/)
    end

    include_examples "generating a gem"

    context "--ext parameter set" do
      let(:flags) { "--ext" }

      it "builds ext skeleton" do
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/extconf.rb")).to exist
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/#{gem_name}.h")).to exist
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/#{gem_name}.c")).to exist
      end

      it "includes rake-compiler" do
        expect(bundled_app("#{gem_name}/Gemfile").read).to include('gem "rake-compiler"')
      end

      it "depends on compile task for build" do
        rakefile = strip_whitespace <<-RAKEFILE
          require "bundler/gem_tasks"
          require "rake/extensiontask"

          task :build => :compile

          Rake::ExtensionTask.new("#{gem_name}") do |ext|
            ext.lib_dir = "lib/#{gem_name}"
          end

          task :default => [:clobber, :compile, :spec]
        RAKEFILE

        expect(bundled_app("#{gem_name}/Rakefile").read).to eq(rakefile)
      end
    end
  end

  context "gem naming with dashed" do
    let(:gem_name) { "test-gem" }

    let(:require_path) { "test/gem" }

    before do
      bundle! "gem #{gem_name}"
    end

    it "nests constants so they work" do
      expect(bundled_app("#{gem_name}/lib/#{require_path}/version.rb").read).to match(/module Test\n  module Gem/)
      expect(bundled_app("#{gem_name}/lib/#{require_path}.rb").read).to match(/module Test\n  module Gem/)
    end

    include_examples "generating a gem"
  end

  describe "uncommon gem names" do
    it "can deal with two dashes" do
      bundle! "gem a--a"

      expect(bundled_app("a--a/a--a.gemspec")).to exist
    end

    it "fails gracefully with a ." do
      bundle "gem foo.gemspec"
      expect(err).to end_with("Invalid gem name foo.gemspec -- `Foo.gemspec` is an invalid constant name")
    end

    it "fails gracefully with a ^" do
      bundle "gem ^"
      expect(err).to end_with("Invalid gem name ^ -- `^` is an invalid constant name")
    end

    it "fails gracefully with a space" do
      bundle "gem 'foo bar'"
      expect(err).to end_with("Invalid gem name foo bar -- `Foo bar` is an invalid constant name")
    end

    it "fails gracefully when multiple names are passed" do
      bundle "gem foo bar baz"
      expect(err).to eq(<<-E.strip)
ERROR: "bundle gem" was called with arguments ["foo", "bar", "baz"]
Usage: "bundle gem NAME [OPTIONS]"
      E
    end
  end

  describe "#ensure_safe_gem_name" do
    before do
      bundle "gem #{subject}"
    end

    context "with an existing const name" do
      subject { "gem" }
      it { expect(err).to include("Invalid gem name #{subject}") }
    end

    context "with an existing hyphenated const name" do
      subject { "gem-specification" }
      it { expect(err).to include("Invalid gem name #{subject}") }
    end

    context "starting with an existing const name" do
      subject { "gem-somenewconstantname" }
      it { expect(err).not_to include("Invalid gem name #{subject}") }
    end

    context "ending with an existing const name" do
      subject { "somenewconstantname-gem" }
      it { expect(err).not_to include("Invalid gem name #{subject}") }
    end
  end

  context "on first run" do
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
      expect(bundled_app("foobar/Gemfile").read).to include('gem "rspec"')
    end

    it "asks about MIT license" do
      global_config "BUNDLE_GEM__TEST" => "false", "BUNDLE_GEM__COC" => "false"

      bundle "config list"

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
      FileUtils.touch("conflict-foobar")
      bundle "gem conflict-foobar"
      expect(err).to include("Errno::ENOTDIR")
      expect(exitstatus).to eql(32) if exitstatus
    end
  end

  context "on conflicts with a previously created directory" do
    it "should succeed" do
      FileUtils.mkdir_p("conflict-foobar/Gemfile")
      bundle! "gem conflict-foobar"
      expect(out).to include("file_clash  conflict-foobar/Gemfile").
        and include "Initializing git repo in #{bundled_app("conflict-foobar")}"
    end
  end
end
