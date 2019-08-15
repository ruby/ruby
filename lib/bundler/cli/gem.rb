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

      git_installed = Bundler.git_present?

      git_author_name = git_installed ? `git config user.name`.chomp : ""
      github_username = git_installed ? `git config github.user`.chomp : ""
      git_user_email = git_installed ? `git config user.email`.chomp : ""

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
        :github_username  => github_username.empty? ? "[USERNAME]" : github_username,
      }
      ensure_safe_gem_name(name, constant_array)

      templates = {
        "Gemfile.tt" => "Gemfile",
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

      templates.merge!("gitignore.tt" => ".gitignore") if Bundler.git_present?

      if test_framework = ask_and_set_test_framework
        config[:test] = test_framework
        config[:test_framework_version] = TEST_FRAMEWORK_VERSIONS[test_framework]

        templates.merge!("travis.yml.tt" => ".travis.yml")

        case test_framework
        when "rspec"
          templates.merge!(
            "rspec.tt" => ".rspec",
            "spec/spec_helper.rb.tt" => "spec/spec_helper.rb",
            "spec/newgem_spec.rb.tt" => "spec/#{namespaced_path}_spec.rb"
          )
        when "minitest"
          templates.merge!(
            "test/test_helper.rb.tt" => "test/test_helper.rb",
            "test/newgem_test.rb.tt" => "test/#{namespaced_path}_test.rb"
          )
        end
      end

      config[:test_task] = config[:test] == "minitest" ? "test" : "spec"

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

      templates.merge!("exe/newgem.tt" => "exe/#{name}") if config[:exe]

      if options[:ext]
        templates.merge!(
          "ext/newgem/extconf.rb.tt" => "ext/#{name}/extconf.rb",
          "ext/newgem/newgem.h.tt" => "ext/#{name}/#{underscored_name}.h",
          "ext/newgem/newgem.c.tt" => "ext/#{name}/#{underscored_name}.c"
        )
      end

      templates.each do |src, dst|
        destination = target.join(dst)
        SharedHelpers.filesystem_access(destination) do
          thor.template("newgem/#{src}", destination, config)
        end
      end

      executables.each do |file|
        SharedHelpers.filesystem_access(target.join(file)) do |path|
          executable = (path.stat.mode | 0o111)
          path.chmod(executable)
        end
      end

      if Bundler.git_present?
        Bundler.ui.info "Initializing git repo in #{target}"
        Dir.chdir(target) do
          `git init`
          `git add .`
        end
      end

      # Open gemspec in editor
      open_editor(options["edit"], target.join("#{name}.gemspec")) if options[:edit]

      Bundler.ui.info "Gem '#{name}' was successfully created. " \
        "For more information on making a RubyGem visit https://bundler.io/guides/creating_gem.html"
    rescue Errno::EEXIST => e
      raise GenericSystemCallError.new(e, "There was a conflict while creating the new gem.")
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
                       "http://guides.rubygems.org/gems-with-extensions/\n"
      exit 1
    end

    def ask_and_set_test_framework
      test_framework = options[:test] || Bundler.settings["gem.test"]

      if test_framework.nil?
        Bundler.ui.confirm "Do you want to generate tests with your gem?"
        result = Bundler.ui.ask "Type 'rspec' or 'minitest' to generate those test files now and " \
          "in the future. rspec/minitest/(none):"
        if result =~ /rspec|minitest/
          test_framework = result
        else
          test_framework = false
        end
      end

      if Bundler.settings["gem.test"].nil?
        Bundler.settings.set_global("gem.test", test_framework)
      end

      test_framework
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
  end
end
