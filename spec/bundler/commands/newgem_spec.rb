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
    bundle "config set path #{rubocop_gems}", dir: bundled_app(gem_name)
    bundle "exec rubocop --debug --config .rubocop.yml", dir: bundled_app(gem_name)
  end

  def bundle_exec_standardrb
    prepare_gemspec(bundled_app(gem_name, "#{gem_name}.gemspec"))
    bundle "config set path #{standard_gems}", dir: bundled_app(gem_name)
    bundle "exec standardrb --debug", dir: bundled_app(gem_name)
  end

  let(:generated_gemspec) { Bundler.load_gemspec_uncached(bundled_app(gem_name).join("#{gem_name}.gemspec")) }

  let(:gem_name) { "mygem" }

  let(:require_path) { "mygem" }

  let(:minitest_test_file_path) { "test/test_mygem.rb" }

  let(:minitest_test_class_name) { "class TestMygem < Minitest::Test" }

  before do
    sys_exec("git config --global user.name 'Bundler User'")
    sys_exec("git config --global user.email user@example.com")
    sys_exec("git config --global github.user bundleuser")
  end

  describe "git repo initialization" do
    it "generates a gem skeleton with a .git folder", :readline do
      bundle "gem #{gem_name}"
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/.git")).to exist
    end

    it "generates a gem skeleton with a .git folder when passing --git", :readline do
      bundle "gem #{gem_name} --git"
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/.git")).to exist
    end

    it "generates a gem skeleton without a .git folder when passing --no-git", :readline do
      bundle "gem #{gem_name} --no-git"
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/.git")).not_to exist
    end

    context "on a path with spaces" do
      before do
        Dir.mkdir(bundled_app("path with spaces"))
      end

      it "properly initializes git repo", :readline do
        bundle "gem #{gem_name}", dir: bundled_app("path with spaces")
        expect(bundled_app("path with spaces/#{gem_name}/.git")).to exist
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
    it "generates a gem skeleton with MIT license" do
      bundle "gem #{gem_name} --coc"
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/CODE_OF_CONDUCT.md")).to exist
    end

    it "generates the README with a section for the Code of Conduct" do
      bundle "gem #{gem_name} --coc"
      expect(bundled_app("#{gem_name}/README.md").read).to include("## Code of Conduct")
      expect(bundled_app("#{gem_name}/README.md").read).to match(%r{https://github\.com/bundleuser/#{gem_name}/blob/.*/CODE_OF_CONDUCT.md})
    end

    it "generates the README with a section for the Code of Conduct, respecting the configured git default branch", git: ">= 2.28.0" do
      sys_exec("git config --global init.defaultBranch main")
      bundle "gem #{gem_name} --coc"

      expect(bundled_app("#{gem_name}/README.md").read).to include("## Code of Conduct")
      expect(bundled_app("#{gem_name}/README.md").read).to include("https://github.com/bundleuser/#{gem_name}/blob/main/CODE_OF_CONDUCT.md")
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

    it "generates the README without a section for the Code of Conduct" do
      expect(bundled_app("#{gem_name}/README.md").read).not_to include("## Code of Conduct")
      expect(bundled_app("#{gem_name}/README.md").read).not_to match(%r{https://github\.com/bundleuser/#{gem_name}/blob/.*/CODE_OF_CONDUCT.md})
    end
  end

  shared_examples_for "--changelog flag" do
    before do
      bundle "gem #{gem_name} --changelog"
    end
    it "generates a gem skeleton with a CHANGELOG", :readline do
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/CHANGELOG.md")).to exist
    end
  end

  shared_examples_for "--no-changelog flag" do
    before do
      bundle "gem #{gem_name} --no-changelog"
    end
    it "generates a gem skeleton without a CHANGELOG", :readline do
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/CHANGELOG.md")).to_not exist
    end
  end

  shared_examples_for "--rubocop flag" do
    context "is deprecated", bundler: "< 3" do
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
  end

  shared_examples_for "--no-rubocop flag" do
    context "is deprecated", bundler: "< 3" do
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
  end

  shared_examples_for "--linter=rubocop flag" do
    before do
      bundle "gem #{gem_name} --linter=rubocop"
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

  shared_examples_for "--linter=standard flag" do
    before do
      bundle "gem #{gem_name} --linter=standard"
    end

    it "generates a gem skeleton with standard" do
      gem_skeleton_assertions
      expect(bundled_app("test-gem/Rakefile")).to read_as(
        include('require "standard/rake"').
        and(match(/default:.+:standard/))
      )
    end

    it "includes standard in generated Gemfile" do
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      builder = Bundler::Dsl.new
      builder.eval_gemfile(bundled_app("#{gem_name}/Gemfile"))
      builder.dependencies
      standard_dep = builder.dependencies.find {|d| d.name == "standard" }
      expect(standard_dep).not_to be_nil
    end

    it "generates a default .standard.yml" do
      expect(bundled_app("#{gem_name}/.standard.yml")).to exist
    end
  end

  shared_examples_for "--linter=none flag" do
    define_negated_matcher :exclude, :include

    before do
      bundle "gem #{gem_name} --linter=none"
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

    it "does not include standard in generated Gemfile" do
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      builder = Bundler::Dsl.new
      builder.eval_gemfile(bundled_app("#{gem_name}/Gemfile"))
      builder.dependencies
      standard_dep = builder.dependencies.find {|d| d.name == "standard" }
      expect(standard_dep).to be_nil
    end

    it "doesn't generate a default .rubocop.yml" do
      expect(bundled_app("#{gem_name}/.rubocop.yml")).to_not exist
    end

    it "doesn't generate a default .standard.yml" do
      expect(bundled_app("#{gem_name}/.standard.yml")).to_not exist
    end
  end

  it "has no rubocop offenses when using --linter=rubocop flag", :readline do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    bundle "gem #{gem_name} --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  it "has no rubocop offenses when using --ext=c and --linter=rubocop flag", :readline do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    bundle "gem #{gem_name} --ext=c --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  it "has no rubocop offenses when using --ext=c, --test=minitest, and --linter=rubocop flag", :readline do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    bundle "gem #{gem_name} --ext=c --test=minitest --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  it "has no rubocop offenses when using --ext=c, --test=rspec, and --linter=rubocop flag", :readline do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    bundle "gem #{gem_name} --ext=c --test=rspec --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  it "has no rubocop offenses when using --ext=c, --test=test-unit, and --linter=rubocop flag", :readline do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    bundle "gem #{gem_name} --ext=c --test=test-unit --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  it "has no standard offenses when using --linter=standard flag", :readline do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    bundle "gem #{gem_name} --linter=standard"
    bundle_exec_standardrb
    expect(last_command).to be_success
  end

  it "has no rubocop offenses when using --ext=rust and --linter=rubocop flag", :readline do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    skip "RubyGems incompatible with Rust builder" if ::Gem::Version.new("3.3.11") > ::Gem.rubygems_version

    bundle "gem #{gem_name} --ext=rust --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  it "has no rubocop offenses when using --ext=rust, --test=minitest, and --linter=rubocop flag", :readline do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    skip "RubyGems incompatible with Rust builder" if ::Gem::Version.new("3.3.11") > ::Gem.rubygems_version

    bundle "gem #{gem_name} --ext=rust --test=minitest --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  it "has no rubocop offenses when using --ext=rust, --test=rspec, and --linter=rubocop flag", :readline do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    skip "RubyGems incompatible with Rust builder" if ::Gem::Version.new("3.3.11") > ::Gem.rubygems_version

    bundle "gem #{gem_name} --ext=rust --test=rspec --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  it "has no rubocop offenses when using --ext=rust, --test=test-unit, and --linter=rubocop flag", :readline do
    skip "ruby_core has an 'ast.rb' file that gets in the middle and breaks this spec" if ruby_core?
    skip "RubyGems incompatible with Rust builder" if ::Gem::Version.new("3.3.11") > ::Gem.rubygems_version

    bundle "gem #{gem_name} --ext=rust --test=test-unit --linter=rubocop"
    bundle_exec_rubocop
    expect(last_command).to be_success
  end

  shared_examples_for "CI config is absent" do
    it "does not create any CI files" do
      expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to_not exist
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
        sys_exec("git config --global --unset github.user")
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

      sys_exec "#{Gem.ruby} #{load_path_str} #{bindir.join("bundle")} gem #{gem_name}", env: { "PATH" => "" }
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
    path = Bundler.feature_flag.default_install_uses_path? ? local_gem_path(base: bundled_app("newgem")) : system_gem_path
    system_gems gems, path: path
    bundle "exec rake build", dir: bundled_app("newgem")

    expect(last_command.stdboth).not_to include("ERROR")
  end

  context "gem naming with relative paths", :readline do
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

  shared_examples_for "--github-username option" do |github_username|
    before do
      bundle "gem #{gem_name} --github-username=#{github_username}"
    end

    it "generates a gem skeleton" do
      gem_skeleton_assertions
    end

    it "contribute URL set to given github username" do
      expect(bundled_app("#{gem_name}/README.md").read).not_to include("[USERNAME]")
      expect(bundled_app("#{gem_name}/README.md").read).to include("github.com/#{github_username}")
    end
  end

  shared_examples_for "github_username configuration" do
    context "with github_username setting set to some value" do
      before do
        global_config "BUNDLE_GEM__GITHUB_USERNAME" => "different_username"
        bundle "gem #{gem_name}"
      end

      it "generates a gem skeleton" do
        gem_skeleton_assertions
      end

      it "contribute URL set to bundle config setting" do
        expect(bundled_app("#{gem_name}/README.md").read).not_to include("[USERNAME]")
        expect(bundled_app("#{gem_name}/README.md").read).to include("github.com/different_username")
      end
    end

    context "with github_username setting set to false" do
      before do
        global_config "BUNDLE_GEM__GITHUB_USERNAME" => "false"
        bundle "gem #{gem_name}"
      end

      it "generates a gem skeleton" do
        gem_skeleton_assertions
      end

      it "contribute URL set to [USERNAME]" do
        expect(bundled_app("#{gem_name}/README.md").read).to include("[USERNAME]")
        expect(bundled_app("#{gem_name}/README.md").read).not_to include("github.com/bundleuser")
      end
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
      expect(bundled_app("#{gem_name}/sig/#{require_path}.rbs")).to exist
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

    it "declare String type for VERSION constant" do
      bundle "gem #{gem_name}"

      expect(bundled_app("#{gem_name}/sig/#{require_path}.rbs").read).to match(/VERSION: String/)
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
        sys_exec("git config --global --unset user.name")
        sys_exec("git config --global --unset user.email")
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

    it "sets a minimum ruby version" do
      bundle "gem #{gem_name}"

      expect(generated_gemspec.required_ruby_version.to_s).to start_with(">=")
    end

    it "requires the version file" do
      bundle "gem #{gem_name}"

      expect(bundled_app("#{gem_name}/lib/#{require_path}.rb").read).to match(%r{require_relative "#{require_relative_path}/version"})
    end

    it "creates a base error class" do
      bundle "gem #{gem_name}"

      expect(bundled_app("#{gem_name}/lib/#{require_path}.rb").read).to match(/class Error < StandardError; end$/)
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

      system_gems ["rake-13.0.1"]

      rakefile = <<~RAKEFILE
        task :default do
          puts 'SUCCESS'
        end
      RAKEFILE
      File.open(bundled_app("#{gem_name}/Rakefile"), "w") do |file|
        file.puts rakefile
      end

      sys_exec(rake, dir: bundled_app(gem_name))
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
        expect(bundled_app("#{gem_name}/#{minitest_test_file_path}")).to exist
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
        expect(bundled_app("#{gem_name}/#{minitest_test_file_path}")).to exist
        expect(bundled_app("#{gem_name}/test/test_helper.rb")).to exist
      end

      it "requires the main file" do
        expect(bundled_app("#{gem_name}/test/test_helper.rb").read).to include(%(require "#{require_path}"))
      end

      it "requires 'test_helper'" do
        expect(bundled_app("#{gem_name}/#{minitest_test_file_path}").read).to include(%(require "test_helper"))
      end

      it "defines valid test class name" do
        expect(bundled_app("#{gem_name}/#{minitest_test_file_path}").read).to include(minitest_test_class_name)
      end

      it "creates a default test which fails" do
        expect(bundled_app("#{gem_name}/#{minitest_test_file_path}").read).to include("assert false")
      end
    end

    context "gem.test setting set to minitest" do
      before do
        bundle "config set gem.test minitest"
        bundle "gem #{gem_name}"
      end

      it "creates a default rake task to run the test suite" do
        rakefile = <<~RAKEFILE
          # frozen_string_literal: true

          require "bundler/gem_tasks"
          require "rake/testtask"

          Rake::TestTask.new(:test) do |t|
            t.libs << "test"
            t.libs << "lib"
            t.test_files = FileList["test/**/test_*.rb"]
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
        expect(bundled_app("#{gem_name}/.gitlab-ci.yml")).to_not exist
        expect(bundled_app("#{gem_name}/.circleci/config.yml")).to_not exist
      end
    end

    context "--ci set to travis" do
      it "generates a GitHub Actions config file" do
        bundle "gem #{gem_name} --ci=travis", raise_on_error: false
        expect(err).to include("Support for Travis CI was removed from gem skeleton generator.")

        expect(bundled_app("#{gem_name}/.travis.yml")).to_not exist
      end
    end

    context "--ci set to travis" do
      it "generates a GitHub Actions config file" do
        bundle "gem #{gem_name} --ci=travis", raise_on_error: false
        expect(err).to include("Support for Travis CI was removed from gem skeleton generator.")

        expect(bundled_app("#{gem_name}/.travis.yml")).to_not exist
      end
    end

    context "--ci set to github" do
      it "generates a GitHub Actions config file" do
        bundle "gem #{gem_name} --ci=github"

        expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to exist
      end

      it "contained .gitlab-ci.yml into ignore list" do
        bundle "gem #{gem_name} --ci=github"

        expect(bundled_app("#{gem_name}/#{gem_name}.gemspec").read).to include(".git .github appveyor")
      end
    end

    context "--ci set to gitlab" do
      it "generates a GitLab CI config file" do
        bundle "gem #{gem_name} --ci=gitlab"

        expect(bundled_app("#{gem_name}/.gitlab-ci.yml")).to exist
      end

      it "contained .gitlab-ci.yml into ignore list" do
        bundle "gem #{gem_name} --ci=gitlab"

        expect(bundled_app("#{gem_name}/#{gem_name}.gemspec").read).to include(".git .gitlab-ci.yml appveyor")
      end
    end

    context "--ci set to circle" do
      it "generates a CircleCI config file" do
        bundle "gem #{gem_name} --ci=circle"

        expect(bundled_app("#{gem_name}/.circleci/config.yml")).to exist
      end

      it "contained .circleci into ignore list" do
        bundle "gem #{gem_name} --ci=circle"

        expect(bundled_app("#{gem_name}/#{gem_name}.gemspec").read).to include(".git .circleci appveyor")
      end
    end

    context "gem.ci setting set to none" do
      it "doesn't generate any CI config" do
        expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to_not exist
        expect(bundled_app("#{gem_name}/.gitlab-ci.yml")).to_not exist
        expect(bundled_app("#{gem_name}/.circleci/config.yml")).to_not exist
      end
    end

    context "gem.ci setting set to travis" do
      it "errors with friendly message" do
        bundle "config set gem.ci travis"
        bundle "gem #{gem_name}", raise_on_error: false

        expect(err).to include("Support for Travis CI was removed from gem skeleton generator,")
        expect(err).to include("bundle config unset gem.ci")

        expect(bundled_app("#{gem_name}/.travis.yml")).to_not exist
      end
    end

    context "gem.ci setting set to github" do
      it "generates a GitHub Actions config file" do
        bundle "config set gem.ci github"
        bundle "gem #{gem_name}"

        expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to exist
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

    context "--linter with no argument" do
      it "does not generate any linter config" do
        bundle "gem #{gem_name}"

        expect(bundled_app("#{gem_name}/.rubocop.yml")).to_not exist
        expect(bundled_app("#{gem_name}/.standard.yml")).to_not exist
      end
    end

    context "--linter set to rubocop" do
      it "generates a RuboCop config" do
        bundle "gem #{gem_name} --linter=rubocop"

        expect(bundled_app("#{gem_name}/.rubocop.yml")).to exist
        expect(bundled_app("#{gem_name}/.standard.yml")).to_not exist
      end
    end

    context "--linter set to standard" do
      it "generates a Standard config" do
        bundle "gem #{gem_name} --linter=standard"

        expect(bundled_app("#{gem_name}/.standard.yml")).to exist
        expect(bundled_app("#{gem_name}/.rubocop.yml")).to_not exist
      end
    end

    context "gem.linter setting set to none" do
      it "doesn't generate any linter config" do
        bundle "gem #{gem_name}"

        expect(bundled_app("#{gem_name}/.rubocop.yml")).to_not exist
        expect(bundled_app("#{gem_name}/.standard.yml")).to_not exist
      end
    end

    context "gem.linter setting set to rubocop" do
      it "generates a RuboCop config file" do
        bundle "config set gem.linter rubocop"
        bundle "gem #{gem_name}"

        expect(bundled_app("#{gem_name}/.rubocop.yml")).to exist
      end
    end

    context "gem.linter setting set to standard" do
      it "generates a Standard config file" do
        bundle "config set gem.linter standard"
        bundle "gem #{gem_name}"

        expect(bundled_app("#{gem_name}/.standard.yml")).to exist
      end
    end

    context "gem.rubocop setting set to true", bundler: "< 3" do
      before do
        bundle "config set gem.rubocop true"
        bundle "gem #{gem_name}"
      end

      it "generates rubocop config" do
        expect(bundled_app("#{gem_name}/.rubocop.yml")).to exist
      end

      it "unsets gem.rubocop" do
        bundle "config gem.rubocop"
        expect(out).to include("You have not configured a value for `gem.rubocop`")
      end

      it "sets gem.linter=rubocop instead" do
        bundle "config gem.linter"
        expect(out).to match(/Set for the current user .*: "rubocop"/)
      end
    end

    context "gem.linter set to rubocop and --linter with no arguments", :hint_text do
      before do
        bundle "config set gem.linter rubocop"
        bundle "gem #{gem_name} --linter"
      end

      it "generates a RuboCop config file" do
        expect(bundled_app("#{gem_name}/.rubocop.yml")).to exist
      end

      it "hints that --linter is already configured" do
        expect(out).to match("rubocop is already configured, ignoring --linter flag.")
      end
    end

    context "gem.linter setting set to false and --linter with no arguments", :hint_text do
      before do
        bundle "config set gem.linter false"
        bundle "gem #{gem_name} --linter"
      end

      it "asks to setup a linter" do
        expect(out).to match("Do you want to add a code linter and formatter to your gem?")
      end

      it "hints that the choice will only be applied to the current gem" do
        expect(out).to match("Your choice will only be applied to this gem.")
      end
    end

    context "gem.linter setting not set and --linter with no arguments", :hint_text do
      before do
        bundle "gem #{gem_name} --linter"
      end

      it "asks to setup a linter" do
        expect(out).to match("Do you want to add a code linter and formatter to your gem?")
      end

      it "hints that the choice will be applied to future bundle gem calls" do
        hint = "Future `bundle gem` calls will use your choice. " \
               "This setting can be changed anytime with `bundle config gem.linter`."
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
      it_behaves_like "--linter=rubocop flag"
      it_behaves_like "--linter=standard flag"
      it_behaves_like "--linter=none flag"
      it_behaves_like "--rubocop flag"
      it_behaves_like "--no-rubocop flag"
    end

    context "with rubocop option in bundle config settings set to false" do
      before do
        global_config "BUNDLE_GEM__RUBOCOP" => "false"
      end
      it_behaves_like "--linter=rubocop flag"
      it_behaves_like "--linter=standard flag"
      it_behaves_like "--linter=none flag"
      it_behaves_like "--rubocop flag"
      it_behaves_like "--no-rubocop flag"
    end

    context "with linter option in bundle config settings set to rubocop" do
      before do
        global_config "BUNDLE_GEM__LINTER" => "rubocop"
      end
      it_behaves_like "--linter=rubocop flag"
      it_behaves_like "--linter=standard flag"
      it_behaves_like "--linter=none flag"
    end

    context "with linter option in bundle config settings set to standard" do
      before do
        global_config "BUNDLE_GEM__LINTER" => "standard"
      end
      it_behaves_like "--linter=rubocop flag"
      it_behaves_like "--linter=standard flag"
      it_behaves_like "--linter=none flag"
    end

    context "with linter option in bundle config settings set to false" do
      before do
        global_config "BUNDLE_GEM__LINTER" => "false"
      end
      it_behaves_like "--linter=rubocop flag"
      it_behaves_like "--linter=standard flag"
      it_behaves_like "--linter=none flag"
    end

    context "with changelog option in bundle config settings set to true" do
      before do
        global_config "BUNDLE_GEM__CHANGELOG" => "true"
      end
      it_behaves_like "--changelog flag"
      it_behaves_like "--no-changelog flag"
    end

    context "with changelog option in bundle config settings set to false" do
      before do
        global_config "BUNDLE_GEM__CHANGELOG" => "false"
      end
      it_behaves_like "--changelog flag"
      it_behaves_like "--no-changelog flag"
    end
  end

  context "testing --github-username option against git and bundle config settings", :readline do
    context "without git config set" do
      before do
        sys_exec("git config --global --unset github.user")
      end
      context "with github-username option in bundle config settings set to some value" do
        before do
          global_config "BUNDLE_GEM__GITHUB_USERNAME" => "different_username"
        end
        it_behaves_like "--github-username option", "gh_user"
      end

      context "with github-username option in bundle config settings set to false" do
        before do
          global_config "BUNDLE_GEM__GITHUB_USERNAME" => "false"
        end
        it_behaves_like "--github-username option", "gh_user"
      end
    end

    context "with git config set" do
      context "with github-username option in bundle config settings set to some value" do
        before do
          global_config "BUNDLE_GEM__GITHUB_USERNAME" => "different_username"
        end
        it_behaves_like "--github-username option", "gh_user"
      end

      context "with github-username option in bundle config settings set to false" do
        before do
          global_config "BUNDLE_GEM__GITHUB_USERNAME" => "false"
        end
        it_behaves_like "--github-username option", "gh_user"
      end
    end
  end

  context "testing github_username bundle config against git config settings", :readline do
    context "without git config set" do
      before do
        sys_exec("git config --global --unset github.user")
      end

      it_behaves_like "github_username configuration"
    end

    context "with git config set" do
      it_behaves_like "github_username configuration"
    end
  end

  context "gem naming with underscore", :readline do
    let(:gem_name) { "test_gem" }

    let(:require_path) { "test_gem" }

    let(:require_relative_path) { "test_gem" }

    let(:minitest_test_file_path) { "test/test_test_gem.rb" }

    let(:minitest_test_class_name) { "class TestTestGem < Minitest::Test" }

    let(:flags) { nil }

    it "does not nest constants" do
      bundle ["gem", gem_name, flags].compact.join(" ")
      expect(bundled_app("#{gem_name}/lib/#{require_path}/version.rb").read).to match(/module TestGem/)
      expect(bundled_app("#{gem_name}/lib/#{require_path}.rb").read).to match(/module TestGem/)
    end

    include_examples "generating a gem"

    context "--ext parameter with no value" do
      context "is deprecated", bundler: "< 3" do
        it "prints deprecation when used after gem name" do
          bundle ["gem", "--ext", gem_name].compact.join(" ")
          expect(err).to include "[DEPRECATED]"
          expect(err).to include "`--ext` with no arguments has been deprecated"
          expect(bundled_app("#{gem_name}/ext/#{gem_name}/#{gem_name}.c")).to exist
        end

        it "prints deprecation when used before gem name" do
          bundle ["gem", gem_name, "--ext"].compact.join(" ")
          expect(err).to include "[DEPRECATED]"
          expect(err).to include "`--ext` with no arguments has been deprecated"
          expect(bundled_app("#{gem_name}/ext/#{gem_name}/#{gem_name}.c")).to exist
        end
      end
    end

    context "--ext parameter set with C" do
      let(:flags) { "--ext=c" }

      before do
        bundle ["gem", gem_name, flags].compact.join(" ")
      end

      it "is not deprecated" do
        expect(err).not_to include "[DEPRECATED] Option `--ext` without explicit value is deprecated."
      end

      it "builds ext skeleton" do
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/extconf.rb")).to exist
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/#{gem_name}.h")).to exist
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/#{gem_name}.c")).to exist
      end

      it "includes rake-compiler, but no Rust related changes" do
        expect(bundled_app("#{gem_name}/Gemfile").read).to include('gem "rake-compiler"')

        expect(bundled_app("#{gem_name}/Gemfile").read).to_not include('gem "rb_sys"')
        expect(bundled_app("#{gem_name}/#{gem_name}.gemspec").read).to_not include('spec.required_rubygems_version = ">= ')
      end

      it "depends on compile task for build" do
        rakefile = <<~RAKEFILE
          # frozen_string_literal: true

          require "bundler/gem_tasks"
          require "rake/extensiontask"

          task build: :compile

          GEMSPEC = Gem::Specification.load("#{gem_name}.gemspec")

          Rake::ExtensionTask.new("#{gem_name}", GEMSPEC) do |ext|
            ext.lib_dir = "lib/#{gem_name}"
          end

          task default: %i[clobber compile]
        RAKEFILE

        expect(bundled_app("#{gem_name}/Rakefile").read).to eq(rakefile)
      end
    end

    context "--ext parameter set with rust and old RubyGems" do
      it "fails in friendly way" do
        if ::Gem::Version.new("3.3.11") <= ::Gem.rubygems_version
          skip "RubyGems compatible with Rust builder"
        end

        expect do
          bundle ["gem", gem_name, "--ext=rust"].compact.join(" ")
        end.to raise_error(RuntimeError, /too old to build Rust extension/)
      end
    end

    context "--ext parameter set with rust" do
      let(:flags) { "--ext=rust" }

      before do
        skip "RubyGems incompatible with Rust builder" if ::Gem::Version.new("3.3.11") > ::Gem.rubygems_version

        bundle ["gem", gem_name, flags].compact.join(" ")
      end

      it "is not deprecated" do
        expect(err).not_to include "[DEPRECATED] Option `--ext` without explicit value is deprecated."
      end

      it "builds ext skeleton" do
        expect(bundled_app("#{gem_name}/Cargo.toml")).to exist
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/Cargo.toml")).to exist
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/extconf.rb")).to exist
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/src/lib.rs")).to exist
      end

      it "includes rake-compiler, rb_sys gems and required_rubygems_version constraint" do
        expect(bundled_app("#{gem_name}/Gemfile").read).to include('gem "rake-compiler"')
        expect(bundled_app("#{gem_name}/Gemfile").read).to include('gem "rb_sys"')
        expect(bundled_app("#{gem_name}/#{gem_name}.gemspec").read).to include('spec.required_rubygems_version = ">= ')
      end

      it "depends on compile task for build" do
        rakefile = <<~RAKEFILE
          # frozen_string_literal: true

          require "bundler/gem_tasks"
          require "rb_sys/extensiontask"

          task build: :compile

          GEMSPEC = Gem::Specification.load("#{gem_name}.gemspec")

          RbSys::ExtensionTask.new("#{gem_name}", GEMSPEC) do |ext|
            ext.lib_dir = "lib/#{gem_name}"
          end

          task default: :compile
        RAKEFILE

        expect(bundled_app("#{gem_name}/Rakefile").read).to eq(rakefile)
      end
    end
  end

  context "gem naming with dashed", :readline do
    let(:gem_name) { "test-gem" }

    let(:require_path) { "test/gem" }

    let(:require_relative_path) { "gem" }

    let(:minitest_test_file_path) { "test/test/test_gem.rb" }

    let(:minitest_test_class_name) { "class Test::TestGem < Minitest::Test" }

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
      bundle "gem foo.gemspec", raise_on_error: false
      expect(err).to end_with("Invalid gem name foo.gemspec -- `Foo.gemspec` is an invalid constant name")
    end

    it "fails gracefully with a ^" do
      bundle "gem ^", raise_on_error: false
      expect(err).to end_with("Invalid gem name ^ -- `^` is an invalid constant name")
    end

    it "fails gracefully with a space" do
      bundle "gem 'foo bar'", raise_on_error: false
      expect(err).to end_with("Invalid gem name foo bar -- `Foo bar` is an invalid constant name")
    end

    it "fails gracefully when multiple names are passed" do
      bundle "gem foo bar baz", raise_on_error: false
      expect(err).to eq(<<-E.strip)
ERROR: "bundle gem" was called with arguments ["foo", "bar", "baz"]
Usage: "bundle gem NAME [OPTIONS]"
      E
    end
  end

  describe "#ensure_safe_gem_name", :readline do
    before do
      bundle "gem #{subject}", raise_on_error: false
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
      rakefile = <<~RAKEFILE
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
      global_config "BUNDLE_GEM__TEST" => "false", "BUNDLE_GEM__MIT" => "false", "BUNDLE_GEM__COC" => "false", "BUNDLE_GEM__LINTER" => "false"

      bundle "gem foobar" do |input, _, _|
        input.puts "github"
      end

      expect(bundled_app("foobar/.github/workflows/main.yml")).to exist
    end

    it "asks about MIT license" do
      global_config "BUNDLE_GEM__TEST" => "false", "BUNDLE_GEM__COC" => "false", "BUNDLE_GEM__CI" => "false", "BUNDLE_GEM__LINTER" => "false"

      bundle "config list"

      bundle "gem foobar" do |input, _, _|
        input.puts "yes"
      end

      expect(bundled_app("foobar/LICENSE.txt")).to exist
    end

    it "asks about CoC" do
      global_config "BUNDLE_GEM__MIT" => "false", "BUNDLE_GEM__TEST" => "false", "BUNDLE_GEM__CI" => "false", "BUNDLE_GEM__LINTER" => "false"

      bundle "gem foobar" do |input, _, _|
        input.puts "yes"
      end

      expect(bundled_app("foobar/CODE_OF_CONDUCT.md")).to exist
    end

    it "asks about CHANGELOG" do
      global_config "BUNDLE_GEM__MIT" => "false", "BUNDLE_GEM__TEST" => "false", "BUNDLE_GEM__CI" => "false", "BUNDLE_GEM__LINTER" => "false",
                    "BUNDLE_GEM__COC" => "false"

      bundle "gem foobar" do |input, _, _|
        input.puts "yes"
      end

      expect(bundled_app("foobar/CHANGELOG.md")).to exist
    end
  end

  context "on conflicts with a previously created file", :readline do
    it "should fail gracefully" do
      FileUtils.touch(bundled_app("conflict-foobar"))
      bundle "gem conflict-foobar", raise_on_error: false
      expect(err).to eq("Couldn't create a new gem named `conflict-foobar` because there's an existing file named `conflict-foobar`.")
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
