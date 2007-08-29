require 'test/unit'

class TestPath < Test::Unit::TestCase
  def test_path
    assert_equal("a", File.basename("a"))
    assert_equal("b", File.basename("a/b"))
    assert_equal("b", File.basename("a/b/"))
    assert_equal("/", File.basename("/"))
    assert_equal("/", File.basename("//"))
    assert_equal("/", File.basename("///"))
    assert_equal("b", File.basename("a/b////"))
    assert_equal("a", File.basename("a.rb", ".rb"))
    assert_equal("a", File.basename("a.rb///", ".rb"))
    assert_equal("a", File.basename("a.rb///", ".*"))
    assert_equal("a.rb", File.basename("a.rb///", ".c"))
    assert_equal(".", File.dirname("a"))
    assert_equal("/", File.dirname("/"))
    assert_equal("/", File.dirname("/a"))
    assert_equal("a", File.dirname("a/b"))
    assert_equal("a/b", File.dirname("a/b/c"))
    assert_equal("/a/b", File.dirname("/a/b/c"))
    assert_equal("/a", File.dirname("/a/b/"))
    assert_equal("/a", File.dirname("/a/b///"))
    case Dir.pwd
    when %r'\A\w:'
      assert_match(/\A\w:\/\z/, File.expand_path(".", "/"))
      assert_match(/\A\w:\/a\z/, File.expand_path("a", "/"))
      dosish = true
    when %r'\A//'
      assert_match(%r'\A//[^/]+/[^/]+\z', File.expand_path(".", "/"))
      assert_match(%r'\A//[^/]+/[^/]+/a\z', File.expand_path(".", "/"))
      dosish = true
    else
      assert_equal("/", File.expand_path(".", "/"))
      assert_equal("/sub", File.expand_path("sub", "/"))
    end
    if dosish
      assert_equal("//machine/share", File.expand_path("/", "//machine/share/sub"))
      assert_equal("//machine/share/dir", File.expand_path("/dir", "//machine/share/sub"))
      assert_equal("z:/", File.expand_path("/", "z:/sub"))
      assert_equal("z:/dir", File.expand_path("/dir", "z:/sub"))
    end
    assert_equal("//", File.expand_path(".", "//"))
    assert_equal("//sub", File.expand_path("sub", "//"))
  end

  def test_dirname # [ruby-dev:27738]
    if /(bcc|ms)win\d|mingw|cygwin|djgpp|human|emx/ =~ RUBY_PLATFORM
      # DOSISH_DRIVE_LETTER
      assert_equal('C:.', File.dirname('C:'))
      assert_equal('C:.', File.dirname('C:a'))
      assert_equal('C:.', File.dirname('C:a/'))
      assert_equal('C:a', File.dirname('C:a/b'))

      assert_equal('C:/', File.dirname('C:/'))
      assert_equal('C:/', File.dirname('C:/a'))
      assert_equal('C:/', File.dirname('C:/a/'))
      assert_equal('C:/a', File.dirname('C:/a/b'))

      assert_equal('C:/', File.dirname('C://'))
      assert_equal('C:/', File.dirname('C://a'))
      assert_equal('C:/', File.dirname('C://a/'))
      assert_equal('C:/a', File.dirname('C://a/b'))

      assert_equal('C:/', File.dirname('C:///'))
      assert_equal('C:/', File.dirname('C:///a'))
      assert_equal('C:/', File.dirname('C:///a/'))
      assert_equal('C:/a', File.dirname('C:///a/b'))
    else
      # others
      assert_equal('.', File.dirname('C:'))
      assert_equal('.', File.dirname('C:a'))
      assert_equal('.', File.dirname('C:a/'))
      assert_equal('C:a', File.dirname('C:a/b'))

      assert_equal('.', File.dirname('C:/'))
      assert_equal('C:', File.dirname('C:/a'))
      assert_equal('C:', File.dirname('C:/a/'))
      assert_equal('C:/a', File.dirname('C:/a/b'))

      assert_equal('.', File.dirname('C://'))
      assert_equal('C:', File.dirname('C://a'))
      assert_equal('C:', File.dirname('C://a/'))
      # not spec.
      #assert_equal('C://a', File.dirname('C://a/b'))

      assert_equal('.', File.dirname('C:///'))
      assert_equal('C:', File.dirname('C:///a'))
      assert_equal('C:', File.dirname('C:///a/'))
      # not spec.
      #assert_equal('C:///a', File.dirname('C:///a/b'))
    end

    assert_equal('.', File.dirname(''))
    assert_equal('.', File.dirname('a'))
    assert_equal('.', File.dirname('a/'))
    assert_equal('a', File.dirname('a/b'))

    assert_equal('/', File.dirname('/'))
    assert_equal('/', File.dirname('/a'))
    assert_equal('/', File.dirname('/a/'))
    assert_equal('/a', File.dirname('/a/b'))

    if /(bcc|ms|cyg)win|mingw|djgpp|human|emx/ =~ RUBY_PLATFORM
      # DOSISH_UNC
      assert_equal('//', File.dirname('//'))
      assert_equal('//a', File.dirname('//a'))
      assert_equal('//a', File.dirname('//a/'))
      assert_equal('//a/b', File.dirname('//a/b'))
      assert_equal('//a/b', File.dirname('//a/b/'))
      assert_equal('//a/b', File.dirname('//a/b/c'))

      assert_equal('//', File.dirname('///'))
      assert_equal('//a', File.dirname('///a'))
      assert_equal('//a', File.dirname('///a/'))
      assert_equal('//a/b', File.dirname('///a/b'))
      assert_equal('//a/b', File.dirname('///a/b/'))
      assert_equal('//a/b', File.dirname('///a/b/c'))
    else
      # others
      assert_equal('/', File.dirname('//'))
      assert_equal('/', File.dirname('//a'))
      assert_equal('/', File.dirname('//a/'))
      assert_equal('/a', File.dirname('//a/b'))
      assert_equal('/a', File.dirname('//a/b/'))
      assert_equal('/a/b', File.dirname('//a/b/c'))

      assert_equal('/', File.dirname('///'))
      assert_equal('/', File.dirname('///a'))
      assert_equal('/', File.dirname('///a/'))
      assert_equal('/a', File.dirname('///a/b'))
      assert_equal('/a', File.dirname('///a/b/'))
      assert_equal('/a/b', File.dirname('///a/b/c'))
    end
  end

  def test_basename # [ruby-dev:27766]
    if /(bcc|ms)win\d|mingw|cygwin|djgpp|human|emx/ =~ RUBY_PLATFORM
      # DOSISH_DRIVE_LETTER
      assert_equal('', File.basename('C:'))
      assert_equal('a', File.basename('C:a'))
      assert_equal('a', File.basename('C:a/'))
      assert_equal('b', File.basename('C:a/b'))

      assert_equal('/', File.basename('C:/'))
      assert_equal('a', File.basename('C:/a'))
      assert_equal('a', File.basename('C:/a/'))
      assert_equal('b', File.basename('C:/a/b'))

      assert_equal('/', File.basename('C://'))
      assert_equal('a', File.basename('C://a'))
      assert_equal('a', File.basename('C://a/'))
      assert_equal('b', File.basename('C://a/b'))

      assert_equal('/', File.basename('C:///'))
      assert_equal('a', File.basename('C:///a'))
      assert_equal('a', File.basename('C:///a/'))
      assert_equal('b', File.basename('C:///a/b'))
    else
      # others
      assert_equal('C:', File.basename('C:'))
      assert_equal('C:a', File.basename('C:a'))
      assert_equal('C:a', File.basename('C:a/'))
      assert_equal('b', File.basename('C:a/b'))

      assert_equal('C:', File.basename('C:/'))
      assert_equal('a', File.basename('C:/a'))
      assert_equal('a', File.basename('C:/a/'))
      assert_equal('b', File.basename('C:/a/b'))

      assert_equal('C:', File.basename('C://'))
      assert_equal('a', File.basename('C://a'))
      assert_equal('a', File.basename('C://a/'))
      assert_equal('b', File.basename('C://a/b'))

      assert_equal('C:', File.basename('C:///'))
      assert_equal('a', File.basename('C:///a'))
      assert_equal('a', File.basename('C:///a/'))
      assert_equal('b', File.basename('C:///a/b'))
    end

    assert_equal('', File.basename(''))
    assert_equal('a', File.basename('a'))
    assert_equal('a', File.basename('a/'))
    assert_equal('b', File.basename('a/b'))

    assert_equal('/', File.basename('/'))
    assert_equal('a', File.basename('/a'))
    assert_equal('a', File.basename('/a/'))
    assert_equal('b', File.basename('/a/b'))

    if /(bcc|ms|cyg)win|mingw|djgpp|human|emx/ =~ RUBY_PLATFORM
      # DOSISH_UNC
      assert_equal('/', File.basename('//'))
      assert_equal('/', File.basename('//a'))
      assert_equal('/', File.basename('//a/'))
      assert_equal('/', File.basename('//a/b'))
      assert_equal('/', File.basename('//a/b/'))
      assert_equal('c', File.basename('//a/b/c'))

      assert_equal('/', File.basename('///'))
      assert_equal('/', File.basename('///a'))
      assert_equal('/', File.basename('///a/'))
      assert_equal('/', File.basename('///a/b'))
      assert_equal('/', File.basename('///a/b/'))
      assert_equal('c', File.basename('///a/b/c'))
    else
      # others
      assert_equal('/', File.basename('//'))
      assert_equal('a', File.basename('//a'))
      assert_equal('a', File.basename('//a/'))
      assert_equal('b', File.basename('//a/b'))
      assert_equal('b', File.basename('//a/b/'))
      assert_equal('c', File.basename('//a/b/c'))

      assert_equal('/', File.basename('///'))
      assert_equal('a', File.basename('///a'))
      assert_equal('a', File.basename('///a/'))
      assert_equal('b', File.basename('///a/b'))
      assert_equal('b', File.basename('///a/b/'))
      assert_equal('c', File.basename('///a/b/c'))
    end
  end
end
