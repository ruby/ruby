require 'rubygems/test_case'
require 'rubygems/util'

class TestGemUtil < Gem::TestCase

  def test_class_popen
    assert_equal "0\n", Gem::Util.popen(Gem.ruby, '-e', 'p 0')

    assert_raises Errno::ECHILD do
      Process.wait(-1)
    end
  end

  def test_silent_system
    assert_silent do
      Gem::Util.silent_system Gem.ruby, '-e', 'puts "hello"; warn "hello"'
    end
  end

  def test_traverse_parents
    FileUtils.mkdir_p 'a/b/c'

    enum = Gem::Util.traverse_parents 'a/b/c'

    assert_equal File.join(@tempdir, 'a/b/c'), enum.next
    assert_equal File.join(@tempdir, 'a/b'),   enum.next
    assert_equal File.join(@tempdir, 'a'),     enum.next
  end

end

