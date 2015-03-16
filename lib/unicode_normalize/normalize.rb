# coding: utf-8

# Copyright Ayumu Nojima (野島 歩) and Martin J. Dürst (duerst@it.aoyama.ac.jp)

require 'unicode_normalize/tables.rb'


module UnicodeNormalize
  ## Constant for max hash capacity to avoid DoS attack
  MAX_HASH_LENGTH = 18000 # enough for all test cases, otherwise tests get slow

  ## Regular Expressions and Hash Constants
  REGEXP_D = Regexp.compile(REGEXP_D_STRING, Regexp::EXTENDED)
  REGEXP_C = Regexp.compile(REGEXP_C_STRING, Regexp::EXTENDED)
  REGEXP_K = Regexp.compile(REGEXP_K_STRING, Regexp::EXTENDED)
  NF_HASH_D = Hash.new do |hash, key|
                         hash.shift if hash.length>MAX_HASH_LENGTH # prevent DoS attack
                         hash[key] = nfd_one(key)
                       end
  NF_HASH_C = Hash.new do |hash, key|
                         hash.shift if hash.length>MAX_HASH_LENGTH # prevent DoS attack
                         hash[key] = nfc_one(key)
                       end

  ## Constants For Hangul
  # for details such as the meaning of the identifiers below, please see
  # http://www.unicode.org/versions/Unicode7.0.0/ch03.pdf, pp. 144/145
  SBASE = 0xAC00
  LBASE = 0x1100
  VBASE = 0x1161
  TBASE = 0x11A7
  LCOUNT = 19
  VCOUNT = 21
  TCOUNT = 28
  NCOUNT = VCOUNT * TCOUNT
  SCOUNT = LCOUNT * NCOUNT

  # Unicode-based encodings (except UTF-8)
  UNICODE_ENCODINGS = [Encoding::UTF_16BE, Encoding::UTF_16LE, Encoding::UTF_32BE, Encoding::UTF_32LE,
                       Encoding::GB18030, Encoding::UCS_2BE, Encoding::UCS_4BE]

  ## Hangul Algorithm
  def self.hangul_decomp_one(target)
    syllable_index = target.ord - SBASE
    return target if syllable_index < 0 || syllable_index >= SCOUNT
    l = LBASE + syllable_index / NCOUNT
    v = VBASE + (syllable_index % NCOUNT) / TCOUNT
    t = TBASE + syllable_index % TCOUNT
    (t==TBASE ? [l, v] : [l, v, t]).pack('U*') + target[1..-1]
  end

  def self.hangul_comp_one(string)
    length = string.length
    if length>1 and 0 <= (lead =string[0].ord-LBASE) and lead  < LCOUNT and
                    0 <= (vowel=string[1].ord-VBASE) and vowel < VCOUNT
      lead_vowel = SBASE + (lead * VCOUNT + vowel) * TCOUNT
      if length>2 and 0 <= (trail=string[2].ord-TBASE) and trail < TCOUNT
        (lead_vowel + trail).chr(Encoding::UTF_8) + string[3..-1]
      else
        lead_vowel.chr(Encoding::UTF_8) + string[2..-1]
      end
    else
      string
    end
  end

  ## Canonical Ordering
  def self.canonical_ordering_one(string)
    sorting = string.each_char.collect { |c| [c, CLASS_TABLE[c]] }
    (sorting.length-2).downto(0) do |i| # almost, but not exactly bubble sort
      (0..i).each do |j|
        later_class = sorting[j+1].last
        if 0<later_class and later_class<sorting[j].last
          sorting[j], sorting[j+1] = sorting[j+1], sorting[j]
        end
      end
    end
    return sorting.collect(&:first).join('')
  end

  ## Normalization Forms for Patterns (not whole Strings)
  def self.nfd_one(string)
    string = string.chars.map! {|c| DECOMPOSITION_TABLE[c] || c}.join('')
    canonical_ordering_one(hangul_decomp_one(string))
  end

  def self.nfc_one(string)
    nfd_string = nfd_one string
    start = nfd_string[0]
    last_class = CLASS_TABLE[start]-1
    accents = ''
    nfd_string[1..-1].each_char do |accent|
      accent_class = CLASS_TABLE[accent]
      if last_class<accent_class and composite = COMPOSITION_TABLE[start+accent]
        start = composite
      else
        accents << accent
        last_class = accent_class
      end
    end
    hangul_comp_one(start+accents)
  end

  def self.normalize(string, form = :nfc)
    encoding = string.encoding
    case encoding
    when Encoding::UTF_8
      case form
      when :nfc then
        string.gsub REGEXP_C, NF_HASH_C
      when :nfd then
        string.gsub REGEXP_D, NF_HASH_D
      when :nfkc then
        string.gsub(REGEXP_K, KOMPATIBLE_TABLE).gsub(REGEXP_C, NF_HASH_C)
      when :nfkd then
        string.gsub(REGEXP_K, KOMPATIBLE_TABLE).gsub(REGEXP_D, NF_HASH_D)
      else
        raise ArgumentError, "Invalid normalization form #{form}."
      end
    when Encoding::US_ASCII
      string
    when *UNICODE_ENCODINGS
      normalize(string.encode(Encoding::UTF_8), form).encode(encoding)
    else
      raise Encoding::CompatibilityError, "Unicode Normalization not appropriate for #{encoding}"
    end
  end

  def self.normalized?(string, form = :nfc)
    encoding = string.encoding
    case encoding
    when Encoding::UTF_8
      case form
      when :nfc then
        string.scan REGEXP_C do |match|
          return false  if NF_HASH_C[match] != match
        end
        true
      when :nfd then
        string.scan REGEXP_D do |match|
          return false  if NF_HASH_D[match] != match
        end
        true
      when :nfkc then
        normalized?(string, :nfc) and string !~ REGEXP_K
      when :nfkd then
        normalized?(string, :nfd) and string !~ REGEXP_K
      else
        raise ArgumentError, "Invalid normalization form #{form}."
      end
    when Encoding::US_ASCII
      true
    when *UNICODE_ENCODINGS
      normalized? string.encode(Encoding::UTF_8), form
    else
      raise Encoding::CompatibilityError, "Unicode Normalization not appropriate for #{encoding}"
    end
  end

end # module
