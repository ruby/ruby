require 'nkf'

module Kconv
  AUTO = NKF::AUTO
  JIS = NKF::JIS
  EUC = NKF::EUC
  SJIS = NKF::SJIS
  BINARY = NKF::BINARY
  NOCONV = NKF::NOCONV
  UNKNOWN = NKF::UNKNOWN
  def kconv(str, out_code, in_code = AUTO)
    opt = '-'
    case in_code
    when NKF::JIS
      opt << 'J'
    when NKF::EUC
      opt << 'E'
    when NKF::SJIS
      opt << 'S'
    end

    case out_code
    when NKF::JIS
      opt << 'j'
    when NKF::EUC
      opt << 'e'
    when NKF::SJIS
      opt << 's'
    when NKF::NOCONV
      return str
    end

    opt = '' if opt == '-'

    NKF::nkf(opt, str)
  end
  module_function :kconv

  def tojis(str)
    NKF::nkf('-j', str)
  end
  module_function :tojis

  def toeuc(str)
    NKF::nkf('-e', str)
  end
  module_function :toeuc

  def tosjis(str)
    NKF::nkf('-s', str)
  end
  module_function :tosjis

  def guess(str)
    NKF::guess(str)
  end
  module_function :guess
end

class String
  def kconv(out_code, in_code=Kconv::AUTO)
    Kconv::kconv(self, out_code, in_code)
  end
  def tojis
    NKF::nkf('-j', self)
  end
  def toeuc
    NKF::nkf('-e', self)
  end
  def tosjis
    NKF::nkf('-s', self)
  end
end
