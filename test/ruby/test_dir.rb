require 'test/unit'

require 'tmpdir'
require 'fileutils'

class TestDir < Test::Unit::TestCase

  ROOT = File.join(Dir.tmpdir, "__test_dir__#{$$}")

  def setup
    Dir.mkdir(ROOT)
    for i in ?a..?z
      if i.ord % 2 == 0
        FileUtils.touch(File.join(ROOT, i))
      else
        FileUtils.mkdir(File.join(ROOT, i))
      end
    end
  end

  def teardown
    FileUtils.rm_rf ROOT if File.directory?(ROOT)
  end

  def test_seek
    dir = Dir.open(ROOT)
    begin
      cache = []
      loop do
        pos = dir.tell
        break unless name = dir.read
        cache << [pos, name]
      end
      for x,y in cache.sort_by {|z| z[0] % 3 } # shuffle
        dir.seek(x)
        assert_equal(y, dir.read)
      end
    ensure
      dir.close
    end
  end

  def test_JVN_13947696
    b = lambda {
      d = Dir.open('.')
      $SAFE = 4
      d.close
    }
    assert_raise(SecurityError) { b.call }
  end

end
