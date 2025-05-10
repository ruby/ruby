module LoadPathCheck
  FIRST_LOAD_PATH = $LOAD_PATH.dup
  FIRST_LOAD_PATH_RESPOND_TO_RESOLVE = $LOAD_PATH.respond_to?(:resolve_feature_path)
  FIRST_LOADED_FEATURES = $LOADED_FEATURES.dup

  HERE = File.dirname(__FILE__)

  def self.current_load_path
    $LOAD_PATH
  end

  def self.current_loaded_features
    $LOADED_FEATURES
  end

  def self.require_blank1
    $LOAD_PATH << HERE
    require 'blank1'
  end

  def self.require_blank2
    require 'blank2'
  end
end

LoadPathCheck.require_blank1
