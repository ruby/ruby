#
# OnigEncodingDefine(foo, Foo) = {
#   ..
#   "Shift_JIS", /* Canonical Name */
#   ..
# };
# ENC_ALIAS("SJIS", "Shift_JIS")
# ENC_REPLICATE("Windows-31J", "Shift_JIS")
# ENC_ALIAS("CP932", "Windows-31J")
#

def check_duplication(encs, name, fn, line)
  if encs.include?(name)
    raise ArgumentError, "%s:%d: encoding %s is already registered" % [fn, line, name]
  end
end

encodings = []
replicas = {}
aliases = {}
encdir = ARGV[0]
Dir.open(encdir) {|d| d.grep(/.+\.c\z/)}.sort.each do |fn|
  open(File.join(encdir,fn)) do |f|
    orig = nil
    name = nil
    encs = []
    f.each_line do |line|
      break if /^OnigEncodingDefine/o =~ line
    end
    f.each_line do |line|
      break if /"(.*?)"/ =~ line
    end
    if $1
      check_duplication(encs, $1, fn, $.)
      encs << $1.upcase
      encodings << $1 
      f.each_line do |line|
	if /^ENC_REPLICATE\(\s*"([^"]+)"\s*,\s*"([^"]+)"/o =~ line
	  raise ArgumentError,
	    '%s:%d: ENC_REPLICATE: %s is not defined yet. (replica %s)' %
	    [fn, $., $2, $1] unless encs.include?($2.upcase)
	  check_duplication(encs, $1, fn, $.)
	  encs << $1.upcase
	  encodings << $1
	  replicas[$1] = $2
	elsif /^ENC_ALIAS\(\s*"([^"]+)"\s*,\s*"([^"]+)"/o =~ line
	  raise ArgumentError,
	    '%s:%d: ENC_ALIAS: %s is not defined yet. (alias %s)' %
	    [fn, $., $2, $1] unless encs.include?($2.upcase)
	  check_duplication(encs, $1, fn, $.)
	  encodings << $1
	  aliases[$1] = $2
	end
      end
    end
  end
end

open('encdb.h', 'wb') do |f|
  f.puts 'static const char *const enc_name_list[] = {'
  encodings.each {|name| f.puts'    "%s",' % name}
  f.puts('};', '', 'static void', 'enc_init_db(void)', '{')
  replicas.each_pair {|name, orig|
    f.puts '    ENC_REPLICATE("%s", "%s");' % [name, orig]
  }
  aliases.each_pair {|name, orig|
    f.puts '    ENC_ALIAS("%s", "%s");' % [name, orig]
  }
  f.puts '}'
end
