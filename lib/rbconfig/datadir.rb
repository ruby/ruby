#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

module RbConfig

  ##
  # Return the path to the data directory associated with the given package
  # name.  Normally this is just
  # "#{RbConfig::CONFIG['datadir']}/#{package_name}", but may be modified by
  # packages like RubyGems to handle versioned data directories.

  def self.datadir(package_name)
    File.join(CONFIG['datadir'], package_name)
  end unless RbConfig.respond_to?(:datadir)

end

