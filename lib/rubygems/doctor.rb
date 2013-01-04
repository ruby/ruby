require 'rubygems'
require 'rubygems/user_interaction'
require 'pathname'

##
# Cleans up after a partially-failed uninstall or for an invalid
# Gem::Specification.
#
# If a specification was removed by hand this will remove any remaining files.
#
# If a corrupt specification was installed this will clean up warnings by
# removing the bogus specification.

class Gem::Doctor

  include Gem::UserInteraction

  ##
  # Maps a gem subdirectory to the files that are expected to exist in the
  # subdirectory.

  REPOSITORY_EXTENSION_MAP = [ # :nodoc:
    ['specifications', '.gemspec'],
    ['build_info',     '.info'],
    ['cache',          '.gem'],
    ['doc',            ''],
    ['gems',           ''],
  ]

  raise 'Update REPOSITORY_EXTENSION_MAP' unless
    Gem::REPOSITORY_SUBDIRECTORIES.sort ==
      REPOSITORY_EXTENSION_MAP.map { |(k,_)| k }.sort

  ##
  # Creates a new Gem::Doctor that will clean up +gem_repository+.  Only one
  # gem repository may be cleaned at a time.
  #
  # If +dry_run+ is true no files or directories will be removed.

  def initialize gem_repository, dry_run = false
    @gem_repository = Pathname(gem_repository)
    @dry_run        = dry_run

    @installed_specs = nil
  end

  ##
  # Specs installed in this gem repository

  def installed_specs # :nodoc:
    @installed_specs ||= Gem::Specification.map { |s| s.full_name }
  end

  ##
  # Are we doctoring a gem repository?

  def gem_repository?
    not installed_specs.empty?
  end

  ##
  # Cleans up uninstalled files and invalid gem specifications

  def doctor
    @orig_home = Gem.dir
    @orig_path = Gem.path

    say "Checking #{@gem_repository}"

    Gem.use_paths @gem_repository.to_s

    unless gem_repository? then
      say 'This directory does not appear to be a RubyGems repository, ' +
          'skipping'
      say
      return
    end

    doctor_children

    say
  ensure
    Gem.use_paths @orig_home, *@orig_path
  end

  ##
  # Cleans up children of this gem repository

  def doctor_children # :nodoc:
    REPOSITORY_EXTENSION_MAP.each do |sub_directory, extension|
      doctor_child sub_directory, extension
    end
  end

  ##
  # Removes files in +sub_directory+ with +extension+

  def doctor_child sub_directory, extension # :nodoc:
    directory = @gem_repository + sub_directory

    directory.children.sort.each do |child|
      next unless child.exist?

      basename = child.basename(extension).to_s
      next if installed_specs.include? basename
      next if /^rubygems-\d/ =~ basename
      next if 'specifications' == sub_directory and 'default' == basename

      type = child.directory? ? 'directory' : 'file'

      action = if @dry_run then
                 'Extra'
               else
                 child.rmtree
                 'Removed'
               end

      say "#{action} #{type} #{sub_directory}/#{child.basename}"
    end
  rescue Errno::ENOENT
    # ignore
  end

end

