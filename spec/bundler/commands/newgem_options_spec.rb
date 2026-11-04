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
      git("config --global init.defaultBranch main")
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
    it "generates a gem skeleton with a CHANGELOG" do
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/CHANGELOG.md")).to exist
    end
  end

  shared_examples_for "--no-changelog flag" do
    before do
      bundle "gem #{gem_name} --no-changelog"
    end
    it "generates a gem skeleton without a CHANGELOG" do
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/CHANGELOG.md")).to_not exist
    end
  end

  shared_examples_for "--bundle flag" do
    before do
      bundle "gem #{gem_name} --bundle"
    end
    it "generates a gem skeleton with bundle install" do
      gem_skeleton_assertions
      expect(out).to include("Running bundle install in the new gem directory.")
    end
  end

  shared_examples_for "--no-bundle flag" do
    before do
      bundle "gem #{gem_name} --no-bundle"
    end
    it "generates a gem skeleton without bundle install" do
      gem_skeleton_assertions
      expect(out).to_not include("Running bundle install in the new gem directory.")
    end
  end

  shared_examples_for "--linter=rubocop flag" do
    before do
      bundle "gem #{gem_name} --linter=rubocop"
    end

    it "generates a gem skeleton with rubocop" do
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/Rakefile")).to read_as(
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
      expect(rubocop_dep).not_to be_specific
      expect(rubocop_dep.requirement).to eq(Gem::Requirement.new([">= 0"]))
    end

    it "generates a default .rubocop.yml" do
      expect(bundled_app("#{gem_name}/.rubocop.yml")).to exist
    end

    it "includes .rubocop.yml into ignore list" do
      expect(ignore_paths).to include(".rubocop.yml")
    end
  end

  shared_examples_for "--linter=standard flag" do
    before do
      bundle "gem #{gem_name} --linter=standard"
    end

    it "generates a gem skeleton with standard" do
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/Rakefile")).to read_as(
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
      expect(standard_dep).not_to be_specific
      expect(standard_dep.requirement).to eq(Gem::Requirement.new([">= 0"]))
    end

    it "generates a default .standard.yml" do
      expect(bundled_app("#{gem_name}/.standard.yml")).to exist
    end

    it "includes .standard.yml into ignore list" do
      expect(ignore_paths).to include(".standard.yml")
    end
  end

  shared_examples_for "--no-linter flag" do
    define_negated_matcher :exclude, :include

    before do
      bundle "gem #{gem_name} --no-linter"
    end

    it "generates a gem skeleton without rubocop" do
      gem_skeleton_assertions
      expect(bundled_app("#{gem_name}/Rakefile")).to read_as(exclude("rubocop"))
      expect(bundled_app("#{gem_name}/#{gem_name}.gemspec")).to read_as(exclude("rubocop"))
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

    it "does not add .rubocop.yml into ignore list" do
      expect(ignore_paths).not_to include(".rubocop.yml")
    end

    it "doesn't generate a default .standard.yml" do
      expect(bundled_app("#{gem_name}/.standard.yml")).to_not exist
    end

    it "does not add .standard.yml into ignore list" do
      expect(ignore_paths).not_to include(".standard.yml")
    end
  end

  shared_examples_for "CI config is absent" do
    it "does not create any CI files" do
      expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to_not exist
      expect(bundled_app("#{gem_name}/.gitlab-ci.yml")).to_not exist
      expect(bundled_app("#{gem_name}/.circleci/config.yml")).to_not exist
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
        bundle_config_global "gem.github_username different_username"
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
        bundle_config_global "gem.github_username false"
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

  context "--ci with no argument" do
    before do
      bundle "gem #{gem_name}"
    end

    it "does not generate any CI config" do
      expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to_not exist
      expect(bundled_app("#{gem_name}/.gitlab-ci.yml")).to_not exist
      expect(bundled_app("#{gem_name}/.circleci/config.yml")).to_not exist
    end

    it "does not add any CI config files into ignore list" do
      expect(ignore_paths).not_to include(".github/")
      expect(ignore_paths).not_to include(".gitlab-ci.yml")
      expect(ignore_paths).not_to include(".circleci/")
    end
  end

  context "--ci set to github" do
    before do
      bundle "gem #{gem_name} --ci=github"
    end

    it "generates a GitHub Actions config file" do
      expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to exist
    end

    it "includes .github/ into ignore list" do
      expect(ignore_paths).to include(".github/")
    end
  end

  context "--ci set to gitlab" do
    before do
      bundle "gem #{gem_name} --ci=gitlab"
    end

    it "generates a GitLab CI config file" do
      expect(bundled_app("#{gem_name}/.gitlab-ci.yml")).to exist
    end

    it "includes .gitlab-ci.yml into ignore list" do
      expect(ignore_paths).to include(".gitlab-ci.yml")
    end
  end

  context "--ci set to circle" do
    before do
      bundle "gem #{gem_name} --ci=circle"
    end

    it "generates a CircleCI config file" do
      expect(bundled_app("#{gem_name}/.circleci/config.yml")).to exist
    end

    it "includes .circleci/ into ignore list" do
      expect(ignore_paths).to include(".circleci/")
    end
  end

  context "--ci set to an invalid value" do
    before do
      bundle "gem #{gem_name} --ci=foo", raise_on_error: false
    end

    it "fails loudly" do
      expect(last_command).to be_failure
      expect(err).to match(/Expected '--ci' to be one of .*; got foo/)
    end
  end

  context "gem.ci setting set to none" do
    it "doesn't generate any CI config" do
      expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to_not exist
      expect(bundled_app("#{gem_name}/.gitlab-ci.yml")).to_not exist
      expect(bundled_app("#{gem_name}/.circleci/config.yml")).to_not exist
    end
  end

  context "gem.ci setting set to github" do
    it "generates a GitHub Actions config file" do
      bundle_config "gem.ci github"
      bundle "gem #{gem_name}"

      expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to exist
    end
  end

  context "gem.ci setting set to gitlab" do
    it "generates a GitLab CI config file" do
      bundle_config "gem.ci gitlab"
      bundle "gem #{gem_name}"

      expect(bundled_app("#{gem_name}/.gitlab-ci.yml")).to exist
    end
  end

  context "gem.ci setting set to circle" do
    it "generates a CircleCI config file" do
      bundle_config "gem.ci circle"
      bundle "gem #{gem_name}"

      expect(bundled_app("#{gem_name}/.circleci/config.yml")).to exist
    end
  end

  context "gem.ci set to github and --ci with no arguments" do
    before do
      bundle_config "gem.ci github"
      bundle "gem #{gem_name} --ci"
    end

    it "generates a GitHub Actions config file" do
      expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to exist
    end

    it "hints that --ci is already configured" do
      expect(out).to match("github is already configured, ignoring --ci flag.")
    end
  end

  context "gem.ci setting set to false and --ci with no arguments", :readline do
    before do
      bundle_config "gem.ci false"
      bundle "gem #{gem_name} --ci" do |input, _, _|
        input.puts "github"
      end
    end

    it "asks to setup CI" do
      expect(out).to match("Do you want to set up continuous integration for your gem?")
    end

    it "hints that the choice will only be applied to the current gem" do
      expect(out).to match("Your choice will only be applied to this gem.")
    end
  end

  context "gem.ci setting not set and --ci with no arguments", :readline do
    before do
      bundle_config_global "BUNDLE_GEM__CI" => nil
      bundle "gem #{gem_name} --ci" do |input, _, _|
        input.puts "github"
      end
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

  context "gem.ci setting set to a CI service and --no-ci" do
    before do
      bundle_config "gem.ci github"
      bundle "gem #{gem_name} --no-ci"
    end

    it "does not generate any CI config" do
      expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to_not exist
      expect(bundled_app("#{gem_name}/.gitlab-ci.yml")).to_not exist
      expect(bundled_app("#{gem_name}/.circleci/config.yml")).to_not exist
    end
  end

  context "--linter with no argument" do
    before do
      bundle "gem #{gem_name}"
    end

    it "does not generate any linter config" do
      expect(bundled_app("#{gem_name}/.rubocop.yml")).to_not exist
      expect(bundled_app("#{gem_name}/.standard.yml")).to_not exist
    end

    it "does not add any linter config files into ignore list" do
      expect(ignore_paths).not_to include(".rubocop.yml")
      expect(ignore_paths).not_to include(".standard.yml")
    end
  end

  context "--linter set to rubocop" do
    before do
      bundle "gem #{gem_name} --linter=rubocop"
    end

    it "generates a RuboCop config" do
      expect(bundled_app("#{gem_name}/.rubocop.yml")).to exist
      expect(bundled_app("#{gem_name}/.standard.yml")).to_not exist
    end

    it "includes .rubocop.yml into ignore list" do
      expect(ignore_paths).to include(".rubocop.yml")
      expect(ignore_paths).not_to include(".standard.yml")
    end
  end

  context "--linter set to standard" do
    before do
      bundle "gem #{gem_name} --linter=standard"
    end

    it "generates a Standard config" do
      expect(bundled_app("#{gem_name}/.standard.yml")).to exist
      expect(bundled_app("#{gem_name}/.rubocop.yml")).to_not exist
    end

    it "includes .standard.yml into ignore list" do
      expect(ignore_paths).to include(".standard.yml")
      expect(ignore_paths).not_to include(".rubocop.yml")
    end
  end

  context "--linter set to an invalid value" do
    before do
      bundle "gem #{gem_name} --linter=foo", raise_on_error: false
    end

    it "fails loudly" do
      expect(last_command).to be_failure
      expect(err).to match(/Expected '--linter' to be one of .*; got foo/)
    end
  end

  context "gem.linter setting set to none" do
    before do
      bundle "gem #{gem_name}"
    end

    it "doesn't generate any linter config" do
      expect(bundled_app("#{gem_name}/.rubocop.yml")).to_not exist
      expect(bundled_app("#{gem_name}/.standard.yml")).to_not exist
    end

    it "does not add any linter config files into ignore list" do
      expect(ignore_paths).not_to include(".rubocop.yml")
      expect(ignore_paths).not_to include(".standard.yml")
    end
  end

  context "gem.linter setting set to rubocop" do
    before do
      bundle_config "gem.linter rubocop"
      bundle "gem #{gem_name}"
    end

    it "generates a RuboCop config file" do
      expect(bundled_app("#{gem_name}/.rubocop.yml")).to exist
    end

    it "includes .rubocop.yml into ignore list" do
      expect(ignore_paths).to include(".rubocop.yml")
    end
  end

  context "gem.linter setting set to standard" do
    before do
      bundle_config "gem.linter standard"
      bundle "gem #{gem_name}"
    end

    it "generates a Standard config file" do
      expect(bundled_app("#{gem_name}/.standard.yml")).to exist
    end

    it "includes .standard.yml into ignore list" do
      expect(ignore_paths).to include(".standard.yml")
    end
  end

  context "gem.linter set to rubocop and --linter with no arguments" do
    before do
      bundle_config "gem.linter rubocop"
      bundle "gem #{gem_name} --linter"
    end

    it "generates a RuboCop config file" do
      expect(bundled_app("#{gem_name}/.rubocop.yml")).to exist
    end

    it "includes .rubocop.yml into ignore list" do
      expect(ignore_paths).to include(".rubocop.yml")
    end

    it "hints that --linter is already configured" do
      expect(out).to match("rubocop is already configured, ignoring --linter flag.")
    end
  end

  context "gem.linter setting set to false and --linter with no arguments", :readline do
    before do
      bundle_config "gem.linter false"
      bundle "gem #{gem_name} --linter" do |input, _, _|
        input.puts "rubocop"
      end
    end

    it "asks to setup a linter" do
      expect(out).to match("Do you want to add a code linter and formatter to your gem?")
    end

    it "hints that the choice will only be applied to the current gem" do
      expect(out).to match("Your choice will only be applied to this gem.")
    end
  end

  context "gem.linter setting not set and --linter with no arguments", :readline do
    before do
      bundle_config_global "BUNDLE_GEM__LINTER" => nil
      bundle "gem #{gem_name} --linter" do |input, _, _|
        input.puts "rubocop"
      end
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

  context "gem.linter setting set to a linter and --no-linter" do
    before do
      bundle_config "gem.linter rubocop"
      bundle "gem #{gem_name} --no-linter"
    end

    it "does not generate any linter config" do
      expect(bundled_app("#{gem_name}/.rubocop.yml")).to_not exist
      expect(bundled_app("#{gem_name}/.standard.yml")).to_not exist
    end

    it "does not add any linter config files into ignore list" do
      expect(ignore_paths).not_to include(".rubocop.yml")
      expect(ignore_paths).not_to include(".standard.yml")
    end
  end

  context "--edit option" do
    it "opens the generated gemspec in the user's text editor" do
      output = bundle "gem #{gem_name} --edit=echo"
      gemspec_path = File.join(bundled_app, gem_name, "#{gem_name}.gemspec")
      expect(output).to include("echo \"#{gemspec_path}\"")
    end
  end

  shared_examples_for "paths that depend on gem name" do
    it "generates entrypoint, version file and signatures file at the proper path, with the proper content" do
      bundle "gem #{gem_name}"

      expect(bundled_app("#{gem_name}/lib/#{require_path}.rb")).to exist
      expect(bundled_app("#{gem_name}/lib/#{require_path}.rb").read).to match(%r{require_relative "#{require_relative_path}/version"})
      expect(bundled_app("#{gem_name}/lib/#{require_path}.rb").read).to match(/class Error < StandardError; end$/)

      expect(bundled_app("#{gem_name}/lib/#{require_path}/version.rb")).to exist
      expect(bundled_app("#{gem_name}/sig/#{require_path}.rbs")).to exist
    end

    context "--exe parameter set" do
      before do
        bundle "gem #{gem_name} --exe"
      end

      it "builds an exe file that requires the proper entrypoint" do
        expect(bundled_app("#{gem_name}/exe/#{gem_name}")).to exist
        expect(bundled_app("#{gem_name}/exe/#{gem_name}").read).to match(/require "#{require_path}"/)
      end
    end

    context "--bin parameter set" do
      before do
        bundle "gem #{gem_name} --bin"
      end

      it "builds an exe file that requires the proper entrypoint" do
        expect(bundled_app("#{gem_name}/exe/#{gem_name}")).to exist
        expect(bundled_app("#{gem_name}/exe/#{gem_name}").read).to match(/require "#{require_path}"/)
      end
    end

    context "--test parameter set to rspec" do
      before do
        bundle "gem #{gem_name} --test=rspec"
      end

      it "builds a spec helper that requires the proper entrypoint, and a default test in the proper path which fails" do
        expect(bundled_app("#{gem_name}/spec/spec_helper.rb")).to exist
        expect(bundled_app("#{gem_name}/spec/spec_helper.rb").read).to include(%(require "#{require_path}"))
        expect(bundled_app("#{gem_name}/spec/#{require_path}_spec.rb")).to exist
        expect(bundled_app("#{gem_name}/spec/#{require_path}_spec.rb").read).to include("expect(false).to eq(true)")
      end
    end

    context "--test parameter set to minitest" do
      before do
        bundle "gem #{gem_name} --test=minitest"
      end

      it "builds a test helper that requires the proper entrypoint, and default test file in the proper path that defines the proper test class name, requires helper, and fails" do
        expect(bundled_app("#{gem_name}/test/test_helper.rb")).to exist
        expect(bundled_app("#{gem_name}/test/test_helper.rb").read).to include(%(require "#{require_path}"))

        expect(bundled_app("#{gem_name}/#{minitest_test_file_path}")).to exist
        expect(bundled_app("#{gem_name}/#{minitest_test_file_path}").read).to include(minitest_test_class_name)
        expect(bundled_app("#{gem_name}/#{minitest_test_file_path}").read).to include(%(require "test_helper"))
        expect(bundled_app("#{gem_name}/#{minitest_test_file_path}").read).to include("assert false")
      end
    end

    context "--test parameter set to test-unit" do
      before do
        bundle "gem #{gem_name} --test=test-unit"
      end

      it "builds a test helper that requires the proper entrypoint, and default test file in the proper path which requires helper and fails" do
        expect(bundled_app("#{gem_name}/test/test_helper.rb")).to exist
        expect(bundled_app("#{gem_name}/test/test_helper.rb").read).to include(%(require "#{require_path}"))
        expect(bundled_app("#{gem_name}/test/#{require_path}_test.rb")).to exist
        expect(bundled_app("#{gem_name}/test/#{require_path}_test.rb").read).to include(%(require "test_helper"))
        expect(bundled_app("#{gem_name}/test/#{require_path}_test.rb").read).to include("assert_equal(\"expected\", \"actual\")")
      end
    end
  end

  context "with mit option in bundle config settings set to true" do
    before do
      bundle_config_global "gem.mit true"
    end
    it_behaves_like "--mit flag"
    it_behaves_like "--no-mit flag"
  end

  context "with mit option in bundle config settings set to false" do
    before do
      bundle_config_global "gem.mit false"
    end
    it_behaves_like "--mit flag"
    it_behaves_like "--no-mit flag"
  end

  context "with coc option in bundle config settings set to true" do
    before do
      bundle_config_global "gem.coc true"
    end
    it_behaves_like "--coc flag"
    it_behaves_like "--no-coc flag"
  end

  context "with coc option in bundle config settings set to false" do
    before do
      bundle_config_global "gem.coc false"
    end
    it_behaves_like "--coc flag"
    it_behaves_like "--no-coc flag"
  end

  context "with rubocop option in bundle config settings set to true" do
    before do
      bundle_config_global "gem.rubocop true"
    end
    it_behaves_like "--linter=rubocop flag"
    it_behaves_like "--linter=standard flag"
    it_behaves_like "--no-linter flag"
  end

  context "with rubocop option in bundle config settings set to false" do
    before do
      bundle_config_global "gem.rubocop false"
    end
    it_behaves_like "--linter=rubocop flag"
    it_behaves_like "--linter=standard flag"
    it_behaves_like "--no-linter flag"
  end

  context "with linter option in bundle config settings set to rubocop" do
    before do
      bundle_config_global "gem.linter rubocop"
    end
    it_behaves_like "--linter=rubocop flag"
    it_behaves_like "--linter=standard flag"
    it_behaves_like "--no-linter flag"
  end

  context "with linter option in bundle config settings set to standard" do
    before do
      bundle_config_global "gem.linter standard"
    end
    it_behaves_like "--linter=rubocop flag"
    it_behaves_like "--linter=standard flag"
    it_behaves_like "--no-linter flag"
  end

  context "with linter option in bundle config settings set to false" do
    before do
      bundle_config_global "gem.linter false"
    end
    it_behaves_like "--linter=rubocop flag"
    it_behaves_like "--linter=standard flag"
    it_behaves_like "--no-linter flag"
  end

  context "with changelog option in bundle config settings set to true" do
    before do
      bundle_config_global "gem.changelog true"
    end
    it_behaves_like "--changelog flag"
    it_behaves_like "--no-changelog flag"
  end

  context "with changelog option in bundle config settings set to false" do
    before do
      bundle_config_global "gem.changelog false"
    end
    it_behaves_like "--changelog flag"
    it_behaves_like "--no-changelog flag"
  end

  context "with bundle option in bundle config settings set to true" do
    before do
      bundle_config_global "gem.bundle true"
    end
    it_behaves_like "--bundle flag"
    it_behaves_like "--no-bundle flag"

    it "runs bundle install" do
      bundle "gem #{gem_name}"
      expect(out).to include("Running bundle install in the new gem directory.")
    end
  end

  context "with bundle option in bundle config settings set to false" do
    before do
      bundle_config_global "gem.bundle false"
    end
    it_behaves_like "--bundle flag"
    it_behaves_like "--no-bundle flag"

    it "does not run bundle install" do
      bundle "gem #{gem_name}"
      expect(out).to_not include("Running bundle install in the new gem directory.")
    end
  end

  context "without git config github.user set" do
    before do
      git("config --global --unset github.user")
    end
    context "with github-username option in bundle config settings set to some value" do
      before do
        bundle_config_global "gem.github_username different_username"
      end
      it_behaves_like "--github-username option", "gh_user"
    end

    it_behaves_like "github_username configuration"

    context "with github-username option in bundle config settings set to false" do
      before do
        bundle_config_global "gem.github_username false"
      end
      it_behaves_like "--github-username option", "gh_user"
    end

    context "when changelog is enabled" do
      it "sets gemspec changelog_uri, homepage, homepage_uri, source_code_uri to TODOs" do
        bundle "gem #{gem_name} --changelog"

        expect(generated_gemspec.metadata["changelog_uri"]).
          to eq("TODO: Put your gem's CHANGELOG.md URL here.")
        expect(generated_gemspec.homepage).to eq("TODO: Put your gem's website or public repo URL here.")
        expect(generated_gemspec.metadata["homepage_uri"]).to eq("TODO: Put your gem's website or public repo URL here.")
        expect(generated_gemspec.metadata["source_code_uri"]).to eq("TODO: Put your gem's public repo URL here.")
      end
    end

    context "when changelog is not enabled" do
      it "sets gemspec homepage, homepage_uri, source_code_uri to TODOs and changelog_uri to nil" do
        bundle "gem #{gem_name}"

        expect(generated_gemspec.metadata["changelog_uri"]).to be_nil
        expect(generated_gemspec.homepage).to eq("TODO: Put your gem's website or public repo URL here.")
        expect(generated_gemspec.metadata["homepage_uri"]).to eq("TODO: Put your gem's website or public repo URL here.")
        expect(generated_gemspec.metadata["source_code_uri"]).to eq("TODO: Put your gem's public repo URL here.")
      end
    end
  end

  context "with git config github.user set" do
    context "with github-username option in bundle config settings set to some value" do
      before do
        bundle_config_global "gem.github_username different_username"
      end
      it_behaves_like "--github-username option", "gh_user"
    end

    it_behaves_like "github_username configuration"

    context "with github-username option in bundle config settings set to false" do
      before do
        bundle_config_global "gem.github_username false"
      end
      it_behaves_like "--github-username option", "gh_user"
    end

    context "when changelog is enabled" do
      it "sets gemspec changelog_uri, homepage, homepage_uri, source_code_uri based on git username" do
        bundle "gem #{gem_name} --changelog"

        expect(generated_gemspec.metadata["changelog_uri"]).
          to eq("https://github.com/bundleuser/#{gem_name}/blob/main/CHANGELOG.md")
        expect(generated_gemspec.homepage).to eq("https://github.com/bundleuser/#{gem_name}")
        expect(generated_gemspec.metadata["homepage_uri"]).to eq("https://github.com/bundleuser/#{gem_name}")
        expect(generated_gemspec.metadata["source_code_uri"]).to eq("https://github.com/bundleuser/#{gem_name}")
      end
    end

    context "when changelog is not enabled" do
      it "sets gemspec source_code_uri, homepage, homepage_uri but not changelog_uri" do
        bundle "gem #{gem_name}"

        expect(generated_gemspec.metadata["changelog_uri"]).to be_nil
        expect(generated_gemspec.homepage).to eq("https://github.com/bundleuser/#{gem_name}")
        expect(generated_gemspec.metadata["homepage_uri"]).to eq("https://github.com/bundleuser/#{gem_name}")
        expect(generated_gemspec.metadata["source_code_uri"]).to eq("https://github.com/bundleuser/#{gem_name}")
      end
    end
  end

  context "standard gem naming" do
    let(:require_path) { gem_name }

    let(:require_relative_path) { gem_name }

    let(:minitest_test_file_path) { "test/test_#{gem_name}.rb" }

    let(:minitest_test_class_name) { "class TestMygem < Minitest::Test" }

    include_examples "paths that depend on gem name"
  end

  context "gem naming with underscore" do
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

    include_examples "paths that depend on gem name"

    context "--ext parameter set with C" do
      let(:flags) { "--ext=c" }

      before do
        bundle ["gem", gem_name, flags].compact.join(" ")
      end

      it "builds ext skeleton" do
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/extconf.rb")).to exist
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/#{gem_name}.h")).to exist
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/#{gem_name}.c")).to exist
      end

      it "generates native extension loading code" do
        expect(bundled_app("#{gem_name}/lib/#{gem_name}.rb").read).to include(<<~RUBY)
          require_relative "test_gem/version"
          require "#{gem_name}/#{gem_name}"
        RUBY
      end

      it "includes rake-compiler, but no Rust related changes" do
        expect(bundled_app("#{gem_name}/Gemfile").read).to include('gem "rake-compiler"')

        expect(bundled_app("#{gem_name}/#{gem_name}.gemspec").read).to_not include('spec.add_dependency "rb_sys"')
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

    context "--ext parameter set with rust" do
      let(:flags) { "--ext=rust" }

      before do
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
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/build.rs")).to exist
      end

      it "includes rake-compiler and rb_sys gems constraint" do
        expect(bundled_app("#{gem_name}/Gemfile").read).to include('gem "rake-compiler"')
        expect(bundled_app("#{gem_name}/#{gem_name}.gemspec").read).to include('spec.add_dependency "rb_sys"')
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

      it "configures the crate such that `cargo test` works", :ruby_repo, :mri_only do
        env = setup_rust_env
        gem_path = bundled_app(gem_name)
        result = sys_exec("cargo test", env: env, dir: gem_path, timeout: 300)

        expect(result).to include("1 passed")
      end

      def setup_rust_env
        skip "rust toolchain of mingw is broken" if RUBY_PLATFORM.match?("mingw")

        env = {
          "CARGO_HOME" => ENV.fetch("CARGO_HOME", File.join(ENV["HOME"], ".cargo")),
          "RUSTUP_HOME" => ENV.fetch("RUSTUP_HOME", File.join(ENV["HOME"], ".rustup")),
          "RUSTUP_TOOLCHAIN" => ENV.fetch("RUSTUP_TOOLCHAIN", "stable"),
        }

        system(env, "cargo", "-V", out: IO::NULL, err: [:child, :out])
        skip "cargo not present" unless $?.success?
        # Hermetic Cargo setup
        RbConfig::CONFIG.each {|k, v| env["RBCONFIG_#{k}"] = v }
        env
      end
    end

    context "--ext parameter set with go" do
      let(:flags) { "--ext=go" }

      before do
        bundle ["gem", gem_name, flags].compact.join(" ")
      end

      after do
        sys_exec("go clean -modcache", raise_on_error: true) if installed_go?
      end

      it "is not deprecated" do
        expect(err).not_to include "[DEPRECATED] Option `--ext` without explicit value is deprecated."
      end

      it "builds ext skeleton" do
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/#{gem_name}.c")).to exist
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/#{gem_name}.go")).to exist
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/#{gem_name}.h")).to exist
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/extconf.rb")).to exist
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/go.mod")).to exist
      end

      it "includes extconf.rb in gem_name.gemspec" do
        expect(bundled_app("#{gem_name}/#{gem_name}.gemspec").read).to include(%(spec.extensions = ["ext/#{gem_name}/extconf.rb"]))
      end

      it "includes go_gem in gem_name.gemspec" do
        expect(bundled_app("#{gem_name}/#{gem_name}.gemspec").read).to include('spec.add_dependency "go_gem", ">= 0.2"')
      end

      it "includes go_gem extension in extconf.rb" do
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/extconf.rb").read).to include(<<~RUBY)
          require "mkmf"
          require "go_gem/mkmf"
        RUBY

        expect(bundled_app("#{gem_name}/ext/#{gem_name}/extconf.rb").read).to include(%(create_go_makefile("#{gem_name}/#{gem_name}")))
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/extconf.rb").read).not_to include("create_makefile")
      end

      it "includes go_gem extension in gem_name.c" do
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/#{gem_name}.c").read).to eq(<<~C)
          #include "#{gem_name}.h"
          #include "_cgo_export.h"
        C
      end

      it "includes skeleton code in gem_name.go" do
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/#{gem_name}.go").read).to include(<<~GO)
          /*
          #include "#{gem_name}.h"

          VALUE rb_#{gem_name}_sum(VALUE self, VALUE a, VALUE b);
          */
          import "C"
        GO

        expect(bundled_app("#{gem_name}/ext/#{gem_name}/#{gem_name}.go").read).to include(<<~GO)
          //export rb_#{gem_name}_sum
          func rb_#{gem_name}_sum(_ C.VALUE, a C.VALUE, b C.VALUE) C.VALUE {
        GO

        expect(bundled_app("#{gem_name}/ext/#{gem_name}/#{gem_name}.go").read).to include(<<~GO)
          //export Init_#{gem_name}
          func Init_#{gem_name}() {
        GO
      end

      it "includes valid module name in go.mod" do
        expect(bundled_app("#{gem_name}/ext/#{gem_name}/go.mod").read).to include("module github.com/bundleuser/#{gem_name}")
      end

      it "includes go_gem extension in Rakefile" do
        expect(bundled_app("#{gem_name}/Rakefile").read).to include(<<~RUBY)
          require "go_gem/rake_task"

          GoGem::RakeTask.new("#{gem_name}")
        RUBY
      end

      context "with --no-ci" do
        let(:flags) { "--ext=go --no-ci" }

        it_behaves_like "CI config is absent"
      end

      context "--ci set to github" do
        let(:flags) { "--ext=go --ci=github" }

        it "generates .github/workflows/main.yml" do
          expect(bundled_app("#{gem_name}/.github/workflows/main.yml")).to exist
          expect(bundled_app("#{gem_name}/.github/workflows/main.yml").read).to include("go-version-file: ext/#{gem_name}/go.mod")
        end
      end

      context "--ci set to circle" do
        let(:flags) { "--ext=go --ci=circle" }

        it "generates a .circleci/config.yml" do
          expect(bundled_app("#{gem_name}/.circleci/config.yml")).to exist

          expect(bundled_app("#{gem_name}/.circleci/config.yml").read).to include(<<-YAML.strip)
    environment:
      GO_VERSION:
          YAML

          expect(bundled_app("#{gem_name}/.circleci/config.yml").read).to include(<<-YAML)
      - run:
          name: Install Go
          command: |
            wget https://go.dev/dl/go$GO_VERSION.linux-amd64.tar.gz -O /tmp/go.tar.gz
            tar -C /usr/local -xzf /tmp/go.tar.gz
            echo 'export PATH=/usr/local/go/bin:"$PATH"' >> "$BASH_ENV"
          YAML
        end
      end

      context "--ci set to gitlab" do
        let(:flags) { "--ext=go --ci=gitlab" }

        it "generates a .gitlab-ci.yml" do
          expect(bundled_app("#{gem_name}/.gitlab-ci.yml")).to exist

          expect(bundled_app("#{gem_name}/.gitlab-ci.yml").read).to include(<<-YAML)
    - wget https://go.dev/dl/go$GO_VERSION.linux-amd64.tar.gz -O /tmp/go.tar.gz
    - tar -C /usr/local -xzf /tmp/go.tar.gz
    - export PATH=/usr/local/go/bin:$PATH
          YAML

          expect(bundled_app("#{gem_name}/.gitlab-ci.yml").read).to include(<<-YAML.strip)
  variables:
    GO_VERSION:
          YAML
        end
      end

      context "without github.user" do
        before do
          # FIXME: GitHub Actions Windows Runner hang up here for some reason...
          skip "Workaround for hung up" if Gem.win_platform?

          git("config --global --unset github.user")
          bundle ["gem", gem_name, flags].compact.join(" ")
        end

        it "includes valid module name in go.mod" do
          expect(bundled_app("#{gem_name}/ext/#{gem_name}/go.mod").read).to include("module github.com/username/#{gem_name}")
        end
      end
    end
  end

  context "gem naming with dashed" do
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

    include_examples "paths that depend on gem name"
  end

  describe "uncommon gem names" do
    it "can deal with two dashes" do
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

  describe "#ensure_safe_gem_name" do
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

    context "starting with a number" do
      subject { "1gem" }
      it { expect(err).to include("Invalid gem name #{subject}") }
    end

    context "including capital letter" do
      subject { "CAPITAL" }
      it "should warn but not error" do
        expect(err).to include("Gem names with capital letters are not recommended")
        expect(bundled_app("#{subject}/#{subject}.gemspec")).to exist
      end
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
      bundle_config_global "BUNDLE_GEM__TEST" => nil

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
      bundle_config_global "BUNDLE_GEM__CI" => nil

      bundle "gem foobar" do |input, _, _|
        input.puts "github"
      end

      expect(bundled_app("foobar/.github/workflows/main.yml")).to exist
    end

    it "asks about MIT license just once" do
      bundle_config_global "BUNDLE_GEM__MIT" => nil

      bundle "config list"

      bundle "gem foobar" do |input, _, _|
        input.puts "yes"
      end

      expect(bundled_app("foobar/LICENSE.txt")).to exist
      expect(out).to include("Using a MIT license means").once
    end

    it "asks about CoC just once" do
      bundle_config_global "BUNDLE_GEM__COC" => nil

      bundle "gem foobar" do |input, _, _|
        input.puts "yes"
      end

      expect(bundled_app("foobar/CODE_OF_CONDUCT.md")).to exist
      expect(out).to include("Codes of conduct can increase contributions to your project").once
    end

    it "asks about CHANGELOG just once" do
      bundle_config_global "BUNDLE_GEM__CHANGELOG" => nil

      bundle "gem foobar" do |input, _, _|
        input.puts "yes"
      end

      expect(bundled_app("foobar/CHANGELOG.md")).to exist
      expect(out).to include("A changelog is a file which contains").once
    end
  end

  context "on conflicts with a previously created file" do
    it "should fail gracefully" do
      FileUtils.touch(bundled_app("conflict-foobar"))
      bundle "gem conflict-foobar", raise_on_error: false
      expect(err).to eq("Couldn't create a new gem named `conflict-foobar` because there's an existing file named `conflict-foobar`.")
      expect(exitstatus).to eql(32)
    end
  end

  context "on conflicts with a previously created directory" do
    it "should succeed" do
      FileUtils.mkdir_p(bundled_app("conflict-foobar/Gemfile"))
      bundle "gem conflict-foobar"
      expect(out).to include("file_clash  conflict-foobar/Gemfile").
        and include "Initializing git repo in #{bundled_app("conflict-foobar")}"
    end
  end
end
