# ostruct.rb - Python Style Object
#  just assign to create field
#
# s = OpenStruct.new
# s.foo = 25
# p s.foo
# s.bar = 2
# p s.bar
# p s

class OpenStruct
  def initialize(hash=nil)
    @table = {}
    if hash
      for k,v in hash
	@table[k.to_sym] = v
      end
    end
  end

  def method_missing(mid, *args)
    mname = mid.id2name
    len = args.length
    if mname =~ /=$/
      if len != 1
	raise ArgumentError, "wrong # of arguments (#{len} for 1)", caller(1)
      end
      mname.chop!
      @table[mname.intern] = args[0]
    elsif len == 0
      @table[mid]
    else
      raise NoMethodError, "undefined method `#{mname}' for #{self}", caller(1)
    end
  end

  def delete_field(name)
    @table.delete name.to_sym
  end

  def inspect
    str = "<#{self.class}"
    for k,v in @table
      str << " #{k}=#{v.inspect}"
    end
    str << ">"
  end
end
