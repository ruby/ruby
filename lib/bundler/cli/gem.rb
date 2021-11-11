# frozen_string_literal: true

require "pathname"

module Bundler
  class CLI
    Bundler.require_thor_actions
    include Thor::Actions
  end

  class CLI::Gem
    TEST_FRAMEWORK_VERSIONS = {
      "rspec" => "3.0",
      "minitest" => "5.0",
      "test-unit" => "3.0",
    }.freeze

    attr_reader :options, :gem_name, :thor, :name, :target

    def initialize(options, gem_name, thor)
      @options = options
      @gem_name = resolve_name(gem_name)

      @thor = thor
      thor.behavior = :invoke
      thor.destination_root = nil

      @name = @gem_name
      @target = SharedHelpers.pwd.join(gem_name)

      validate_ext_name if options[:ext]
    end

    def run
      Bundler.ui.confirm "Creating gem '#{name}'..."

      underscored_name = name.tr("-", "_")
      namespaced_path = name.tr("-", "/")
      constant_name = name.gsub(/-[_-]*(?![_-]|$)/) { "::" }.gsub(/([_-]+|(::)|^)(.|$)/) { $2.to_s + $3.upcase }
      constant_array = constant_name.split("::")

      use_git = Bundler.git_present? && options[:git]

      git_author_name = use_git ? `git config user.name`.chomp : ""
      git_username = use_git ? `git config github.user`.chomp : ""
      git_user_email = use_git ? `git config user.email`.chomp : ""

      github_username = if options[:github_username].nil?
        git_username
      elsif options[:github_username] == false
        ""
      else
        options[:github_username]
      end

      config = {
        :name             => name,
        :underscored_name => underscored_name,
        :namespaced_path  => namespaced_path,
        :makefile_path    => "#{underscored_name}/#{underscored_name}",
        :constant_name    => constant_name,
        :constant_array   => constant_array,
        :author           => git_author_name.empty? ? "TODO: Write your name" : git_author_name,
        :email            => git_user_email.empty? ? "TODO: Write your email address" : git_user_email,
        :test             => options[:test],
        :ext              => options[:ext],
        :exe              => options[:exe],
        :bundler_version  => bundler_dependency_version,
        :git              => use_git,
        :github_username  => github_username.empty? ? "[USERNAME]" : github_username,
        :required_ruby_version => required_ruby_version,
      }
      ensure_safe_gem_name(name, constant_array)

      templates = {
        "#{Bundler.preferred_gemfile_name}.tt" => Bundler.preferred_gemfile_name,
        "lib/newgem.rb.tt" => "lib/#{namespaced_path}.rb",
        "lib/newgem/version.rb.tt" => "lib/#{namespaced_path}/version.rb",
        "newgem.gemspec.tt" => "#{name}.gemspec",
        "Rakefile.tt" => "Rakefile",
        "README.md.tt" => "README.md",
        "bin/console.tt" => "bin/console",
        "bin/setup.tt" => "bin/setup",
      }

      executables = %w[
        bin/console
        bin/setup
      ]

      templates.merge!("gitignore.tt" => ".gitignore") if use_git

      if test_framework = ask_and_set_test_framework
        config[:test] = test_framework
        config[:test_framework_version] = TEST_FRAMEWORK_VERSIONS[test_framework]

        case test_framework
        when "rspec"
          templates.merge!(
            "rspec.tt" => ".rspec",
            "spec/spec_helper.rb.tt" => "spec/spec_helper.rb",
            "spec/newgem_spec.rb.tt" => "spec/#{namespaced_path}_spec.rb"
          )
          config[:test_task] = :spec
        when "minitest"
          templates.merge!(
            "test/minitest/test_helper.rb.tt" => "test/test_helper.rb",
            "test/minitest/newgem_test.rb.tt" => "test/#{namespaced_path}_test.rb"
          )
          config[:test_task] = :test
        when "test-unit"
          templates.merge!(
            "test/test-unit/test_helper.rb.tt" => "test/test_helper.rb",
            "test/test-unit/newgem_test.rb.tt" => "test/#{namespaced_path}_test.rb"
          )
          config[:test_task] = :test
        end
      end

      config[:ci] = ask_and_set_ci
      case config[:ci]
      when "github"
        templates.merge!("github/workflows/main.yml.tt" => ".github/workflows/main.yml")
      when "travis"
        templates.merge!("travis.yml.tt" => ".travis.yml")
      when "gitlab"
        templates.merge!("gitlab-ci.yml.tt" => ".gitlab-ci.yml")
      when "circle"
        templates.merge!("circleci/config.yml.tt" => ".circleci/config.yml")
      end

      if ask_and_set(:mit, "Do you want to license your code permissively under the MIT license?",
        "This means that any other developer or company will be legally allowed to use your code " \
        "for free as long as they admit you created it. You can read more about the MIT license " \
        "at https://choosealicense.com/licenses/mit.")
        config[:mit] = true
        Bundler.ui.info "MIT License enabled in config"
        templates.merge!("LICENSE.txt.tt" => "LICENSE.txt")
      end

      if ask_and_set(:coc, "Do you want to include a code of conduct in gems you generate?",
        "Codes of conduct can increase contributions to your project by contributors who " \
        "prefer collaborative, safe spaces. You can read more about the code of conduct at " \
        "contributor-covenant.org. Having a code of conduct means agreeing to the responsibility " \
        "of enforcing it, so be sure that you are prepared to do that. Be sure that your email " \
        "address is specified as a contact in the generated code of conduct so that people know " \
        "who to contact in case of a violation. For suggestions about " \
        "how to enforce codes of conduct, see https://bit.ly/coc-enforcement.")
        config[:coc] = true
        Bundler.ui.info "Code of conduct enabled in config"
        templates.merge!("CODE_OF_CONDUCT.md.tt" => "CODE_OF_CONDUCT.md")
      end

      if ask_and_set(:changelog, "Do you want to include a changelog?",
        "A changelog is a file which contains a curated, chronologically ordered list of notable " \
        "changes for each version of a project. To make it easier for users and contributors to" \
        " see precisely what notable changes have been made between each release (or version) of" \
        " the project. Whether consumers or developers, the end users of software are" \
        " human beings who care about what's in the software. When the software changes, people " \
        "want to know why and how. see https://keepachangelog.com")
        config[:changelog] = true
        Bundler.ui.info "Changelog enabled in config"
        templates.merge!("CHANGELOG.md.tt" => "CHANGELOG.md")
      end

      if ask_and_set(:rubocop, "Do you want to add rubocop as a dependency for gems you generate?",
        "RuboCop is a static code analyzer that has out-of-the-box rules for many " \
        "of the guidelines in the community style guide. " \
        "For more information, see the RuboCop docs (https://docs.rubocop.org/en/stable/) " \
        "and the Ruby Style Guides (https://github.com/rubocop-hq/ruby-style-guide).")
        config[:rubocop] = true
        config[:rubocop_version] = rubocop_version
        Bundler.ui.info "RuboCop enabled in config"
        templates.merge!("rubocop.yml.tt" => ".rubocop.yml")
      end

      templates.merge!("exe/newgem.tt" => "exe/#{name}") if config[:exe]

      if options[:ext]
        templates.merge!(
          "ext/newgem/extconf.rb.tt" => "ext/#{name}/extconf.rb",
          "ext/newgem/newgem.h.tt" => "ext/#{name}/#{underscored_name}.h",
          "ext/newgem/newgem.c.tt" => "ext/#{name}/#{underscored_name}.c"
        )
      end

      if target.exist? && !target.directory?
        Bundler.ui.error "Couldn't create a new gem named `#{gem_name}` because there's an existing file named `#{gem_name}`."
        exit Bundler::BundlerError.all_errors[Bundler::GenericSystemCallError]
      end

      if use_git
        Bundler.ui.info "Initializing git repo in #{target}"
        require "shellwords"
        `git init #{target.to_s.shellescape}`

        config[:git_default_branch] = File.read("#{target}/.git/HEAD").split("/").last.chomp
      end

      templates.each do |src, dst|
        destination = target.join(dst)
        thor.template("newgem/#{src}", destination, config)
      end

      executables.each do |file|
        path = target.join(file)
        executable = (path.stat.mode | 0o111)
        path.chmod(executable)
      end

      if use_git
        Dir.chdir(target) do
          `git add .`
        end
      end

      # Open gemspec in editor
      open_editor(options["edit"], target.join("#{name}.gemspec")) if options[:edit]

      Bundler.ui.info "Gem '#{name}' was successfully created. " \
        "For more information on making a RubyGem visit https://bundler.io/guides/creating_gem.html"
    end

    private

    def resolve_name(name)
      SharedHelpers.pwd.join(name).basename.to_s
    end

    def ask_and_set(key, header, message)
      choice = options[key]
      choice = Bundler.settings["gem.#{key}"] if choice.nil?

      if choice.nil?
        Bundler.ui.confirm header
        choice = Bundler.ui.yes? "#{message} y/(n):"
        Bundler.settings.set_global("gem.#{key}", choice)
      end

      choice
    end

    def validate_ext_name
      return unless gem_name.index("-")

      Bundler.ui.error "You have specified a gem name which does not conform to the \n" \
                       "naming guidelines for C extensions. For more information, \n" \
                       "see the 'Extension Naming' section at the following URL:\n" \
                       "https://guides.rubygems.org/gems-with-extensions/\n"
      exit 1
    end

    def ask_and_set_test_framework
      test_framework = options[:test] || Bundler.settings["gem.test"]

      if test_framework.to_s.empty?
        Bundler.ui.confirm "Do you want to generate tests with your gem?"
        Bundler.ui.info hint_text("test")

        result = Bundler.ui.ask "Enter a test framework. rspec/minitest/test-unit/(none):"
        if result =~ /rspec|minitest|test-unit/
          test_framework = result
        else
          test_framework = false
        end
      end

      if Bundler.settings["gem.test"].nil?
        Bundler.settings.set_global("gem.test", test_framework)
      end

      if options[:test] == Bundler.settings["gem.test"]
        Bundler.ui.info "#{options[:test]} is already configured, ignoring --test flag."
      end

      test_framework
    end

    def hint_text(setting)
      if Bundler.settings["gem.#{setting}"] == false
        "Your choice will only be applied to this gem."
      else
        "Future `bundle gem` calls will use your choice. " \
        "This setting can be changed anytime with `bundle config gem.#{setting}`."
      end
    end

    def ask_and_set_ci
      ci_template = options[:ci] || Bundler.settings["gem.ci"]

      if ci_template.to_s.empty?
        Bundler.ui.confirm "Do you want to set up continuous integration for your gem? " \
          "Supported services:\n" \
          "* CircleCI:       https://circleci.com/\n" \
          "* GitHub Actions: https://github.com/features/actions\n" \
          "* GitLab CI:      https://docs.gitlab.com/ee/ci/\n" \
          "* Travis CI:      https://travis-ci.org/\n" \
          "\n"
        Bundler.ui.info hint_text("ci")

        result = Bundler.ui.ask "Enter a CI service. github/travis/gitlab/circle/(none):"
        if result =~ /github|travis|gitlab|circle/
          ci_template = result
        else
          ci_template = false
        end
      end

      if Bundler.settings["gem.ci"].nil?
        Bundler.settings.set_global("gem.ci", ci_template)
      end

      if options[:ci] == Bundler.settings["gem.ci"]
        Bundler.ui.info "#{options[:ci]} is already configured, ignoring --ci flag."
      end

      ci_template
    end

    def bundler_dependency_version
      v = Gem::Version.new(Bundler::VERSION)
      req = v.segments[0..1]
      req << "a" if v.prerelease?
      req.join(".")
    end

    def ensure_safe_gem_name(name, constant_array)
      if name =~ /^\d/
        Bundler.ui.error "Invalid gem name #{name} Please give a name which does not start with numbers."
        exit 1
      end

      constant_name = constant_array.join("::")

      existing_constant = constant_array.inject(Object) do |c, s|
        defined = begin
          c.const_defined?(s)
        rescue NameError
          Bundler.ui.error "Invalid gem name #{name} -- `#{constant_name}` is an invalid constant name"
          exit 1
        end
        (defined && c.const_get(s)) || break
      end

      return unless existing_constant
      Bundler.ui.error "Invalid gem name #{name} constant #{constant_name} is already in use. Please choose another gem name."
      exit 1
    end

    def open_editor(editor, file)
      thor.run(%(#{editor} "#{file}"))
    end

    def required_ruby_version
      if Gem.ruby_version < Gem::Version.new("2.4.a") then "2.3.0"
      elsif Gem.ruby_version < Gem::Version.new("2.5.a") then "2.4.0"
      elsif Gem.ruby_version < Gem::Version.new("2.6.a") then "2.5.0"
      else
        "2.6.0"
      end
    end

    def rubocop_version
      if Gem.ruby_version < Gem::Version.new("2.4.a") then "0.81.0"
      elsif Gem.ruby_version < Gem::Version.new("2.5.a") then "1.12"
      else
        "1.21"
      end
    end
  end
end
