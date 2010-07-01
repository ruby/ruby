require 'test/unit'

class TestRand < Test::Unit::TestCase
  def test_mt
    srand(0x00000456_00000345_00000234_00000123)
    %w(1067595299  955945823  477289528 4107218783 4228976476).each {|w|
      assert_equal(w.to_i, rand(0x100000000))
    }
  end

  def test_0x3fffffff
    srand(0)
    %w(209652396 398764591 924231285 404868288 441365315).each {|w|
      assert_equal(w.to_i, rand(0x3fffffff))
    }
  end

  def test_0x40000000
    srand(0)
    %w(209652396 398764591 924231285 404868288 441365315).each {|w|
      assert_equal(w.to_i, rand(0x40000000))
    }
  end

  def test_0x40000001
    srand(0)
    %w(209652396 398764591 924231285 441365315 192771779).each {|w|
      assert_equal(w.to_i, rand(0x40000001))
    }
  end

  def test_0xffffffff
    srand(0)
    %w(2357136044 2546248239 3071714933 3626093760 2588848963).each {|w|
      assert_equal(w.to_i, rand(0xffffffff))
    }
  end

  def test_0x100000000
    srand(0)
    %w(2357136044 2546248239 3071714933 3626093760 2588848963).each {|w|
      assert_equal(w.to_i, rand(0x100000000))
    }
  end

  def test_0x100000001
    srand(0)
    %w(2546248239 1277901399 243580376 1171049868 2051556033).each {|w|
      assert_equal(w.to_i, rand(0x100000001))
    }
  end

  def test_rand_0x100000000
    srand(311702798)
    %w(4119812344 3870378946 80324654 4294967296 410016213).each {|w|
      assert_equal(w.to_i, rand(0x100000001))
    }
  end

  def test_0x1000000000000
    srand(0)
    %w(11736396900911
       183025067478208
       197104029029115
       130583529618791
       180361239846611).each {|w|
      assert_equal(w.to_i, rand(0x1000000000000))
    }
  end

  def test_0x1000000000001
    srand(0)
    %w(187121911899765
       197104029029115
       180361239846611
       236336749852452
       208739549485656).each {|w|
      assert_equal(w.to_i, rand(0x1000000000001))
    }
  end

  def test_0x3fffffffffffffff
    srand(0)
    %w(900450186894289455
       3969543146641149120
       1895649597198586619
       827948490035658087
       3203365596207111891).each {|w|
      assert_equal(w.to_i, rand(0x3fffffffffffffff))
    }
  end

  def test_0x4000000000000000
    srand(0)
    %w(900450186894289455
       3969543146641149120
       1895649597198586619
       827948490035658087
       3203365596207111891).each {|w|
      assert_equal(w.to_i, rand(0x4000000000000000))
    }
  end

  def test_0x4000000000000001
    srand(0)
    %w(900450186894289455
       3969543146641149120
       1895649597198586619
       827948490035658087
       2279347887019741461).each {|w|
      assert_equal(w.to_i, rand(0x4000000000000001))
    }
  end

  def test_neg_0x10000000000
    ws = %w(455570294424 1073054410371 790795084744 2445173525 1088503892627)
    srand(3)
    ws.each {|w| assert_equal(w.to_i, rand(0x10000000000)) }
    srand(3)
    ws.each {|w| assert_equal(w.to_i, rand(-0x10000000000)) }
  end

  def test_neg_0x10000
    ws = %w(2732 43567 42613 52416 45891)
    srand(0)
    ws.each {|w| assert_equal(w.to_i, rand(0x10000)) }
    srand(0)
    ws.each {|w| assert_equal(w.to_i, rand(-0x10000)) }
  end

  def test_types
    srand(0)
    assert_equal(44, rand(100.0))
    assert_equal(1245085576965981900420779258691, rand((2**100).to_f))
    assert_equal(914679880601515615685077935113, rand(-(2**100).to_f))

    srand(0)
    assert_equal(997707939797331598305742933184, rand(2**100))
    assert_in_delta(0.602763376071644, rand((2**100).coerce(0).first),
                    0.000000000000001)

    srand(0)
    assert_in_delta(0.548813503927325, rand(nil),
                    0.000000000000001)
    srand(0)
    o = Object.new
    def o.to_i; 100; end
    assert_equal(44, rand(o))
    assert_equal(47, rand(o))
    assert_equal(64, rand(o))
  end

  def test_srand
    srand
    assert_kind_of(Integer, rand(2))

    srand(2**100)
    %w(3258412053).each {|w|
      assert_equal(w.to_i, rand(0x100000000))
    }
  end

  def test_shuffle
    srand(0)
    assert_equal([1,4,2,5,3], [1,2,3,4,5].shuffle)
  end
  
  def test_fork_shuffle
    pid = fork do
      (1..10).to_a.shuffle
      raise 'default seed is not set' if srand == 0
    end
    p2, st = Process.waitpid2(pid)
    assert(st.success?)
  rescue NotImplementedError, ArgumentError
  end
end
