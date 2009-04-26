require 'optparse'
require 'erb'
require 'fileutils'

NUM_ELEM_BYTELOOKUP = 2

C_ESC = {
  "\\" => "\\\\",
  '"' => '\"',
  "\n" => '\n',
}

0x00.upto(0x1f) {|ch| C_ESC[[ch].pack("C")] ||= "\\%03o" % ch }
0x7f.upto(0xff) {|ch| C_ESC[[ch].pack("C")] = "\\%03o" % ch }
C_ESC_PAT = Regexp.union(*C_ESC.keys)

def c_esc(str)
  '"' + str.gsub(C_ESC_PAT) { C_ESC[$&] } + '"'
end

class StrSet
  def self.parse(pattern)
    if /\A\s*(([0-9a-f][0-9a-f]|\{([0-9a-f][0-9a-f]|[0-9a-f][0-9a-f]-[0-9a-f][0-9a-f])(,([0-9a-f][0-9a-f]|[0-9a-f][0-9a-f]-[0-9a-f][0-9a-f]))*\})+(\s+|\z))*\z/i !~ pattern
      raise ArgumentError, "invalid pattern: #{pattern.inspect}"
    end
    result = []
    pattern.scan(/\S+/) {|seq|
      seq_result = []
      while !seq.empty?
        if /\A([0-9a-f][0-9a-f])/i =~ seq
          byte = $1.to_i(16)
          seq_result << [byte..byte]
          seq = $'
        elsif /\A\{([^\}]+)\}/ =~ seq
          set = $1
          seq = $'
          set_result = []
          set.scan(/[^,]+/) {|range|
            if /\A([0-9a-f][0-9a-f])-([0-9a-f][0-9a-f])\z/i =~ range
              b = $1.to_i(16)
              e = $2.to_i(16)
              set_result << (b..e)
            elsif /\A([0-9a-f][0-9a-f])\z/i =~ range
              byte = $1.to_i(16)
              set_result << (byte..byte)
            else
              raise "invalid range: #{range.inspect}"
            end
          }
          seq_result << set_result
        else
          raise "invalid sequence: #{seq.inspect}"
        end
      end
      result << seq_result
    }
    self.new(result)
  end

  def initialize(pat)
    @pat = pat
  end

  def hash
    return @hash if defined? @hash
    @hash = @pat.hash
  end

  def eql?(other)
    self.class == other.class &&
    @pat == other.instance_eval { @pat }
  end

  alias == eql?

  def to_s
    if @pat.empty?
      "(empset)"
    else
      @pat.map {|seq|
        if seq.empty?
          "(empstr)"
        else
          seq.map {|byteset|
            if byteset.length == 1 && byteset[0].begin == byteset[0].end
              "%02x" % byteset[0].begin
            else
              "{" + 
              byteset.map {|range|
                if range.begin == range.end
                  "%02x" % range.begin
                else
                  "%02x-%02x" % [range.begin, range.end]
                end
              }.join(',') +
              "}"
            end
          }.join('')
        end
      }.join(' ')
    end
  end

  def inspect
    "\#<#{self.class}: #{self.to_s}>"
  end

  def min_length
    if @pat.empty?
      nil
    else
      @pat.map {|seq| seq.length }.min
    end
  end

  def max_length
    if @pat.empty?
      nil
    else
      @pat.map {|seq| seq.length }.max
    end
  end

  def emptyable?
    @pat.any? {|seq|
      seq.empty?
    }
  end

  def first_bytes
    result = {}
    @pat.each {|seq|
      next if seq.empty?
      seq.first.each {|range|
        range.each {|byte|
          result[byte] = true
        }
      }
    }
    result.keys.sort
  end

  def each_firstbyte
    h = {}
    @pat.each {|seq|
      next if seq.empty?
      seq.first.each {|range|
        range.each {|byte|
          (h[byte] ||= []) << seq[1..-1]
        }
      }
    }
    h.keys.sort.each {|byte|
      yield byte, StrSet.new(h[byte])
    }
  end
end

class ArrayCode
  def initialize(type, name)
    @type = type
    @name = name
    @len = 0;
    @content = ''
  end

  def length
    @len
  end

  def insert_at_last(num, str)
    newnum = self.length + num
    @content << str
    @len += num
  end

  def to_s
    <<"End"
static const #{@type}
#{@name}[#{@len}] = {
#{@content}};
End
  end
end

class ActionMap
  def self.parse(hash)
    h = {}
    hash.each {|pat, action|
      h[StrSet.parse(pat)] = action
    }
    self.new(h)
  end

  def initialize(h)
    @map = h
  end

  def hash
    return @hash if defined? @hash
    hash = 0
    @map.each {|k,v|
      hash ^= k.hash ^ v.hash
    }
    @hash = hash
  end

  def eql?(other)
    self.class == other.class &&
    @map == other.instance_eval { @map }
  end

  alias == eql?

  def inspect
    "\#<#{self.class}:" + 
    @map.map {|k, v| " [" + k.to_s + "]=>" + v.inspect }.join('') +
    ">"
  end

  def max_input_length
    @map.keys.map {|k| k.max_length }.max
  end

  def empty_action
    @map.each {|ss, action|
      return action if ss.emptyable?
    }
    nil
  end

  def each_firstbyte(valid_encoding=nil)
    h = {}
    @map.each {|ss, action|
      if ss.emptyable?
        raise "emptyable pattern"
      else
        ss.each_firstbyte {|byte, rest|
          h[byte] ||= {}
          if h[byte][rest]
            raise "ambiguous %s or %s (%02X/%s)" % [h[byte][rest], action, byte, rest]
          end
          h[byte][rest] = action
        }
      end
    }
    if valid_encoding
      valid_encoding.each_firstbyte {|byte, rest|
        if h[byte]
          am = ActionMap.new(h[byte])
          yield byte, am, rest
        else
          am = ActionMap.new(rest => :undef)
          yield byte, am, nil
        end
      }
    else
      h.keys.sort.each {|byte|
        am = ActionMap.new(h[byte])
        yield byte, am, nil
      }
    end
  end

  OffsetsMemo = {}
  InfosMemo = {}

  def format_offsets(min, max, offsets)
    offsets = offsets[min..max]
    code = "%d, %d,\n" % [min, max]
    0.step(offsets.length-1,16) {|i|
      code << "    "
      code << offsets[i,8].map {|off| "%3d," % off.to_s }.join('')
      if i+8 < offsets.length
        code << "  "
        code << offsets[i+8,8].map {|off| "%3d," % off.to_s }.join('')
      end
      code << "\n"
    }
    code
  end

  UsedName = {}

  StrMemo = {}

  def str_name(bytes)
    size = @bytes_code.length
    rawbytes = [bytes].pack("H*")

    n = nil
    if !n && !(suf = rawbytes.gsub(/[^A-Za-z0-9_]/, '')).empty? && !UsedName[nn = "str1_" + suf] then n = nn end
    if !n && !UsedName[nn = "str1_" + bytes] then n = nn end
    n ||= "str1s_#{size}"

    StrMemo[bytes] = n
    UsedName[n] = true
    n
  end

  def gen_str(bytes)
    if n = StrMemo[bytes]
      n
    else
      len = bytes.length/2
      size = @bytes_code.length
      n = str_name(bytes)
      @bytes_code.insert_at_last(1 + len,
        "\#define #{n} makeSTR1(#{size})\n" +
        "    makeSTR1LEN(#{len})," + bytes.gsub(/../, ' 0x\&,') + "\n\n")
      n
    end
  end

  def generate_info(info)
    case info
    when :nomap
      "NOMAP"
    when :undef
      "UNDEF"
    when :invalid
      "INVALID"
    when :func_ii
      "FUNii"
    when :func_si
      "FUNsi"
    when :func_io
      "FUNio"
    when :func_so
      "FUNso"
    when /\A([0-9a-f][0-9a-f])\z/i
      "o1(0x#$1)"
    when /\A([0-9a-f][0-9a-f])([0-9a-f][0-9a-f])\z/i
      "o2(0x#$1,0x#$2)"
    when /\A([0-9a-f][0-9a-f])([0-9a-f][0-9a-f])([0-9a-f][0-9a-f])\z/i
      "o3(0x#$1,0x#$2,0x#$3)"
    when /\A([0-9a-f][0-9a-f])(3[0-9])([0-9a-f][0-9a-f])(3[0-9])\z/i
      "g4(0x#$1,0x#$2,0x#$3,0x#$4)"
    when /\A(f[0-7])([0-9a-f][0-9a-f])([0-9a-f][0-9a-f])([0-9a-f][0-9a-f])\z/i
      "o4(0x#$1,0x#$2,0x#$3,0x#$4)"
    when /\A([0-9a-f][0-9a-f]){4,259}\z/i
      gen_str(info.upcase)
    when /\A\/\*BYTE_LOOKUP\*\// # pointer to BYTE_LOOKUP structure
      $'.to_s
    else
      raise "unexpected action: #{info.inspect}"
    end
  end

  def format_infos(infos)
    infos = infos.map {|info| generate_info(info) }
    maxlen = infos.map {|info| info.length }.max
    columns = maxlen <= 16 ? 4 : 2
    code = ""
    0.step(infos.length-1, columns) {|i|
      code << "    "
      is = infos[i,columns]
      is.each {|info|
        code << sprintf(" %#{maxlen}s,", info)
      }
      code << "\n"
    }
    code
  end

  def generate_lookup_node(bytes_code, words_code, name, table)
    offsets = []
    infos = []
    infomap = {}
    min = max = nil
    table.each_with_index {|action, byte|
      action ||= :invalid
      if action != :invalid
        min = byte if !min
        max = byte
      end
      unless o = infomap[action]
        infomap[action] = o = infos.length
        infos[o] = action
      end
      offsets[byte] = o
    }
    if !min
      min = max = 0
    end

    offsets_key = [min, max, offsets[min..max]]
    if n = OffsetsMemo[offsets_key]
      offsets_name = n
    else
      offsets_name = "#{name}_offsets"
      OffsetsMemo[offsets_key] = offsets_name
      size = bytes_code.length
      bytes_code.insert_at_last(2+max-min+1,
        "\#define #{offsets_name} #{size}\n" +
        format_offsets(min,max,offsets) + "\n")
    end

    if n = InfosMemo[infos]
      infos_name = n
    else
      infos_name = "#{name}_infos"
      InfosMemo[infos] = infos_name

      size = words_code.length
      words_code.insert_at_last(infos.length,
        "\#define #{infos_name} WORDINDEX2INFO(#{size})\n" +
        format_infos(infos) + "\n")
    end

    size = words_code.length
    words_code.insert_at_last(NUM_ELEM_BYTELOOKUP,
      "\#define #{name} WORDINDEX2INFO(#{size})\n" +
      <<"End" + "\n")
    #{offsets_name},
    #{infos_name},
End
  end

  PreMemo = {}
  PostMemo = {}
  NextName = "a"

  def generate_node(bytes_code, words_code, name_hint=nil, valid_encoding=nil)
    if n = PreMemo[[self,valid_encoding]]
      return n
    end

    table = Array.new(0x100, :invalid)
    each_firstbyte(valid_encoding) {|byte, rest, rest_valid_encoding|
      if a = rest.empty_action
        table[byte] = a
      else
        name_hint2 = nil
        name_hint2 = "#{name_hint}_#{'%02X' % byte}" if name_hint
        table[byte] = "/*BYTE_LOOKUP*/" + rest.gennode(bytes_code, words_code, name_hint2, rest_valid_encoding)
      end
    }

    if n = PostMemo[table]
      return n
    end

    if !name_hint
      name_hint = "fun_" + NextName.dup
      NextName.succ!
    end

    PreMemo[[self,valid_encoding]] = PostMemo[table] = name_hint

    generate_lookup_node(bytes_code, words_code, name_hint, table)
    name_hint
  end

  def gennode(bytes_code, words_code, name_hint=nil, valid_encoding=nil)
    @bytes_code = bytes_code
    @words_code = words_code
    name = generate_node(bytes_code, words_code, name_hint, valid_encoding)
    @bytes_code = nil
    @words_code = nil
    return name
  end
end

def citrus_mskanji_cstomb(csid, index)
  case csid
  when 0
    index
  when 1
    index + 0x80
  when 2, 3
    row = index >> 8
    raise "invalid byte sequence" if row < 0x21
    if csid == 3
      if row <= 0x2F
        offset = (row == 0x22 || row >= 0x26) ? 0xED : 0xF0
      elsif row >= 0x4D && row <= 0x7E
        offset = 0xCE
      else
        raise "invalid byte sequence"
      end
    else
      raise "invalid byte sequence" if row > 0x97
      offset = (row < 0x5F) ? 0x81 : 0xC1
    end
    col = index & 0xFF
    raise "invalid byte sequence" if (col < 0x21 || col > 0x7E)

    row -= 0x21
    col -= 0x21
    if (row & 1) == 0
      col += 0x40
      col += 1 if (col >= 0x7F)
    else
      col += 0x9F;
    end
    row = row / 2 + offset
    (row << 8) | col
  end.to_s(16)
end

def citrus_euc_cstomb(csid, index)
  case csid
  when 0x0000
    index
  when 0x8080
    index | 0x8080
  when 0x0080
    index | 0x8E80
  when 0x8000
    index | 0x8F8080
  end.to_s(16)
end

def citrus_cstomb(ces, csid, index)
  case ces
  when 'mskanji'
    citrus_mskanji_cstomb(csid, index)
  when 'euc'
    citrus_euc_cstomb(csid, index)
  end
end

SUBDIR = %w/APPLE AST BIG5 CNS CP EBCDIC GB GEORGIAN ISO646 ISO-8859 JIS KAZAKH KOI KS MISC TCVN/


def citrus_decode_mapsrc(ces, csid, mapsrcs)
  table = []
  mapsrcs.split(',').each do |mapsrc|
    path = [$srcdir]
    mode = nil
    if mapsrc.rindex('UCS', 0)
      mode = :from_ucs
      from = mapsrc[4..-1]
      path << SUBDIR.find{|x| from.rindex(x, 0) }
    else
      mode = :to_ucs
      path << SUBDIR.find{|x| mapsrc.rindex(x, 0) }
    end
    path << mapsrc.gsub(':', '@')
    path = File.join(*path)
    path << ".src"
    path[path.rindex('/')] = '%'
    STDERR.puts 'load mapsrc %s' % path if VERBOSE_MODE
    open(path) do |f|
      f.each_line do |l|
        break if /^BEGIN_MAP/ =~ l
      end
      f.each_line do |l|
        next if /^\s*(?:#|$)/ =~ l
          break if /^END_MAP/ =~ l
        case mode
        when :from_ucs
          case l
          when /0x(\w+)\s*-\s*0x(\w+)\s*=\s*INVALID/
            # Citrus OOB_MODE
          when /(0x\w+)\s*=\s*(0x\w+)/
            table.push << [$1.hex, citrus_cstomb(ces, csid, $2.hex)]
          else
            raise "unknown notation '%s'"% l
          end
        when :to_ucs
          case l
          when /(0x\w+)\s*=\s*(0x\w+)/
            table.push << [citrus_cstomb(ces, csid, $1.hex), $2.hex]
          else
            raise "unknown notation '%s'"% l
          end
        end
      end
    end
  end
  return table
end

def encode_utf8(map)
  r = []
  map.each {|k, v|
    # integer means UTF-8 encoded sequence.
    k = [k].pack("U").unpack("H*")[0].upcase if Integer === k
    v = [v].pack("U").unpack("H*")[0].upcase if Integer === v
    r << [k,v]
  }
  r
end

def transcode_compile_tree(name, from, map)
  map = encode_utf8(map)
  h = {}
  map.each {|k, v|
    h[k] = v unless h[k] # use first mapping
  }
  am = ActionMap.parse(h)

  max_input = am.max_input_length

  if ValidEncoding[from]
    valid_encoding = StrSet.parse(ValidEncoding[from])
  else
    valid_encoding = nil
  end

  defined_name = am.gennode(TRANSCODE_GENERATED_BYTES_CODE, TRANSCODE_GENERATED_WORDS_CODE, name, valid_encoding)
  return defined_name, max_input
end

TRANSCODERS = []
TRANSCODE_GENERATED_TRANSCODER_CODE = ''

def transcode_tbl_only(from, to, map)
  if VERBOSE_MODE
    if from.empty? || to.empty?
      STDERR.puts "converter for #{from.empty? ? to : from}"
    else
      STDERR.puts "converter from #{from} to #{to}"
    end
  end
  id_from = from.tr('^0-9A-Za-z', '_')
  id_to = to.tr('^0-9A-Za-z', '_')
  if from == "UTF-8"
    tree_name = "to_#{id_to}"
  elsif to == "UTF-8"
    tree_name = "from_#{id_from}"
  else
    tree_name = "from_#{id_from}_to_#{id_to}"
  end
  map = encode_utf8(map)
  real_tree_name, max_input = transcode_compile_tree(tree_name, from, map)
  return map, tree_name, real_tree_name, max_input
end

def transcode_tblgen(from, to, map)
  map, tree_name, real_tree_name, max_input = transcode_tbl_only(from, to, map)
  transcoder_name = "rb_#{tree_name}"
  TRANSCODERS << transcoder_name
  input_unit_length = UnitLength[from]
  max_output = map.map {|k,v| String === v ? v.length/2 : 1 }.max
  transcoder_code = <<"End"
static const rb_transcoder
#{transcoder_name} = {
    #{c_esc from}, #{c_esc to}, #{real_tree_name},
    TRANSCODE_TABLE_INFO,
    #{input_unit_length}, /* input_unit_length */
    #{max_input}, /* max_input */
    #{max_output}, /* max_output */
    asciicompat_converter, /* asciicompat_type */
    0, NULL, NULL, /* state_size, state_init, state_fini */
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL
};
End
  TRANSCODE_GENERATED_TRANSCODER_CODE << transcoder_code
  ''
end

def transcode_generate_node(am, name_hint=nil)
  STDERR.puts "converter for #{name_hint}" if VERBOSE_MODE
  name = am.gennode(TRANSCODE_GENERATED_BYTES_CODE, TRANSCODE_GENERATED_WORDS_CODE, name_hint)
  ''
end

def transcode_generated_code
  TRANSCODE_GENERATED_BYTES_CODE.to_s +
    TRANSCODE_GENERATED_WORDS_CODE.to_s +
    "\#define TRANSCODE_TABLE_INFO " +
    "#{OUTPUT_PREFIX}byte_array, #{TRANSCODE_GENERATED_BYTES_CODE.length}, " +
    "#{OUTPUT_PREFIX}word_array, #{TRANSCODE_GENERATED_WORDS_CODE.length}, " +
    "sizeof(unsigned int)\n" +
    TRANSCODE_GENERATED_TRANSCODER_CODE
end

def transcode_register_code
  code = ''
  TRANSCODERS.each {|transcoder_name|
    code << "    rb_register_transcoder(&#{transcoder_name});\n"
  }
  code
end

UnitLength = {
  'UTF-16BE'    => 2,
  'UTF-16LE'    => 2,
  'UTF-32BE'    => 4,
  'UTF-32LE'    => 4,
}
UnitLength.default = 1

ValidEncoding = {
  '1byte'       => '{00-ff}',
  '2byte'       => '{00-ff}{00-ff}',
  '4byte'       => '{00-ff}{00-ff}{00-ff}{00-ff}',
  'US-ASCII'    => '{00-7f}',
  'UTF-8'       => '{00-7f}
                    {c2-df}{80-bf}
                         e0{a0-bf}{80-bf}
                    {e1-ec}{80-bf}{80-bf}
                         ed{80-9f}{80-bf}
                    {ee-ef}{80-bf}{80-bf}
                         f0{90-bf}{80-bf}{80-bf}
                    {f1-f3}{80-bf}{80-bf}{80-bf}
                         f4{80-8f}{80-bf}{80-bf}',
  'UTF-16BE'    => '{00-d7,e0-ff}{00-ff}
                    {d8-db}{00-ff}{dc-df}{00-ff}',
  'UTF-16LE'    => '{00-ff}{00-d7,e0-ff}
                    {00-ff}{d8-db}{00-ff}{dc-df}',
  'UTF-32BE'    => '0000{00-d7,e0-ff}{00-ff}
                    00{01-10}{00-ff}{00-ff}',
  'UTF-32LE'    => '{00-ff}{00-d7,e0-ff}0000
                    {00-ff}{00-ff}{01-10}00',
  'EUC-JP'      => '{00-7f}
                    {a1-fe}{a1-fe}
                    8e{a1-fe}
                    8f{a1-fe}{a1-fe}',
  'CP51932'     => '{00-7f}
                    {a1-fe}{a1-fe}
                    8e{a1-fe}',
  'Shift_JIS'   => '{00-7f}
                    {81-9f,e0-fc}{40-7e,80-fc}
                    {a1-df}',
  'EUC-KR'      => '{00-7f}
                    {a1-fe}{a1-fe}',
  'CP949'       => '{00-7f}
                    {81-fe}{41-5a,61-7a,81-fe}',
  'Big5'        => '{00-7f}
                    {81-fe}{40-7e,a1-fe}',
  'EUC-TW'      => '{00-7f}
                    {a1-fe}{a1-fe}
                    8e{a1-b0}{a1-fe}{a1-fe}',
  'GBK'         => '{00-80}
                    {81-fe}{40-7e,80-fe}',
  'GB18030'     => '{00-7f}
                    {81-fe}{40-7e,80-fe}
                    {81-fe}{30-39}{81-fe}{30-39}',
}

def set_valid_byte_pattern (encoding, pattern_or_label)
  pattern =
    if ValidEncoding[pattern_or_label]
      ValidEncoding[pattern_or_label]
    else
      pattern_or_label
    end
  if ValidEncoding[encoding] and ValidEncoding[encoding]!=pattern
    raise ArgumentError, "trying to change valid byte pattern for encoding #{encoding} from #{ValidEncoding[encoding]} to #{pattern}"
  end
  ValidEncoding[encoding] = pattern
end

# the following may be used in different places, so keep them here for the moment
set_valid_byte_pattern 'ASCII-8BIT', '1byte'
set_valid_byte_pattern 'Windows-31J', 'Shift_JIS'
set_valid_byte_pattern 'eucJP-ms', 'EUC-JP'

def make_signature(filename, src)
  "src=#{filename.dump}, len=#{src.length}, checksum=#{src.sum}"
end

output_filename = nil
verbose_mode = false
force_mode = false

op = OptionParser.new
op.def_option("--help", "show help message") { puts op; exit 0 }
op.def_option("--verbose", "verbose mode") { verbose_mode = true }
op.def_option("--force", "force table generation") { force_mode = true }
op.def_option("--output=FILE", "specify output file") {|arg| output_filename = arg }
op.parse!

VERBOSE_MODE = verbose_mode

OUTPUT_FILENAME = output_filename
OUTPUT_PREFIX = output_filename ? File.basename(output_filename)[/\A[A-Za-z0-9_]*/] : ""
OUTPUT_PREFIX.sub!(/\A_+/, '')
OUTPUT_PREFIX.sub!(/_*\z/, '_')

TRANSCODE_GENERATED_BYTES_CODE = ArrayCode.new("unsigned char", "#{OUTPUT_PREFIX}byte_array")
TRANSCODE_GENERATED_WORDS_CODE = ArrayCode.new("unsigned int", "#{OUTPUT_PREFIX}word_array")

arg = ARGV.shift
$srcdir = File.dirname(arg)
$:.unshift $srcdir unless $:.include? $srcdir
src = File.read(arg)
src.force_encoding("ascii-8bit") if src.respond_to? :force_encoding
this_script = File.read(__FILE__)
this_script.force_encoding("ascii-8bit") if this_script.respond_to? :force_encoding

base_signature = "/* autogenerated. */\n"
base_signature << "/* #{make_signature(File.basename(__FILE__), this_script)} */\n"
base_signature << "/* #{make_signature(File.basename(arg), src)} */\n"

if !force_mode && output_filename && File.readable?(output_filename)
  old_signature = File.open(output_filename) {|f| f.gets("").chomp }
  chk_signature = base_signature.dup
  old_signature.each_line {|line|
    if %r{/\* src="([0-9a-z_.-]+)",} =~ line
      name = $1
      next if name == File.basename(arg) || name == File.basename(__FILE__)
      path = File.join($srcdir, name)
      if File.readable? path
        chk_signature << "/* #{make_signature(name, File.read(path))} */\n"
      end
    end
  }
  if old_signature == chk_signature
    now = Time.now
    File.utime(now, now, output_filename)
    STDERR.puts "already up-to-date: #{output_filename}" if VERBOSE_MODE
    exit
  end
end

if VERBOSE_MODE
  if output_filename
    STDERR.puts "generating #{output_filename} ..."
  end
end

libs1 = $".dup
erb = ERB.new(src, nil, '%')
erb.filename = arg
erb_result = erb.result(binding)
libs2 = $".dup

libs = libs2 - libs1
lib_sigs = ''
libs.each {|lib|
  lib = File.basename(lib)
  path = File.join($srcdir, lib)
  if File.readable? path
    lib_sigs << "/* #{make_signature(lib, File.read(path))} */\n"
  end
}

result = ''
result << base_signature
result << lib_sigs
result << "\n"
result << erb_result
result << "\n"

if output_filename
  new_filename = output_filename + ".new"
  FileUtils.mkdir_p(File.dirname(output_filename))
  File.open(new_filename, "wb") {|f| f << result }
  File.rename(new_filename, output_filename)
  STDERR.puts "done." if VERBOSE_MODE
else
  print result
end
