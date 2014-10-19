# coding: utf-8

# Copyright Ayumu Nojima (野島 歩) and Martin J. Dürst (duerst@it.aoyama.ac.jp)

require 'unicode_normalize/normalize.rb'

# additions to class String for Unicode normalization
class String
  # === Unicode Normalization
  #
  # :call-seq:
  #    str.unicode_normalize(form=:nfc)
  #
  # Returns a normalized form of +str+, using Unicode normalizations
  # NFC, NFD, NFKC, or NFKD. The normalization form used is determined
  # by +form+, which is any of the four values :nfc, :nfd, :nfkc, or :nfkd.
  # The default is :nfc.
  #
  # If the string is not in a Unicode Encoding, then an Exception is raised.
  # In this context, 'Unicode Encoding' means any of  UTF-8, UTF-16BE/LE,
  # and UTF-32BE/LE. Currently, anything else than UTF-8 is implemented
  # by converting to UTF-8, which makes it slower than UTF-8.
  #
  # _Examples_
  #
  #   "a\u0300".unicode_normalize        #=> 'à' (same as "\u00E0")
  #   "a\u0300".unicode_normalize(:nfc)  #=> 'à' (same as "\u00E0")
  #   "\u00E0".unicode_normalize(:nfd)   #=> 'à' (same as "a\u0300")
  #   "\xE0".force_encoding('ISO-8859-1').unicode_normalize(:nfd)
  #                                      #=> Encoding::CompatibilityError raised
  #
  def unicode_normalize(form = :nfc)
    UnicodeNormalize.normalize(self, form)
  end

  # :call-seq:
  #    str.unicode_normalize(form=:nfc)
  #
  # Destructive version of String#unicode_normalize, doing Unicode
  # normalization in place.
  #
  def unicode_normalize!(form = :nfc)
    replace(self.normalize(form))
  end

  # :call-seq:
  #    str.unicode_normalized?(form=:nfc)
  #
  # Checks whether +str+ is in Unicode normalization form +form+,
  # which is any of the four values :nfc, :nfd, :nfkc, or :nfkd.
  # The default is :nfc.
  #
  # If the string is not in a Unicode Encoding, then an Exception is raised.
  # For details, see String#unicode_normalize.
  #
  # _Examples_
  #
  #   "a\u0300".unicode_normalized?        #=> false
  #   "a\u0300".unicode_normalized?(:nfd)  #=> true
  #   "\u00E0".unicode_normalized?         #=> true
  #   "\u00E0".unicode_normalized?(:nfd)   #=> false
  #   "\xE0".force_encoding('ISO-8859-1').unicode_normalized?
  #                                      #=> Encoding::CompatibilityError raised
  #
  def unicode_normalized?(form = :nfc)
    UnicodeNormalize.normalized?(self, form)
  end
end

