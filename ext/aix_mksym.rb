
def uniq(data)
  last=nil
  data.delete_if do |name|
    if last == name
      TRUE
    else
      last = name
      FALSE
    end
  end
end

def extract(nm, out)
  data = nm.readlines.collect{|line|
    line = line.split
    case line[1]
    when "B", "D"
      line[0]
    else
      next
    end
  }.compact!.sort!
  uniq(data)
  exp = open(out, "w")
  exp.printf "#!\n"
  for line in data
    exp.printf "%s\n", line
  end
  exp.close
  nm.close
end
extract(open("|/usr/ccs/bin/nm -p ../libruby.a"), "../ruby.imp")
