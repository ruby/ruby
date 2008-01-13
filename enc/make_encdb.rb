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

encodings = []
replicas = {}
aliases = {}
encdir = ARGV[0]
Dir.open(encdir) {|d| d.grep(/.+\.c\z/)}.sort.each do |fn|
  open(File.join(encdir,fn)) do |f|
    orig = nil
    name = nil
    f.each_line do |line|
      break if /^OnigEncodingDefine/o =~ line
    end
    f.each_line do |line|
      break if /"(.*?)"/ =~ line
    end
    encodings << $1 if $1
    f.each_line do |line|
      if /^ENC_REPLICATE\(\s*"([^"]+)"\s*,\s*"([^"]+)"/o =~ line
	encodings << $1
	replicas[$1] = $2
      elsif /^ENC_ALIAS\(\s*"([^"]+)"\s*,\s*"([^"]+)"/o =~ line
	encodings << $1
	aliases[$1] = $2
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
