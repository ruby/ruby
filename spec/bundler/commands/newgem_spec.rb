# frozen_string_literal: true

RSpec.describe "bundle gem" do
  def gem_skeleton_assertions
    expect(bundled_app("#{gem_name}/#{gem_name}.gemspec")).to exist
    expect(bundled_app("#{gem_name}/README.md")).to exist
    expect(bundled_app("#{gem_name}/Gemfile")).to exist
    expect(bundled_app("#{gem_name}/Rakefile")).to exist
    expect(bundled_app("#{gem_name}/lib/#{gem_name}.rb")).to exist
    expect(bundled_app("#{gem_name}/lib/#{gem_name}/version.rb")).to exist

    expect(ignore_paths).to include("bin/")
    expect(ignore_paths).to include("Gemfile")
  end

  def bundle_exec_rubocop
    prepare_gemspec(bundled_app(gem_name, "#{gem_name}.gemspec"))
    bundle "config set path #{rubocop_gem_path}", dir: bundled_app(gem_name)
    bundle "exec rubocop --debug --config .rubocop.yml", dir: bundled_app(gem_name)
  end

  def bundle_exec_standardrb
    prepare_gemspec(bundled_app(gem_name, "#{gem_name}.gemspec"))
    bundle "config set path #{standard_gem_path}", dir: bundled_app(gem_name)
    bundle "exec standardrb --debug", dir: bundled_app(gem_name)
  end

  def ignore_paths
    generated = bundled_app("#{gem_name}/#{gem_name}.gemspec").read
    matched = generated.match(/^\s+f\.start_with\?\(\*%w\[(?<ignored>.*)\]\)$/)
    matched[:ignored]&.split(" ")
  end

  def installed_go?
    sys_exec("go version", raise_on_error: true)
    true
  rescue StandardError
    false
  end

  let(:generated_gemspec) { Bundler.load_gemspec_uncached(bundled_app(gem_name).join("#{gem_name}.gemspec")) }

  let(:gem_name) { "mygem" }

  before do
    # Write the global git config directly instead of shelling out to `git
    # config --global` three times per example: this `before` runs for every
    # example in the file, and each `git` call is a separate subprocess.
    File.write(home(".gitconfig"), <<~GITCONFIG)
      [user]
      name = Bundler User
      email = user@example.com
      [github]
      user = bundleuser
    GITCONFIG

    bundle_config_global "gem.mit false"
    bundle_config_global "gem.test false"
    bundle_config_global "gem.coc false"
    bundle_config_global "gem.linter false"
    bundle_config_global "gem.ci false"
    bundle_config_global "gem.changelog false"
    bundle_config_global "gem.bundle false"
  end

  describe "git repo initialization" do
    it "generates a gem skeleton with a .git folder" do
      bundle "gem #{gem_name}"
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/.git")).to exist
    end

    it "generates a gem skeleton with a .git folder when passing --git" do
      bundle "gem #{gem_name} --git"
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/.git")).to exist
    end

    it "generates a gem skeleton without a .git folder when passing --no-git" do
      bundle "gem #{gem_name} --no-git"
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/.git")).not_to exist
    end

    context "on a path with spaces" do
      before do
        Dir.mkdir(bundled_app("path with spaces"))
      end

      it "properly initializes git repo" do
        bundle "gem #{gem_name}", dir: bundled_app("path with spaces")
        expect(bundled_app("path with spaces/#{gem_name}/.git")).to exist
      end
    end
  end

  it "has no rubocop offenses when using --linter=rubocop flag" do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    bundle "gem #{gem_name} --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  it "has no rubocop offenses when using --ext=c and --linter=rubocop flag" do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    bundle "gem #{gem_name} --ext=c --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  it "has no rubocop offenses when using --ext=c, --test=minitest, and --linter=rubocop flag" do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    bundle "gem #{gem_name} --ext=c --test=minitest --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  it "has no rubocop offenses when using --ext=c, --test=rspec, and --linter=rubocop flag" do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    bundle "gem #{gem_name} --ext=c --test=rspec --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  it "has no rubocop offenses when using --ext=c, --test=test-unit, and --linter=rubocop flag" do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    bundle "gem #{gem_name} --ext=c --test=test-unit --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  it "has no standard offenses when using --linter=standard flag" do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    bundle "gem #{gem_name} --linter=standard"
    bundle_exec_standardrb
    expect(last_command).to be_success
  end

  it "has no rubocop offenses when using --ext=rust and --linter=rubocop flag" do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?

    bundle "gem #{gem_name} --ext=rust --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  it "has no rubocop offenses when using --ext=rust, --test=minitest, and --linter=rubocop flag" do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?

    bundle "gem #{gem_name} --ext=rust --test=minitest --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  it "has no rubocop offenses when using --ext=rust, --test=rspec, and --linter=rubocop flag" do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?

    bundle "gem #{gem_name} --ext=rust --test=rspec --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  it "has no rubocop offenses when using --ext=rust, --test=test-unit, and --linter=rubocop flag" do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?

    bundle "gem #{gem_name} --ext=rust --test=test-unit --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  shared_examples_for "test framework is absent" do
    it "does not create any test framework files" do
      expect(bundled_app("#{gem_name}/.rspec")).to_not exist
      expect(bundled_app("#{gem_name}/spec/#{gem_name}_spec.rb")).to_not exist
      expect(bundled_app("#{gem_name}/spec/spec_helper.rb")).to_not exist
      expect(bundled_app("#{gem_name}/test/#{gem_name}.rb")).to_not exist
      expect(bundled_app("#{gem_name}/test/test_helper.rb")).to_not exist
    end

    it "does not add any test framework files into ignore list" do
      expect(ignore_paths).not_to include("test/")
      expect(ignore_paths).not_to include(".rspec")
      expect(ignore_paths).not_to include("spec/")
    end
  end

  context "README.md" do
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
        git("config --global --unset github.user")
        bundle "gem #{gem_name}"
      end

      it "contribute URL set to [USERNAME]" do
        expect(bundled_app("#{gem_name}/README.md").read).to include("[USERNAME]")
        expect(bundled_app("#{gem_name}/README.md").read).not_to include("github.com/bundleuser")
      end
    end

    describe "test task name on readme" do
      shared_examples_for "test task name on readme" do |framework, task_name|
        before do
          bundle "gem #{gem_name} --test=#{framework}"
        end

        it "renders with correct name" do
          expect(bundled_app("#{gem_name}/README.md").read).to include("Then, run `rake #{task_name}` to run the tests.")
        end
      end

      it_behaves_like "test task name on readme", "test-unit", "test"
      it_behaves_like "test task name on readme", "minitest", "test"
      it_behaves_like "test task name on readme", "rspec", "spec"
    end
  end

  it "creates a new git repository" do
    bundle "gem #{gem_name}"
    expect(bundled_app("#{gem_name}/.git")).to exist
  end

  context "when git is not available" do
    # This spec cannot have `git` available in the test env
    before do
      bundle "gem #{gem_name}", env: { "PATH" => "" }
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

    it "does not add .gitignore into ignore list" do
      expect(ignore_paths).not_to include(".gitignore")
    end
  end

  it "generates a valid gemspec" do
    bundle "gem newgem --bin"

    prepare_gemspec(bundled_app("newgem", "newgem.gemspec"))

    build_repo2 do
      build_dummy_irb "9.9.9"
    end
    gems = ["rake-#{rake_version}", "irb-9.9.9"]
    system_gems gems, path: system_gem_path, gem_repo: gem_repo2
    bundle "exec rake build", dir: bundled_app("newgem")

    expect(stdboth).not_to include("ERROR")
  end

  context "gem naming with relative paths" do
    it "resolves ." do
      create_temporary_dir("tmp")

      bundle "gem .", dir: bundled_app("tmp")

      expect(bundled_app("tmp/lib/tmp.rb")).to exist
    end

    it "resolves .." do
      create_temporary_dir("temp/empty_dir")

      bundle "gem ..", dir: bundled_app("temp/empty_dir")

      expect(bundled_app("temp/lib/temp.rb")).to exist
    end

    it "resolves relative directory" do
      create_temporary_dir("tmp/empty/tmp")

      bundle "gem ../../empty", dir: bundled_app("tmp/empty/tmp")

      expect(bundled_app("tmp/empty/lib/empty.rb")).to exist
    end

    def create_temporary_dir(dir)
      FileUtils.mkdir_p(bundled_app(dir))
    end
  end

  it "generates a gem skeleton" do
    bundle "gem #{gem_name}"

    expect(bundled_app("#{gem_name}/#{gem_name}.gemspec")).to exist
    expect(bundled_app("#{gem_name}/Gemfile")).to exist
    expect(bundled_app("#{gem_name}/Rakefile")).to exist
    expect(bundled_app("#{gem_name}/lib/#{gem_name}.rb")).to exist
    expect(bundled_app("#{gem_name}/lib/#{gem_name}/version.rb")).to exist
    expect(bundled_app("#{gem_name}/sig/#{gem_name}.rbs")).to exist
    expect(bundled_app("#{gem_name}/.gitignore")).to exist

    expect(bundled_app("#{gem_name}/bin/setup")).to exist
    expect(bundled_app("#{gem_name}/bin/console")).to exist

    unless Gem.win_platform?
      expect(bundled_app("#{gem_name}/bin/setup")).to be_executable
      expect(bundled_app("#{gem_name}/bin/console")).to be_executable
    end

    expect(bundled_app("#{gem_name}/bin/setup").read).to start_with("#!")
    expect(bundled_app("#{gem_name}/bin/console").read).to start_with("#!")
  end

  it "includes bin/ into ignore list" do
    bundle "gem #{gem_name}"

    expect(ignore_paths).to include("bin/")
  end

  it "includes Gemfile into ignore list" do
    bundle "gem #{gem_name}"

    expect(ignore_paths).to include("Gemfile")
  end

  it "includes .gitignore into ignore list" do
    bundle "gem #{gem_name}"

    expect(ignore_paths).to include(".gitignore")
  end

  it "starts with version 0.1.0" do
    bundle "gem #{gem_name}"

    expect(bundled_app("#{gem_name}/lib/#{gem_name}/version.rb").read).to match(/VERSION = "0.1.0"/)
  end

  it "declare String type for VERSION constant" do
    bundle "gem #{gem_name}"

    expect(bundled_app("#{gem_name}/sig/#{gem_name}.rbs").read).to match(/VERSION: String/)
  end

  context "git config user.{name,email} is set" do
    before do
      bundle "gem #{gem_name}"
    end

    it "sets gemspec author to git user.name if available" do
      expect(generated_gemspec.authors.first).to eq("Bundler User")
    end

    it "sets gemspec email to git user.email if available" do
      expect(generated_gemspec.email.first).to eq("user@example.com")
    end
  end

  context "git config user.{name,email} is not set" do
    before do
      git("config --global --unset user.name")
      git("config --global --unset user.email")
      bundle "gem #{gem_name}"
    end

    it "sets gemspec author to default message if git user.name is not set or empty" do
      expect(generated_gemspec.authors.first).to eq("TODO: Write your name")
    end

    it "sets gemspec email to default message if git user.email is not set or empty" do
      expect(generated_gemspec.email.first).to eq("TODO: Write your email address")
    end
  end

  it "sets gemspec metadata['allowed_push_host']" do
    bundle "gem #{gem_name}"

    expect(generated_gemspec.metadata["allowed_push_host"]).
      to match(/example\.com/)
  end

  it "includes a commented-out rubygems_mfa_required metadata hint" do
    bundle "gem #{gem_name}"

    gemspec_contents = bundled_app("#{gem_name}/#{gem_name}.gemspec").read

    expect(gemspec_contents).to include('# spec.metadata["rubygems_mfa_required"] = "true"')
    expect(gemspec_contents).to include("https://guides.rubygems.org/mfa-requirement-opt-in/")
  end

  it "sets a minimum ruby version" do
    bundle "gem #{gem_name}"

    expect(generated_gemspec.required_ruby_version.to_s).to start_with(">=")
  end

  it "does not include the gemspec file in files" do
    bundle "gem #{gem_name}"

    bundler_gemspec = Bundler::GemHelper.new(bundled_app(gem_name), gem_name).gemspec

    expect(bundler_gemspec.files).not_to include("#{gem_name}.gemspec")
  end

  it "does not include the Gemfile file in files" do
    bundle "gem #{gem_name}"

    bundler_gemspec = Bundler::GemHelper.new(bundled_app(gem_name), gem_name).gemspec

    expect(bundler_gemspec.files).not_to include("Gemfile")
  end

  it "runs rake without problems" do
    bundle "gem #{gem_name}"

    system_gems ["rake-#{rake_version}"]

    rakefile = <<~RAKEFILE
      task :default do
        puts 'SUCCESS'
      end
    RAKEFILE
    File.open(bundled_app("#{gem_name}/Rakefile"), "w") do |file|
      file.puts rakefile
    end

    sys_exec("rake", dir: bundled_app(gem_name))
    expect(out).to include("SUCCESS")
  end

  context "--exe parameter set" do
    before do
      bundle "gem #{gem_name} --exe"
    end

    it "builds exe skeleton" do
      expect(bundled_app("#{gem_name}/exe/#{gem_name}")).to exist
      unless Gem.win_platform?
        expect(bundled_app("#{gem_name}/exe/#{gem_name}")).to be_executable
      end
    end
  end

  context "--bin parameter set" do
    before do
      bundle "gem #{gem_name} --bin"
    end

    it "builds exe skeleton" do
      expect(bundled_app("#{gem_name}/exe/#{gem_name}")).to exist
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
      expect(bundled_app("#{gem_name}/spec/#{gem_name}_spec.rb")).to exist
      expect(bundled_app("#{gem_name}/spec/spec_helper.rb")).to exist
    end

    it "includes .rspec and spec/ into ignore list" do
      expect(ignore_paths).to include(".rspec")
      expect(ignore_paths).to include("spec/")
    end

    it "depends on a non-specific version of rspec in generated Gemfile" do
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      builder = Bundler::Dsl.new
      builder.eval_gemfile(bundled_app("#{gem_name}/Gemfile"))
      builder.dependencies
      rspec_dep = builder.dependencies.find {|d| d.name == "rspec" }
      expect(rspec_dep).not_to be_specific
      expect(rspec_dep.requirement).to eq(Gem::Requirement.new([">= 0"]))
    end
  end

  context "init_gems_rb setting to true" do
    before do
      bundle_config "init_gems_rb true"
      bundle "gem #{gem_name}"
    end

    it "generates gems.rb instead of Gemfile" do
      expect(bundled_app("#{gem_name}/gems.rb")).to exist
      expect(bundled_app("#{gem_name}/Gemfile")).to_not exist
    end

    it "includes gems.rb and gems.locked into ignore list" do
      expect(ignore_paths).to include("gems.rb")
      expect(ignore_paths).to include("gems.locked")
      expect(ignore_paths).not_to include("Gemfile")
    end
  end

  context "init_gems_rb setting to false" do
    before do
      bundle_config "init_gems_rb false"
      bundle "gem #{gem_name}"
    end

    it "generates Gemfile instead of gems.rb" do
      expect(bundled_app("#{gem_name}/gems.rb")).to_not exist
      expect(bundled_app("#{gem_name}/Gemfile")).to exist
    end

    it "includes Gemfile into ignore list" do
      expect(ignore_paths).to include("Gemfile")
      expect(ignore_paths).not_to include("gems.rb")
      expect(ignore_paths).not_to include("gems.locked")
    end
  end

  context "gem.test setting set to rspec" do
    before do
      bundle_config "gem.test rspec"
      bundle "gem #{gem_name}"
    end

    it "builds spec skeleton" do
      expect(bundled_app("#{gem_name}/.rspec")).to exist
      expect(bundled_app("#{gem_name}/spec/#{gem_name}_spec.rb")).to exist
      expect(bundled_app("#{gem_name}/spec/spec_helper.rb")).to exist
    end

    it "includes .rspec and spec/ into ignore list" do
      expect(ignore_paths).to include(".rspec")
      expect(ignore_paths).to include("spec/")
    end
  end

  context "gem.test setting set to rspec and --test is set to minitest" do
    before do
      bundle_config "gem.test rspec"
      bundle "gem #{gem_name} --test=minitest"
    end

    it "builds spec skeleton" do
      expect(bundled_app("#{gem_name}/test/test_#{gem_name}.rb")).to exist
      expect(bundled_app("#{gem_name}/test/test_helper.rb")).to exist
    end

    it "includes test/ into ignore list" do
      expect(ignore_paths).to include("test/")
    end
  end

  context "--test parameter set to minitest" do
    before do
      bundle "gem #{gem_name} --test=minitest"
    end

    it "depends on a non-specific version of minitest" do
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      builder = Bundler::Dsl.new
      builder.eval_gemfile(bundled_app("#{gem_name}/Gemfile"))
      builder.dependencies
      minitest_dep = builder.dependencies.find {|d| d.name == "minitest" }
      expect(minitest_dep).not_to be_specific
      expect(minitest_dep.requirement).to eq(Gem::Requirement.new([">= 0"]))
    end

    it "builds spec skeleton" do
      expect(bundled_app("#{gem_name}/test/test_#{gem_name}.rb")).to exist
      expect(bundled_app("#{gem_name}/test/test_helper.rb")).to exist
    end

    it "includes test/ into ignore list" do
      expect(ignore_paths).to include("test/")
    end

    it "creates a default rake task to run the test suite" do
      rakefile = <<~RAKEFILE
        # frozen_string_literal: true

        require "bundler/gem_tasks"
        require "minitest/test_task"

        Minitest::TestTask.create

        task default: :test
      RAKEFILE

      expect(bundled_app("#{gem_name}/Rakefile").read).to eq(rakefile)
    end
  end

  context "gem.test setting set to minitest" do
    before do
      bundle_config "gem.test minitest"
      bundle "gem #{gem_name}"
    end

    it "creates a default rake task to run the test suite" do
      rakefile = <<~RAKEFILE
        # frozen_string_literal: true

        require "bundler/gem_tasks"
        require "minitest/test_task"

        Minitest::TestTask.create

        task default: :test
      RAKEFILE

      expect(bundled_app("#{gem_name}/Rakefile").read).to eq(rakefile)
    end
  end

  context "--test parameter set to test-unit" do
    before do
      bundle "gem #{gem_name} --test=test-unit"
    end

    it "depends on a non-specific version of test-unit" do
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      builder = Bundler::Dsl.new
      builder.eval_gemfile(bundled_app("#{gem_name}/Gemfile"))
      builder.dependencies
      test_unit_dep = builder.dependencies.find {|d| d.name == "test-unit" }
      expect(test_unit_dep).not_to be_specific
      expect(test_unit_dep.requirement).to eq(Gem::Requirement.new([">= 0"]))
    end

    it "builds spec skeleton" do
      expect(bundled_app("#{gem_name}/test/#{gem_name}_test.rb")).to exist
      expect(bundled_app("#{gem_name}/test/test_helper.rb")).to exist
    end

    it "includes test/ into ignore list" do
      expect(ignore_paths).to include("test/")
    end

    it "creates a default rake task to run the test suite" do
      rakefile = <<~RAKEFILE
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

  context "--test parameter set to an invalid value" do
    before do
      bundle "gem #{gem_name} --test=foo", raise_on_error: false
    end

    it "fails loudly" do
      expect(last_command).to be_failure
      expect(err).to match(/Expected '--test' to be one of .*; got foo/)
    end
  end

  context "gem.test set to rspec and --test with no arguments" do
    before do
      bundle_config "gem.test rspec"
      bundle "gem #{gem_name} --test"
    end

    it "builds spec skeleton" do
      expect(bundled_app("#{gem_name}/.rspec")).to exist
      expect(bundled_app("#{gem_name}/spec/#{gem_name}_spec.rb")).to exist
      expect(bundled_app("#{gem_name}/spec/spec_helper.rb")).to exist
    end

    it "includes .rspec and spec/ into ignore list" do
      expect(ignore_paths).to include(".rspec")
      expect(ignore_paths).to include("spec/")
    end

    it "hints that --test is already configured" do
      expect(out).to match("rspec is already configured, ignoring --test flag.")
    end
  end

  context "gem.test setting set to false and --test with no arguments", :readline do
    before do
      bundle_config "gem.test false"
      bundle "gem #{gem_name} --test" do |input, _, _|
        input.puts
      end
    end

    it "asks to generate test files" do
      expect(out).to match("Do you want to generate tests with your gem?")
    end

    it "hints that the choice will only be applied to the current gem" do
      expect(out).to match("Your choice will only be applied to this gem.")
    end

    it_behaves_like "test framework is absent"
  end

  context "gem.test setting not set and --test with no arguments", :readline do
    before do
      bundle_config_global "BUNDLE_GEM__TEST" => nil
      bundle "gem #{gem_name} --test" do |input, _, _|
        input.puts
      end
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

  context "gem.test setting set to a test framework and --no-test" do
    before do
      bundle_config "gem.test rspec"
      bundle "gem #{gem_name} --no-test"
    end

    it_behaves_like "test framework is absent"
  end
end
