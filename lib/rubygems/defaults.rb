module Gem

  # An Array of the default sources that come with RubyGems.
  def self.default_sources
    %w[http://gems.rubyforge.org]
  end

  # Default home directory path to be used if an alternate value is not
  # specified in the environment.
  def self.default_dir
    if defined? RUBY_FRAMEWORK_VERSION then
      File.join File.dirname(ConfigMap[:sitedir]), 'Gems',
                ConfigMap[:ruby_version]
    else
      File.join ConfigMap[:libdir], 'ruby', 'gems', ConfigMap[:ruby_version]
    end
  end

  # Default gem path.
  def self.default_path
    default_dir
  end

  # Deduce Ruby's --program-prefix and --program-suffix from its install name.
  def self.default_exec_format
    baseruby = ConfigMap[:BASERUBY] || 'ruby'
    ConfigMap[:RUBY_INSTALL_NAME].sub(baseruby, '%s') rescue '%s'
  end

  # The default directory for binaries
  def self.default_bindir
    Config::CONFIG['bindir']
  end

  # The default system-wide source info cache directory.
  def self.default_system_source_cache_dir
    File.join Gem.dir, 'source_cache'
  end

  # The default user-specific source info cache directory.
  def self.default_user_source_cache_dir
    File.join Gem.user_home, '.gem', 'source_cache'
  end

end

