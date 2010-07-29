#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

module Kernel

  ##
  # The Kernel#require from before RubyGems was loaded.

  alias gem_original_require require

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

  def require(path) # :doc:
    gem_original_require path
  rescue LoadError => load_error
    if load_error.message.end_with?(path)
      if Gem.try_activate(path)
        return gem_original_require(path)
      end
    end

    raise load_error
  end

  private :require
  private :gem_original_require

end unless Kernel.private_method_defined?(:gem_original_require)

