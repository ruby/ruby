
module Profiler__
  Start = Float(Time.now)
  top = "toplevel".intern
  Stack = [[0, 0, top]]
  MAP = {top => [1, 0, 0, "toplevel", top]}

  p = proc{|event, file, line, id, binding, klass|
    case event
    when "call", "c-call"
      now = Float(Time.now)
      Stack.push [now, 0.0, id]
    when "return", "c-return"
      now = Float(Time.now)
      tick = Stack.pop
      data = MAP[id]
      unless data
	name = klass.to_s
	if klass.kind_of? Class
	  name += "#"
	else
	  name += "."
	end
	data = [0, 0, 0, name+id.id2name, id]
	MAP[id] = data
      end
      data[0] += 1
      cost = now - tick[0]
      data[1] += cost unless id == Stack[-1][2]
      data[2] += cost - tick[1]
      Stack[-1][1] += cost
    end
  }
  END {
    set_trace_func nil
    total = MAP[:toplevel][1] = Float(Time.now) - Start
#    f = open("./rmon.out", "w")
    f = STDERR
    data = MAP.values.sort!{|a,b| b[2] <=> a[2]}
    f.printf "  %%   cumulative   self              self     total\n"           
    f.printf " time   seconds   seconds    calls  ms/call  ms/call  name\n"
    for d in data
      f.printf "%6.2f %8.2f  %8.2f %8d ", d[2]/total*100, d[1], d[2], d[0]
      f.printf "%8.2f %8.2f  %s\n", d[2]*1000/d[0], d[1]*1000/d[0], d[3]
    end
    f.close
  }
  set_trace_func p
end
