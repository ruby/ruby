require 'nkf'

module Kconv
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
  
  #Regexp of Encoding
  Iconv_Shift_JIS = /\A(?:
		  [\x00-\x7f\xa1-\xdf]                                             |
		  \x81[\x40-\x7e\x80-\xac\xb8-\xbf\xc8-\xce\xda-\xe8\xf0-\xf7\xfc] |
		  \x82[\x4f-\x58\x60-\x79\x81-\x9a\x9f-\xf1]                       |
		  \x83[\x40-\x7e\x80-\x96\x9f-\xb6\xbf-\xd6\x40-\x60]              |
		  \x84[\x40-\x60\x70-\x7e\x80-\x91\x9f-\xbe\x9f-\xfc]              |
		  [\x89-\x8f\x90-\x97\x99-\x9f\xe0-\xea][\x40-\x7e]                |
		  [\x89-\x97\x99-\x9f\xe0-\xe9][\x80-\xfc]                         |
		  \x98[\x40-\x72\x9f-\xfc]                                         |
		  \xea[\x80-\xa4]
		 )*\z/nx
  Iconv_EUC_JP = /\A(?:
	       [\x00-\x7f]                                             |
	       \x8e        [\xa1-\xdf]                                 |
	       \x8f        [\xa1-\xdf] [\xa1-\xdf]                     |
	       [\xa1\xb0-\xbce\xd0-\xf3][\xa1-\xfe]                    |
	       \xa2[\xa1-\xae\xba-\xc1\xca-\xd0\xdc-\xea\xf2-\xf9\xfe] |
	       \xa3[\xb0-\xb9\xc1-\xda\xe1-\xfa]                       |
	       \xa4[\xa1-\xf3]                                         |
	       \xa5[\xa1-\xf6]                                         |
	       \xa6[\xa1-\xb8\xc1-\xd8]                                |
	       \xa7[\xa1-\xc1\xd1-\xf1]                                |
	       \xa8[\xa1-\xc0]                                         |
	       \xcf[\xa1-\xd3]                                         |
	       \xf4[\xa1-\xa6]
	      )*\z/nx
  Iconv_UTF8  = /\A(?:\xef\xbb\xbf)?(?:
  [\x00-\x7f]                                                       |
  \xc2[\x80-\x8d\x90-\x9f\xa1\xaa\xac\xae-\xb1\xb4\xb6\xb8\xba\xbf] |
  \xc3[\x80-\xbf]                                                   |
  \xc4[\x80-\x93\x96-\xa2\xa4-\xab\xae-\xbf]                        |
  \xc5[\x80-\x8d\x90-\xbe]                                          |
  \xc7[\x8d-\x9c\xb5]                                               |
  \xcb[\x87\x98-\x9b\x9d]                                           |
  \xce[\x84-\x86\x88-\x8a\x8c\x8e-\xa1\xa3-\xbf]                    |
  \xcf[\x80-\x8e]                                                   |
  \xd0[\x81-\x8c\x8e-\xbf]                                          |
  \xd1[\x80-\x8f\x91-\x9f]                                          |
  \xe2\x84[\x83\x96\xa2\xab]                                        |
  \xe2\x86[\x83\x91-\x93\x96\xa2\xab]                               |
  \xe2\x87[\x83\x91-\x94\x96\xa2\xab]                               |
  \xe2\x88[\x82-\x83\x87-\x88\x8b\x91-\x94\x96\x9a\x9d-\x9e\xa0\xa2\xa7-\xac\xb4-\xb5\xbd]  |
  \xe2\x89[\x82-\x83\x87-\x88\x8b\x91-\x94\x96\x9a\x9d-\x9e\xa0-\xa2\xa6-\xac\xb4-\xb5\xbd] |
  \xe2[\x8a\x8c][\x82-\x83\x86-\x88\x8b\x91-\x94\x96\x9a\x9d-\x9e\xa0-\xa2\xa5-\xac\xb4-\xb5\xbd] |
  \xe2[\x94-\x99][\x81-\x83\x86-\x88\x8b-\x8c\x8f-\x94\x96-\x98\x9a-\x9e\xa0-\xac\xaf-\xb0\xb3-\xb5\xb7-\xb8\xbb-\xbd\xbf] |
  \xe3\x80[\x81-\x83\x85-\x98\x9a-\x9e\xa0-\xad\xaf-\xb0\xb2-\xb5\xb7-\xb8\xbb-\xbd\xbf] |
  \xe3[\x81-\x83\xb8-\xbf][\x81-\xbf]          |
  [\xe5-\xe7][\x80-\xbf][\x81-\xbf]            |
  \xe8[\x80-\xae\xb0-\xbf][\x81-\xbf]          |
  \xe9[\x80-\x92\x95-\xb1\xb3-\xbe][\x81-\xbf] |
  \xef[\xbc-\xbe][\x81-\xbf]                   |
  )*\z/nx
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

  #
  # kconv
  #
  
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

  def tojis(str)
    ::NKF::nkf('-j', str)
  end
  module_function :tojis

  def toeuc(str)
    ::NKF::nkf('-e', str)
  end
  module_function :toeuc

  def tosjis(str)
    ::NKF::nkf('-s', str)
  end
  module_function :tosjis

  def toutf8(str)
    ::NKF::nkf('-w', str)
  end
  module_function :toutf8

  def toutf16(str)
    ::NKF::nkf('-w16', str)
  end
  module_function :toutf16

  #
  # guess
  #

  def guess(str)
    ::NKF::guess(str)
  end
  module_function :guess

  def guess_old(str)
    ::NKF::guess1(str)
  end
  module_function :guess_old

  #
  # isEncoding
  #

  def iseuc(str)
    RegexpEucjp.match( str )
  end
  module_function :iseuc

  def issjis(str)
    RegexpShiftjis.match( str )
  end
  module_function :issjis

  def isutf8(str)
    RegexpUtf8.match( str )
  end
  module_function :isutf8

end

class String
  def kconv(out_code, in_code=Kconv::AUTO)
    Kconv::kconv(self, out_code, in_code)
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
  
  # is Encoding
  def iseuc
    Kconv.iseuc( self )
  end

  def issjis
    Kconv.issjis( self )
  end

  def isutf8
    Kconv.isutf8( self )
  end
end
