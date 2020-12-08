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

  def bundle_exec_rubocop
    prepare_gemspec(bundled_app(gem_name, "#{gem_name}.gemspec"))
    rubocop_version = RUBY_VERSION > "2.4" ? "0.90.0" : "0.80.1"
    gems = ["minitest", "rake", "rake-compiler", "rspec", "rubocop -v #{rubocop_version}", "test-unit"]
    gems.unshift "parallel -v 1.19.2" if RUBY_VERSION < "2.5"
    gems += ["rubocop-ast -v 0.4.0"] if rubocop_version == "0.90.0"
    path = Bundler.feature_flag.default_install_uses_path? ? local_gem_path(:base => bundled_app(gem_name)) : system_gem_path
    realworld_system_gems gems, :path => path
    bundle "exec rubocop --debug --config .rubocop.yml", :dir => bundled_app(gem_name)
  end

  let(:generated_gemspec) { Bundler.load_gemspec_uncached(bundled_app(gem_name).join("#{gem_name}.gemspec")) }

  let(:gem_name) { "mygem" }

  let(:require_path) { "mygem" }

  before do
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
        bundle "gem #{gem_name} #{flags}"
      end

      it "generates a gem skeleton with a .git folder", :readline do
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

    context "when passing --no-git", :readline do
      before do
        bundle "gem #{gem_name} --no-git"
      end
      it "generates a gem skeleton without a .git folder" do
        gem_skeleton_assertions
        expect(bundled_app("#{gem_name}/.git")).not_to exist
      end
    end
  end

  shared_examples_for "--mit flag" do
    before do
      bundle "gem #{gem_name} --mit"
    end
    it "generates a gem skeleton with MIT license" do
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/LICENSE.txt")).to exist
      expect(generated_gemspec.license).to eq("MIT")
    end
  end

  shared_examples_for "--no-mit flag" do
    before do
      bundle "gem #{gem_name} --no-mit"
    end
    it "generates a gem skeleton without MIT license" do
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/LICENSE.txt")).to_not exist
    end
  end

  shared_examples_for "--coc flag" do
    before do
      bundle "gem #{gem_name} --coc"
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
      bundle "gem #{gem_name} --no-coc"
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

  shared_examples_for "--rubocop flag" do
    before do
      bundle "gem #{gem_name} --rubocop"
    end

    it "generates a gem skeleton with rubocop" do
      gem_skeleton_assertions
      expect(bundled_app("test-gem/Rakefile")).to read_as(
        include("# frozen_string_literal: true").
        and(include('require "rubocop/rake_task"').
        and(include("RuboCop::RakeTask.new").
        and(match(/default:.+:rubocop/))))
      )
    end

    it "includes rubocop in generated Gemfile" do
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      builder = Bundler::Dsl.new
      builder.eval_gemfile(bundled_app("#{gem_name}/Gemfile"))
      builder.dependencies
      rubocop_dep = builder.dependencies.find {|d| d.name == "rubocop" }
      expect(rubocop_dep).not_to be_nil
    end

    it "generates a default .rubocop.yml" do
      expect(bundled_app("#{gem_name}/.rubocop.yml")).to exist
    end
  end

  shared_examples_for "--no-rubocop flag" do
    define_negated_matcher :exclude, :include

    before do
      bundle "gem #{gem_name} --no-rubocop"
    end

    it "generates a gem skeleton without rubocop" do
      gem_skeleton_assertions
      expect(bundled_app("test-gem/Rakefile")).to read_as(exclude("rubocop"))
      expect(bundled_app("test-gem/#{gem_name}.gemspec")).to read_as(exclude("rubocop"))
    end

    it "does not include rubocop in generated Gemfile" do
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      builder = Bundler::Dsl.new
      builder.eval_gemfile(bundled_app("#{gem_name}/Gemfile"))
      builder.dependencies
      rubocop_dep = builder.dependencies.find {|d| d.name == "rubocop" }
      expect(rubocop_dep).to be_nil
    end

    it "doesn't generate a default .rubocop.yml" do
      expect(bundled_app("#{gem_name}/.rubocop.yml")).to_not exist
    end
  end

  it "has no rubocop offenses when using --rubocop flag", :readline do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    bundle "gem #{gem_name} --rubocop"
    bundle_exec_rubocop
    expect(err).to be_empty
  end

  it "has no rubocop offenses when using --ext and --rubocop flag", :readline do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    bundle "gem #{gem_name} --ext --rubocop"
    bundle_exec_rubocop
    expect(err).to be_empty
  end

  it "has no rubocop offenses when using --ext, --test=minitest, and --rubocop flag", :readline do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    bundle "gem #{gem_name} --ext --test=minitest --rubocop"
    bundle_exec_rubocop
    expect(err).to be_empty
  end

  it "has no rubocop offenses when using --ext, --test=rspec, and --rubocop flag", :readline do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    bundle "gem #{gem_name} --ext --test=rspec --rubocop"
    bundle_exec_rubocop
    expect(err).to be_empty
  end

  it "has no rubocop offenses when using --ext, --ext=test-unit, and --rubocop flag", :readline do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    bundle "gem #{gem_name} --ext --test=test-unit --rubocop"
    bundle_exec_rubocop
    expect(err).to be_empty
  end

  shared_examples_for "CI config is absent" do
    it "does not create any CI files" do
      expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to_not exist
      expect(bundled_app("#{gem_name}/.travis.yml")).to_not exist
      expect(bundled_app("#{gem_name}/.gitlab-ci.yml")).to_not exist
      expect(bundled_app("#{gem_name}/.circleci/config.yml")).to_not exist
    end
  end

  shared_examples_for "test framework is absent" do
    it "does not create any test framework files" do
      expect(bundled_app("#{gem_name}/.rspec")).to_not exist
      expect(bundled_app("#{gem_name}/spec/#{require_path}_spec.rb")).to_not exist
      expect(bundled_app("#{gem_name}/spec/spec_helper.rb")).to_not exist
      expect(bundled_app("#{gem_name}/test/#{require_path}.rb")).to_not exist
      expect(bundled_app("#{gem_name}/test/test_helper.rb")).to_not exist
    end
  end

  context "README.md", :readline do
    context "git config github.user present" do
      before do
        bundle "gem #{gem_name}"
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

  it "creates a new git repository", :readline do
    bundle "gem #{gem_name}"
    expect(bundled_app("#{gem_name}/.git")).to exist
  end

  context "when git is not available", :readline do
    # This spec cannot have `git` available in the test env
    before do
      load_paths = [lib_dir, spec_dir]
      load_path_str = "-I#{load_paths.join(File::PATH_SEPARATOR)}"

      sys_exec "#{Gem.ruby} #{load_path_str} #{bindir.join("bundle")} gem #{gem_name}", :env => { "PATH" => "" }
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

  it "generates a valid gemspec", :readline, :ruby_repo do
    bundle "gem newgem --bin"

    prepare_gemspec(bundled_app("newgem", "newgem.gemspec"))

    gems = ["rake-13.0.1"]
    path = Bundler.feature_flag.default_install_uses_path? ? local_gem_path(:base => bundled_app("newgem")) : system_gem_path
    system_gems gems, :path => path
    bundle "exec rake build", :dir => bundled_app("newgem")

    expect(last_command.stdboth).not_to include("ERROR")
  end

  context "gem naming with relative paths", :readline do
    it "resolves ." do
      create_temporary_dir("tmp")

      bundle "gem .", :dir => bundled_app("tmp")

      expect(bundled_app("tmp/lib/tmp.rb")).to exist
    end

    it "resolves .." do
      create_temporary_dir("temp/empty_dir")

      bundle "gem ..", :dir => bundled_app("temp/empty_dir")

      expect(bundled_app("temp/lib/temp.rb")).to exist
    end

    it "resolves relative directory" do
      create_temporary_dir("tmp/empty/tmp")

      bundle "gem ../../empty", :dir => bundled_app("tmp/empty/tmp")

      expect(bundled_app("tmp/empty/lib/empty.rb")).to exist
    end

    def create_temporary_dir(dir)
      FileUtils.mkdir_p(bundled_app(dir))
    end
  end

  shared_examples_for "generating a gem" do
    it "generates a gem skeleton" do
      bundle "gem #{gem_name}"

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
      expect(bundled_app("#{gem_name}/bin/setup").read).to start_with("#!")
      expect(bundled_app("#{gem_name}/bin/console").read).to start_with("#!")
    end

    it "starts with version 0.1.0" do
      bundle "gem #{gem_name}"

      expect(bundled_app("#{gem_name}/lib/#{require_path}/version.rb").read).to match(/VERSION = "0.1.0"/)
    end

    context "git config user.{name,email} is set" do
      before do
        bundle "gem #{gem_name}"
      end

      it_should_behave_like "git config is present"
    end

    context "git config user.{name,email} is not set" do
      before do
        sys_exec("git config --unset user.name", :dir => bundled_app)
        sys_exec("git config --unset user.email", :dir => bundled_app)
        bundle "gem #{gem_name}"
      end

      it_should_behave_like "git config is absent"
    end

    it "sets gemspec metadata['allowed_push_host']" do
      bundle "gem #{gem_name}"

      expect(generated_gemspec.metadata["allowed_push_host"]).
        to match(/mygemserver\.com/)
    end

    it "sets a minimum ruby version" do
      bundle "gem #{gem_name}"

      bundler_gemspec = Bundler::GemHelper.new(gemspec_dir).gemspec

      expect(bundler_gemspec.required_ruby_version).to eq(generated_gemspec.required_ruby_version)
    end

    it "requires the version file" do
      bundle "gem #{gem_name}"

      expect(bundled_app("#{gem_name}/lib/#{require_path}.rb").read).to match(%r{require_relative "#{require_relative_path}/version"})
    end

    it "creates a base error class" do
      bundle "gem #{gem_name}"

      expect(bundled_app("#{gem_name}/lib/#{require_path}.rb").read).to match(/class Error < StandardError; end$/)
    end

    it "runs rake without problems" do
      bundle "gem #{gem_name}"

      system_gems ["rake-13.0.1"]

      rakefile = strip_whitespace <<-RAKEFILE
        task :default do
          puts 'SUCCESS'
        end
      RAKEFILE
      File.open(bundled_app("#{gem_name}/Rakefile"), "w") do |file|
        file.puts rakefile
      end

      sys_exec(rake, :dir => bundled_app(gem_name))
      expect(out).to include("SUCCESS")
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

      it_behaves_like "test framework is absent"
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
        allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
        builder = Bundler::Dsl.new
        builder.eval_gemfile(bundled_app("#{gem_name}/Gemfile"))
        builder.dependencies
        rspec_dep = builder.dependencies.find {|d| d.name == "rspec" }
        expect(rspec_dep).to be_specific
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
        allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
        builder = Bundler::Dsl.new
        builder.eval_gemfile(bundled_app("#{gem_name}/Gemfile"))
        builder.dependencies
        minitest_dep = builder.dependencies.find {|d| d.name == "minitest" }
        expect(minitest_dep).to be_specific
      end

      it "builds spec skeleton" do
        expect(bundled_app("#{gem_name}/test/#{require_path}_test.rb")).to exist
        expect(bundled_app("#{gem_name}/test/test_helper.rb")).to exist
      end

      it "requires the main file" do
        expect(bundled_app("#{gem_name}/test/test_helper.rb").read).to include(%(require "#{require_path}"))
      end

      it "requires 'test_helper'" do
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
          # frozen_string_literal: true

          require "bundler/gem_tasks"
          require "rake/testtask"

          Rake::TestTask.new(:test) do |t|
            t.libs << "test"
            t.libs << "lib"
            t.test_files = FileList["test/**/*_test.rb"]
          end

          task default: :test
        RAKEFILE

        expect(bundled_app("#{gem_name}/Rakefile").read).to eq(rakefile)
      end
    end

    context "--test parameter set to test-unit" do
      before do
        bundle "gem #{gem_name} --test=test-unit"
      end

      it "depends on a specific version of test-unit" do
        allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
        builder = Bundler::Dsl.new
        builder.eval_gemfile(bundled_app("#{gem_name}/Gemfile"))
        builder.dependencies
        test_unit_dep = builder.dependencies.find {|d| d.name == "test-unit" }
        expect(test_unit_dep).to be_specific
      end

      it "builds spec skeleton" do
        expect(bundled_app("#{gem_name}/test/#{require_path}_test.rb")).to exist
        expect(bundled_app("#{gem_name}/test/test_helper.rb")).to exist
      end

      it "requires the main file" do
        expect(bundled_app("#{gem_name}/test/test_helper.rb").read).to include(%(require "#{require_path}"))
      end

      it "requires 'test_helper'" do
        expect(bundled_app("#{gem_name}/test/#{require_path}_test.rb").read).to include(%(require "test_helper"))
      end

      it "creates a default test which fails" do
        expect(bundled_app("#{gem_name}/test/#{require_path}_test.rb").read).to include("assert_equal(\"expected\", \"actual\")")
      end
    end

    context "gem.test setting set to test-unit" do
      before do
        bundle "config set gem.test test-unit"
        bundle "gem #{gem_name}"
      end

      it "creates a default rake task to run the test suite" do
        rakefile = strip_whitespace <<-RAKEFILE
          # frozen_string_literal: true

          require "bundler/gem_tasks"
          require "rake/testtask"

          Rake::TestTask.new(:test) do |t|
            t.libs << "test"
            t.libs << "lib"
            t.test_files = FileList["test/**/*_test.rb"]
          end

          task default: :test
        RAKEFILE

        expect(bundled_app("#{gem_name}/Rakefile").read).to eq(rakefile)
      end
    end

    context "gem.test set to rspec and --test with no arguments", :hint_text do
      before do
        bundle "config set gem.test rspec"
        bundle "gem #{gem_name} --test"
      end

      it "builds spec skeleton" do
        expect(bundled_app("#{gem_name}/.rspec")).to exist
        expect(bundled_app("#{gem_name}/spec/#{require_path}_spec.rb")).to exist
        expect(bundled_app("#{gem_name}/spec/spec_helper.rb")).to exist
      end

      it "hints that --test is already configured" do
        expect(out).to match("rspec is already configured, ignoring --test flag.")
      end
    end

    context "gem.test setting set to false and --test with no arguments", :hint_text do
      before do
        bundle "config set gem.test false"
        bundle "gem #{gem_name} --test"
      end

      it "asks to generate test files" do
        expect(out).to match("Do you want to generate tests with your gem?")
      end

      it "hints that the choice will only be applied to the current gem" do
        expect(out).to match("Your choice will only be applied to this gem.")
      end

      it_behaves_like "test framework is absent"
    end

    context "gem.test setting not set and --test with no arguments", :hint_text do
      before do
        bundle "gem #{gem_name} --test"
      end

      it "asks to generate test files" do
        expect(out).to match("Do you want to generate tests with your gem?")
      end

      it "hints that the choice will be applied to future bundle gem calls" do
        hint = "Future `bundle gem` calls will use your choice. " \
               "This setting can be changed anytime with `bundle config gem.test`."
        expect(out).to match(hint)
      end

      it_behaves_like "test framework is absent"
    end

    context "--ci with no argument" do
      it "does not generate any CI config" do
        bundle "gem #{gem_name}"

        expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to_not exist
        expect(bundled_app("#{gem_name}/.travis.yml")).to_not exist
        expect(bundled_app("#{gem_name}/.gitlab-ci.yml")).to_not exist
        expect(bundled_app("#{gem_name}/.circleci/config.yml")).to_not exist
      end
    end

    context "--ci set to github" do
      it "generates a GitHub Actions config file" do
        bundle "gem #{gem_name} --ci=github"

        expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to exist
      end
    end

    context "--ci set to gitlab" do
      it "generates a GitLab CI config file" do
        bundle "gem #{gem_name} --ci=gitlab"

        expect(bundled_app("#{gem_name}/.gitlab-ci.yml")).to exist
      end
    end

    context "--ci set to circle" do
      it "generates a CircleCI config file" do
        bundle "gem #{gem_name} --ci=circle"

        expect(bundled_app("#{gem_name}/.circleci/config.yml")).to exist
      end
    end

    context "--ci set to travis" do
      it "generates a Travis CI config file" do
        bundle "gem #{gem_name} --ci=travis"

        expect(bundled_app("#{gem_name}/.travis.yml")).to exist
      end
    end

    context "gem.ci setting set to none" do
      it "doesn't generate any CI config" do
        expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to_not exist
        expect(bundled_app("#{gem_name}/.travis.yml")).to_not exist
        expect(bundled_app("#{gem_name}/.gitlab-ci.yml")).to_not exist
        expect(bundled_app("#{gem_name}/.circleci/config.yml")).to_not exist
      end
    end

    context "gem.ci setting set to github" do
      it "generates a GitHub Actions config file" do
        bundle "config set gem.ci github"
        bundle "gem #{gem_name}"

        expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to exist
      end
    end

    context "gem.ci setting set to travis" do
      it "generates a Travis CI config file" do
        bundle "config set gem.ci travis"
        bundle "gem #{gem_name}"

        expect(bundled_app("#{gem_name}/.travis.yml")).to exist
      end
    end

    context "gem.ci setting set to gitlab" do
      it "generates a GitLab CI config file" do
        bundle "config set gem.ci gitlab"
        bundle "gem #{gem_name}"

        expect(bundled_app("#{gem_name}/.gitlab-ci.yml")).to exist
      end
    end

    context "gem.ci setting set to circle" do
      it "generates a CircleCI config file" do
        bundle "config set gem.ci circle"
        bundle "gem #{gem_name}"

        expect(bundled_app("#{gem_name}/.circleci/config.yml")).to exist
      end
    end

    context "gem.ci set to github and --ci with no arguments", :hint_text do
      before do
        bundle "config set gem.ci github"
        bundle "gem #{gem_name} --ci"
      end

      it "generates a GitHub Actions config file" do
        expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to exist
      end

      it "hints that --ci is already configured" do
        expect(out).to match("github is already configured, ignoring --ci flag.")
      end
    end

    context "gem.ci setting set to false and --ci with no arguments", :hint_text do
      before do
        bundle "config set gem.ci false"
        bundle "gem #{gem_name} --ci"
      end

      it "asks to setup CI" do
        expect(out).to match("Do you want to set up continuous integration for your gem?")
      end

      it "hints that the choice will only be applied to the current gem" do
        expect(out).to match("Your choice will only be applied to this gem.")
      end
    end

    context "gem.ci setting not set and --ci with no arguments", :hint_text do
      before do
        bundle "gem #{gem_name} --ci"
      end

      it "asks to setup CI" do
        expect(out).to match("Do you want to set up continuous integration for your gem?")
      end

      it "hints that the choice will be applied to future bundle gem calls" do
        hint = "Future `bundle gem` calls will use your choice. " \
               "This setting can be changed anytime with `bundle config gem.ci`."
        expect(out).to match(hint)
      end
    end

    context "--edit option" do
      it "opens the generated gemspec in the user's text editor" do
        output = bundle "gem #{gem_name} --edit=echo"
        gemspec_path = File.join(bundled_app, gem_name, "#{gem_name}.gemspec")
        expect(output).to include("echo \"#{gemspec_path}\"")
      end
    end
  end

  context "testing --mit and --coc options against bundle config settings", :readline do
    let(:gem_name) { "test-gem" }

    let(:require_path) { "test/gem" }

    context "with mit option in bundle config settings set to true" do
      before do
        global_config "BUNDLE_GEM__MIT" => "true"
      end
      it_behaves_like "--mit flag"
      it_behaves_like "--no-mit flag"
    end

    context "with mit option in bundle config settings set to false" do
      before do
        global_config "BUNDLE_GEM__MIT" => "false"
      end
      it_behaves_like "--mit flag"
      it_behaves_like "--no-mit flag"
    end

    context "with coc option in bundle config settings set to true" do
      before do
        global_config "BUNDLE_GEM__COC" => "true"
      end
      it_behaves_like "--coc flag"
      it_behaves_like "--no-coc flag"
    end

    context "with coc option in bundle config settings set to false" do
      before do
        global_config "BUNDLE_GEM__COC" => "false"
      end
      it_behaves_like "--coc flag"
      it_behaves_like "--no-coc flag"
    end

    context "with rubocop option in bundle config settings set to true" do
      before do
        global_config "BUNDLE_GEM__RUBOCOP" => "true"
      end
      it_behaves_like "--rubocop flag"
      it_behaves_like "--no-rubocop flag"
    end

    context "with rubocop option in bundle config settings set to false" do
      before do
        global_config "BUNDLE_GEM__RUBOCOP" => "false"
      end
      it_behaves_like "--rubocop flag"
      it_behaves_like "--no-rubocop flag"
    end
  end

  context "gem naming with underscore", :readline do
    let(:gem_name) { "test_gem" }

    let(:require_path) { "test_gem" }

    let(:require_relative_path) { "test_gem" }

    let(:flags) { nil }

    it "does not nest constants" do
      bundle ["gem", gem_name, flags].compact.join(" ")
      expect(bundled_app("#{gem_name}/lib/#{require_path}/version.rb").read).to match(/module TestGem/)
      expect(bundled_app("#{gem_name}/lib/#{require_path}.rb").read).to match(/module TestGem/)
    end

    include_examples "generating a gem"

    context "--ext parameter set" do
      let(:flags) { "--ext" }

      before do
        bundle ["gem", gem_name, flags].compact.join(" ")
      end

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
          # frozen_string_literal: true

          require "bundler/gem_tasks"
          require "rake/extensiontask"

          task build: :compile

          Rake::ExtensionTask.new("#{gem_name}") do |ext|
            ext.lib_dir = "lib/#{gem_name}"
          end

          task default: %i[clobber compile]
        RAKEFILE

        expect(bundled_app("#{gem_name}/Rakefile").read).to eq(rakefile)
      end
    end
  end

  context "gem naming with dashed", :readline do
    let(:gem_name) { "test-gem" }

    let(:require_path) { "test/gem" }

    let(:require_relative_path) { "gem" }

    it "nests constants so they work" do
      bundle "gem #{gem_name}"
      expect(bundled_app("#{gem_name}/lib/#{require_path}/version.rb").read).to match(/module Test\n  module Gem/)
      expect(bundled_app("#{gem_name}/lib/#{require_path}.rb").read).to match(/module Test\n  module Gem/)
    end

    include_examples "generating a gem"
  end

  describe "uncommon gem names" do
    it "can deal with two dashes", :readline do
      bundle "gem a--a"

      expect(bundled_app("a--a/a--a.gemspec")).to exist
    end

    it "fails gracefully with a ." do
      bundle "gem foo.gemspec", :raise_on_error => false
      expect(err).to end_with("Invalid gem name foo.gemspec -- `Foo.gemspec` is an invalid constant name")
    end

    it "fails gracefully with a ^" do
      bundle "gem ^", :raise_on_error => false
      expect(err).to end_with("Invalid gem name ^ -- `^` is an invalid constant name")
    end

    it "fails gracefully with a space" do
      bundle "gem 'foo bar'", :raise_on_error => false
      expect(err).to end_with("Invalid gem name foo bar -- `Foo bar` is an invalid constant name")
    end

    it "fails gracefully when multiple names are passed" do
      bundle "gem foo bar baz", :raise_on_error => false
      expect(err).to eq(<<-E.strip)
ERROR: "bundle gem" was called with arguments ["foo", "bar", "baz"]
Usage: "bundle gem NAME [OPTIONS]"
      E
    end
  end

  describe "#ensure_safe_gem_name", :readline do
    before do
      bundle "gem #{subject}", :raise_on_error => false
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

  context "on first run", :readline do
    it "asks about test framework" do
      global_config "BUNDLE_GEM__MIT" => "false", "BUNDLE_GEM__COC" => "false"

      bundle "gem foobar" do |input, _, _|
        input.puts "rspec"
      end

      expect(bundled_app("foobar/spec/spec_helper.rb")).to exist
      rakefile = strip_whitespace <<-RAKEFILE
        # frozen_string_literal: true

        require "bundler/gem_tasks"
        require "rspec/core/rake_task"

        RSpec::Core::RakeTask.new(:spec)

        task default: :spec
      RAKEFILE

      expect(bundled_app("foobar/Rakefile").read).to eq(rakefile)
      expect(bundled_app("foobar/Gemfile").read).to include('gem "rspec"')
    end

    it "asks about CI service" do
      global_config "BUNDLE_GEM__TEST" => "false", "BUNDLE_GEM__MIT" => "false", "BUNDLE_GEM__COC" => "false", "BUNDLE_GEM__RUBOCOP" => "false"

      bundle "gem foobar" do |input, _, _|
        input.puts "github"
      end

      expect(bundled_app("foobar/.github/workflows/main.yml")).to exist
    end

    it "asks about MIT license" do
      global_config "BUNDLE_GEM__TEST" => "false", "BUNDLE_GEM__COC" => "false", "BUNDLE_GEM__CI" => "false", "BUNDLE_GEM__RUBOCOP" => "false"

      bundle "config list"

      bundle "gem foobar" do |input, _, _|
        input.puts "yes"
      end

      expect(bundled_app("foobar/LICENSE.txt")).to exist
    end

    it "asks about CoC" do
      global_config "BUNDLE_GEM__MIT" => "false", "BUNDLE_GEM__TEST" => "false", "BUNDLE_GEM__CI" => "false", "BUNDLE_GEM__RUBOCOP" => "false"

      bundle "gem foobar" do |input, _, _|
        input.puts "yes"
      end

      expect(bundled_app("foobar/CODE_OF_CONDUCT.md")).to exist
    end
  end

  context "on conflicts with a previously created file", :readline do
    it "should fail gracefully" do
      FileUtils.touch(bundled_app("conflict-foobar"))
      bundle "gem conflict-foobar", :raise_on_error => false
      expect(err).to include("Errno::ENOTDIR")
      expect(exitstatus).to eql(32)
    end
  end

  context "on conflicts with a previously created directory", :readline do
    it "should succeed" do
      FileUtils.mkdir_p(bundled_app("conflict-foobar/Gemfile"))
      bundle "gem conflict-foobar"
      expect(out).to include("file_clash  conflict-foobar/Gemfile").
        and include "Initializing git repo in #{bundled_app("conflict-foobar")}"
    end
  end
end
