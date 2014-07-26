require 'weakref'

foo = Object.new
p foo.to_s                    # original's class
foo = WeakRef.new(foo)
p foo.to_s                    # should be same class
ObjectSpace.garbage_collect
ObjectSpace.garbage_collect
p foo.to_s                    # should raise exception (recycled)
