# frozen_string_literal: true

#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

class Gem::Ext::ConfigureBuilder < Gem::Ext::Builder
  def self.build(extension, dest_path, results, args=[], lib_dir=nil, configure_dir=Dir.pwd,
    target_rbconfig=Gem.target_rbconfig)
    if target_rbconfig.path
      warn "--target-rbconfig is not yet supported for configure-based extensions. Ignoring"
    end

    unless File.exist?(File.join(configure_dir, "Makefile"))
      cmd = ["sh", "./configure", "--prefix=#{dest_path}", *args]

      run cmd, results, class_name, configure_dir
    end

    make dest_path, results, configure_dir, target_rbconfig: target_rbconfig

    results
  end
end
