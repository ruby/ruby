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

count = 0
lines = []
encodings = []
encdir = ARGV[0]
outhdr = ARGV[1] || 'encdb.h'
Dir.open(encdir) {|d| d.grep(/.+\.[ch]\z/)}.sort.each do |fn|
  open(File.join(encdir,fn)) do |f|
    orig = nil
    name = nil
    encs = []
    f.each_line do |line|
      if (/^OnigEncodingDefine/ =~ line)..(/"(.*?)"/ =~ line)
        if $1
          check_duplication(encs, $1, fn, $.)
          encs << $1.upcase
          encodings << $1
          count += 1
        end
      else
        case line
        when /^\s*rb_enc_register\(\s*"([^"]+)"/
          count += 1
          line = nil
        when /^ENC_REPLICATE\(\s*"([^"]+)"\s*,\s*"([^"]+)"/
          raise ArgumentError,
          '%s:%d: ENC_REPLICATE: %s is not defined yet. (replica %s)' %
            [fn, $., $2, $1] unless encs.include?($2.upcase)
          count += 1
        when /^ENC_ALIAS\(\s*"([^"]+)"\s*,\s*"([^"]+)"/
          raise ArgumentError,
          '%s:%d: ENC_ALIAS: %s is not defined yet. (alias %s)' %
            [fn, $., $2, $1] unless encs.include?($2.upcase)
        when /^ENC_DUMMY\(\s*"([^"]+)"/
          count += 1
        else
          next
        end
        check_duplication(encs, $1, fn, $.)
        encs << $1.upcase
        lines << line.sub(/;.*/m, ";\n") if line
      end
    end
  end
end

result = encodings.map {|e| %[ENC_DEFINE("#{e}");\n]}.join + lines.join + 
  "\n#define ENCODING_COUNT #{count}\n"
mode = IO::RDWR|IO::CREAT
mode |= IO::BINARY if defined?(IO::BINARY)
open(outhdr, mode) do |f|
  unless f.read == result
    f.rewind
    f.truncate(0)
    f.print result
  end
end
