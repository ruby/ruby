# coding: utf-8

# Copyright Ayumu Nojima (野島 歩) and Martin J. Dürst (duerst@it.aoyama.ac.jp)

# Script to generate Ruby data structures used in implementing
# String#unicode_normalize,...

# Constants for input and ouput directory
InputDataDir = '../enc/unicode/data'
OuputDataDir = '../lib/unicode_normalize'

# convenience methods
class Integer
  def to_UTF8() # convert to string, taking legibility into account
    if self>0xFFFF
      "\\u{#{to_s(16).upcase}}"
    elsif self>0x7f
      "\\u#{to_s(16).upcase.rjust(4, '0')}"
    else
      chr.sub(/[\\\"]/, '\\\&')
    end
  end
end

class Array
  def line_slice(new_line) # joins items, 8 items per line
    each_slice(8).collect(&:join).join(new_line).gsub(/ +$/, '')
  end

  def to_UTF8()  collect(&:to_UTF8).join  end

  def to_regexp_chars # converts an array of Integers to character ranges
    sort.inject([]) do |ranges, value|
      if ranges.last and ranges.last[1]+1>=value
        ranges.last[1] = value
        ranges
      else
        ranges << [value, value]
      end
    end.collect do |first, last|
      case last-first
      when 0
        first.to_UTF8
      when 1
        first.to_UTF8 + last.to_UTF8
      else
        first.to_UTF8 + '-' + last.to_UTF8
      end
    end.line_slice "\" \\\n    \""
  end
end

class Hash
  def to_hash_string
    collect do |key, value|
      "\"#{key.to_UTF8}\"=>\"#{value.to_UTF8}\".freeze, "
    end.line_slice "\n    "
  end
end

# read the file 'CompositionExclusions.txt'
composition_exclusions = IO.readlines("#{InputDataDir}/CompositionExclusions.txt")
                           .select { |line| line =~ /^[A-Z0-9]{4,5}/ }
                           .collect { |line| line.split(' ').first.hex }

decomposition_table = {}
kompatible_table = {}
CombiningClass = {}  # constant to allow use in Integer#to_UTF8

# read the file 'UnicodeData.txt'
IO.foreach("#{InputDataDir}/UnicodeData.txt") do |line|
  codepoint, name, _2, char_class, _4, decomposition, *_rest = line.split(";")

  case decomposition
  when /^[0-9A-F]/
    decomposition_table[codepoint.hex] = decomposition.split(' ').collect(&:hex)
  when /^</
    kompatible_table[codepoint.hex] = decomposition.split(' ').drop(1).collect(&:hex)
  end
  CombiningClass[codepoint.hex] = char_class.to_i if char_class != "0"

  if name=~/(First|Last)>$/ and (char_class!="0" or decomposition!="")
    warn "Unexpected: Character range with data relevant to normalization!"
  end
end

# calculate compositions from decompositions
composition_table = decomposition_table.reject do |character, decomposition|
  composition_exclusions.member? character or # predefined composition exclusion
    decomposition.length<=1 or                # Singleton Decomposition
    CombiningClass[character] or              # character is not a Starter
    CombiningClass[decomposition.first]       # decomposition begins with a character that is not a Starter
end.invert

# recalculate composition_exclusions
composition_exclusions = decomposition_table.keys - composition_table.values

accent_array = CombiningClass.keys + composition_table.keys.collect(&:last)

composition_starters = composition_table.keys.collect(&:first)

hangul_no_trailing = 0xAC00.step(0xD7A3, 28).to_a

# expand decomposition table values
decomposition_table.each do |key, value|
  position = 0
  while position < value.length
    if decomposition = decomposition_table[value[position]]
      decomposition_table[key] = value = value.dup # avoid overwriting composition_table key
      value[position, 1] = decomposition
    else
      position += 1
    end
  end
end

# deal with relationship between canonical and kompatibility decompositions
decomposition_table.each do |key, value|
  value = value.dup
  expanded = false
  position = 0
  while position < value.length
    if decomposition = kompatible_table[value[position]]
      value[position, 1] = decomposition
      expanded = true
    else
      position += 1
    end
  end
  kompatible_table[key] = value if expanded
end

class_table_str = CombiningClass.collect do |key, value|
  "\"#{key.to_UTF8}\"=>#{value}, "
end.line_slice "\n    "

# generate normalization tables file
open("#{OuputDataDir}/normalize_tables.rb", "w").print <<MAPPING_TABLE_FILE_END
# coding: us-ascii

# automatically generated by tool/unicode_norm_gen.rb

module Normalize
  accents = "" \\
    "[#{accent_array.to_regexp_chars}]" \\
  "".freeze
  ACCENTS = accents
  REGEXP_D_STRING = "\#{''  # composition starters and composition exclusions
    }" \\
    "[#{(composition_table.values+composition_exclusions).to_regexp_chars}]\#{accents}*" \\
    "|\#{''  # characters that can be the result of a composition, except composition starters
    }" \\
    "[#{(composition_starters-composition_table.values).to_regexp_chars}]?\#{accents}+" \\
    "|\#{''  # precomposed Hangul syllables
    }" \\
    "[\\u{AC00}-\\u{D7A4}]" \\
  "".freeze
  REGEXP_C_STRING = "\#{''  # composition exclusions
    }" \\
    "[#{composition_exclusions.to_regexp_chars}]\#{accents}*" \\
    "|\#{''  # composition starters and characters that can be the result of a composition
    }" \\
    "[#{(composition_starters+composition_table.values).to_regexp_chars}]?\#{accents}+" \\
    "|\#{''  # Hangul syllables with separate trailer
    }" \\
    "[#{hangul_no_trailing.to_regexp_chars}][\\u11A8-\\u11C2]" \\
    "|\#{''  # decomposed Hangul syllables
    }" \\
    "[\\u1100-\\u1112][\\u1161-\\u1175][\\u11A8-\\u11C2]?" \\
  "".freeze
  REGEXP_K_STRING = "" \\
    "[#{kompatible_table.keys.to_regexp_chars}]" \\
  "".freeze

  class_table = {
    #{class_table_str}
  }
  class_table.default = 0
  CLASS_TABLE = class_table.freeze

  DECOMPOSITION_TABLE = {
    #{decomposition_table.to_hash_string}
  }.freeze

  KOMPATIBLE_TABLE = {
    #{kompatible_table.to_hash_string}
  }.freeze

  COMPOSITION_TABLE = {
    #{composition_table.to_hash_string}
  }.freeze
end
MAPPING_TABLE_FILE_END
