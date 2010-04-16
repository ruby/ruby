# XSD4R - Charset handling library.
# Copyright (C) 2001, 2003, 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


module XSD


module Charset
  @internal_encoding = $KCODE

  class XSDError < StandardError; end
  class CharsetError < XSDError; end
  class UnknownCharsetError < CharsetError; end
  class CharsetConversionError < CharsetError; end

public

  ###
  ## Maps
  #
  EncodingConvertMap = {}
  def Charset.init
    EncodingConvertMap[['UTF8', 'X_ISO8859_1']] =
      Proc.new { |str| str.unpack('U*').pack('C*') }
    EncodingConvertMap[['X_ISO8859_1', 'UTF8']] =
      Proc.new { |str| str.unpack('C*').pack('U*') }
    begin
      require 'xsd/iconvcharset'
      @internal_encoding = 'UTF8'
      sjtag = (/(mswin|bccwin|mingw|cygwin|emx)/ =~ RUBY_PLATFORM) ? 'cp932' :
        'shift_jis'
      EncodingConvertMap[['UTF8', 'EUC' ]] =
        Proc.new { |str| IconvCharset.safe_iconv("euc-jp", "utf-8", str) }
      EncodingConvertMap[['EUC' , 'UTF8']] =
        Proc.new { |str| IconvCharset.safe_iconv("utf-8", "euc-jp", str) }
      EncodingConvertMap[['EUC' , 'SJIS']] =
        Proc.new { |str| IconvCharset.safe_iconv(sjtag, "euc-jp", str) }
      EncodingConvertMap[['UTF8', 'SJIS']] =
        Proc.new { |str| IconvCharset.safe_iconv(sjtag, "utf-8", str) }
      EncodingConvertMap[['SJIS', 'UTF8']] =
        Proc.new { |str| IconvCharset.safe_iconv("utf-8", sjtag, str) }
      EncodingConvertMap[['SJIS', 'EUC' ]] =
        Proc.new { |str| IconvCharset.safe_iconv("euc-jp", sjtag, str) }
    rescue LoadError
      begin
       	require 'nkf'
	EncodingConvertMap[['EUC' , 'SJIS']] =
          Proc.new { |str| NKF.nkf('-sXm0', str) }
	EncodingConvertMap[['SJIS', 'EUC' ]] =
          Proc.new { |str| NKF.nkf('-eXm0', str) }
      rescue LoadError
      end

      begin
	require 'uconv'
	@internal_encoding = 'UTF8'
	EncodingConvertMap[['UTF8', 'EUC' ]] = Uconv.method(:u8toeuc)
	EncodingConvertMap[['UTF8', 'SJIS']] = Uconv.method(:u8tosjis)
	EncodingConvertMap[['EUC' , 'UTF8']] = Uconv.method(:euctou8)
	EncodingConvertMap[['SJIS', 'UTF8']] = Uconv.method(:sjistou8)
      rescue LoadError
      end
    end
  end
  self.init

  CharsetMap = {
    'NONE' => 'us-ascii',
    'EUC' => 'euc-jp',
    'SJIS' => 'shift_jis',
    'UTF8' => 'utf-8',
    'X_ISO_8859_1' => 'iso-8859-1',
    'X_UNKNOWN' => nil,
  }


  ###
  ## handlers
  #
  def Charset.encoding
    @internal_encoding
  end

  def Charset.encoding=(encoding)
    warn("xsd charset is set to #{encoding}") if $DEBUG
    @internal_encoding = encoding
  end

  def Charset.xml_encoding_label
    charset_label(@internal_encoding)
  end

  def Charset.encoding_to_xml(str, charset)
    encoding_conv(str, @internal_encoding, charset_str(charset))
  end

  def Charset.encoding_from_xml(str, charset)
    encoding_conv(str, charset_str(charset), @internal_encoding)
  end

  def Charset.encoding_conv(str, enc_from, enc_to)
    if enc_from == enc_to or enc_from == 'NONE' or enc_to == 'NONE'
      str
    elsif converter = EncodingConvertMap[[enc_from, enc_to]]
      converter.call(str)
    else
      raise CharsetConversionError.new(
	"Converter not found: #{enc_from} -> #{enc_to}")
    end
  end

  def Charset.charset_label(encoding)
    CharsetMap[encoding.upcase]
  end

  def Charset.charset_str(label)
    if CharsetMap.respond_to?(:key)
      CharsetMap.key(label.downcase) || 'X_UNKNOWN'
    else
      CharsetMap.index(label.downcase) || 'X_UNKNOWN'
    end
  end

  # us_ascii = '[\x00-\x7F]'
  us_ascii = '[\x9\xa\xd\x20-\x7F]'	# XML 1.0 restricted.
  USASCIIRegexp = Regexp.new("\\A#{us_ascii}*\\z", nil, "NONE")

  twobytes_euc = '(?:[\x8E\xA1-\xFE][\xA1-\xFE])'
  threebytes_euc = '(?:\x8F[\xA1-\xFE][\xA1-\xFE])'
  character_euc = "(?:#{us_ascii}|#{twobytes_euc}|#{threebytes_euc})"
  EUCRegexp = Regexp.new("\\A#{character_euc}*\\z", nil, "NONE")

  # onebyte_sjis = '[\x00-\x7F\xA1-\xDF]'
  onebyte_sjis = '[\x9\xa\xd\x20-\x7F\xA1-\xDF]'	# XML 1.0 restricted.
  twobytes_sjis = '(?:[\x81-\x9F\xE0-\xFC][\x40-\x7E\x80-\xFC])'
  character_sjis = "(?:#{onebyte_sjis}|#{twobytes_sjis})"
  SJISRegexp = Regexp.new("\\A#{character_sjis}*\\z", nil, "NONE")

  # 0xxxxxxx
  # 110yyyyy 10xxxxxx
  twobytes_utf8 = '(?:[\xC0-\xDF][\x80-\xBF])'
  # 1110zzzz 10yyyyyy 10xxxxxx
  threebytes_utf8 = '(?:[\xE0-\xEF][\x80-\xBF][\x80-\xBF])'
  # 11110uuu 10uuuzzz 10yyyyyy 10xxxxxx
  fourbytes_utf8 = '(?:[\xF0-\xF7][\x80-\xBF][\x80-\xBF][\x80-\xBF])'
  character_utf8 =
    "(?:#{us_ascii}|#{twobytes_utf8}|#{threebytes_utf8}|#{fourbytes_utf8})"
  UTF8Regexp = Regexp.new("\\A#{character_utf8}*\\z", nil, "NONE")

  def Charset.is_us_ascii(str)
    USASCIIRegexp =~ str
  end

  def Charset.is_utf8(str)
    UTF8Regexp =~ str
  end

  def Charset.is_euc(str)
    EUCRegexp =~ str
  end

  def Charset.is_sjis(str)
    SJISRegexp =~ str
  end

  def Charset.is_ces(str, code = $KCODE)
    case code
    when 'NONE'
      is_us_ascii(str)
    when 'UTF8'
      is_utf8(str)
    when 'EUC'
      is_euc(str)
    when 'SJIS'
      is_sjis(str)
    else
      raise UnknownCharsetError.new("Unknown charset: #{code}")
    end
  end
end


end
