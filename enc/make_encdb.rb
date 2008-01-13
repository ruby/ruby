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
Dir.open(encdir) {|d| d.grep(/.+\.c\z/)}.each do |fn|
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
	replicas[$1] = $2
      elsif /^ENC_ALIAS\(\s*"([^"]+)"\s*,\s*"([^"]+)"/o =~ line
	aliases[$1] = $2
      end
    end
  end
end
p aliases
open('encdb.h', 'wb') do |f|
  f.puts 'static const char *enc_name_list[] = {'
  encodings.each {|name| f.puts'    "%s",' % name}
  replicas.each_key {|name| f.puts'    "%s",' % name}
  aliases.each_key {|name| f.puts'    "%s",' % name}
  f.puts(<<"_TEXT_")
};
#define enc_name_list_size (sizeof(enc_name_list)/sizeof(enc_name_list[0]))

static void enc_init_db(void)
{
    if (!enc_table.replica_name) {
	enc_table.replica_name = st_init_strcasetable();
    }
    if (!enc_table.alias_name) {
	enc_table.alias_name = st_init_strcasetable();
    }
_TEXT_
  replicas.each_pair {|name, orig|
    f.puts'    st_insert(enc_table.replica_name, (st_data_t)"%s", (st_data_t)"%s");' % [name, orig]}
  aliases.each_pair {|name, orig|
    f.puts'    st_insert(enc_table.alias_name, (st_data_t)"%s", (st_data_t)"%s");' % [name, orig]}
  f.puts '}'
end
