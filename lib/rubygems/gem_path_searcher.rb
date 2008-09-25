#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems'

##
# GemPathSearcher has the capability to find loadable files inside
# gems.  It generates data up front to speed up searches later.

class Gem::GemPathSearcher

  ##
  # Initialise the data we need to make searches later.

  def initialize
    # We want a record of all the installed gemspecs, in the order
    # we wish to examine them.
    @gemspecs = init_gemspecs
    # Map gem spec to glob of full require_path directories.
    # Preparing this information may speed up searches later.
    @lib_dirs = {}
    @gemspecs.each do |spec|
      @lib_dirs[spec.object_id] = lib_dirs_for(spec)
    end
  end

  ##
  # Look in all the installed gems until a matching _path_ is found.
  # Return the _gemspec_ of the gem where it was found.  If no match
  # is found, return nil.
  #
  # The gems are searched in alphabetical order, and in reverse
  # version order.
  #
  # For example:
  #
  #   find('log4r')              # -> (log4r-1.1 spec)
  #   find('log4r.rb')           # -> (log4r-1.1 spec)
  #   find('rake/rdoctask')      # -> (rake-0.4.12 spec)
  #   find('foobarbaz')          # -> nil
  #
  # Matching paths can have various suffixes ('.rb', '.so', and
  # others), which may or may not already be attached to _file_.
  # This method doesn't care about the full filename that matches;
  # only that there is a match.

  def find(path)
    @gemspecs.find do |spec| matching_file? spec, path end
  end

  ##
  # Works like #find, but finds all gemspecs matching +path+.

  def find_all(path)
    @gemspecs.select do |spec|
      matching_file? spec, path
    end
  end

  ##
  # Attempts to find a matching path using the require_paths of the given
  # +spec+.

  def matching_file?(spec, path)
    !matching_files(spec, path).empty?
  end

  ##
  # Returns files matching +path+ in +spec+.
  #--
  # Some of the intermediate results are cached in @lib_dirs for speed.

  def matching_files(spec, path)
    glob = File.join @lib_dirs[spec.object_id], "#{path}#{Gem.suffix_pattern}"
    Dir[glob].select { |f| File.file? f.untaint }
  end

  ##
  # Return a list of all installed gemspecs, sorted by alphabetical order and
  # in reverse version order.

  def init_gemspecs
    Gem.source_index.map { |_, spec| spec }.sort { |a,b|
      (a.name <=> b.name).nonzero? || (b.version <=> a.version)
    }
  end

  ##
  # Returns library directories glob for a gemspec.  For example,
  #   '/usr/local/lib/ruby/gems/1.8/gems/foobar-1.0/{lib,ext}'

  def lib_dirs_for(spec)
    "#{spec.full_gem_path}/{#{spec.require_paths.join(',')}}"
  end

end

