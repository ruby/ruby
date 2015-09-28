class C; 1000.times{|i|eval("def i#{i};end")}; end
c = C.new; m = C.instance_methods(false)
1_000.times{m.each{|n|c.tap(&n)}}
