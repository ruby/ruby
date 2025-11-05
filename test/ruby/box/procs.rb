class String
  FOO = "foo"
  def yay
    "yay"
  end
end

module ProcLookupTestA
  module B
    VALUE = 222
  end
end

module ProcInNS
  def self.make_proc_from_block(&b)
    b
  end

  def self.call_proc(proc_arg)
    proc_arg.call
  end

  def self.make_str_proc(type)
    case type
    when :proc_new then Proc.new { String.new.yay }
    when :proc_f   then proc { String.new.yay }
    when :lambda_f then lambda { String.new.yay }
    when :lambda_l then ->(){ String.new.yay }
    when :block    then make_proc_from_block { String.new.yay }
    else
      raise "invalid type :#{type}"
    end
  end

  def self.make_const_proc(type)
    case type
    when :proc_new then Proc.new { ProcLookupTestA::B::VALUE }
    when :proc_f   then proc { ProcLookupTestA::B::VALUE }
    when :lambda_f then lambda { ProcLookupTestA::B::VALUE }
    when :lambda_l then ->(){ ProcLookupTestA::B::VALUE }
    when :block    then make_proc_from_block { ProcLookupTestA::B::VALUE }
    else
      raise "invalid type :#{type}"
    end
  end

  def self.make_str_const_proc(type)
    case type
    when :proc_new then Proc.new { String::FOO }
    when :proc_f   then proc { String::FOO }
    when :lambda_f then lambda { String::FOO }
    when :lambda_l then ->(){ String::FOO }
    when :block    then make_proc_from_block { String::FOO }
    else
      raise "invalid type :#{type}"
    end
  end

  CONST_PROC_NEW = Proc.new { [String.new.yay, String::FOO, ProcLookupTestA::B::VALUE.to_s].join(',') }
  CONST_PROC_F   = proc { [String.new.yay, String::FOO, ProcLookupTestA::B::VALUE.to_s].join(',') }
  CONST_LAMBDA_F = lambda { [String.new.yay, String::FOO, ProcLookupTestA::B::VALUE.to_s].join(',') }
  CONST_LAMBDA_L = ->() { [String.new.yay, String::FOO, ProcLookupTestA::B::VALUE.to_s].join(',') }
  CONST_BLOCK    = make_proc_from_block { [String.new.yay, String::FOO, ProcLookupTestA::B::VALUE.to_s].join(',') }
end
