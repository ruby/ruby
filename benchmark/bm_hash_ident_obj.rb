h = {}.compare_by_identity
objs = 26.times.map { Object.new }
objs.each { |o| h[o] = o }
500_000.times { objs.each { |o| h[o] } }
