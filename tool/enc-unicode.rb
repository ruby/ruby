#!/usr/bin/env ruby

# Creates the data structures needed by Onigurma to map Unicode codepoints to
# property names and POSIX character classes

unless ARGV.size == 2
  $stderr.puts "Usage: #{$0} UnicodeData.txt Scripts.txt"
  exit(1)
end

POSIX_NAMES = %w[NEWLINE Alpha Blank Cntrl Digit Graph Lower Print Punct Space Upper XDigit Word Alnum ASCII]

def pair_codepoints(codepoints)

  # We have a sorted Array of codepoints that we wish to partition into
  # ranges such that the start- and endpoints form an inclusive set of
  # codepoints with property _property_. Note: It is intended that some ranges
  # will begin with the value with  which they end, e.g. 0x0020 -> 0x0020

  codepoints = codepoints.uniq.sort
  last_cp = codepoints.first
  pairs = [[last_cp, nil]]
  codepoints[1..-1].each do |codepoint|

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
  data = {'Cn' => []}
  IO.foreach(file) do |line|
    fields = line.split(';')
    cp = fields[0].to_i(16)

    # The Cn category represents unassigned characters. These are not listed in
    # UnicodeData.txt so we must derive them by looking for 'holes' in the range
    # of listed codepoints. We increment the last codepoint seen and compare it
    # with the current codepoint. If the current codepoint is less than
    # last_cp.next we have found a hole, so we add the missing codepoint to the
    # Cn category.
    while ((last_cp = last_cp.next) < cp)
      data['Cn'] << last_cp
    end

    # The third field denotes the 'General' category, e.g. Lu
    (data[fields[2]] ||= []) << cp

    # The 'Major' category is the first letter of the 'General' category, e.g.
    # 'Lu' -> 'L'
    (data[fields[2][0,1]] ||= []) << cp
    last_cp = cp
  end

  # General Category property
  gcps = %w[Any Assigned]
  gcps.concat data.keys.sort

  # The last Cn codepoint should be 0x10ffff. If it's not, append the missing
  # codepoints to Cn and C
  cn_remainder = (data['Cn'].last.next..0x10ffff).to_a
  data['Cn'] += cn_remainder
  data['C'] += cn_remainder

  # We now derive the character classes (POSIX brackets), e.g. [[:alpha:]]
  #

  # alnum    Letter | Mark | Decimal_Number
  data['Alnum'] = data['L'] + data['M'] + data['Nd']

  # alpha    Letter | Mark
  data['Alpha'] = data['L'] + data['M']

  # ascii    0000 - 007F
  data['ASCII'] = (0..0x007F).to_a

  # blank    Space_Separator | 0009
  data['Blank'] = data['Zs'] + [0x0009]

  # cntrl    Control
  data['Cntrl'] = data['Cc']

  # digit    Decimal_Number
  data['Digit'] = data['Nd']

  # lower    Lowercase_Letter
  data['Lower'] = data['Ll']

  # punct    Connector_Punctuation | Dash_Punctuation | Close_Punctuation |
  #          Final_Punctuation | Initial_Punctuation | Other_Punctuation |
  #          Open_Punctuation
  # NOTE: This definition encompasses the entire P category, and the current
  # mappings agree, but we explcitly declare this way to marry it with the above
  # definition.
  data['Punct'] = data['Pc'] + data['Pd'] + data['Pe'] + data['Pf'] +
                  data['Pi'] + data['Po'] + data['Ps']

  # space    Space_Separator | Line_Separator | Paragraph_Separator |
  #               0009 | 000A | 000B | 000C | 000D | 0085
  data['Space'] = data['Zs'] + data['Zl'] + data['Zp'] +
                  [0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0085]

  # upper    Uppercase_Letter
  data['Upper'] = data['Lu']

  # xdigit   0030 - 0039 | 0041 - 0046 | 0061 - 0066
  #          (0-9, a-f, A-F)
  data['XDigit'] = (0x0030..0x0039).to_a + (0x0041..0x0046).to_a +
                   (0x0061..0x0066).to_a

  # word     Letter | Mark | Decimal_Number | Connector_Punctuation
  data['Word'] = data['L'] + data['M'] + data['Nd'] + data['Pc']

  # graph    [[:^space:]] && ^Control && ^Unassigned && ^Surrogate
  data['Graph'] = data['L'] + data['M'] + data['N'] + data['P'] + data['S']
  data['Graph'] -= data['Space'] - data['C']

  # print    [[:graph:]] | [[:space:]]
  data['Print'] = data['Graph'] + data['Space']

  # NEWLINE - This was defined in unicode.c
  data['NEWLINE'] = [0x000a]

  # Any - Defined in unicode.c
  data['Any'] = (0x0000..0x10ffff).to_a

  # Assigned - Defined in unicode.c; interpreted as every character in the
  # Unicode range minus the unassigned characters
  data['Assigned'] = data['Any'] - data['Cn']

  # Returns General Category Property names and the data
  [gcps, data]
end


def parse_scripts(file)
  script = nil
  data = []
  names = []
  IO.foreach(file) do |line|
    if /^# Total code points: / =~ line
      make_const(script, pair_codepoints(data), 'Script')
      names << script
      data = []
    elsif /^([[:xdigit:]]+)(?:..([[:xdigit:]]+))?\s*;\s*(\w+)/ =~ line
      script = $3
      $2 ? data.concat(($1.to_i(16)..$2.to_i(16)).to_a) : data.push($1.to_i(16))
    end
  end
  names
end

# make_const(property, pairs, name): Prints a 'static const' structure for a
# given property, group of paired codepoints, and a human-friendly name for
# the group
def make_const(prop, pairs, name)
  puts "\n/* '#{prop}': #{name} */"
  puts "static const OnigCodePoint CR_#{prop}[] = {"
  # The first element of the constant is the number of pairs of codepoints
  puts "\t#{pairs.size},"
  pairs.each do |pair|
    pair.map! { |c|  c == 0 ? '0x0000' : sprintf("%0#6x", c) }
    puts "\t#{pair.first}, #{pair.last},"
  end
  puts "}; /* CR_#{prop} */"
end

puts '%{'
gcps, data = parse_unicode_data(ARGV[0])
POSIX_NAMES.each do |name|
  make_const(name, pair_codepoints(data[name]), "[[:#{name}:]]")
end
print "\n#ifdef USE_UNICODE_PROPERTIES"
gcps.each do |name|
  category =
    case name.size
    when 1 then 'Major Category'
    when 2 then 'General Category'
    else        '-'
    end
  make_const(name, pair_codepoints(data[name]), category)
end
scripts = parse_scripts(ARGV[1])
puts "#endif /* USE_UNICODE_PROPERTIES */"

puts "\n\nstatic const OnigCodePoint* const CodeRanges[] = {"
POSIX_NAMES.each{|name|puts"  CR_#{name},"}
puts "#ifdef USE_UNICODE_PROPERTIES"
gcps.each{|name|puts"  CR_#{name},"}
scripts.each{|name|puts"  CR_#{name},"}
puts "#endif /* USE_UNICODE_PROPERTIES */"
puts "};"

puts(<<'__HEREDOC')
struct uniname2ctype_struct {
  int name, ctype;
};

static const struct uniname2ctype_struct *uniname2ctype_p(const char *, unsigned int);
%}
struct uniname2ctype_struct;
%%
__HEREDOC
i = -1
POSIX_NAMES.each  {|name|puts"%-21s %3d"%[name+',', i+=1]}
puts "#ifdef USE_UNICODE_PROPERTIES"
gcps.each{|name|puts"%-21s %3d"%[name+',', i+=1]}
scripts.each{|name|puts"%-21s %3d"%[name+',', i+=1]}
puts "#endif /* USE_UNICODE_PROPERTIES */\n"
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
