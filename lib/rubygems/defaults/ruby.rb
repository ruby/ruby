module Gem
  class << self

    def bundled_gems_dir
      File.join(RbConfig::CONFIG["rubylibprefix"], "bundled_gems", RbConfig::CONFIG["ruby_version"])
    end

    def default_gems_dir
      File.join(RbConfig::CONFIG["rubylibprefix"], "default_gems", RbConfig::CONFIG["ruby_version"])
    end

    undef :default_specifications_dir if method_defined? :default_specifications_dir

    if method_defined? :default_path
      alias orig_default_path default_path
      undef :default_path
    end

    ##
    # Path to specification files of default gems.

    def default_specifications_dir
      @default_specifications_dir ||= File.join(Gem.default_gems_dir, "specifications", "default")
    end

    ##
    # Default gem load path

    def default_path
      path = orig_default_path
      path << bundled_gems_dir
      path << default_gems_dir
      path
    end

  end
end
