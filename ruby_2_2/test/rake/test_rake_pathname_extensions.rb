require File.expand_path('../helper', __FILE__)
require 'rake/ext/pathname'

class TestRakePathnameExtensions < Rake::TestCase
  def test_ext_works_on_pathnames
    pathname = Pathname.new("abc.foo")
    assert_equal Pathname.new("abc.bar"), pathname.ext("bar")
  end

  def test_path_map_works_on_pathnames
    pathname = Pathname.new("this/is/a/dir/abc.rb")
    assert_equal Pathname.new("abc.rb"), pathname.pathmap("%f")
    assert_equal Pathname.new("this/is/a/dir"), pathname.pathmap("%d")
  end
end
