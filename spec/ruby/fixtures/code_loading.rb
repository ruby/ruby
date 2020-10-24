module CodeLoadingSpecs
  # The #require instance method is private, so this class enables
  # calling #require like obj.require(file). This is used to share
  # specs between Kernel#require and Kernel.require.
  class Method
    def require(name)
      super name
    end

    def load(name, wrap=false)
      super
    end
  end

  def self.preload_rubygems
    # Require RubyGems eagerly, to ensure #require is already the RubyGems
    # version and RubyGems is only loaded once, before starting #require/#autoload specs
    # which snapshot $LOADED_FEATURES and could cause RubyGems to load twice.
    # #require specs also snapshot #require, and could end up redefining #require as the original core Kernel#require.
    @rubygems ||= begin
      require "rubygems"
      true
    rescue LoadError
      true
    end
  end

  def self.spec_setup
    preload_rubygems

    @saved_loaded_features = $LOADED_FEATURES.clone
    @saved_load_path = $LOAD_PATH.clone
    ScratchPad.record []
  end

  def self.spec_cleanup
    $LOADED_FEATURES.replace @saved_loaded_features
    $LOAD_PATH.replace @saved_load_path
    ScratchPad.clear
  end
end
