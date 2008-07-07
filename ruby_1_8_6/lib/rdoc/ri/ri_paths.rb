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

    version = Config::CONFIG['ruby_version']

    base    = File.join(Config::CONFIG['datadir'], "ri", version)
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

    begin
      require 'rubygems'
      GEMDIRS = Dir["#{Gem.path}/doc/*/ri"]
      GEMDIRS.each { |path| RI::Paths::PATH << path }
    rescue LoadError
      GEMDIRS = nil
    end

    # Returns the selected documentation directories as an Array, or PATH if no
    # overriding directories were given.

    def self.path(use_system, use_site, use_home, use_gems, *extra_dirs)
      path = raw_path(use_system, use_site, use_home, use_gems, *extra_dirs)
      return path.select { |path| File.directory? path }
    end

    # Returns the selected documentation directories including nonexistent
    # directories.  Used to print out what paths were searched if no ri was
    # found.

    def self.raw_path(use_system, use_site, use_home, use_gems, *extra_dirs)
      return PATH unless use_system or use_site or use_home or use_gems or
                         not extra_dirs.empty?

      path = []
      path << extra_dirs unless extra_dirs.empty?
      path << RI::Paths::SYSDIR if use_system
      path << RI::Paths::SITEDIR if use_site
      path << RI::Paths::HOMEDIR if use_home
      path << RI::Paths::GEMDIRS if use_gems

      return path.flatten.compact
    end

  end
end
