require 'test/unit'

$KCODE = 'none'

class TestPath < Test::Unit::TestCase
  def test_path
    assert(File.basename("a") == "a")
    assert(File.basename("a/b") == "b")
    assert(File.basename("a/b/") == "b")
    assert(File.basename("/") == "/")
    assert(File.basename("//") == "/")
    assert(File.basename("///") == "/")
    assert(File.basename("a/b////") == "b")
    assert(File.basename("a.rb", ".rb") == "a")
    assert(File.basename("a.rb///", ".rb") == "a")
    assert(File.basename("a.rb///", ".*") == "a")
    assert(File.basename("a.rb///", ".c") == "a.rb")
    assert(File.dirname("a") == ".")
    assert(File.dirname("/") == "/")
    assert(File.dirname("/a") == "/")
    assert(File.dirname("a/b") == "a")
    assert(File.dirname("a/b/c") == "a/b")
    assert(File.dirname("/a/b/c") == "/a/b")
    assert(File.dirname("/a/b/") == "/a")
    assert(File.dirname("/a/b///") == "/a")
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
      assert(File.expand_path(".", "/") == "/")
      assert(File.expand_path("sub", "/") == "/sub")
    end
    if dosish
      assert(File.expand_path("/", "//machine/share/sub") == "//machine/share")
      assert(File.expand_path("/dir", "//machine/share/sub") == "//machine/share/dir")
      assert(File.expand_path("/", "z:/sub") == "z:/")
      assert(File.expand_path("/dir", "z:/sub") == "z:/dir")
    end
    assert(File.expand_path(".", "//") == "//")
    assert(File.expand_path("sub", "//") == "//sub")
  end
end
