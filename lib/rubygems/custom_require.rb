######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

module Kernel

  if defined?(gem_original_require) then
    # Ruby ships with a custom_require, override its require
    remove_method :require
  else
    ##
    # The Kernel#require from before RubyGems was loaded.

    alias gem_original_require require
    private :gem_original_require
  end

  ##
  # When RubyGems is required, Kernel#require is replaced with our own which
  # is capable of loading gems on demand.
  #
  # When you call <tt>require 'x'</tt>, this is what happens:
  # * If the file can be loaded from the existing Ruby loadpath, it
  #   is.
  # * Otherwise, installed gems are searched for a file that matches.
  #   If it's found in gem 'y', that gem is activated (added to the
  #   loadpath).
  #
  # The normal <tt>require</tt> functionality of returning false if
  # that file has already been loaded is preserved.

  def require path
    if Gem.unresolved_deps.empty? or Gem.loaded_path? path then
      gem_original_require path
    else
      spec = Gem.searcher.find_active path

      unless spec then
        found_specs = Gem.searcher.find_in_unresolved path
        unless found_specs.empty? then
          found_specs = [found_specs.last]
        else
          found_specs = Gem.searcher.find_in_unresolved_tree path
        end

        found_specs.each do |found_spec|
          # FIX: this is dumb, activate a spec instead of name/version
          Gem.activate found_spec.name, found_spec.version
        end
      end

      return gem_original_require path
    end
  rescue LoadError => load_error
    if load_error.message.end_with?(path) and Gem.try_activate(path) then
      return gem_original_require(path)
    end

    raise load_error
  end

  private :require

end

