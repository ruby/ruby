#! ./ruby
# split into multi part
# usage: mpart.rb [-nnn] file..

class MPart < File
  def self.new(basename, extname, part, parts)
    super(sprintf("%s.%s%02d", basename, extname, part), "w").
      begin_mpart(basename, part, parts)
  end

  def begin_mpart(basename, part, parts)
    printf("%s part%02d/%02d\n", basename, part, parts)
    write("BEGIN--cut here--cut here\n")
    self
  end

  def close
    write("END--cut here--cut here\n")
    super
  end
end

lines = 1000

if (ARGV[0] =~ /^-(\d+)$/ )
  lines = $1.to_i
  ARGV.shift
end

basename = ARGV[0]
extname = "part"

part = 1
line = 0
ofp = nil

fline = 0
File.foreach(basename) {fline += 1}

parts = fline / lines + 1

File.foreach(basename) do |i|
  if line == 0
    ofp = MPart.new(basename, extname, part, parts)
  end
  ofp.write(i)
  line += 1
  if line >= lines
    ofp.close
    part += 1
    line = 0
  end
end
ofp.close
