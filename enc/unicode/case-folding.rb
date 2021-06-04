#!/usr/bin/ruby
require 'stringio'

# Usage (for case folding only):
#   $ wget http://www.unicode.org/Public/UNIDATA/CaseFolding.txt
#   $ ruby case-folding.rb CaseFolding.txt -o casefold.h
#  or (for case folding and case mapping):
#   $ wget http://www.unicode.org/Public/UNIDATA/CaseFolding.txt
#   $ wget http://www.unicode.org/Public/UNIDATA/UnicodeData.txt
#   $ wget http://www.unicode.org/Public/UNIDATA/SpecialCasing.txt
#   $ ruby case-folding.rb -m . -o casefold.h
# using -d or --debug will include UTF-8 characters in comments for debugging

class CaseFolding
  module Util
    module_function

    def hex_seq(v)
      v.map { |i| "0x%04x" % i }.join(", ")
    end

    def print_table_1(dest, type, mapping_data, data)
      for k, v in data = data.sort
        sk = (Array === k and k.length > 1) ? "{#{hex_seq(k)}}" : ("0x%04x" % k)
        if type=='CaseUnfold_11' and v.length>1
          # reorder CaseUnfold_11 entries to avoid special treatment for U+03B9/U+03BC/U+A64B
          item = mapping_data.map("%04X" % k[0])
          upper = item.upper if item
          v = v.sort_by { |i| ("%04X"%i) == upper ? 0 : 1 }
        end
        ck = @debug ? ' /* ' + Array(k).pack("U*") + ' */' : ''
        cv = @debug ? ' /* ' + Array(v).map{|c|[c].pack("U*")}.join(", ") + ' */' : ''
        dest.print("  {#{sk}#{ck}, {#{v.length}#{mapping_data.flags(k, type, v)}, {#{hex_seq(v)}#{cv}}}},\n")
      end
      data
    end

    def print_table(dest, type, mapping_data, data)
      dest.print("static const #{type}_Type #{type}_Table[] = {\n")
      i = 0
      ret = data.inject([]) do |a, (n, d)|
        dest.print("#define #{n} (*(#{type}_Type (*)[#{d.size}])(#{type}_Table+#{i}))\n")
        i += d.size
        a.concat(print_table_1(dest, type, mapping_data, d))
      end
      dest.print("};\n\n")
      ret
    end
  end

  include Util

  attr_reader :fold, :fold_locale, :unfold, :unfold_locale, :version

  def load(filename)
    pattern = /([0-9A-F]{4,6}); ([CFT]); ([0-9A-F]{4,6})(?: ([0-9A-F]{4,6}))?(?: ([0-9A-F]{4,6}))?;/

    @fold = fold = {}
    @unfold = unfold = [{}, {}, {}]
    @debug = false
    @version = nil
    turkic = []

    IO.foreach(filename, mode: "rb") do |line|
      @version ||= line[/-([0-9.]+).txt/, 1]
      next unless res = pattern.match(line)
      ch_from = res[1].to_i(16)

      if res[2] == 'T'
        # Turkic case folding
        turkic << ch_from
        next
      end

      # store folding data
      ch_to = res[3..6].inject([]) do |a, i|
        break a unless i
        a << i.to_i(16)
      end
      fold[ch_from] = ch_to

      # store unfolding data
      i = ch_to.length - 1
      (unfold[i][ch_to] ||= []) << ch_from
    end

    # move locale dependent data to (un)fold_locale
    @fold_locale = fold_locale = {}
    @unfold_locale = unfold_locale = [{}, {}]
    for ch_from in turkic
      key = fold[ch_from]
      i = key.length - 1
      unfold_locale[i][i == 0 ? key[0] : key] = unfold[i].delete(key)
      fold_locale[ch_from] = fold.delete(ch_from)
    end
    self
  end

  def range_check(code)
    "#{code} <= MAX_CODE_VALUE && #{code} >= MIN_CODE_VALUE"
  end

  def lookup_hash(key, type, data)
    hash = "onigenc_unicode_#{key}_hash"
    lookup = "onigenc_unicode_#{key}_lookup"
    arity = Array(data[0][0]).size
    gperf = %W"gperf -7 -k#{[*1..(arity*3)].join(',')} -F,-1 -c -j1 -i1 -t -T -E -C -H #{hash} -N #{lookup} -n"
    argname = arity > 1 ? "codes" : "code"
    argdecl = "const OnigCodePoint #{arity > 1 ? "*": ""}#{argname}"
    n = 7
    m = (1 << n) - 1
    min, max = data.map {|c, *|c}.flatten.minmax
    src = IO.popen(gperf, "r+") {|f|
      f << "short\n%%\n"
      data.each_with_index {|(k, _), i|
        k = Array(k)
        ks = k.map {|j| [(j >> n*2) & m, (j >> n) & m, (j) & m]}.flatten.map {|c| "\\x%.2x" % c}.join("")
        f.printf "\"%s\", ::::/*%s*/ %d\n", ks, k.map {|c| "0x%.4x" % c}.join(","), i
      }
      f << "%%\n"
      f.close_write
      f.read
    }
    src.sub!(/^(#{hash})\s*\(.*?\).*?\n\{\n(.*)^\}/m) {
      name = $1
      body = $2
      body.gsub!(/\(unsigned char\)str\[(\d+)\]/, "bits_#{arity > 1 ? 'at' : 'of'}(#{argname}, \\1)")
      "#{name}(#{argdecl})\n{\n#{body}}"
    }
    src.sub!(/const short *\*\n^(#{lookup})\s*\(.*?\).*?\n\{\n(.*)^\}/m) {
      name = $1
      body = $2
      body.sub!(/\benum\s+\{(\n[ \t]+)/, "\\&MIN_CODE_VALUE = 0x#{min.to_s(16)},\\1""MAX_CODE_VALUE = 0x#{max.to_s(16)},\\1")
      body.gsub!(/(#{hash})\s*\(.*?\)/, "\\1(#{argname})")
      body.gsub!(/\{"",-1}/, "-1")
      body.gsub!(/\{"(?:[^"]|\\")+", *::::(.*)\}/, '\1')
      body.sub!(/(\s+if\s)\(len\b.*\)/) do
        "#$1(" <<
          (arity > 1 ? (0...arity).map {|i| range_check("#{argname}[#{i}]")}.join(" &&\n      ") : range_check(argname)) <<
          ")"
      end
      v = nil
      body.sub!(/(if\s*\(.*MAX_HASH_VALUE.*\)\n([ \t]*))\{(.*?)\n\2\}/m) {
        pre = $1
        indent = $2
        s = $3
        s.sub!(/const char *\* *(\w+)( *= *wordlist\[\w+\]).\w+/, 'short \1 = wordlist[key]')
        v = $1
        s.sub!(/\bif *\(.*\)/, "if (#{v} >= 0 && code#{arity}_equal(#{argname}, #{key}_Table[#{v}].from))")
        "#{pre}{#{s}\n#{indent}}"
      }
      body.sub!(/\b(return\s+&)([^;]+);/, '\1'"#{key}_Table[#{v}].to;")
      "static const #{type} *\n#{name}(#{argdecl})\n{\n#{body}}"
    }
    src
  end

  def display(dest, mapping_data)
    # print the header
    dest.print("/* DO NOT EDIT THIS FILE. */\n")
    dest.print("/* Generated by enc/unicode/case-folding.rb */\n\n")

    versions = version.scan(/\d+/)
    dest.print("#if defined ONIG_UNICODE_VERSION_STRING && !( \\\n")
    %w[MAJOR MINOR TEENY].zip(versions) do |n, v|
      dest.print("      ONIG_UNICODE_VERSION_#{n} == #{v} && \\\n")
    end
    dest.print("      1)\n")
    dest.print("# error ONIG_UNICODE_VERSION_STRING mismatch\n")
    dest.print("#endif\n")
    dest.print("#define ONIG_UNICODE_VERSION_STRING #{version.dump}\n")
    %w[MAJOR MINOR TEENY].zip(versions) do |n, v|
      dest.print("#define ONIG_UNICODE_VERSION_#{n} #{v}\n")
    end
    dest.print("\n")

    # print folding data

    # CaseFold + CaseFold_Locale
    name = "CaseFold_11"
    data = print_table(dest, name, mapping_data, "CaseFold"=>fold, "CaseFold_Locale"=>fold_locale)
    dest.print lookup_hash(name, "CodePointList3", data)

    # print unfolding data

    # CaseUnfold_11 + CaseUnfold_11_Locale
    name = "CaseUnfold_11"
    data = print_table(dest, name, mapping_data, name=>unfold[0], "#{name}_Locale"=>unfold_locale[0])
    dest.print lookup_hash(name, "CodePointList3", data)

    # CaseUnfold_12 + CaseUnfold_12_Locale
    name = "CaseUnfold_12"
    data = print_table(dest, name, mapping_data, name=>unfold[1], "#{name}_Locale"=>unfold_locale[1])
    dest.print lookup_hash(name, "CodePointList2", data)

    # CaseUnfold_13
    name = "CaseUnfold_13"
    data = print_table(dest, name, mapping_data, name=>unfold[2])
    dest.print lookup_hash(name, "CodePointList2", data)

    # TitleCase
    dest.print mapping_data.specials_output
  end

  def debug!
    @debug = true
  end

  def self.load(*args)
    new.load(*args)
  end
end

class MapItem
  attr_accessor :upper, :lower, :title, :code

  def initialize(code, upper, lower, title)
    @code = code
    @upper = upper unless upper == ''
    @lower = lower unless lower == ''
    @title = title unless title == ''
  end
end

class CaseMapping
  attr_reader :filename, :version

  def initialize(mapping_directory)
    @mappings = {}
    @specials = []
    @specials_length = 0
    @version = nil
    IO.foreach(File.join(mapping_directory, 'UnicodeData.txt'), mode: "rb") do |line|
      next if line =~ /^</
      code, _, _, _, _, _, _, _, _, _, _, _, upper, lower, title = line.chomp.split ';'
      unless upper and lower and title and (upper+lower+title)==''
        @mappings[code] = MapItem.new(code, upper, lower, title)
      end
    end

    @filename = File.join(mapping_directory, 'SpecialCasing.txt')
    IO.foreach(@filename, mode: "rb") do |line|
      @version ||= line[/-([0-9.]+).txt/, 1]
      line.chomp!
      line, comment = line.split(/ *#/)
      next if not line or line == ''
      code, lower, title, upper, conditions = line.split(/ *; */)
      unless conditions
        item = @mappings[code]
        item.lower = lower
        item.title = title
        item.upper = upper
      end
    end
  end

  def map (from)
    @mappings[from]
  end

  def flags(from, type, to)
    # types: CaseFold_11, CaseUnfold_11, CaseUnfold_12, CaseUnfold_13
    flags = ""
    from = Array(from).map {|i| "%04X" % i}.join(" ")
    to   = Array(to).map {|i| "%04X" % i}.join(" ")
    item = map(from)
    specials = []
    case type
    when 'CaseFold_11'
      flags += '|F'
      if item
        flags += '|U'  if to==item.upper
        flags += '|D'  if to==item.lower
        unless item.upper == item.title
          if item.code == item.title
            flags += '|IT'
            swap = case item.code
            when '01C5' then '0064 017D'
            when '01C8' then '006C 004A'
            when '01CB' then '006E 004A'
            when '01F2' then '0064 005A'
            else # Greek
              to.split(' ').first + ' 0399'
            end
            specials << swap
          else
            flags += '|ST'
            specials << item.title
          end
        end
        unless item.lower.nil? or item.lower==from or item.lower==to
          specials << item.lower
          flags += '|SL'
        end
        unless item.upper.nil? or item.upper==from or item.upper==to
          specials << item.upper
          flags += '|SU'
        end
      end
    when 'CaseUnfold_11'
      to = to.split(/ /)
      if item
        case to.first
        when item.upper  then  flags += '|U'
        when item.lower  then  flags += '|D'
        else
          raise "Unpredicted case 0 in enc/unicode/case_folding.rb. Please contact https://bugs.ruby-lang.org/."
        end
        unless item.upper == item.title
          if item.code == item.title
            flags += '|IT'   # was unpredicted case 1
          elsif item.title==to[1]
            flags += '|ST'
          else
            raise "Unpredicted case 2 in enc/unicode/case_folding.rb. Please contact https://bugs.ruby-lang.org/."
          end
        end
      end
    end
    unless specials.empty?
      flags += "|I(#{@specials_length})"
      @specials_length += specials.map { |s| s.split(/ /).length }.reduce(:+)
      @specials << specials
    end
    flags
  end

  def debug!
    @debug = true
  end

  def specials_output
    "static const OnigCodePoint CaseMappingSpecials[] = {\n" +
    @specials.map do |sps|
      '   ' + sps.map do |sp|
        chars = sp.split(/ /)
        ct = ' /* ' + Array(chars).map{|c|[c.to_i(16)].pack("U*")}.join(", ") + ' */' if @debug
        " L(#{chars.length})|#{chars.map {|c| "0x"+c }.join(', ')}#{ct},"
      end.join + "\n"
    end.join + "};\n"
  end

  def self.load(*args)
    new(*args)
  end
end

class CaseMappingDummy
  def flags(from, type, to)
    ""
  end

  def titlecase_output()  ''  end
  def debug!()  end
end

if $0 == __FILE__
  require 'optparse'
  dest = nil
  mapping_directory = nil
  mapping_data = nil
  debug = false
  fold_1 = false
  ARGV.options do |opt|
    opt.banner << " [INPUT]"
    opt.on("--output-file=FILE", "-o", "output to the FILE instead of STDOUT") {|output|
      dest = (output unless output == '-')
    }
    opt.on('--mapping-data-directory=DIRECTORY', '-m', 'data DIRECTORY of mapping files') { |directory|
      mapping_directory = directory
    }
    opt.on('--debug', '-d') {
      debug = true
    }
    opt.parse!
    abort(opt.to_s) if ARGV.size > 1
  end
  if mapping_directory
    if ARGV[0]
      warn "Either specify directory or individual file, but not both."
      exit
    end
    filename = File.join(mapping_directory, 'CaseFolding.txt')
    mapping_data = CaseMapping.load(mapping_directory)
  end
  filename ||= ARGV[0] || 'CaseFolding.txt'
  data = CaseFolding.load(filename)
  if mapping_data and data.version != mapping_data.version
    abort "Unicode data version mismatch\n" \
          "  #{filename} = #{data.version}\n" \
          "  #{mapping_data.filename} = #{mapping_data.version}"
  end
  mapping_data ||= CaseMappingDummy.new

  if debug
    data.debug!
    mapping_data.debug!
  end
  f = StringIO.new
  begin
    data.display(f, mapping_data)
  rescue Errno::ENOENT => e
    raise unless /gperf/ =~ e.message
    warn e.message
    abort unless dest
    File.utime(nil, nil, dest) # assume existing file is OK
    exit
  else
    s = f.string
  end
  if dest
    open(dest, "wb") do |file|
      file.print(s)
    end
  else
    STDOUT.print(s)
  end
end
