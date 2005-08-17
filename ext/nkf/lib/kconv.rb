#
# kconv.rb - Kanji Converter.
#
# $Id$
#

require 'nkf'

module Kconv
  #
  # Public Constants
  #
  
  #Constant of Encoding
  AUTO = ::NKF::AUTO
  JIS = ::NKF::JIS
  EUC = ::NKF::EUC
  SJIS = ::NKF::SJIS
  BINARY = ::NKF::BINARY
  NOCONV = ::NKF::NOCONV
  ASCII = ::NKF::ASCII
  UTF8 = ::NKF::UTF8
  UTF16 = ::NKF::UTF16
  UTF32 = ::NKF::UTF32
  UNKNOWN = ::NKF::UNKNOWN
  
  #
  # Private Constants
  #
  
  REVISION = %q$Revision$
  
  #Regexp of Encoding
  RegexpShiftjis = /\A(?:
		       [\x00-\x7f\xa1-\xdf] |
		       [\x81-\x9f\xe0-\xfc][\x40-\x7e\x80-\xfc] 
		      )*\z/nx
  RegexpEucjp = /\A(?:
		    [\x00-\x7f]                         |
		    \x8e        [\xa1-\xdf]             |
		    \x8f        [\xa1-\xdf] [\xa1-\xfe] |
		    [\xa1-\xdf] [\xa1-\xfe]
		   )*\z/nx
  RegexpUtf8  = /\A(?:
		    [\x00-\x7f]                                     |
		    [\xc2-\xdf] [\x80-\xbf]                         |
		    \xe0        [\xa0-\xbf] [\x80-\xbf]             |
		    [\xe1-\xef] [\x80-\xbf] [\x80-\xbf]             |
		    \xf0        [\x90-\xbf] [\x80-\xbf] [\x80-\xbf] |
		    [\xf1-\xf3] [\x80-\xbf] [\x80-\xbf] [\x80-\xbf] |
		    \xf4        [\x80-\x8f] [\x80-\xbf] [\x80-\xbf]
		   )*\z/nx
  
  # SYMBOL_TO_OPTION is the table for Kconv#conv
  # Kconv#conv is intended to generic convertion method,
  # so this table specifies symbols which can be supported not only nkf...
  SYMBOL_TO_OPTION = {
    :iso2022jp	=> '-j',
    :jis	=> '-j',
    :eucjp	=> '-e',
    :euc	=> '-e',
    :eucjpms	=> '-e --cp932',
    :shiftjis	=> '-s',
    :sjis	=> '-s',
    :cp932	=> '-s --cp932',
    :windows31j	=> '-s --cp932',
    :utf8	=> '-w',
    :utf8bom	=> '-w8',
    :utf8n	=> '-w80',
    :utf8mac	=> '-w --utf8mac-input',
    :utf16	=> '-w16',
    :utf16be	=> '-w16B',
    :utf16ben	=> '-w16B0',
    :utf16le	=> '-w16L',
    :utf16len	=> '-w16L0',
    :lf		=> '-Lu',	# LF
    :cr		=> '-Lm',	# CR
    :crlf	=> '-Lw',	# CRLF
  }
  
  CONSTANT_TO_SYMBOL = {
    JIS		=> :iso2022jp,
    EUC		=> :eucjp,
    SJIS	=> :shiftjis,
    BINARY	=> :binary,
    NOCONV	=> :noconv,
    ASCII	=> :ascii,
    UTF8	=> :utf8,
    UTF16	=> :utf16,
    UTF32	=> :utf32,
    UNKNOWN	=> :unknown
  }
  
  #
  # Public Methods
  #
  
  #
  # Kconv.conv( str, :to => :"euc-jp", :from => :shift_jis, :opt => [:hiragana, :katakana] )
  #
  def conv(str, *args)
    option = nil
    if args[0].is_a? Hash
      option = [
	args[0][:to]||args[0]['to'],
	args[0][:from]||args[0]['from'],
	args[0][:opt]||args[0]['opt'] ]
    elsif args[0].is_a? String or args[0].is_a? Symbol or args[0].is_a? Integer
      option = args
    else
      return str
    end
    
    to = symbol_to_option(option[0])
    from = symbol_to_option(option[1]).to_s.sub(/(-[jesw])/o){$1.upcase}
    opt = option[2..-1].to_a.flatten.map{|x|symbol_to_option(x)}.compact.join(' ')
    
    nkf_opt = '-x -m0 %s %s %s' % [to, from, opt]
    result = ::NKF::nkf( nkf_opt, str)
  end
  alias :kconv :conv

  #
  # Encode to
  #

  def tojis(str)
    ::NKF::nkf('-j', str)
  end

  def toeuc(str)
    ::NKF::nkf('-e', str)
  end

  def tosjis(str)
    ::NKF::nkf('-s', str)
  end

  def toutf8(str)
    ::NKF::nkf('-w', str)
  end

  def toutf16(str)
    ::NKF::nkf('-w16', str)
  end

  alias :to_jis :tojis
  alias :to_euc :toeuc
  alias :to_eucjp :toeuc
  alias :to_sjis :tosjis
  alias :to_shiftjis :tosjis
  alias :to_iso2022jp :tojis
  alias :to_utf8 :toutf8
  alias :to_utf16 :toutf16

  #
  # guess
  #

  def guess(str)
    ::NKF::guess(str)
  end

  def guess_old(str)
    ::NKF::guess1(str)
  end

  def guess_as_symbol(str)
    CONSTANT_TO_SYMBOL[guess(str)]
  end

  #
  # isEncoding
  #

  def iseuc(str)
    RegexpEucjp.match( str )
  end
  
  def issjis(str)
    RegexpShiftjis.match( str )
  end

  def isutf8(str)
    RegexpUtf8.match( str )
  end

  #
  # encoding?
  #

  def eucjp?(str)
    RegexpEucjp.match( str ) ? true : false
  end

  def shiftjis?(str)
    RegexpShiftjis.match( str ) ? true : false
  end

  def utf8?(str)
    RegexpUtf8.match( str ) ? true : false
  end

  alias :euc? :eucjp?
  alias :sjis? :shiftjis?

  #
  # Private Methods
  #
  def symbol_to_option(symbol)
    if symbol.is_a? Integer
      symbol = CONSTANT_TO_SYMBOL[symbol]
    elsif symbol.to_s[0] == ?-
      return symbol.to_s
    end
    begin
      SYMBOL_TO_OPTION[ symbol.to_s.downcase.delete('-_').to_sym ]
    rescue
      return nil
    end
  end

  #
  # Make them module functions
  #
  module_function(*instance_methods(false))
  private_class_method :symbol_to_option

end

class String
  def kconv(*args)
    Kconv::kconv(self, *args)
  end
  
  def conv(*args)
    Kconv::conv(self, *args)
  end
  
  # to Encoding
  def tojis
    ::NKF::nkf('-j', self)
  end
  def toeuc
    ::NKF::nkf('-e', self)
  end
  def tosjis
    ::NKF::nkf('-s', self)
  end
  def toutf8
    ::NKF::nkf('-w', self)
  end
  def toutf16
    ::NKF::nkf('-w16', self)
  end
  alias :to_jis :tojis
  alias :to_euc :toeuc
  alias :to_eucjp :toeuc
  alias :to_sjis :tosjis
  alias :to_shiftjis :tosjis
  alias :to_iso2022jp :tojis
  alias :to_utf8 :toutf8
  alias :to_utf16 :toutf16
  
  # is Encoding
  def iseuc;	Kconv.iseuc( self ) end
  def issjis;	Kconv.issjis( self ) end
  def isutf8;	Kconv.isutf8( self ) end
  def eucjp?;	Kconv.eucjp?( self ) end
  def shiftjis?;Kconv.shiftjis?( self ) end
  def utf8?;	Kconv.utf8?( self ) end
  alias :euc? :eucjp?
  alias :sjis? :shiftjis?
  
  def guess_as_symbol;	Kconv.guess_as_symbol( self ) end
end
