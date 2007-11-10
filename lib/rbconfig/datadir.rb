#!/usr/bin/env ruby
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++


module Config

  # Only define datadir if it doesn't already exist.
  unless Config.respond_to?(:datadir)
    
    # Return the path to the data directory associated with the given
    # package name.  Normally this is just
    # "#{Config::CONFIG['datadir']}/#{package_name}", but may be
    # modified by packages like RubyGems to handle versioned data
    # directories.
    def Config.datadir(package_name)
      File.join(CONFIG['datadir'], package_name)
    end

  end
end
