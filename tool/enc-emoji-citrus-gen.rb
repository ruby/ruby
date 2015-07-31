require File.expand_path('../jisx0208', __FILE__)

ENCODES = [
  {
    name: "SHIFT_JIS-DOCOMO",
    src_zone: [0xF8..0xFC, 0x40..0xFC, 8],
    dst_ilseq: 0xFFFE,
    map: [
      [0xE63E..0xE757, JISX0208::Char.from_sjis(0xF89F)],
    ],
  },
  {
    name: "ISO-2022-JP-KDDI",
    src_zone: [0x21..0x7E, 0x21..0x7E, 8],
    dst_ilseq: 0xFFFE,
    map: [
      [0xE468..0xE5B4, JISX0208::Char.new(0x7521)],
      [0xE5B5..0xE5CC, JISX0208::Char.new(0x7867)],
      [0xE5CD..0xE5DF, JISX0208::Char.new(0x7921)],
      [0xEA80..0xEAFA, JISX0208::Char.new(0x7934)],
      [0xEAFB..0xEB0D, JISX0208::Char.new(0x7854)],
      [0xEB0E..0xEB8E, JISX0208::Char.new(0x7A51)],
    ],
  },
  {
    name: "SHIFT_JIS-KDDI",
    src_zone: [0xF3..0xFC, 0x40..0xFC, 8],
    dst_ilseq: 0xFFFE,
    map: [
      [0xE468..0xE5B4, JISX0208::Char.from_sjis(0xF640)],
      [0xE5B5..0xE5CC, JISX0208::Char.from_sjis(0xF7E5)],
      [0xE5CD..0xE5DF, JISX0208::Char.from_sjis(0xF340)],
      [0xEA80..0xEAFA, JISX0208::Char.from_sjis(0xF353)],
      [0xEAFB..0xEB0D, JISX0208::Char.from_sjis(0xF7D2)],
      [0xEB0E..0xEB8E, JISX0208::Char.from_sjis(0xF3CF)],
    ],
  },
  {
    name: "SHIFT_JIS-SOFTBANK",
    src_zone: [0xF3..0xFC, 0x40..0xFC, 8],
    dst_ilseq: 0xFFFE,
    map: [
      [0xE001..0xE05A, JISX0208::Char.from_sjis(0xF941)],
      [0xE101..0xE15A, JISX0208::Char.from_sjis(0xF741)],
      [0xE201..0xE25A, JISX0208::Char.from_sjis(0xF7A1)],
      [0xE301..0xE34D, JISX0208::Char.from_sjis(0xF9A1)],
      [0xE401..0xE44C, JISX0208::Char.from_sjis(0xFB41)],
      [0xE501..0xE53E, JISX0208::Char.from_sjis(0xFBA1)],
    ],
  },
]

def zone(*args)
  bits = args.pop
  [*args.map{|range| "0x%02X-0x%02X" % [range.begin, range.end] }, bits].join(' / ')
end

def header(params)
  (<<END_HEADER_TEMPLATE % [params[:name], zone(*params[:src_zone]), params[:dst_ilseq]])
# DO NOT EDIT THIS FILE DIRECTLY

TYPE		ROWCOL
NAME		%s
SRC_ZONE	%s
OOB_MODE	ILSEQ
DST_ILSEQ	0x%04X
DST_UNIT_BITS	16
END_HEADER_TEMPLATE
end

def generate_to_ucs(params, pairs)
  pairs.sort_by! {|u, c| c }
  name = "EMOJI_#{params[:name]}%UCS"
  open("#{name}.src", "w") do |io|
    io.print header(params.merge(name: name.tr('%', '/')))
    io.puts
    io.puts  "BEGIN_MAP"
    io.print pairs.inject("") {|acc, uc| acc += "0x%04X = 0x%04X\n" % uc.reverse }
    io.puts  "END_MAP"
  end
end

def generate_from_ucs(params, pairs)
  pairs.sort_by! {|u, c| u }
  name = "UCS%EMOJI_#{params[:name]}"
  open("#{name}.src", "w") do |io|
    io.print header(params.merge(name: name.tr('%', '/')))
    io.puts
    io.puts  "BEGIN_MAP"
    io.print pairs.inject("") {|acc, uc| acc += "0x%04X = 0x%04X\n" % uc }
    io.puts  "END_MAP"
  end
end

def make_pairs(code_map)
  pairs = code_map.inject([]) {|acc, (range, ch)|
    acc += range.map{|uni| pair = [uni, Integer(ch)]; ch = ch.succ; next pair }
  }
end

ENCODES.each do |params|
  pairs = make_pairs(params[:map], &params[:conv])
  generate_to_ucs(params, pairs)
  generate_from_ucs(params, pairs)
end

# generate KDDI-UNDOC for Shift_JIS-KDDI
kddi_sjis_map = ENCODES.select{|enc| enc[:name] == "SHIFT_JIS-KDDI"}.first[:map]
pairs = kddi_sjis_map.inject([]) {|acc, (range, ch)|
  acc += range.map{|uni| pair = [ch.to_sjis - 0x700, Integer(ch)]; ch = ch.succ; next pair }
}
params = {
  name: "SHIFT_JIS-KDDI-UNDOC",
  src_zone: [0xF3..0xFC, 0x40..0xFC, 8],
  dst_ilseq: 0xFFFE,
}
generate_from_ucs(params, pairs)
generate_to_ucs(params, pairs)

# generate KDDI-UNDOC for ISO-2022-JP-KDDI
kddi_2022_map = ENCODES.select{|enc| enc[:name] == "ISO-2022-JP-KDDI"}.first[:map]
pairs = kddi_2022_map.each_with_index.inject([]) {|acc, ((range, ch), i)|
  sjis = kddi_sjis_map[i][1]
  acc += range.map{|uni| pair = [sjis.to_sjis - 0x700, Integer(ch)]; ch = ch.succ; sjis = sjis.succ; next pair }
}
params = {
  name: "ISO-2022-JP-KDDI-UNDOC",
  src_zone: [0x21..0x7E, 0x21..0x7E, 8],
  dst_ilseq: 0xFFFE,
}
generate_from_ucs(params, pairs)
