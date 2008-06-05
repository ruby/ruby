begin
  require 'iconv'
rescue LoadError
else
  require 'test/unit'
end

module TestIconv
  if defined?(::Iconv)
    def self.testcase(name, &block)
      const_set(name, klass = Class.new(::Test::Unit::TestCase))
      klass.name
      klass.__send__(:include, self)
      klass.class_eval(&block)
    end
  else
    def self.testcase(name)
    end
  end
end

module TestIconv
  if defined?(::Encoding) and String.method_defined?(:force_encoding)
    def self.encode(str, enc)
      str.force_encoding(enc)
    end
  else
    def self.encode(str, enc)
      str
    end
  end

  ASCII = "ascii"
  EUCJ_STR = encode("\xa4\xa2\xa4\xa4\xa4\xa6\xa4\xa8\xa4\xaa", "EUC-JP").freeze
  SJIS_STR = encode("\x82\xa0\x82\xa2\x82\xa4\x82\xa6\x82\xa8", "Shift_JIS").freeze
end if defined?(::Iconv)
