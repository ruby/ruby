#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems'

# forward-declare

module Gem::Security # :nodoc:
  class Policy # :nodoc:
  end
end

##
# Mixin methods for install and update options for Gem::Commands

module Gem::InstallUpdateOptions

  ##
  # Add the install/update options to the option parser.

  def add_install_update_options
    # TODO: use @parser.accept
    OptionParser.accept Gem::Security::Policy do |value|
      require 'rubygems/security'

      value = Gem::Security::Policies[value]
      valid = Gem::Security::Policies.keys.sort
      message = "#{value} (#{valid.join ', '} are valid)"
      raise OptionParser::InvalidArgument, message if value.nil?
      value
    end

    add_option(:"Install/Update", '-i', '--install-dir DIR',
               'Gem repository directory to get installed',
               'gems') do |value, options|
      options[:install_dir] = File.expand_path(value)
    end

    add_option(:"Install/Update", '-n', '--bindir DIR',
               'Directory where binary files are',
               'located') do |value, options|
      options[:bin_dir] = File.expand_path(value)
    end

    add_option(:"Install/Update",       '--[no-]document [TYPES]', Array,
               'Generate documentation for installed gems',
               'List the documentation types you wish to',
               'generate.  For example: rdoc,ri') do |value, options|
      options[:document] = case value
                           when nil   then %w[ri]
                           when false then []
                           else            value
                           end
    end

    add_option(:"Install/Update", '-N', '--no-document',
               'Disable documentation generation') do |value, options|
      options[:document] = []
    end

    add_option(:Deprecated, '--[no-]rdoc',
               'Generate RDoc for installed gems',
               'Use --document instead') do |value, options|
      if value then
        options[:document] << 'rdoc'
      else
        options[:document].delete 'rdoc'
      end

      options[:document].uniq!
    end

    add_option(:Deprecated, '--[no-]ri',
               'Generate ri data for installed gems.',
               'Use --document instead') do |value, options|
      if value then
        options[:document] << 'ri'
      else
        options[:document].delete 'ri'
      end

      options[:document].uniq!
    end

    add_option(:"Install/Update", '-E', '--[no-]env-shebang',
               "Rewrite the shebang line on installed",
               "scripts to use /usr/bin/env") do |value, options|
      options[:env_shebang] = value
    end

    add_option(:"Install/Update", '-f', '--[no-]force',
               'Force gem to install, bypassing dependency',
               'checks') do |value, options|
      options[:force] = value
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

    add_option(:"Install/Update",       '--[no-]format-executable',
               'Make installed executable names match ruby.',
               'If ruby is ruby18, foo_exec will be',
               'foo_exec18') do |value, options|
      options[:format_executable] = value
    end

    add_option(:"Install/Update",       '--[no-]user-install',
               'Install in user\'s home directory instead',
               'of GEM_HOME.') do |value, options|
      options[:user_install] = value
    end

    add_option(:"Install/Update", "--development",
                "Install additional development",
                "dependencies") do |value, options|
      options[:development] = true
      options[:dev_shallow] = true
    end

    add_option(:"Install/Update", "--development-all",
                "Install development dependencies for all",
                "gems (including dev deps themselves)") do |value, options|
      options[:development] = true
      options[:dev_shallow] = false
    end

    add_option(:"Install/Update", "--conservative",
                "Don't attempt to upgrade gems already",
                "meeting version requirement") do |value, options|
      options[:conservative] = true
      options[:minimal_deps] = true
    end

    add_option(:"Install/Update", "--minimal-deps",
                "Don't upgrade any dependencies that already",
                "meet version requirements") do |value, options|
      options[:minimal_deps] = true
    end
  end

  ##
  # Default options for the gem install command.

  def install_update_defaults_str
    '--document=rdoc,ri --wrappers'
  end

end

