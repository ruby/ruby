#!/usr/bin/env ruby

# Creates the data structures needed by Oniguruma to map Unicode codepoints to
# property names and POSIX character classes
#
# To use this, get UnicodeData.txt, Scripts.txt, PropList.txt,
# PropertyAliases.txt, PropertyValueAliases.txt, DerivedCoreProperties.txt,
# DerivedAge.txt and Blocks.txt  from unicode.org.
# (http://unicode.org/Public/UNIDATA/) And run following command.
# ruby1.9 tool/enc-unicode.rb data_dir > enc/unicode/name2ctype.kwd
# You can get source file for gperf.  After this, simply make ruby.

if ARGV[0] == "--header"
  header = true
  ARGV.shift
end
unless ARGV.size == 1
  abort "Usage: #{$0} data_directory"
end

$unicode_version = File.basename(ARGV[0])[/\A[.\d]+\z/]

POSIX_NAMES = %w[NEWLINE Alpha Blank Cntrl Digit Graph Lower Print XPosixPunct Space Upper XDigit Word Alnum ASCII Punct]

def pair_codepoints(codepoints)

  # We have a sorted Array of codepoints that we wish to partition into
  # ranges such that the start- and endpoints form an inclusive set of
  # codepoints with property _property_. Note: It is intended that some ranges
  # will begin with the value with  which they end, e.g. 0x0020 -> 0x0020

  codepoints.sort!
  last_cp = codepoints.first
  pairs = [[last_cp, nil]]
  codepoints[1..-1].each do |codepoint|
    next if last_cp == codepoint

    # If the current codepoint does not follow directly on from the last
    # codepoint, the last codepoint represents the end of the current range,
    # and the current codepoint represents the start of the next range.
    if last_cp.next != codepoint
      pairs[-1][-1] = last_cp
      pairs << [codepoint, nil]
    end
    last_cp = codepoint
  end

  # The final pair has as its endpoint the last codepoint for this property
  pairs[-1][-1] = codepoints.last
  pairs
end

def parse_unicode_data(file)
  last_cp = 0
  data = {'Any' => (0x0000..0x10ffff).to_a, 'Assigned' => [],
    'ASCII' => (0..0x007F).to_a, 'NEWLINE' => [0x0a], 'Cn' => []}
  beg_cp = nil
  IO.foreach(file) do |line|
    fields = line.split(';')
    cp = fields[0].to_i(16)

    case fields[1]
    when /\A<(.*),\s*First>\z/
      beg_cp = cp
      next
    when /\A<(.*),\s*Last>\z/
      cps = (beg_cp..cp).to_a
    else
      beg_cp = cp
      cps = [cp]
    end

    # The Cn category represents unassigned characters. These are not listed in
    # UnicodeData.txt so we must derive them by looking for 'holes' in the range
    # of listed codepoints. We increment the last codepoint seen and compare it
    # with the current codepoint. If the current codepoint is less than
    # last_cp.next we have found a hole, so we add the missing codepoint to the
    # Cn category.
    data['Cn'].concat((last_cp.next...beg_cp).to_a)

    # Assigned - Defined in unicode.c; interpreted as every character in the
    # Unicode range minus the unassigned characters
    data['Assigned'].concat(cps)

    # The third field denotes the 'General' category, e.g. Lu
    (data[fields[2]] ||= []).concat(cps)

    # The 'Major' category is the first letter of the 'General' category, e.g.
    # 'Lu' -> 'L'
    (data[fields[2][0,1]] ||= []).concat(cps)
    last_cp = cp
  end

  # The last Cn codepoint should be 0x10ffff. If it's not, append the missing
  # codepoints to Cn and C
  cn_remainder = (last_cp.next..0x10ffff).to_a
  data['Cn'] += cn_remainder
  data['C'] += data['Cn']

  # Special case for LC (Cased_Letter). LC = Ll + Lt + Lu
  data['LC'] = data['Ll'] + data['Lt'] + data['Lu']

  # Define General Category properties
  gcps = data.keys.sort - POSIX_NAMES

  # Returns General Category Property names and the data
  [gcps, data]
end

def define_posix_props(data)
  # We now derive the character classes (POSIX brackets), e.g. [[:alpha:]]
  #

  data['Alpha'] = data['Alphabetic']
  data['Upper'] = data['Uppercase']
  data['Lower'] = data['Lowercase']
  data['Punct'] = data['Punctuation']
  data['XPosixPunct'] = data['Punctuation'] + [0x24, 0x2b, 0x3c, 0x3d, 0x3e, 0x5e, 0x60, 0x7c, 0x7e]
  data['Digit'] = data['Decimal_Number']
  data['XDigit'] = (0x0030..0x0039).to_a + (0x0041..0x0046).to_a +
                   (0x0061..0x0066).to_a
  data['Alnum'] = data['Alpha'] + data['Digit']
  data['Space'] = data['White_Space']
  data['Blank'] = data['Space_Separator'] + [0x0009]
  data['Cntrl'] = data['Cc']
  data['Word'] = data['Alpha'] + data['Mark'] + data['Digit'] + data['Connector_Punctuation']
  data['Graph'] = data['Any'] - data['Space'] - data['Cntrl'] -
    data['Surrogate'] - data['Unassigned']
  data['Print'] = data['Graph'] + data['Space_Separator']
end

def parse_scripts(data, categories)
  files = [
    {:fn => 'DerivedCoreProperties.txt', :title => 'Derived Property'},
    {:fn => 'Scripts.txt', :title => 'Script'},
    {:fn => 'PropList.txt', :title => 'Binary Property'}
  ]
  current = nil
  cps = []
  names = {}
  files.each do |file|
    data_foreach(file[:fn]) do |line|
      if /^# Total code points: / =~ line
        data[current] = cps
        categories[current] = file[:title]
        (names[file[:title]] ||= []) << current
        cps = []
      elsif /^([0-9a-fA-F]+)(?:\.\.([0-9a-fA-F]+))?\s*;\s*(\w+)/ =~ line
        current = $3
        $2 ? cps.concat(($1.to_i(16)..$2.to_i(16)).to_a) : cps.push($1.to_i(16))
      end
    end
  end
  #  All code points not explicitly listed for Script
  #  have the value Unknown (Zzzz).
  data['Unknown'] =  (0..0x10ffff).to_a - data.values_at(*names['Script']).flatten
  categories['Unknown'] = 'Script'
  names.values.flatten << 'Unknown'
end

def parse_aliases(data)
  kv = {}
  data_foreach('PropertyAliases.txt') do |line|
    next unless /^(\w+)\s*; (\w+)/ =~ line
    data[$1] = data[$2]
    kv[normalize_propname($1)] = normalize_propname($2)
  end
  data_foreach('PropertyValueAliases.txt') do |line|
    next unless /^(sc|gc)\s*; (\w+)\s*; (\w+)(?:\s*; (\w+))?/ =~ line
    if $1 == 'gc'
      data[$3] = data[$2]
      data[$4] = data[$2]
      kv[normalize_propname($3)] = normalize_propname($2)
      kv[normalize_propname($4)] = normalize_propname($2) if $4
    else
      data[$2] = data[$3]
      data[$4] = data[$3]
      kv[normalize_propname($2)] = normalize_propname($3)
      kv[normalize_propname($4)] = normalize_propname($3) if $4
    end
  end
  kv
end

# According to Unicode6.0.0/ch03.pdf, Section 3.1, "An update version
# never involves any additions to the character repertoire." Versions
# in DerivedAge.txt should always be /\d+\.\d+/
def parse_age(data)
  current = nil
  last_constname = nil
  cps = []
  ages = []
  data_foreach('DerivedAge.txt') do |line|
    if /^# Total code points: / =~ line
      constname = constantize_agename(current)
      # each version matches all previous versions
      cps.concat(data[last_constname]) if last_constname
      data[constname] = cps
      make_const(constname, cps, "Derived Age #{current}")
      ages << current
      last_constname = constname
      cps = []
    elsif /^([0-9a-fA-F]+)(?:\.\.([0-9a-fA-F]+))?\s*;\s*(\d+\.\d+)/ =~ line
      current = $3
      $2 ? cps.concat(($1.to_i(16)..$2.to_i(16)).to_a) : cps.push($1.to_i(16))
    end
  end
  ages
end

def parse_GraphemeBreakProperty(data)
  current = nil
  cps = []
  ages = []
  data_foreach('auxiliary/GraphemeBreakProperty.txt') do |line|
    if /^# Total code points: / =~ line
      constname = constantize_Grapheme_Cluster_Break(current)
      data[constname] = cps
      make_const(constname, cps, "Grapheme_Cluster_Break=#{current}")
      ages << current
      cps = []
    elsif /^([0-9a-fA-F]+)(?:\.\.([0-9a-fA-F]+))?\s*;\s*(\w+)/ =~ line
      current = $3
      $2 ? cps.concat(($1.to_i(16)..$2.to_i(16)).to_a) : cps.push($1.to_i(16))
    end
  end
  ages
end

def parse_block(data)
  current = nil
  cps = []
  blocks = []
  data_foreach('Blocks.txt') do |line|
    if /^([0-9a-fA-F]+)\.\.([0-9a-fA-F]+);\s*(.*)/ =~ line
      cps = ($1.to_i(16)..$2.to_i(16)).to_a
      constname = constantize_blockname($3)
      data[constname] = cps
      make_const(constname, cps, "Block")
      blocks << constname
    end
  end

  # All code points not belonging to any of the named blocks
  # have the value No_Block.
  no_block = (0..0x10ffff).to_a - data.values_at(*blocks).flatten
  constname = constantize_blockname("No_Block")
  make_const(constname, no_block, "Block")
  blocks << constname
end

# shim for Ruby 1.8
unless {}.respond_to?(:key)
  class Hash
    alias key index
  end
end

$const_cache = {}
# make_const(property, pairs, name): Prints a 'static const' structure for a
# given property, group of paired codepoints, and a human-friendly name for
# the group
def make_const(prop, data, name)
  if name.empty?
    puts "\n/* '#{prop}' */"
  else
    puts "\n/* '#{prop}': #{name} */"
  end
  if origprop = $const_cache.key(data)
    puts "#define CR_#{prop} CR_#{origprop}"
  else
    $const_cache[prop] = data
    pairs = pair_codepoints(data)
    puts "static const OnigCodePoint CR_#{prop}[] = {"
    # The first element of the constant is the number of pairs of codepoints
    puts "\t#{pairs.size},"
    pairs.each do |pair|
      pair.map! { |c|  c == 0 ? '0x0000' : sprintf("%0#6x", c) }
      puts "\t#{pair.first}, #{pair.last},"
    end
    puts "}; /* CR_#{prop} */"
  end
end

def normalize_propname(name)
  name = name.downcase
  name.delete!('- _')
  name
end

def constantize_agename(name)
  "Age_#{name.sub(/\./, '_')}"
end

def constantize_Grapheme_Cluster_Break(name)
  "Grapheme_Cluster_Break_#{name}"
end

def constantize_blockname(name)
  "In_#{name.gsub(/\W/, '_')}"
end

def get_file(name)
  File.join(ARGV[0], name)
end

def data_foreach(name, &block)
  fn = get_file(name)
  warn "Reading #{name}"
  pat = /^# #{File.basename(name).sub(/\./, '-([\\d.]+)\\.')}/
  File.open(fn, 'rb') do |f|
    line = f.gets
    unless pat =~ line
      raise ArgumentError, "#{name}: no Unicode version"
    end
    if !$unicode_version
      $unicode_version = $1
    elsif $unicode_version != $1
      raise ArgumentError, "#{name}: Unicode version mismatch: #$1"
    end
    f.each(&block)
  end
end

# Write Data
class Unifdef
  attr_accessor :output, :top, :stack, :stdout, :kwdonly
  def initialize(out)
    @top = @output = []
    @stack = []
    $stdout, @stdout = self, out
  end
  def restore
    $stdout = @stdout
  end
  def ifdef(sym)
    if @kwdonly
      @stdout.puts "#ifdef #{sym}"
    else
      @stack << @top
      @top << tmp = [sym]
      @top = tmp
    end
    if block_given?
      begin
        return yield
      ensure
        endif(sym)
      end
    end
  end
  def endif(sym)
    if @kwdonly
      @stdout.puts "#endif /* #{sym} */"
    else
      unless sym == @top[0]
        restore
        raise ArgumentError, "#{sym} unmatch to #{@top[0]}"
      end
      @top = @stack.pop
    end
  end
  def show(dest, *syms)
    _show(dest, @output, syms)
  end
  def _show(dest, ary, syms)
    if Symbol === (sym = ary[0])
      unless syms.include?(sym)
        return
      end
    end
    ary.each do |e|
      case e
      when Array
        _show(dest, e, syms)
      when String
        dest.print e
      end
    end
  end
  def write(str)
    if @kwdonly
      @stdout.write(str)
    else
      @top << str
    end
    self
  end
  alias << write
end

output = Unifdef.new($stdout)
output.kwdonly = !header

puts '%{'
props, data = parse_unicode_data(get_file('UnicodeData.txt'))
categories = {}
props.concat parse_scripts(data, categories)
aliases = parse_aliases(data)
ages = blocks = graphemeBreaks = nil
define_posix_props(data)
POSIX_NAMES.each do |name|
  if name == 'XPosixPunct'
    make_const(name, data[name], "[[:Punct:]]")
  elsif name == 'Punct'
    make_const(name, data[name], "")
  else
    make_const(name, data[name], "[[:#{name}:]]")
  end
end
output.ifdef :USE_UNICODE_PROPERTIES do
  props.each do |name|
    category = categories[name] ||
               case name.size
               when 1 then 'Major Category'
               when 2 then 'General Category'
               else        '-'
               end
    make_const(name, data[name], category)
  end
  output.ifdef :USE_UNICODE_AGE_PROPERTIES do
    ages = parse_age(data)
  end
  graphemeBreaks = parse_GraphemeBreakProperty(data)
  blocks = parse_block(data)
end
puts(<<'__HEREDOC')

static const OnigCodePoint* const CodeRanges[] = {
__HEREDOC
POSIX_NAMES.each{|name|puts"  CR_#{name},"}
output.ifdef :USE_UNICODE_PROPERTIES do
  props.each{|name| puts"  CR_#{name},"}
  output.ifdef :USE_UNICODE_AGE_PROPERTIES do
    ages.each{|name|  puts"  CR_#{constantize_agename(name)},"}
  end
  graphemeBreaks.each{|name|  puts"  CR_#{constantize_Grapheme_Cluster_Break(name)},"}
  blocks.each{|name|puts"  CR_#{name},"}
end

puts(<<'__HEREDOC')
};
struct uniname2ctype_struct {
  short name;
  unsigned short ctype;
};
#define uniname2ctype_offset(str) offsetof(struct uniname2ctype_pool_t, uniname2ctype_pool_##str)

static const struct uniname2ctype_struct *uniname2ctype_p(const char *, unsigned int);
%}
struct uniname2ctype_struct;
%%
__HEREDOC

i = -1
name_to_index = {}
POSIX_NAMES.each do |name|
  i += 1
  next if name == 'NEWLINE'
  name = normalize_propname(name)
  name_to_index[name] = i
  puts"%-40s %3d" % [name + ',', i]
end
output.ifdef :USE_UNICODE_PROPERTIES do
  props.each do |name|
    i += 1
    name = normalize_propname(name)
    name_to_index[name] = i
    puts "%-40s %3d" % [name + ',', i]
  end
  aliases.each_pair do |k, v|
    next if name_to_index[k]
    next unless v = name_to_index[v]
    puts "%-40s %3d" % [k + ',', v]
  end
  output.ifdef :USE_UNICODE_AGE_PROPERTIES do
    ages.each do |name|
      i += 1
      name = "age=#{name}"
      name_to_index[name] = i
      puts "%-40s %3d" % [name + ',', i]
    end
  end
  graphemeBreaks.each do |name|
    i += 1
    name = "graphemeclusterbreak=#{name.delete('_').downcase}"
    name_to_index[name] = i
    puts "%-40s %3d" % [name + ',', i]
  end
  blocks.each do |name|
    i += 1
    name = normalize_propname(name)
    name_to_index[name] = i
    puts "%-40s %3d" % [name + ',', i]
  end
end
puts(<<'__HEREDOC')
%%
static int
uniname2ctype(const UChar *name, unsigned int len)
{
  const struct uniname2ctype_struct *p = uniname2ctype_p((const char *)name, len);
  if (p) return p->ctype;
  return -1;
}
__HEREDOC
versions = $unicode_version.scan(/\d+/)
print("#if defined ONIG_UNICODE_VERSION_STRING && !( \\\n")
%w[MAJOR MINOR TEENY].zip(versions) do |n, v|
  print("      ONIG_UNICODE_VERSION_#{n} == #{v} && \\\n")
end
print("      1)\n")
print("# error ONIG_UNICODE_VERSION_STRING mismatch\n")
print("#endif\n")
print("#define ONIG_UNICODE_VERSION_STRING #{$unicode_version.dump}\n")
%w[MAJOR MINOR TEENY].zip(versions) do |n, v|
  print("#define ONIG_UNICODE_VERSION_#{n} #{v}\n")
end

output.restore

if header
  require 'tempfile'

  NAME2CTYPE = %w[gperf -7 -c -j1 -i1 -t -C -P -T -H uniname2ctype_hash -Q uniname2ctype_pool -N uniname2ctype_p]

  fds = []
  syms = %i[USE_UNICODE_PROPERTIES USE_UNICODE_AGE_PROPERTIES]
  begin
    fds << (tmp = Tempfile.new(%w"name2ctype .h"))
    IO.popen([*NAME2CTYPE, out: tmp], "w") {|f| output.show(f, *syms)}
  end while syms.pop
  fds.each(&:close)
  IO.popen(%W[diff -DUSE_UNICODE_AGE_PROPERTIES #{fds[1].path} #{fds[0].path}], "r") {|age|
    IO.popen(%W[diff -DUSE_UNICODE_PROPERTIES #{fds[2].path} -], "r", in: age) {|f|
      f.each {|line|
        line.gsub!(/\(int\)\((?:long|size_t)\)&\(\(struct uniname2ctype_pool_t \*\)0\)->uniname2ctype_pool_(str\d+),\s+/,
                   'uniname2ctype_offset(\1), ')
        puts line
      }
    }
  }
end
