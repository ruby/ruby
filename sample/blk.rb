def foo()
  $block = Block.new
end

foo(){i| print "i = ", i, "\n"}
$block.call(2)

foo(){i| print "i*2 = ", i*2, "\n"}
$block.call(2)
