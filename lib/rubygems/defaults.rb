module Gem

  @post_install_hooks   ||= []
  @post_uninstall_hooks ||= []
  @pre_uninstall_hooks  ||= []
  @pre_install_hooks    ||= []

  ##
  # An Array of the default sources that come with RubyGems

  def self.default_sources
    %w[http://gems.rubyforge.org/]
  end

  ##
  # Default home directory path to be used if an alternate value is not
  # specified in the environment

  def self.default_dir
    if defined? RUBY_FRAMEWORK_VERSION then
      File.join File.dirname(ConfigMap[:sitedir]), 'Gems',
                ConfigMap[:ruby_version]
    elsif RUBY_VERSION >= '1.9.2' then
      File.join(ConfigMap[:rubylibprefix], 'gems',
                ConfigMap[:ruby_version])
    # only Ruby 1.9.1 has a peculiar feature
    elsif RUBY_VERSION > '1.9' and 
      File.join(ConfigMap[:libdir], ConfigMap[:ruby_install_name], 'gems',
                ConfigMap[:ruby_version])
    else
      File.join(ConfigMap[:libdir], ruby_engine, 'gems',
                ConfigMap[:ruby_version])
    end
  end

  ##
  # Path for gems in the user's home directory

  def self.user_dir
    File.join(Gem.user_home, '.gem', ruby_engine,
              ConfigMap[:ruby_version])
  end

  ##
  # Default gem load path

  def self.default_path
    if File.exist?(Gem.user_home)
      [user_dir, default_dir]
    else
      [default_dir]
    end
  end

  ##
  # Deduce Ruby's --program-prefix and --program-suffix from its install name

  def self.default_exec_format
    exec_format = ConfigMap[:ruby_install_name].sub('ruby', '%s') rescue '%s'

    unless exec_format =~ /%s/ then
      raise Gem::Exception,
        "[BUG] invalid exec_format #{exec_format.inspect}, no %s"
    end

    exec_format
  end

  ##
  # The default directory for binaries

  def self.default_bindir
    if defined? RUBY_FRAMEWORK_VERSION then # mac framework support
      '/usr/bin'
    else # generic install
      ConfigMap[:bindir]
    end
  end

  ##
  # The default system-wide source info cache directory

  def self.default_system_source_cache_dir
    File.join Gem.dir, 'source_cache'
  end

  ##
  # The default user-specific source info cache directory

  def self.default_user_source_cache_dir
    File.join Gem.user_home, '.gem', 'source_cache'
  end

  ##
  # A wrapper around RUBY_ENGINE const that may not be defined

  def self.ruby_engine
    if defined? RUBY_ENGINE then
      RUBY_ENGINE
    else
      'ruby'
    end
  end

end

