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

end
