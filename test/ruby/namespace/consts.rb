class String
  STR_CONST1 = 111
  STR_CONST2 = 222
  STR_CONST3 = 333
end

class String
  STR_CONST1 = 112

  def self.set0(val)
    const_set(:STR_CONST0, val)
  end

  def self.remove0
    remove_const(:STR_CONST0)
  end

  def refer0
    STR_CONST0
  end

  def refer1
    STR_CONST1
  end

  def refer2
    STR_CONST2
  end

  def refer3
    STR_CONST3
  end
end

module ForConsts
  CONST1 = 111
end

TOP_CONST = 10

module ForConsts
  CONST1 = 112
  CONST2 = 222
  CONST3 = 333

  def self.refer_all
    ForConsts::CONST1
    ForConsts::CONST2
    ForConsts::CONST3
    String::STR_CONST1
    String::STR_CONST2
    String::STR_CONST3
  end

  def self.refer1
    CONST1
  end

  def self.get1
    const_get(:CONST1)
  end

  def self.refer2
    CONST2
  end

  def self.get2
    const_get(:CONST2)
  end

  def self.refer3
    CONST3
  end

  def self.get3
    const_get(:CONST3)
  end

  def self.refer_top_const
    TOP_CONST
  end

  # for String
  class Proxy
    def call_str_refer0
      String.new.refer0
    end

    def call_str_get0
      String.const_get(:STR_CONST0)
    end

    def call_str_set0(val)
      String.set0(val)
    end

    def call_str_remove0
      String.remove0
    end

    def call_str_refer1
      String.new.refer1
    end

    def call_str_get1
      String.const_get(:STR_CONST1)
    end

    String::STR_CONST2 = 223

    def call_str_refer2
      String.new.refer2
    end

    def call_str_get2
      String.const_get(:STR_CONST2)
    end

    def call_str_set3
      String.const_set(:STR_CONST3, 334)
    end

    def call_str_refer3
      String.new.refer3
    end

    def call_str_get3
      String.const_get(:STR_CONST3)
    end

    # for Integer
    Integer::INT_CONST1 = 1

    def refer_int_const1
      Integer::INT_CONST1
    end
  end
end

# should not raise errors
ForConsts.refer_all
String::STR_CONST1
Integer::INT_CONST1

# If we execute this sentence once, the constant value will be cached on ISeq inline constant cache.
# And it changes the behavior of ForConsts.refer_consts_directly called from global.
# ForConsts.refer_consts_directly # should not raise errors too
