#
# kconv.rb - Kanji Converter.
#
# $Id$
#
# ----
#
# kconv.rb implements the Kconv class for Kanji Converter.  Additionally,
# some methods in String classes are added to allow easy conversion.
#

require 'nkf'

#
# Kanji Converter for Ruby.
#
module Kconv
  #
  # Public Constants
  #

  #Constant of Encoding

  # Auto-Detect
  AUTO = NKF::AUTO
  # ISO-2022-JP
  JIS = NKF::JIS
  # EUC-JP
  EUC = NKF::EUC
  # Shift_JIS
  SJIS = NKF::SJIS
  # BINARY
  BINARY = NKF::BINARY
  # NOCONV
  NOCONV = NKF::NOCONV
  # ASCII
  ASCII = NKF::ASCII
  # UTF-8
  UTF8 = NKF::UTF8
  # UTF-16
  UTF16 = NKF::UTF16
  # UTF-32
  UTF32 = NKF::UTF32
  # UNKNOWN
  UNKNOWN = NKF::UNKNOWN

  #
  #
  # Private Constants
  #
  
  #Regexp of Encoding
  
  # Regexp of Shift_JIS string (private constant)
  RegexpShiftjis = /\A(?:
		       [\x00-\x7f\xa1-\xdf] |
		       [\x81-\x9f\xe0-\xfc][\x40-\x7e\x80-\xfc] 
		      )*\z/nx

  # Regexp of EUC-JP string (private constant)
  RegexpEucjp = /\A(?:
		    [\x00-\x7f]                         |
		    \x8e        [\xa1-\xdf]             |
		    \x8f        [\xa1-\xfe] [\xa1-\xfe] |
		    [\xa1-\xfe] [\xa1-\xfe]
		   )*\z/nx

  # Regexp of UTF-8 string (private constant)
  RegexpUtf8  = /\A(?:
		    [\x00-\x7f]                                     |
		    [\xc2-\xdf] [\x80-\xbf]                         |
		    \xe0        [\xa0-\xbf] [\x80-\xbf]             |
		    [\xe1-\xef] [\x80-\xbf] [\x80-\xbf]             |
		    \xf0        [\x90-\xbf] [\x80-\xbf] [\x80-\xbf] |
		    [\xf1-\xf3] [\x80-\xbf] [\x80-\xbf] [\x80-\xbf] |
		    \xf4        [\x80-\x8f] [\x80-\xbf] [\x80-\xbf]
		   )*\z/nx

  #
  # Public Methods
  #
  
  # call-seq:
  #    Kconv.kconv(str, to_enc, from_enc=nil)
  #
  # Convert <code>str</code> to out_code.
  # <code>out_code</code> and <code>in_code</code> are given as constants of Kconv.
  def kconv(str, to_enc, from_enc=nil)
    opt = ''
    opt += ' --ic=' + from_enc.name if from_enc
    opt += ' --oc=' + to_enc.name if to_enc

    ::NKF::nkf(opt, str)
  end
  module_function :kconv

  #
  # Encode to
  #

  # call-seq:
  #    Kconv.tojis(str)   -> string
  #
  # Convert <code>str</code> to ISO-2022-JP
  def tojis(str)
    kconv(str, JIS)
  end
  module_function :tojis

  # call-seq:
  #    Kconv.toeuc(str)   -> string
  #
  # Convert <code>str</code> to EUC-JP
  def toeuc(str)
    kconv(str, EUC)
  end
  module_function :toeuc

  # call-seq:
  #    Kconv.tosjis(str)   -> string
  #
  # Convert <code>str</code> to Shift_JIS
  def tosjis(str)
    kconv(str, SJIS)
  end
  module_function :tosjis

  # call-seq:
  #    Kconv.toutf8(str)   -> string
  #
  # Convert <code>str</code> to UTF-8
  def toutf8(str)
    kconv(str, UTF8)
  end
  module_function :toutf8

  # call-seq:
  #    Kconv.toutf16(str)   -> string
  #
  # Convert <code>str</code> to UTF-16
  def toutf16(str)
    kconv(str, UTF16)
  end
  module_function :toutf16

  # call-seq:
  #    Kconv.toutf32(str)   -> string
  #
  # Convert <code>str</code> to UTF-32
  def toutf32(str)
    kconv(str, UTF32)
  end
  module_function :toutf32

  #
  # guess
  #

  # call-seq:
  #    Kconv.guess(str)   -> integer
  #
  # Guess input encoding by NKF.guess
  def guess(str)
    ::NKF::guess(str)
  end
  module_function :guess

  #
  # isEncoding
  #

  # call-seq:
  #    Kconv.iseuc(str)   -> obj or nil
  #
  # Returns whether input encoding is EUC-JP or not.
  #
  # *Note* don't expect this return value is MatchData.
  def iseuc(str)
    RegexpEucjp.match( str )
  end
  module_function :iseuc

  # call-seq:
  #    Kconv.issjis(str)   -> obj or nil
  #
  # Returns whether input encoding is Shift_JIS or not.
  #
  # *Note* don't expect this return value is MatchData.
  def issjis(str)
    RegexpShiftjis.match( str )
  end
  module_function :issjis

  # call-seq:
  #    Kconv.isutf8(str)   -> obj or nil
  #
  # Returns whether input encoding is UTF-8 or not.
  #
  # *Note* don't expect this return value is MatchData.
  def isutf8(str)
    RegexpUtf8.match( str )
  end
  module_function :isutf8

end

class String
  # call-seq:
  #    String#kconv(to_enc, from_enc)
  #
  # Convert <code>self</code> to out_code.
  # <code>out_code</code> and <code>in_code</code> are given as constants of Kconv.
  #
  # *Note*
  # This method decode MIME encoded string and
  # convert halfwidth katakana to fullwidth katakana.
  # If you don't want to decode them, use NKF.nkf.
  def kconv(to_enc, from_enc=nil)
    form_enc = self.encoding.name if !from_enc && self.encoding != Encoding.list[0]
    Kconv::kconv(self, to_enc, from_enc)
  end
  
  #
  # to Encoding
  #
  
  # call-seq:
  #    String#tojis   -> string
  #
  # Convert <code>self</code> to ISO-2022-JP
  def tojis; Kconv.tojis(self) end

  # call-seq:
  #    String#toeuc   -> string
  #
  # Convert <code>self</code> to EUC-JP
  def toeuc; Kconv.toeuc(self) end

  # call-seq:
  #    String#tosjis   -> string
  #
  # Convert <code>self</code> to Shift_JIS
  def tosjis; Kconv.tosjis(self) end

  # call-seq:
  #    String#toutf8   -> string
  #
  # Convert <code>self</code> to UTF-8
  def toutf8; Kconv.toutf8(self) end

  # call-seq:
  #    String#toutf16   -> string
  #
  # Convert <code>self</code> to UTF-16
  def toutf16; Kconv.toutf16(self) end

  # call-seq:
  #    String#toutf32   -> string
  #
  # Convert <code>self</code> to UTF-32
  def toutf32; Kconv.toutf32(self) end

  #
  # is Encoding
  #

  # call-seq:
  #    String#iseuc   -> obj or nil
  #
  # Returns whether <code>self</code>'s encoding is EUC-JP or not.
  #
  # *Note* don't expect this return value is MatchData.
  def iseuc;	Kconv.iseuc(self) end

  # call-seq:
  #    String#issjis   -> obj or nil
  #
  # Returns whether <code>self</code>'s encoding is Shift_JIS or not.
  #
  # *Note* don't expect this return value is MatchData.
  def issjis;	Kconv.issjis(self) end

  # call-seq:
  #    String#isutf8   -> obj or nil
  #
  # Returns whether <code>self</code>'s encoding is UTF-8 or not.
  #
  # *Note* don't expect this return value is MatchData.
  def isutf8;	Kconv.isutf8(self) end
end
