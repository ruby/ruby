require_relative "test_helper"

class RbConfigTest < StdlibTest
  target RbConfig

  using hook.refinement

  def test_expand
    RbConfig.expand("/home/userName/.rbenv/versions/2.7.0/bin")
    RbConfig.expand("/home/userName/.rbenv/versions/2.7.0/bin", "UNICODE_VERSION"=>"12.1.0")
  end

  def test_fire_update!
    # Add test on nothing changed
    RbConfig.fire_update!("CC", "gcc-8")
    RbConfig.fire_update!("CC", "gcc-8", "UNICODE_VERSION"=>"12.1.0")
    RbConfig.fire_update!("CC", "gcc-8", "UNICODE_VERSION"=>"12.1.0", "PATH_SEPARATOR"=>":")
  end

  def test_ruby
    RbConfig.ruby
  end
end
