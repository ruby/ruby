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
	@table[k] = v
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
      @table[mname] = args[0]
    elsif args.length == 0
      @table[mname]
    else
      raise NameError, "undefined method `#{mname}'", caller(1)
    end
  end
  
  def delete_field(name)
    if name.type == Fixnum
      name = name.id2name
    end
    @table.delete name
  end

  def inspect
    str = "<#{self.type}"
    for k,v in @table
      str += " "
      str += k.to_s
      str += "="
      str += v.inspect
    end
    str += ">"
    str
  end
end
