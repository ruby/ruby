#
# static const rb_transcoder
# rb_from_US_ASCII = {
#     "US-ASCII", "UTF-8", &from_US_ASCII, 1, 0,
#     NULL, NULL,
# };
#

count = 0
converters = {}
transdirs = ARGV.dup
outhdr = transdirs.shift || 'transdb.h'
transdirs << 'enc/trans' if transdirs.empty?
files = {}
transdirs.each do |transdir|
  next unless File.directory?(transdir)
  Dir.open(transdir) {|d| d.grep(/.+\.[ch]\z/) }.sort_by {|e|
    e.scan(/(\d+)|(\D+)/).map {|n,a| a||[n.size,n.to_i]}.flatten
  }.each do |fn|
    next if files[fn]
    files[fn] = true
    path = File.join(transdir,fn)
    open(path) do |f|
      f.each_line do |line|
        if (/^static const rb_transcoder/ =~ line)..(/"(.*?)"\s*,\s*"(.*?)"/ =~ line)
          if $1 && $2
            from_to = "%s to %s" % [$1, $2]
            if converters[from_to]
              raise ArgumentError, '%s:%d: transcode "%s" is already registered at %s:%d' %
              [path, $., from_to, *converters[from_to].values_at(3, 4)]
            else
              converters[from_to] = [$1, $2, fn[0..-3], path, $.]
            end
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
