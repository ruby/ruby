module RI

  # Encapsulate all the strangeness to do with finding out
  # where to find RDoc files
  #
  # We basically deal with three directories:
  #
  # 1. The 'system' documentation directory, which holds
  #    the documentation distributed with Ruby, and which
  #    is managed by the Ruby install process
  # 2. The 'site' directory, which contains site-wide
  #    documentation added locally.
  # 3. The 'user' documentation directory, stored under the
  #    user's own home directory.
  #
  # There's contention about all this, but for now:
  #
  # system:: $datadir/ri/<ver>/system/...
  # site::   $datadir/ri/<ver>/site/...
  # user::   ~/.rdoc

  module Paths

    #:stopdoc:
    require 'rbconfig'
    
    DOC_DIR  = "doc/rdoc"

    version = RbConfig::CONFIG['ruby_version']

    base    = File.join(RbConfig::CONFIG['datadir'], "ri", version)
    SYSDIR  = File.join(base, "system")
    SITEDIR = File.join(base, "site")
    homedir = ENV['HOME'] || ENV['USERPROFILE'] || ENV['HOMEPATH']

    if homedir
      HOMEDIR = File.join(homedir, ".rdoc")
    else
      HOMEDIR = nil
    end

    # This is the search path for 'ri'
    PATH = [ SYSDIR, SITEDIR, HOMEDIR ].find_all {|p| p && File.directory?(p)}
  end
end
