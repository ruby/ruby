#!./miniruby -s

SYM = {}

objs = ARGV.collect {|s| p s+'\n'; s.tr('/', '\\') }
IO.foreach("|dumpbin -symbols " + objs.join(' ')) do |l|
  next if /^[0-9A-F]+ 0+ UNDEF / =~ l
  next unless l.sub!(/.*\sExternal\s+\|\s+/, '')
  if ARGV[1]=="sh3"
    if l.sub!(/^_/, '')                            # _ で始まるならtrue
      next if /@.*@/ =~ l || /@[0-9a-f]{16}$/ =~ l #   かつ、@ とか混じったら next
    elsif !l.sub!(/^(\S+) \([^@?\`\']*\)$/, '\1')  # _ ではじまっていなくて、@ とか混じっていたらnext
      next
    end
  else
    next if /@.*@/ =~ l || /@[0-9a-f]{16}$/ =~ l #   かつ、@ とか混じったら next
  end
  SYM[l.strip] = true
end


exports = []
if $name
  exports << "Name " + $name
elsif $library
  exports << "Library " + $library
end
exports << "Description " + $description.dump if $description
exports << "EXPORTS" << SYM.keys.sort

if $output
  open($output, 'w') {|f| f.puts exports.join("\n")}
else
  puts exports.join("\n")
end
