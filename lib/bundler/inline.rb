# frozen_string_literal: true

# Allows for declaring a Gemfile inline in a ruby script, optionally installing
# any gems that aren't already installed on the user's system.
#
# @note Every gem that is specified in this 'Gemfile' will be `require`d, as if
#       the user had manually called `Bundler.require`. To avoid a requested gem
#       being automatically required, add the `:require => false` option to the
#       `gem` dependency declaration.
#
# @param install [Boolean] whether gems that aren't already installed on the
#                          user's system should be installed.
#                          Defaults to `false`.
#
# @param gemfile [Proc]    a block that is evaluated as a `Gemfile`.
#
# @example Using an inline Gemfile
#
#          #!/usr/bin/env ruby
#
#          require 'bundler/inline'
#
#          gemfile do
#            source 'https://rubygems.org'
#            gem 'json', require: false
#            gem 'nap', require: 'rest'
#            gem 'cocoapods', '~> 0.34.1'
#          end
#
#          puts Pod::VERSION # => "0.34.4"
#
def gemfile(install = false, options = {}, &gemfile)
  require_relative "../bundler"

  opts = options.dup
  ui = opts.delete(:ui) { Bundler::UI::Shell.new }
  ui.level = "silent" if opts.delete(:quiet)
  raise ArgumentError, "Unknown options: #{opts.keys.join(", ")}" unless opts.empty?

  old_root = Bundler.method(:root)
  bundler_module = class << Bundler; self; end
  bundler_module.send(:remove_method, :root)
  def Bundler.root
    Bundler::SharedHelpers.pwd.expand_path
  end
  Bundler::SharedHelpers.set_env "BUNDLE_GEMFILE", "Gemfile"

  Bundler::Plugin.gemfile_install(&gemfile) if Bundler.feature_flag.plugins?
  builder = Bundler::Dsl.new
  builder.instance_eval(&gemfile)

  Bundler.settings.temporary(:frozen => false) do
    definition = builder.to_definition(nil, true)
    def definition.lock(*); end
    definition.validate_runtime!

    missing_specs = proc do
      definition.missing_specs?
    end

    Bundler.ui = install ? ui : Bundler::UI::Silent.new
    if install || missing_specs.call
      Bundler.settings.temporary(:inline => true, :disable_platform_warnings => true) do
        installer = Bundler::Installer.install(Bundler.root, definition, :system => true)
        installer.post_install_messages.each do |name, message|
          Bundler.ui.info "Post-install message from #{name}:\n#{message}"
        end
      end
    end

    runtime = Bundler::Runtime.new(nil, definition)
    runtime.setup.require
  end
ensure
  if bundler_module
    bundler_module.send(:remove_method, :root)
    bundler_module.send(:define_method, :root, old_root)
  end
end
