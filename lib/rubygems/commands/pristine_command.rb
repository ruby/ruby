######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require 'rubygems/command'
require 'rubygems/format'
require 'rubygems/installer'
require 'rubygems/version_option'

class Gem::Commands::PristineCommand < Gem::Command

  include Gem::VersionOption

  def initialize
    super 'pristine',
          'Restores installed gems to pristine condition from files located in the gem cache',
          :version => Gem::Requirement.default

    add_option('--all',
               'Restore all installed gems to pristine',
               'condition') do |value, options|
      options[:all] = value
    end

    add_version_option('restore to', 'pristine condition')
  end

  def arguments # :nodoc:
    "GEMNAME       gem to restore to pristine condition (unless --all)"
  end

  def defaults_str # :nodoc:
    "--all"
  end

  def description # :nodoc:
    <<-EOF
The pristine command compares the installed gems with the contents of the
cached gem and restores any files that don't match the cached gem's copy.

If you have made modifications to your installed gems, the pristine command
will revert them.  After all the gem's files have been checked all bin stubs
for the gem are regenerated.

If the cached gem cannot be found, you will need to use `gem install` to
revert the gem.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} [args]"
  end

  def execute
    gem_name = nil

    specs = if options[:all] then
              Gem::SourceIndex.from_installed_gems.map do |name, spec|
                spec
              end
            else
              gem_name = get_one_gem_name
              Gem::SourceIndex.from_installed_gems.find_name(gem_name,
                                                          options[:version])
            end

    if specs.empty? then
      raise Gem::Exception,
            "Failed to find gem #{gem_name} #{options[:version]}"
    end

    install_dir = Gem.dir # TODO use installer option

    raise Gem::FilePermissionError.new(install_dir) unless
      File.writable?(install_dir)

    say "Restoring gem(s) to pristine condition..."

    specs.each do |spec|
      gem = spec.cache_gem

      if gem.nil? then
        say "Cached gem for #{spec.full_name} not found, attempting to fetch..."
        dep = Gem::Dependency.new spec.name, spec.version
        Gem::RemoteFetcher.fetcher.download_to_cache dep
        gem = spec.cache_gem
      end

      # TODO use installer options
      installer = Gem::Installer.new gem, :wrappers => true, :force => true
      installer.install

      say "Restored #{spec.full_name}"
    end
  end

end

