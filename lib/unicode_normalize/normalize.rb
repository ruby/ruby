# coding: utf-8
# frozen_string_literal: true

# Copyright Ayumu Nojima (野島 歩) and Martin J. Dürst (duerst@it.aoyama.ac.jp)

# This file, the companion file tables.rb (autogenerated), and the module,
# constants, and method defined herein are part of the implementation of the
# built-in String class, not part of the standard library. They should
# therefore never be gemified. They implement the methods
# String#unicode_normalize, String#unicode_normalize!, and String#unicode_normalized?.
#
# They are placed here because they are written in Ruby. They are loaded on
# demand when any of the three methods mentioned above is executed for the
# first time. This reduces the memory footprint and startup time for scripts
# and applications that do not use those methods.
#
# The name and even the existence of the module UnicodeNormalize and all of its
# content are purely an implementation detail, and should not be exposed in
# any test or spec or otherwise.

require_relative 'tables'

# :stopdoc:
module UnicodeNormalize # :nodoc:
  ## Constant for max hash capacity to avoid DoS attack
  MAX_HASH_LENGTH = 18000 # enough for all test cases, otherwise tests get slow

  ## Regular Expressions and Hash Constants
  REGEXP_D = Regexp.compile(REGEXP_D_STRING, Regexp::EXTENDED)
  REGEXP_C = Regexp.compile(REGEXP_C_STRING, Regexp::EXTENDED)
  REGEXP_K = Regexp.compile(REGEXP_K_STRING, Regexp::EXTENDED)
  NF_HASH_D = Hash.new do |hash, key|
    hash.shift if hash.length > MAX_HASH_LENGTH # prevent DoS attack
    hash[key] = nfd_one(key).pack("U*")
  end
  NF_HASH_C = Hash.new do |hash, key|
    hash.shift if hash.length > MAX_HASH_LENGTH # prevent DoS attack
    hash[key] = nfc_one(key).pack("U*")
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
    syllable_index = target[0] - SBASE
    return target if syllable_index < 0 || syllable_index >= SCOUNT

    l = LBASE + syllable_index / NCOUNT
    v = VBASE + (syllable_index % NCOUNT) / TCOUNT
    t = syllable_index % TCOUNT
    (t == 0 ? [l, v] : [l, v, TBASE + t]) + target[1..-1]
  end

  def self.hangul_comp_one(codepoints)
    length = codepoints.length
    if length > 1 && 0 <= (lead = codepoints[0] - LBASE) && lead < LCOUNT &&
      0 <= (vowel = codepoints[1] - VBASE) && vowel < VCOUNT
      lead_vowel = SBASE + (lead * VCOUNT + vowel) * TCOUNT
      if length > 2 && 0 < (trail = codepoints[2] - TBASE) && trail < TCOUNT
        codepoints[3..-1].unshift(lead_vowel + trail)
      else
        codepoints[2..-1].unshift(lead_vowel)
      end
    else
      codepoints
    end
  end

  ## Canonical Ordering
  def self.canonical_ordering_one(codepoints)
    # almost, but not exactly bubble sort
    (codepoints.length - 2).downto(0) do |i|
      (0..i).each do |j|
        later_class = CLASS_TABLE[codepoints[j + 1]]
        if 0 < later_class && later_class < CLASS_TABLE[codepoints[j]]
          codepoints[j], codepoints[j + 1] = codepoints[j + 1], codepoints[j]
        end
      end
    end
    codepoints
  end

  ## Normalization Forms for Patterns (not whole Strings)
  def self.nfd_one(string)
    res = []
    string.each_codepoint { |cp| subst = DECOMPOSITION_TABLE[cp]; subst ? res.concat(subst) : res << cp }

    canonical_ordering_one(hangul_decomp_one(res))
  end

  def self.nfc_one(string)
    nfd_codepoints = nfd_one(string)
    start = nfd_codepoints[0]
    last_class = CLASS_TABLE[start] - 1
    accents = []
    nfd_codepoints[1..-1].each do |accent|
      accent_class = CLASS_TABLE[accent]
      if last_class < accent_class && (composite = COMPOSITION_TABLE[[start, accent]])
        start = composite
      else
        accents << accent
        last_class = accent_class
      end
    end
    hangul_comp_one(accents.unshift(start))
  end

  def self.normalize(string, form = :nfc)
    encoding = string.encoding
    case encoding
    when Encoding::UTF_8
      return string if string.ascii_only?

      case form
      when :nfc
        string.gsub REGEXP_C, NF_HASH_C
      when :nfd
        string.gsub REGEXP_D, NF_HASH_D
      when :nfkc
        string.gsub(REGEXP_K, KOMPATIBLE_TABLE).tap { |s| s.gsub!(REGEXP_C, NF_HASH_C) }
      when :nfkd
        string.gsub(REGEXP_K, KOMPATIBLE_TABLE).tap { |s| s.gsub!(REGEXP_D, NF_HASH_D) }
      else
        raise ArgumentError, "Invalid normalization form #{form}."
      end
    when Encoding::US_ASCII
      string
    when *UNICODE_ENCODINGS
      return string if string.ascii_only?

      normalize(string.encode(Encoding::UTF_8), form).encode(encoding)
    else
      raise Encoding::CompatibilityError, "Unicode Normalization not appropriate for #{encoding}"
    end
  end

  def self.normalized?(string, form = :nfc)
    encoding = string.encoding
    case encoding
    when Encoding::UTF_8
      return true if string.ascii_only?

      case form
      when :nfc
        string.scan REGEXP_C do |match|
          return false if NF_HASH_C[match] != match
        end
        true
      when :nfd
        string.scan REGEXP_D do |match|
          return false if NF_HASH_D[match] != match
        end
        true
      when :nfkc
        normalized?(string, :nfc) && string !~ REGEXP_K
      when :nfkd
        normalized?(string, :nfd) && string !~ REGEXP_K
      else
        raise ArgumentError, "Invalid normalization form #{form}."
      end
    when Encoding::US_ASCII
      true
    when *UNICODE_ENCODINGS
      return true if string.ascii_only?

      normalized? string.encode(Encoding::UTF_8), form
    else
      raise Encoding::CompatibilityError, "Unicode Normalization not appropriate for #{encoding}"
    end
  end
end # module
