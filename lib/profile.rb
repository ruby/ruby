
module Profiler__
  Start = Float(Time.times[0])
  top = "toplevel".intern
  Stack = [[0, 0, top]]
  MAP = {"#toplevel" => [1, 0, 0, "#toplevel"]}

  p = proc{|event, file, line, id, binding, klass|
    case event
    when "call", "c-call"
      now = Float(Time.times[0])
      Stack.push [now, 0.0, id]
    when "return", "c-return"
      now = Float(Time.times[0])
      tick = Stack.pop
      name = klass.to_s
      if name.nil? then name = '' end
      if klass.kind_of? Class
	name += "#"
      else
	name += "."
      end
      name += id.id2name
      data = MAP[name]
      unless data
	data = [0.0, 0.0, 0.0, name]
	MAP[name] = data
      end
      data[0] += 1
      cost = now - tick[0]
      data[1] += cost
      data[2] += cost - tick[1]
      Stack[-1][1] += cost
    end
  }
  END {
    set_trace_func nil
    total = Float(Time.times[0]) - Start
    if total == 0 then total = 0.01 end
    MAP["#toplevel"][1] = total
#    f = open("./rmon.out", "w")
    f = STDERR
    data = MAP.values.sort!{|a,b| b[2] <=> a[2]}
    sum = 0
    f.printf "  %%   cumulative   self              self     total\n"           
    f.printf " time   seconds   seconds    calls  ms/call  ms/call  name\n"
    for d in data
      sum += d[2]
      f.printf "%6.2f %8.2f  %8.2f %8d ", d[2]/total*100, sum, d[2], d[0]
      f.printf "%8.2f %8.2f  %s\n", d[2]*1000/d[0], d[1]*1000/d[0], d[3]
    end
    f.close
  }
  set_trace_func p
end
