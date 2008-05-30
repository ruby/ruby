#
# static const rb_transcoder
# rb_from_US_ASCII = {
#     "US-ASCII", "UTF-8", &from_US_ASCII, 1, 0,
#     NULL, NULL,
# };
#

count = 0
converters = {}
transdir = ARGV[0]
outhdr = ARGV[1] || 'transdb.h'
Dir.open(transdir) {|d| d.grep(/.+\.[ch]\z/)}.sort_by {|e|
  e.scan(/(\d+)|(\D+)/).map {|n,a| a||[n.size,n.to_i]}.flatten
}.each do |fn|
  open(File.join(transdir,fn)) do |f|
    f.each_line do |line|
      if (/^static const rb_transcoder/ =~ line)..(/"(.*?)"\s*,\s*"(.*?)"/ =~ line)
        if $1 && $2
	  from_to = "%s to %s" % [$1, $2]
          converters[from_to]
          if converters[from_to]
	    raise ArgumentError, '%s:%d: transcode "%s" is already registered (%s:%d)' %
	      [fn, $., from_to, *converters[from_to].values_at(2, 3)]
	  else
	    converters[from_to] = [$1, $2, fn[0..-3], $.]
	  end
        end
      end
    end
  end
end
result = converters.map {|k, v| %[rb_declare_transcoder("%s", "%s", "%s");\n] % v}.join
open(outhdr, 'wb') do |f|
  f.print result
end
