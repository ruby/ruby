def foo()
  $block = Block.new
end

foo(){i | print "i = ", i, "\n"}
$block.do(2)

foo(){i | print "i*2 = ", i*2, "\n"}
$block.do(2)
