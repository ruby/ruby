module Profiler__
  Times = if defined? Process.times then Process else Time end
  # internal values
  @@start = @@stack = @@map = nil
  PROFILE_PROC = proc{|event, file, line, id, binding, klass|
    case event
    when "call", "c-call"
      now = Float(Times::times[0])
      @@stack.push [now, 0.0, id]
    when "return", "c-return"
      now = Float(Times::times[0])
      tick = @@stack.pop
      name = klass.to_s
      if name.nil? then name = '' end
      if klass.kind_of? Class
	name += "#"
      else
	name += "."
      end
      name += id.id2name
      data = @@map[name]
      unless data
	data = [0.0, 0.0, 0.0, name]
	@@map[name] = data
      end
      data[0] += 1
      cost = now - tick[0]
      data[1] += cost
      data[2] += cost - tick[1]
      @@stack[-1][1] += cost
    end
  }
module_function
  def start_profile
    @@start = Float(Times::times[0])
    @@stack = [[0, 0, :toplevel], [0, 0, :dummy]]
    @@map = {"#toplevel" => [1, 0, 0, "#toplevel"]}
    set_trace_func PROFILE_PROC
  end
  def stop_profile
    set_trace_func nil
  end
  def print_profile(f)
    stop_profile
    total = Float(Times::times[0]) - @@start
    if total == 0 then total = 0.01 end
    @@map["#toplevel"][1] = total
    data = @@map.values
    data.sort!{|a,b| b[2] <=> a[2]}
    sum = 0
    f.printf "  %%   cumulative   self              self     total\n"           
    f.printf " time   seconds   seconds    calls  ms/call  ms/call  name\n"
    for d in data
      sum += d[2]
      f.printf "%6.2f %8.2f  %8.2f %8d ", d[2]/total*100, sum, d[2], d[0]
      f.printf "%8.2f %8.2f  %s\n", d[2]*1000/d[0], d[1]*1000/d[0], d[3]
    end
  end
end
