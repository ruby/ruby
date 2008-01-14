assert_equal %q{ok}, %q{
  Thread.new{
  }.join
  :ok
}
assert_equal %q{ok}, %q{
  Thread.new{
    :ok
  }.value
}
assert_equal %q{20100}, %q{
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
assert_equal %q{5000}, %q{
  5000.times{|e|
    (1..2).map{
      Thread.new{
      }
    }.each{|e|
      e.join()
    }
  }
}
assert_equal %q{5000}, %q{
  5000.times{|e|
    (1..2).map{
      Thread.new{
      }
    }.each{|e|
      e.join(1000000000)
    }
  }
}
assert_equal %q{5000}, %q{
  5000.times{
    t = Thread.new{}
    while t.alive?
      Thread.pass
    end
  }
}
assert_equal %q{100}, %q{
  100.times{
    Thread.new{loop{Thread.pass}}
  }
}
assert_equal %q{ok}, %q{
  Thread.new{
    :ok
  }.join.value
}
assert_equal %q{ok}, %q{
  begin
    Thread.new{
      raise "ok"
    }.join
  rescue => e
    e
  end
}
assert_equal %q{ok}, %q{
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
assert_equal %q{ok}, %q{
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
assert_equal %q{ok}, %q{
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
assert_equal %q{ok}, %q{
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
assert_equal %q{run}, %q{
  t = Thread.new{
    loop{}
  }
  st = t.status
  t.kill
  st
}
assert_equal %q{sleep}, %q{
  t = Thread.new{
    sleep
  }
  sleep 0.1
  st = t.status
  t.kill
  st
}
assert_equal %q{false}, %q{
  t = Thread.new{
  }
  t.kill
  sleep 0.1
  t.status
}
assert_equal %q{[ThreadGroup, true]}, %q{
  ptg = Thread.current.group
  Thread.new{
    ctg = Thread.current.group
    [ctg.class, ctg == ptg]
  }.value
}
assert_equal %q{[1, 1]}, %q{
  thg = ThreadGroup.new

  t = Thread.new{
    thg.add Thread.current
    sleep
  }
  sleep 0.1
  [thg.list.size, ThreadGroup::Default.list.size]
}
assert_equal %q{[true, nil, true]}, %q{
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
assert_equal %q{11}, %q{
  Thread.current[:a] = 1
  Thread.new{
    Thread.current[:a] = 10
    Thread.pass
    Thread.current[:a]
  }.value + Thread.current[:a]
}
assert_equal %q{100}, %q{
begin
  100.times do |i|
    begin
      Thread.start(Thread.current) {|u| u.raise }
      raise
    rescue
    ensure
    end
  end
rescue
  100
end
}, '[ruby-dev:31371]'
assert_equal 'true', %{
  t = Thread.new { loop {} }
  pid = fork {
      exit t.status != "run"
  }
  Process.wait pid
  $?.success?
}
