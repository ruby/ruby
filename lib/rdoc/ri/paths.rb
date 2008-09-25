require 'rdoc/ri'

##
# Encapsulate all the strangeness to do with finding out where to find RDoc
# files
#
# We basically deal with three directories:
#
# 1. The 'system' documentation directory, which holds the documentation
#    distributed with Ruby, and which is managed by the Ruby install process
# 2. The 'site' directory, which contains site-wide documentation added
#    locally.
# 3. The 'user' documentation directory, stored under the user's own home
#    directory.
#
# There's contention about all this, but for now:
#
# system:: $datadir/ri/<ver>/system/...
# site::   $datadir/ri/<ver>/site/...
# user::   ~/.rdoc

module RDoc::RI::Paths

  #:stopdoc:
  require 'rbconfig'

  DOC_DIR  = "doc/rdoc"

  VERSION = RbConfig::CONFIG['ruby_version']

  base    = File.join(RbConfig::CONFIG['datadir'], "ri", VERSION)
  SYSDIR  = File.join(base, "system")
  SITEDIR = File.join(base, "site")
  homedir = ENV['HOME'] || ENV['USERPROFILE'] || ENV['HOMEPATH']

  if homedir then
    HOMEDIR = File.join(homedir, ".rdoc")
  else
    HOMEDIR = nil
  end

  begin
    require 'rubygems' unless defined?(Gem) and defined?(Gem::Enable) and
                              Gem::Enable

    # HACK dup'd from Gem.latest_partials and friends
    all_paths = []

    all_paths = Gem.path.map do |dir|
      Dir[File.join(dir, 'doc', '*', 'ri')]
    end.flatten

    ri_paths = {}

    all_paths.each do |dir|
      base = File.basename File.dirname(dir)
      if base =~ /(.*)-((\d+\.)*\d+)/ then
        name, version = $1, $2
        ver = Gem::Version.new version
        if ri_paths[name].nil? or ver > ri_paths[name][0] then
          ri_paths[name] = [ver, dir]
        end
      end
    end

    GEMDIRS = ri_paths.map { |k,v| v.last }.sort
  rescue LoadError
    GEMDIRS = []
  end

  # Returns the selected documentation directories as an Array, or PATH if no
  # overriding directories were given.

  def self.path(use_system, use_site, use_home, use_gems, *extra_dirs)
    path = raw_path(use_system, use_site, use_home, use_gems, *extra_dirs)
    return path.select { |directory| File.directory? directory }
  end

  # Returns the selected documentation directories including nonexistent
  # directories.  Used to print out what paths were searched if no ri was
  # found.

  def self.raw_path(use_system, use_site, use_home, use_gems, *extra_dirs)
    path = []
    path << extra_dirs unless extra_dirs.empty?
    path << SYSDIR if use_system
    path << SITEDIR if use_site
    path << HOMEDIR if use_home
    path << GEMDIRS if use_gems

    return path.flatten.compact
  end
end
