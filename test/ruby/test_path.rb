require 'test/unit'

$KCODE = 'none'

class TestPath < Test::Unit::TestCase
  def test_path
    assert_equal(File.basename("a"), "a")
    assert_equal(File.basename("a/b"), "b")
    assert_equal(File.basename("a/b/"), "b")
    assert_equal(File.basename("/"), "/")
    assert_equal(File.basename("//"), "/")
    assert_equal(File.basename("///"), "/")
    assert_equal(File.basename("a/b////"), "b")
    assert_equal(File.basename("a.rb", ".rb"), "a")
    assert_equal(File.basename("a.rb///", ".rb"), "a")
    assert_equal(File.basename("a.rb///", ".*"), "a")
    assert_equal(File.basename("a.rb///", ".c"), "a.rb")
    assert_equal(File.dirname("a"), ".")
    assert_equal(File.dirname("/"), "/")
    assert_equal(File.dirname("/a"), "/")
    assert_equal(File.dirname("a/b"), "a")
    assert_equal(File.dirname("a/b/c"), "a/b")
    assert_equal(File.dirname("/a/b/c"), "/a/b")
    assert_equal(File.dirname("/a/b/"), "/a")
    assert_equal(File.dirname("/a/b///"), "/a")
    case Dir.pwd
    when %r'\A\w:'
      assert(/\A\w:\/\z/ =~ File.expand_path(".", "/"))
      assert(/\A\w:\/a\z/ =~ File.expand_path("a", "/"))
      dosish = true
    when %r'\A//'
      assert(%r'\A//[^/]+/[^/]+\z' =~ File.expand_path(".", "/"))
      assert(%r'\A//[^/]+/[^/]+/a\z' =~ File.expand_path(".", "/"))
      dosish = true
    else
      assert_equal(File.expand_path(".", "/"), "/")
      assert_equal(File.expand_path("sub", "/"), "/sub")
    end
    if dosish
      assert_equal(File.expand_path("/", "//machine/share/sub"), "//machine/share")
      assert_equal(File.expand_path("/dir", "//machine/share/sub"), "//machine/share/dir")
      assert_equal(File.expand_path("/", "z:/sub"), "z:/")
      assert_equal(File.expand_path("/dir", "z:/sub"), "z:/dir")
    end
    assert_equal(File.expand_path(".", "//"), "//")
    assert_equal(File.expand_path("sub", "//"), "//sub")
  end
end
