require "rubygems/test_case"
require "rubygems/stub_specification"

class TestStubSpecification < Gem::TestCase
  SPECIFICATIONS = File.expand_path(File.join("..", "specifications"), __FILE__)
  FOO = File.join SPECIFICATIONS, "foo-0.0.1.gemspec"
  BAR = File.join SPECIFICATIONS, "bar-0.0.2.gemspec"

  def test_basic
    stub = Gem::StubSpecification.new(FOO)
    assert_equal "foo", stub.name
    assert_equal Gem::Version.new("0.0.1"), stub.version
    assert_equal Gem::Platform.new("mswin32"), stub.platform
    assert_equal ["lib", "lib/f oo/ext"], stub.require_paths
  end

  def test_missing_stubline
    stub = Gem::StubSpecification.new(BAR)
    assert_equal "bar", stub.name
    assert_equal Gem::Version.new("0.0.2"), stub.version
    assert_equal Gem::Platform.new("ruby"), stub.platform
    assert_equal ["lib"], stub.require_paths
  end

  def test_to_spec
    stub = Gem::StubSpecification.new(FOO)
    assert stub.to_spec.is_a?(Gem::Specification)
    assert_equal "foo", stub.to_spec.name
  end
end
