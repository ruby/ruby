require 'test/unit'

$KCODE = 'none'

class TestHash < Test::Unit::TestCase
  def test_hash
    $x = {1=>2, 2=>4, 3=>6}
    $y = {1, 2, 2, 4, 3, 6}
    
    assert($x[1] == 2)
    
    assert(begin   
         for k,v in $y
           raise if k*2 != v
         end
         true
       rescue
         false
       end)
    
    assert($x.length == 3)
    assert($x.has_key?(1))
    assert($x.has_value?(4))
    assert($x.values_at(2,3) == [4,6])
    assert($x == {1=>2, 2=>4, 3=>6})
    
    $z = $y.keys.join(":")
    assert($z == "1:2:3")
    
    $z = $y.values.join(":")
    assert($z == "2:4:6")
    assert($x == $y)
    
    $y.shift
    assert($y.length == 2)
    
    $z = [1,2]
    $y[$z] = 256
    assert($y[$z] == 256)
    
    $x = Hash.new(0)
    $x[1] = 1
    assert($x[1] == 1)
    assert($x[2] == 0)
    
    $x = Hash.new([])
    assert($x[22] == [])
    assert($x[22].equal?($x[22]))
    
    $x = Hash.new{[]}
    assert($x[22] == [])
    assert(!$x[22].equal?($x[22]))
    
    $x = Hash.new{|h,k| $z = k; h[k] = k*2}
    $z = 0
    assert($x[22] == 44)
    assert($z == 22)
    $z = 0
    assert($x[22] == 44)
    assert($z == 0)
    $x.default = 5
    assert($x[23] == 5)
    
    $x = Hash.new
    def $x.default(k)
      $z = k
      self[k] = k*2
    end
    $z = 0
    assert($x[22] == 44)
    assert($z == 22)
    $z = 0
    assert($x[22] == 44)
    assert($z == 0)
  end
end
