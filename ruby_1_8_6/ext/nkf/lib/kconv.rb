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
  # Private Constants
  #
  
  # Revision of kconv.rb
  REVISION = %q$Revision$
  
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
  #    Kconv.kconv(str, out_code, in_code = Kconv::AUTO)
  #
  # Convert <code>str</code> to out_code.
  # <code>out_code</code> and <code>in_code</code> are given as constants of Kconv.
  #
  # *Note*
  # This method decode MIME encoded string and
  # convert halfwidth katakana to fullwidth katakana.
  # If you don't want to decode them, use NKF.nkf.
  def kconv(str, out_code, in_code = AUTO)
    opt = '-'
    case in_code
    when ::NKF::JIS
      opt << 'J'
    when ::NKF::EUC
      opt << 'E'
    when ::NKF::SJIS
      opt << 'S'
    when ::NKF::UTF8
      opt << 'W'
    when ::NKF::UTF16
      opt << 'W16'
    end

    case out_code
    when ::NKF::JIS
      opt << 'j'
    when ::NKF::EUC
      opt << 'e'
    when ::NKF::SJIS
      opt << 's'
    when ::NKF::UTF8
      opt << 'w'
    when ::NKF::UTF16
      opt << 'w16'
    when ::NKF::NOCONV
      return str
    end

    opt = '' if opt == '-'

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
  #
  # *Note*
  # This method decode MIME encoded string and
  # convert halfwidth katakana to fullwidth katakana.
  # If you don't want it, use NKF.nkf('-jxm0', str).
  def tojis(str)
    ::NKF::nkf('-jm', str)
  end
  module_function :tojis

  # call-seq:
  #    Kconv.toeuc(str)   -> string
  #
  # Convert <code>str</code> to EUC-JP
  #
  # *Note*
  # This method decode MIME encoded string and
  # convert halfwidth katakana to fullwidth katakana.
  # If you don't want it, use NKF.nkf('-exm0', str).
  def toeuc(str)
    ::NKF::nkf('-em', str)
  end
  module_function :toeuc

  # call-seq:
  #    Kconv.tosjis(str)   -> string
  #
  # Convert <code>str</code> to Shift_JIS
  #
  # *Note*
  # This method decode MIME encoded string and
  # convert halfwidth katakana to fullwidth katakana.
  # If you don't want it, use NKF.nkf('-sxm0', str).
  def tosjis(str)
    ::NKF::nkf('-sm', str)
  end
  module_function :tosjis

  # call-seq:
  #    Kconv.toutf8(str)   -> string
  #
  # Convert <code>str</code> to UTF-8
  #
  # *Note*
  # This method decode MIME encoded string and
  # convert halfwidth katakana to fullwidth katakana.
  # If you don't want it, use NKF.nkf('-wxm0', str).
  def toutf8(str)
    ::NKF::nkf('-wm', str)
  end
  module_function :toutf8

  # call-seq:
  #    Kconv.toutf16(str)   -> string
  #
  # Convert <code>str</code> to UTF-16
  #
  # *Note*
  # This method decode MIME encoded string and
  # convert halfwidth katakana to fullwidth katakana.
  # If you don't want it, use NKF.nkf('-w16xm0', str).
  def toutf16(str)
    ::NKF::nkf('-w16m', str)
  end
  module_function :toutf16

  #
  # guess
  #

  # call-seq:
  #    Kconv.guess(str)   -> integer
  #
  # Guess input encoding by NKF.guess2
  def guess(str)
    ::NKF::guess(str)
  end
  module_function :guess

  # call-seq:
  #    Kconv.guess_old(str)   -> integer
  #
  # Guess input encoding by NKF.guess1
  def guess_old(str)
    ::NKF::guess1(str)
  end
  module_function :guess_old

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
  #    String#kconv(out_code, in_code = Kconv::AUTO)
  #
  # Convert <code>self</code> to out_code.
  # <code>out_code</code> and <code>in_code</code> are given as constants of Kconv.
  #
  # *Note*
  # This method decode MIME encoded string and
  # convert halfwidth katakana to fullwidth katakana.
  # If you don't want to decode them, use NKF.nkf.
  def kconv(out_code, in_code=Kconv::AUTO)
    Kconv::kconv(self, out_code, in_code)
  end
  
  #
  # to Encoding
  #
  
  # call-seq:
  #    String#tojis   -> string
  #
  # Convert <code>self</code> to ISO-2022-JP
  #
  # *Note*
  # This method decode MIME encoded string and
  # convert halfwidth katakana to fullwidth katakana.
  # If you don't want it, use NKF.nkf('-jxm0', str).
  def tojis; Kconv.tojis(self) end

  # call-seq:
  #    String#toeuc   -> string
  #
  # Convert <code>self</code> to EUC-JP
  #
  # *Note*
  # This method decode MIME encoded string and
  # convert halfwidth katakana to fullwidth katakana.
  # If you don't want it, use NKF.nkf('-exm0', str).
  def toeuc; Kconv.toeuc(self) end

  # call-seq:
  #    String#tosjis   -> string
  #
  # Convert <code>self</code> to Shift_JIS
  #
  # *Note*
  # This method decode MIME encoded string and
  # convert halfwidth katakana to fullwidth katakana.
  # If you don't want it, use NKF.nkf('-sxm0', str).
  def tosjis; Kconv.tosjis(self) end

  # call-seq:
  #    String#toutf8   -> string
  #
  # Convert <code>self</code> to UTF-8
  #
  # *Note*
  # This method decode MIME encoded string and
  # convert halfwidth katakana to fullwidth katakana.
  # If you don't want it, use NKF.nkf('-wxm0', str).
  def toutf8; Kconv.toutf8(self) end

  # call-seq:
  #    String#toutf16   -> string
  #
  # Convert <code>self</code> to UTF-16
  #
  # *Note*
  # This method decode MIME encoded string and
  # convert halfwidth katakana to fullwidth katakana.
  # If you don't want it, use NKF.nkf('-w16xm0', str).
  def toutf16; Kconv.toutf16(self) end

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
