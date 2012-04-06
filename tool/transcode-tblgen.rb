# -*- coding: utf-8 -*-
require 'optparse'
require 'erb'
require 'fileutils'
require 'pp'

class Array
  unless [].respond_to? :product
    def product(*args)
      if args.empty?
        self.map {|e| [e] }
      else
        result = []
        self.each {|e0|
          result.concat args.first.product(*args[1..-1]).map {|es| [e0, *es] }
        }
        result
      end
    end
  end
end

class String
  unless "".respond_to? :start_with?
    def start_with?(*prefixes)
      prefixes.each {|prefix|
        return true if prefix.length <= self.length && prefix == self[0, prefix.length]
      }
      false
    end
  end
end

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

HEX2 = /(?:[0-9A-Fa-f]{2})/

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

class Action
  def initialize(value)
    @value = value
  end
  attr_reader :value

  def hash
    @value.hash
  end

  def eql?(other)
    self.class == other.class &&
    @value == other.value
  end
  alias == eql?
end

class Branch
  def initialize(byte_min, byte_max, child_tree)
    @byte_min = byte_min
    @byte_max = byte_max
    @child_tree = child_tree
    @hash = byte_min.hash ^ byte_max.hash ^ child_tree.hash
  end
  attr_reader :byte_min, :byte_max, :child_tree, :hash

  def eql?(other)
    self.class == other.class &&
    @hash == other.hash &&
    @byte_min == other.byte_min &&
    @byte_max == other.byte_max &&
    @child_tree == other.child_tree
  end
  alias == eql?
end

class ActionMap
  def self.parse_to_rects(mapping)
    rects = []
    n = 0
    mapping.each {|pat, action|
      pat = pat.to_s
      if /\A\s*\(empset\)\s*\z/ =~ pat
        next
      elsif /\A\s*\(empstr\)\s*\z/ =~ pat
        rects << ['', '', action]
        n += 1
      elsif /\A\s*(#{HEX2}+)\s*\z/o =~ pat
        hex = $1.upcase
        rects << [hex, hex, action]
      elsif /\A\s*((#{HEX2}|\{#{HEX2}(?:-#{HEX2})?(,#{HEX2}(?:-#{HEX2})?)*\})+(\s+|\z))*\z/o =~ pat
        pat = pat.upcase
        pat.scan(/\S+/) {
          pat1 = $&
          ranges_list = []
          pat1.scan(/#{HEX2}|\{([^\}]*)\}/o) {
            ranges_list << []
            if !$1
              ranges_list.last << [$&,$&]
            else
              set = {}
              $1.scan(/(#{HEX2})(?:-(#{HEX2}))?/o) {
                if !$2
                  c = $1.to_i(16)
                  set[c] = true
                else
                  b = $1.to_i(16)
                  e = $2.to_i(16)
                  b.upto(e) {|c| set[c] = true }
                end
              }
              i = nil
              0.upto(256) {|j|
                if set[j]
                  if !i
                    i = j
                  end
                  if !set[j+1]
                    ranges_list.last << ["%02X" % i, "%02X" % j]
                    i = nil
                  end
                end
              }
            end
          }
          first_ranges = ranges_list.shift
          first_ranges.product(*ranges_list).each {|range_list|
            min = range_list.map {|x, y| x }.join
            max = range_list.map {|x, y| y }.join
            rects << [min, max, action]
          }
        }
      else
        raise ArgumentError, "invalid pattern: #{pat.inspect}"
      end
    }
    rects
  end

  def self.unambiguous_action(actions0)
    actions = actions0.uniq
    if actions.length == 1
      actions[0]
    else
      actions.delete(:nomap0)
      if actions.length == 1
        actions[0]
      else
        raise ArgumentError, "ambiguous actions: #{actions0.inspect}"
      end
    end
  end

  def self.build_tree(rects)
    expand(rects) {|prefix, actions|
      unambiguous_action(actions)
    }
  end

  def self.parse(mapping)
    rects = parse_to_rects(mapping)
    tree = build_tree(rects)
    self.new(tree)
  end

  def self.merge_rects(*rects_list)
    if rects_list.length < 2
      raise ArgumentError, "not enough arguments"
    end

    all_rects = []
    rects_list.each_with_index {|rects, i|
      all_rects.concat rects.map {|min, max, action| [min, max, [i, action]] }
    }

    tree = expand(all_rects) {|prefix, actions|
      args = Array.new(rects_list.length) { [] }
      actions.each {|i, action|
        args[i] << action
      }
      yield(prefix, *args)
    }

    self.new(tree)
  end

  def self.merge(*mappings, &block)
    merge_rects(*mappings.map {|m| parse_to_rects(m) }, &block)
  end

  def self.merge2(map1, map2, &block)
    rects1 = parse_to_rects(map1)
    rects2 = parse_to_rects(map2)

    actions = []
    all_rects = []

    rects1.each {|rect|
      min, max, action = rect
      rect[2] = actions.length
      actions << action
      all_rects << rect
    }

    boundary = actions.length

    rects2.each {|rect|
      min, max, action = rect
      rect[2] = actions.length
      actions << action
      all_rects << rect
    }

    tree = expand(all_rects) {|prefix, as0|
      as1 = []
      as2 = []
      as0.each {|i|
        if i < boundary
          as1 << actions[i]
        else
          as2 << actions[i]
        end
      }
      yield(prefix, as1, as2)
    }

    self.new(tree)
  end

  def self.expand(rects, &block)
    #numsing = numreg = 0
    #rects.each {|min, max, action| if min == max then numsing += 1 else numreg += 1 end }
    #puts "#{numsing} singleton mappings and #{numreg} region mappings."
    singleton_rects = []
    region_rects = []
    rects.each {|rect|
      min, max, action = rect
      if min == max
        singleton_rects << rect
      else
        region_rects << rect
      end
    }
    @singleton_rects = singleton_rects.sort_by {|min, max, action| min }
    @singleton_rects.reverse!
    ret = expand_rec("", region_rects, &block)
    @singleton_rects = nil
    ret
  end

  TMPHASH = {}
  def self.expand_rec(prefix, region_rects, &block)
    return region_rects if region_rects.empty? && !((s_rect = @singleton_rects.last) && s_rect[0].start_with?(prefix))
    if region_rects.empty? ? s_rect[0].length == prefix.length : region_rects[0][0].empty?
      h = TMPHASH
      while (s_rect = @singleton_rects.last) && s_rect[0].start_with?(prefix)
        min, max, action = @singleton_rects.pop
        raise ArgumentError, "ambiguous pattern: #{prefix}" if min.length != prefix.length
        h[action] = true
      end
      region_rects.each {|min, max, action|
        raise ArgumentError, "ambiguous pattern: #{prefix}" if !min.empty?
        h[action] = true
      }
      tree = Action.new(block.call(prefix, h.keys))
      h.clear
    else
      tree = []
      each_firstbyte_range(prefix, region_rects) {|byte_min, byte_max, r_rects2|
        if byte_min == byte_max
          prefix2 = prefix + "%02X" % byte_min
        else
          prefix2 = prefix + "{%02X-%02X}" % [byte_min, byte_max]
        end
        child_tree = expand_rec(prefix2, r_rects2, &block)
        tree << Branch.new(byte_min, byte_max, child_tree)
      }
    end
    return tree
  end

  def self.each_firstbyte_range(prefix, region_rects)
    index_from = TMPHASH

    region_ary = []
    region_rects.each {|min, max, action|
      raise ArgumentError, "ambiguous pattern: #{prefix}" if min.empty?
      min_firstbyte = min[0,2].to_i(16)
      min_rest = min[2..-1]
      max_firstbyte = max[0,2].to_i(16)
      max_rest = max[2..-1]
      region_ary << [min_firstbyte, max_firstbyte, [min_rest, max_rest, action]]
      index_from[min_firstbyte] = true
      index_from[max_firstbyte+1] = true
    }

    byte_from = Array.new(index_from.size)
    bytes = index_from.keys
    bytes.sort!
    bytes.reverse!
    bytes.each_with_index {|byte, i|
      index_from[byte] = i
      byte_from[i] = byte
    }

    region_rects_ary = Array.new(index_from.size) { [] }
    region_ary.each {|min_firstbyte, max_firstbyte, rest_elt|
      index_from[min_firstbyte].downto(index_from[max_firstbyte+1]+1) {|i|
        region_rects_ary[i] << rest_elt
      }
    }

    index_from.clear

    r_rects = region_rects_ary.pop
    region_byte = byte_from.pop
    prev_r_start = region_byte
    prev_r_rects = []
    while r_rects && (s_rect = @singleton_rects.last) && (seq = s_rect[0]).start_with?(prefix)
      singleton_byte = seq[prefix.length, 2].to_i(16)
      min_byte = singleton_byte < region_byte ? singleton_byte : region_byte
      if prev_r_start < min_byte && !prev_r_rects.empty?
        yield prev_r_start, min_byte-1, prev_r_rects
      end
      if region_byte < singleton_byte
        prev_r_start = region_byte
        prev_r_rects = r_rects
        r_rects = region_rects_ary.pop
        region_byte = byte_from.pop
      elsif region_byte > singleton_byte
        yield singleton_byte, singleton_byte, prev_r_rects
        prev_r_start = singleton_byte+1
      else # region_byte == singleton_byte
        prev_r_start = region_byte+1
        prev_r_rects = r_rects
        r_rects = region_rects_ary.pop
        region_byte = byte_from.pop
        yield singleton_byte, singleton_byte, prev_r_rects
      end
    end

    while r_rects
      if prev_r_start < region_byte && !prev_r_rects.empty?
        yield prev_r_start, region_byte-1, prev_r_rects
      end
      prev_r_start = region_byte
      prev_r_rects = r_rects
      r_rects = region_rects_ary.pop
      region_byte = byte_from.pop
    end

    while (s_rect = @singleton_rects.last) && (seq = s_rect[0]).start_with?(prefix)
      singleton_byte = seq[prefix.length, 2].to_i(16)
      yield singleton_byte, singleton_byte, []
    end
  end

  def initialize(tree)
    @tree = tree
  end

  def inspect
    "\#<#{self.class}:" +
    @tree.inspect +
    ">"
  end

  def max_input_length_rec(tree)
    case tree
    when Action
      0
    else
      tree.map {|branch|
        max_input_length_rec(branch.child_tree)
      }.max + 1
    end
  end

  def max_input_length
    max_input_length_rec(@tree)
  end

  def empty_action
    if @tree.kind_of? Action
      @tree.value
    else
      nil
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
    when :nomap, :nomap0
      # :nomap0 is low priority.  it never collides.
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
    when /\A(#{HEX2})\z/o
      "o1(0x#$1)"
    when /\A(#{HEX2})(#{HEX2})\z/o
      "o2(0x#$1,0x#$2)"
    when /\A(#{HEX2})(#{HEX2})(#{HEX2})\z/o
      "o3(0x#$1,0x#$2,0x#$3)"
    when /funsio\((\d+)\)/
      "funsio(#{$1})"
    when /\A(#{HEX2})(3[0-9])(#{HEX2})(3[0-9])\z/o
      "g4(0x#$1,0x#$2,0x#$3,0x#$4)"
    when /\A(f[0-7])(#{HEX2})(#{HEX2})(#{HEX2})\z/o
      "o4(0x#$1,0x#$2,0x#$3,0x#$4)"
    when /\A(#{HEX2}){4,259}\z/o
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

  def generate_lookup_node(name, table)
    bytes_code = @bytes_code
    words_code = @words_code
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
    infomap.clear
    if !min
      min = max = 0
    end

    # 一つの文字コード変換を Tables クラスとしてデータで格納
    GENERATED_CODE << Tables.new(name, min, max, offsets, infos)

=begin
      # 文字列化をしない
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

        infos_state = 0
      end

      size = words_code.length
      words_code.insert_at_last(NUM_ELEM_BYTELOOKUP,
                           "\#define #{name} WORDINDEX2INFO(#{size})\n" +
                           <<"End" + "\n")
    #{offsets_name},
    #{infos_name},
End
=end

  end

  PreMemo = {}
  NextName = "a"

  def generate_node(name_hint=nil)
    if n = PreMemo[@tree]
      return n
    end

    table = Array.new(0x100, :invalid)
    @tree.each {|branch|
      byte_min, byte_max, child_tree = branch.byte_min, branch.byte_max, branch.child_tree
      rest = ActionMap.new(child_tree)
      if a = rest.empty_action
        table.fill(a, byte_min..byte_max)
      else
        name_hint2 = nil
        if name_hint
          name_hint2 = "#{name_hint}_#{byte_min == byte_max ? '%02X' % byte_min : '%02Xto%02X' % [byte_min, byte_max]}"
        end
        v = "/*BYTE_LOOKUP*/" + rest.gennode(@bytes_code, @words_code, name_hint2)
        table.fill(v, byte_min..byte_max)
      end
    }

    if !name_hint
      name_hint = "fun_" + NextName
      NextName.succ!
    end

    PreMemo[@tree] = name_hint

    generate_lookup_node(name_hint, table)
    name_hint
  end

  def gennode(bytes_code, words_code, name_hint=nil)
    @bytes_code = bytes_code
    @words_code = words_code
    name = generate_node(name_hint)
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

def citrus_stateless_iso_cstomb(csid, index)
  (index | 0x8080 | (csid << 16)).to_s(16)
end

def citrus_cstomb(ces, csid, index)
  case ces
  when 'mskanji'
    citrus_mskanji_cstomb(csid, index)
  when 'euc'
    citrus_euc_cstomb(csid, index)
  when 'stateless_iso'
    citrus_stateless_iso_cstomb(csid, index)
  end
end

SUBDIR = %w/APPLE AST BIG5 CNS CP EBCDIC EMOJI GB GEORGIAN ISO646 ISO-8859 JIS KAZAKH KOI KS MISC TCVN/


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

def import_ucm(path)
  to_ucs = []
  from_ucs = []
  File.foreach(File.join($srcdir, "ucm", path)) do |line|
    uc, bs, fb = nil
    if /^<U([0-9a-fA-F]+)>\s*([\+0-9a-fA-Fx\\]+)\s*\|(\d)/ =~ line
      uc = $1.hex
      bs = $2.delete('x\\')
      fb = $3.to_i
      next if uc < 128 && uc == bs.hex
    elsif /^([<U0-9a-fA-F>+]+)\s*([\+0-9a-fA-Fx\\]+)\s*\|(\d)/ =~ line
      uc = $1.scan(/[0-9a-fA-F]+>/).map(&:hex).pack("U*").unpack("H*")[0]
      bs = $2.delete('x\\')
      fb = $3.to_i
    end
    to_ucs << [bs, uc] if fb == 0 || fb == 3
    from_ucs << [uc, bs] if fb == 0 || fb == 1
  end
  [to_ucs, from_ucs]
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

UnspecifiedValidEncoding = Object.new

def transcode_compile_tree(name, from, map, valid_encoding)
  map = encode_utf8(map)
  h = {}
  map.each {|k, v|
    h[k] = v unless h[k] # use first mapping
  }
  if valid_encoding.equal? UnspecifiedValidEncoding
    valid_encoding = ValidEncoding.fetch(from)
  end
  if valid_encoding
    am = ActionMap.merge2(h, {valid_encoding => :undef}) {|prefix, as1, as2|
      a1 = as1.empty? ? nil : ActionMap.unambiguous_action(as1)
      a2 = as2.empty? ? nil : ActionMap.unambiguous_action(as2)
      if !a2
        raise "invalid mapping: #{prefix}"
      end
      a1 || a2
    }
  else
    am = ActionMap.parse(h)
  end
  h.clear

  max_input = am.max_input_length
  defined_name = am.gennode(TRANSCODE_GENERATED_BYTES_CODE, TRANSCODE_GENERATED_WORDS_CODE, name)
  return defined_name, max_input
end

TRANSCODERS = []
TRANSCODE_GENERATED_TRANSCODER_CODE = ''

def transcode_tbl_only(from, to, map, valid_encoding=UnspecifiedValidEncoding)
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
  real_tree_name, max_input = transcode_compile_tree(tree_name, from, map, valid_encoding)
  return map, tree_name, real_tree_name, max_input
end

def transcode_tblgen(from, to, map, valid_encoding=UnspecifiedValidEncoding)
  map, tree_name, real_tree_name, max_input = transcode_tbl_only(from, to, map, valid_encoding)
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

# 一つの offsets テーブルを表すクラス
class Offsets
  attr_accessor :content, :min, :max
  attr_reader :name
  def initialize(name, min, max, content)
    @name = name
    @content = content
    @min = min
    @max = max
  end

  # 以下、既存のものをコピー・修正
  def format_offsets
    offsets = @content[@min..@max]
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
end

# 一つの infos テーブルを表すクラス
class Infos
  attr_accessor :content
  attr_reader :name
  def initialize(name, content)
    @name = name
    @content = content
  end

  # 以下、既存のものをコピー・修正
  UsedName = {}

  StrMemo = {}

  def str_name(bytes)
    size = TRANSCODE_GENERATED_BYTES_CODE.length
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
      size = TRANSCODE_GENERATED_BYTES_CODE.length
      n = str_name(bytes)
      TRANSCODE_GENERATED_BYTES_CODE.insert_at_last(1 + len,
        "\#define #{n} makeSTR1(#{size})\n" +
        "    makeSTR1LEN(#{len})," + bytes.gsub(/../, ' 0x\&,') + "\n\n")
      n
    end
  end

  def generate_info(info)
    case info
    when :info_a
      "INFO_A"
    when :info_b
      "INFO_B"
    when :info_c
      "INFO_C"
    when :info_d
      "INFO_D"
    when :info_e
      "INFO_E"
    when :nomap, :nomap0
      # :nomap0 is low priority.  it never collides.
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
    when /\A(#{HEX2})\z/o
      "o1(0x#$1)"
    when /\A(#{HEX2})(#{HEX2})\z/o
      "o2(0x#$1,0x#$2)"
    when /\A(#{HEX2})(#{HEX2})(#{HEX2})\z/o
      "o3(0x#$1,0x#$2,0x#$3)"
    when /funsio\((\d+)\)/
      "funsio(#{$1})"
    when /\A(#{HEX2})(3[0-9])(#{HEX2})(3[0-9])\z/o
      "g4(0x#$1,0x#$2,0x#$3,0x#$4)"
    when /\A(f[0-7])(#{HEX2})(#{HEX2})(#{HEX2})\z/o
      "o4(0x#$1,0x#$2,0x#$3,0x#$4)"
    when /\A(#{HEX2}){4,259}\z/o
      gen_str(info.upcase)
    when /\A\/\*BYTE_LOOKUP\*\// # pointer to BYTE_LOOKUP structure
      $'.to_s
    else
      raise "unexpected action: #{info.inspect}"
    end
  end

  def format_infos
    infos = @content.map {|info| generate_info(info) }
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
end

# 一つの文字コード変換を表すクラス
class Tables
  attr_accessor :offsets, :infos, :have_tbls
  attr_reader :offsets_org, :infos_org, :name
  def initialize(name, min, max, offsets, infos)
    @name = name
    @offsets = Offsets.new(name + "_offsets", min, max, offsets)
    # 元の offsets テーブル（変更されない）
    @offsets_org = Offsets.new(name + "_offsets", min, max, offsets)
    @infos = Infos.new(name + "_infos", infos)
    # 元の infos テーブル（変更されない）
    @infos_org = Infos.new(name + "_infos", infos)
    @have_tbls = 1 # 自分を含めて共用してるテーブルの数
  end
end

# 完全に offsets が一致する場合に共有
def share_no_change
  GENERATED_CODE.each_with_index do |tables, i|
    # 対象の offsets がすでに共用されているかどうかチェック
    # 共用済みだった場合は次へ
    next if tables.offsets.class == Tables
    j = i + 1
    while j < GENERATED_CODE.length
      # offsets の content, min, max 全てが一致すれば共用
      # 既存の変換と整合性を保つ
      if tables.offsets.class == Offsets && GENERATED_CODE[j].offsets.class == Offsets
        if tables.offsets_org.content == GENERATED_CODE[j].offsets_org.content &&
            tables.offsets_org.min == GENERATED_CODE[j].offsets_org.min &&
            tables.offsets_org.max == GENERATED_CODE[j].offsets_org.max
          # 共用する Tables クラスを 共用される Tables クラスの offsets に代入
          # 共用の関係を保存しておく
          GENERATED_CODE[j].offsets = tables
          # 削減メモリ計算のための処理
          tables.have_tbls += GENERATED_CODE[j].have_tbls
        end
      end
      j += 1
    end
  end
end

# 片方を共用することができるパターン
# 共用する方は infos テーブルの変更が必要（generate_string メソッドで行っている）
def share_infos_change
  cutback = [0] # 削減したメモリ量を保存（一つのファイルの削減）
  GENERATED_CODE.each do |trg| # trg = target
    STDERR.print "." # 処理の経過を見る

    # target が共有済みで無ければ
    if trg.offsets.class == Offsets
      GENERATED_CODE.each do |comp|
        # 同じ文字コード変換の場合はスキップ
        next if trg.name == comp.name

        # 比較する方が共用済みで無ければ
        if comp.offsets.class == Offsets
          if comp_offsets(trg, comp, cutback)
            # trg の offsets テーブルのサイズが comp のものより狭い場合
            # comp のサイズに合わせる必要がある
            trg.offsets.max = comp.offsets.max if comp.offsets.max > trg.offsets.max
            trg.offsets.min = comp.offsets.min if comp.offsets.min < trg.offsets.min
            # comp の offsets を Tables クラス trg に変更
            comp.offsets = trg
            # 共用されたテーブルの数を増やす
            trg.have_tbls += comp.have_tbls
          end
        end
      end
    end
  end
  STDERR.puts # STDERR.print "." を見やすくする
  # puts cutback[0] # 削減メモリを出力
end

# 二つの文字コード変換の offsets テーブルが片方に共用可能かどうか判断する
def comp_offsets(trg, comp, cutback)
  # target の offset の種類が comp の offsets の種類より小さいと共用できない
  return FALSE if trg.offsets.content.max <= comp.offsets.content.max
  return FALSE if calc_cut(trg, comp) <= 0 # 削減量による共用の条件を指定
  set_offset = {} # それぞれの offsets テーブルにある同位置の offset をセットとする

  # 同位置にある offset のペアの種類を調べ、出現回数をカウント
  trg.offsets.content.each_with_index do |o_trg, i|
    o_comp = comp.offsets.content[i]
    key = [o_trg, o_comp]
    if set_offset[key]
      set_offset[key] += 1
    else
      set_offset[key] = 1
    end
  end

  # offset ペアの数が target の offset の種類以下（等しい）でなければそのまま共用できない
  return FALSE if set_offset.length > trg.offsets.content.max + 1

  # 以下、共用可能
  # どれくらい削減できるか計算して、条件によって実行するかどうか決める
  cutback[0] += calc_cut(trg, comp) # デバック用として削減できたメモリの量を再計算
  return TRUE
end

def calc_cut(trg, comp) # 今のところは offsets のみを代えた場合の計算
  # offset 共用により削減できる量
  cut_offsets = comp.offsets.max - comp.offsets.min + 1
  # infos 増加より増加する量
  # (共用 offsets の種類 - 削減 offsets の種類) * 4 byte * (削減するテーブルが共用してる数)
  add_infos = ((trg.offsets.content.max + 1) - (comp.offsets.content.max + 1)) * 4 * comp.have_tbls

  return cut_offsets - add_infos
end

# 共用されていた場合に最終的に利用する offsets テーブルを探索する
def search_real_offsets(target)
  if target.offsets.class == Tables
    return search_real_offsets(target.offsets)
  else
    return target.offsets
  end
end

# 共用されていた場合に最終的に利用する infos テーブルを探索する
def search_real_infos(target)
  if target.infos.class == Tables
    return search_real_infos(target.infos)
  else
    return target.infos
  end
end

# データとして格納していた文字コード変換を文字列化
# 文字列化の部分は既存の処理を一部修正し、利用している
def generate_string
  GENERATED_CODE.each do |tables|
    name = tables.name # 文字コード変換自体の名前

    # 共用済みとそうでない場合で処理を分ける
    if tables.offsets.class == Offsets # 共用なし
      # 既存の処理と変わらない
      offsets_name = tables.offsets.name
      size = TRANSCODE_GENERATED_BYTES_CODE.length
      TRANSCODE_GENERATED_BYTES_CODE.insert_at_last(2+tables.offsets.max-tables.offsets.min+1,
        "\#define #{offsets_name} #{size}\n" +
        tables.offsets.format_offsets + "\n")
    else # 共用あり
      # 実際に利用している offsets テーブルを探索
      offsets_real = search_real_offsets(tables.offsets)
      offsets_name = offsets_real.name

      # 実際に利用している infos テーブルを探索
      infos_real = search_real_infos(tables)
      if tables.infos.class == Infos
        # offsets 共用済みかつ infos の共用なしの場合
        # offsets の変更による infos の変更を調整
        tables.infos.content = adjust_infos(tables, offsets_real)
      end
    end

    # 変更後の offsets から infos を計算し、変更前と同じかどうか確かめるテスト
    # test_tables(tables, offsets_real)

    key = tables.infos.content # 完全に一致するものを共用するためのもの
    # infos の共用は既存の処理と同じ
    if i_name = WORD_CODE[key]
      infos_name = i_name
    else
      WORD_CODE[key] = infos_name = tables.infos.name
      size = TRANSCODE_GENERATED_WORDS_CODE.length
      TRANSCODE_GENERATED_WORDS_CODE.insert_at_last(tables.infos.content.length,
        "\#define #{infos_name} WORDINDEX2INFO(#{size})\n" +
        tables.infos.format_infos + "\n")
    end

    size = TRANSCODE_GENERATED_WORDS_CODE.length
    TRANSCODE_GENERATED_WORDS_CODE.insert_at_last(NUM_ELEM_BYTELOOKUP,
      "\#define #{name} WORDINDEX2INFO(#{size})\n" +
      <<"End" + "\n")
    #{offsets_name},
    #{infos_name},
End
  end
end

# 新旧の 2 段階テーブルの整合性を確かめるテスト
def test_tables(tables, new_offsets)
  old_o = tables.offsets_org.content.dup # 元の offsets テーブル
  old_i = tables.infos_org.content.dup   # 元の infos テーブル
  new_i = tables.infos.content.dup       # 新しい infos テーブル
  # 新しい offsets（共用なしなら、自分自身を新しい offsets テーブルとする）
  new_o = tables.offsets.class == Offsets ?
            tables.offsets.content.dup : new_offsets.content.dup

  # offsets から求めた infos が新旧で正しいか正しくないかを格納
  t_or_f = {"true"=>0, "false"=>0}

  # offsets から求めた infos が新旧で正しいか正しくないかを一つずつ検証
  i = 0
  while (i < 256)
    index_old = old_o[i]
    info_old = old_i[index_old]
    index_new = new_o[i]
    info_new = new_i[index_new]

    info_old == info_new ? t_or_f["true"] += 1 : t_or_f["false"] += 1

    i += 1
  end

  puts t_or_f
  # output_tables は文字コート変換を形式的に出力するメソッド
  output_tables(tables) if t_or_f["false"] > 0
end

# 変更後の offsets に対応した infos を作成するメソッド
def adjust_infos(tables, offsets_real)
  o_new = offsets_real.content
  o_old = tables.offsets_org.content
  i_old = tables.infos_org.content

  # 新しい offsets の最大値が新しい infos の数となる
  num_info = o_new.max
  i_new = []
  # あらかじめ必要となる infos の配列を初期化
  # offsets の数値が順番通りに並んでいないことを考慮
  i_new.fill("", 0..num_info)
  set_offset = {}

  # 旧 offset と 新 offset のペアを作る
  o_old.each_with_index do |o1, i|
    o2 = o_new[i]
    key = [o1, o2]
    if !set_offset[key]
      set_offset[key] = 1
    end
  end

  # 新 offset の値の場所に、旧 offset が示す info を挿入
  set_offset.each_key do |key|
    num_old, num_new = key
    i_new[num_new] = i_old[num_old]
  end

  return i_new
end

# 文字コート変換を形式的に出力するメソッド
def output_tables(tables)
  puts "##TRANSCODE_NAME##"
  puts tables.name

  puts "##OFFSETS_INFO##"
  real_offsets = search_real_offsets(tables)

  if tables.offsets.class == Offsets
    puts tables.offsets.name
  else
    print tables.name + " > "
    puts output_real_offsets(tables.offsets)
  end

  puts
  puts "It has #{tables.have_tbls} offsets tables."
  puts "changed #{real_offsets.content.max + 1} <> original #{tables.offsets_org.content.max + 1}"

  puts "##INFOS_INFO##"
  real_infos = search_real_infos(tables)
  p tables.infos_org.content
  p real_infos.content

  puts
  puts
end

# 実際の offsets テーブルまでのつながりを出力
def output_real_offsets(tables)
  if tables.offsets.class == Tables
    return tables.name + " > " + output_real_offsets(tables.offsets)
  else
    return tables.name
  end
end

def transcode_generated_code
  share_no_change # 完全に一致する offsets を共用
  share_infos_change # 片方を利用できる offsets を共用 （infos に変更が必要）
  generate_string # 最終的な文字列化と infos テーブルが完全に一致する場合の共用を行う

  TRANSCODE_GENERATED_BYTES_CODE.to_s +
    TRANSCODE_GENERATED_WORDS_CODE.to_s +
    "\#define TRANSCODE_TABLE_INFO " +
    "#{OUTPUT_PREFIX}byte_array, #{TRANSCODE_GENERATED_BYTES_CODE.length}, " +
    "#{OUTPUT_PREFIX}word_array, #{TRANSCODE_GENERATED_WORDS_CODE.length}, " +
    "((int)sizeof(unsigned int))\n" +
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

def ValidEncoding(enc)
  ValidEncoding.fetch(enc)
end

def set_valid_byte_pattern(encoding, pattern_or_label)
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

if __FILE__ == $0
  start_time = Time.now

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

  GENERATED_CODE = [] # 文字コード変換の Tables クラスを格納する変数
  WORD_CODE = {} # infos テーブルの完全一致を判断するために格納するハッシュ

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
    tms = Process.times
    elapsed = Time.now - start_time
    STDERR.puts "done.  (#{'%.2f' % tms.utime}user #{'%.2f' % tms.stime}system #{'%.2f' % elapsed}elapsed)" if VERBOSE_MODE
  else
    #print result
  end
end
