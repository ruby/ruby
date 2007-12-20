#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems'
require 'rubygems/security'

##
# Mixin methods for install and update options for Gem::Commands
module Gem::InstallUpdateOptions

  # Add the install/update options to the option parser.
  def add_install_update_options
    OptionParser.accept Gem::Security::Policy do |value|
      value = Gem::Security::Policies[value]
      raise OptionParser::InvalidArgument, value if value.nil?
      value
    end

    add_option(:"Install/Update", '-i', '--install-dir DIR',
               'Gem repository directory to get installed',
               'gems') do |value, options|
      options[:install_dir] = File.expand_path(value)
    end

    add_option(:"Install/Update", '-d', '--[no-]rdoc',
               'Generate RDoc documentation for the gem on',
               'install') do |value, options|
      options[:generate_rdoc] = value
    end

    add_option(:"Install/Update", '--[no-]ri',
               'Generate RI documentation for the gem on',
               'install') do |value, options|
      options[:generate_ri] = value
    end

    add_option(:"Install/Update", '-E', '--env-shebang',
               "Rewrite the shebang line on installed",
               "scripts to use /usr/bin/env") do |value, options|
      options[:env_shebang] = value
    end

    add_option(:"Install/Update", '-f', '--[no-]force',
               'Force gem to install, bypassing dependency',
               'checks') do |value, options|
      options[:force] = value
    end

    add_option(:"Install/Update", '-t', '--[no-]test',
               'Run unit tests prior to installation') do |value, options|
      options[:test] = value
    end

    add_option(:"Install/Update", '-w', '--[no-]wrappers',
               'Use bin wrappers for executables',
               'Not available on dosish platforms') do |value, options|
      options[:wrappers] = value
    end

    add_option(:"Install/Update", '-P', '--trust-policy POLICY',
               Gem::Security::Policy,
               'Specify gem trust policy') do |value, options|
      options[:security_policy] = value
    end

    add_option(:"Install/Update", '--ignore-dependencies',
               'Do not install any required dependent gems') do |value, options|
      options[:ignore_dependencies] = value
    end

    add_option(:"Install/Update", '-y', '--include-dependencies',
               'Unconditionally install the required',
               'dependent gems') do |value, options|
      options[:include_dependencies] = value
    end

    add_option(:"Install/Update",       '--[no-]format-executable',
               'Make installed executable names match ruby.',
               'If ruby is ruby18, foo_exec will be',
               'foo_exec18') do |value, options|
      options[:format_executable] = value
    end
  end

  # Default options for the gem install command.
  def install_update_defaults_str
    '--rdoc --no-force --no-test --wrappers'
  end

end

