
require 'yarvtest/yarvtest'

class TestThread < YarvTestBase
  def test_create
    ae %q{
      Thread.new{
      }.join
      :ok
    }
    ae %q{
      Thread.new{
        :ok
      }.value
    }
  end

  def test_create_many_threads1
    ae %q{
      v = 0
      (1..200).map{|i|
        Thread.new{
          i
        }
      }.each{|t|
        v += t.value
      }
      v
    }
  end

  def test_create_many_threads2
    ae %q{
      5000.times{|e|
        (1..2).map{
          Thread.new{
          }
        }.each{|e|
          e.join
        }
      }
    }
  end

  def test_create_many_threads3
    ae %q{
      5000.times{
        t = Thread.new{}
        while t.alive?
          Thread.pass
        end
      }
    }
  end

  def test_create_many_threads4
    ae %q{
      100.times{
        Thread.new{loop{Thread.pass}}
      }
    }
  end

  def test_raise
    ae %q{
      t = Thread.new{
        sleep
      }
      sleep 0.1
      t.raise
      begin
        t.join
        :ng
      rescue
        :ok
      end
    }
    ae %q{
      t = Thread.new{
        loop{}
      }
      Thread.pass
      t.raise
      begin
        t.join
        :ng
      rescue
        :ok
      end
    }
    ae %q{
      t = Thread.new{
      }
      Thread.pass
      t.join
      t.raise # raise to exited thread
      begin
        t.join
        :ok
      rescue
        :ng
      end
    }
  end

  def test_status
    ae %q{
      t = Thread.new{
        loop{}
      }
      st = t.status
      t.kill
      st
    }
    ae %q{
      t = Thread.new{
        sleep
      }
      sleep 0.1
      st = t.status
      t.kill
      st
    }
    ae %q{
      t = Thread.new{
      }
      t.kill
      sleep 0.1
      t.status
    }
  end

  def test_tlv
    ae %q{
      Thread.current[:a] = 1
      Thread.new{
        Thread.current[:a] = 10
        Thread.pass
        Thread.current[:a]
      }.value + Thread.current[:a]
    }
  end

  def test_thread_group
    ae %q{
      ptg = Thread.current.group
      Thread.new{
        ctg = Thread.current.group
        [ctg.class, ctg == ptg]
      }.value
    }
    ae %q{
      thg = ThreadGroup.new

      t = Thread.new{
        thg.add Thread.current
        sleep
      }
      sleep 0.1
      [thg.list.size, ThreadGroup::Default.list.size]
    }
  end

  def test_thread_local_svar
    ae %q{
      /a/ =~ 'a'
      $a = $~
      Thread.new{
        $b = $~
        /a/ =~ 'a'
        $c = $~
      }
      $d = $~
      [$a == $d, $b, $c != $d]
    }
  end

  def test_join
    ae %q{
      Thread.new{
        :ok
      }.join.value
    }
    ae %q{
      begin
        Thread.new{
          raise "ok"
        }.join
      rescue => e
        e
      end
    }
    ae %q{
      ans = nil
      t = Thread.new{
        begin
          sleep 0.5
        ensure
          ans = :ok
        end
      }
      Thread.pass
      t.kill
      t.join
      ans
    }
  end
end

