#! /usr/local/bin/ruby

def older(file1, file2)
  if !File.exist?(file1) then
    return TRUE
  end
  if !File.exist?(file2) then
    return FALSE
  end
  if File.mtime(file1) < File.mtime(file2)
    return TRUE
  end
  return FALSE
end

target = ARGV.shift
unless target =~ /\.so/
  STDERR.printf "wrong suffix specified\n"
  exit 1
end
base = File.basename(target, ".so")
entry="Init_#{base}"
ldargs = "-e#{entry} -bI:../ruby.imp -bM:SRE -T512 -H512 -lc"

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
if older("../ruby.imp", "../../miniruby")
  nm = open("|/usr/ccs/bin/nm -p ../../*.o")
  extract(nm, "../ruby.imp")
end

#objs = Dir["*.o"].join(" ")
#nm = open("|/usr/ccs/bin/nm -p #{objs}")
#extract(nm, "#{base}.exp")

cmd = format("/usr/ccs/bin/ld %s %s ", ldargs, ARGV.join(' '))
printf "\t%s\n", cmd
system cmd
