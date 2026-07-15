# RLGCv2: aggressive Ractor#send(move:) churn -- many movers receiving moves
# from a busy main, deep/mixed graphs, generic ivars, GC pressure, and the
# consistency verifier interleaved on receivers. Flushes out concurrency in
# the receive-side move re-home (design_v2.md section 4.5).
Warning[:experimental] = false

def mkgraph(n)
  g = [+"s#{n}", n, { +"k#{n}" => [+"v#{n}", n * 2] }]
  o = Object.new
  o.instance_variable_set(:@a, [+"x#{n}", g])
  o.instance_variable_set(:@b, +"tag#{n}")
  6.times { |d| g = [+"d#{d}-#{n}", g, o] }
  g
end

movers = 8.times.map do |id|
  Ractor.new(id) do |idx|
    got = 0
    held = nil
    loop do
      msg = Ractor.receive
      break if msg == :stop
      got += 1
      # walk the moved graph (touches every re-homed node)
      depth = 0; m = msg
      while m.is_a?(Array)
        depth += 1
        m.each { |e| } # touch elements
        m = m[1]
        break if depth > 20
      end
      Array.new(200) { +"local#{idx}" }       # local churn -> local GC
      held = msg if got % 3 == 0               # retain some
      if got % 50 == 0
        GC.verify_internal_consistency
        GC.start(full_mark: got % 200 == 0)
      end
    end
    GC.verify_internal_consistency
    [got, held ? :held : :none]
  end
end

# main: busy sender (allocation + GC drive global/local GC during receivers' re-home)
1500.times do |n|
  movers[n % movers.size].send(mkgraph(n), move: true)
  if n % 25 == 0
    Array.new(500) { +"main#{n}" }
    GC.start(full_mark: n % 100 == 0)
  end
end
movers.each { |m| m.send(:stop) }
res = movers.map(&:value)
raise "a mover got nothing: #{res.inspect}" unless res.all? { |(g, _)| g > 0 }
GC.verify_internal_consistency
puts "MOVE_CHURN_OK"
