SCRIPT_LINES__={}

class Object
  @@golf_hash = {}
  def method_missing m, *a, &b
    t = @@golf_hash.fetch(k = [m,self.class]) do
      r = /^#{m.to_s.gsub(/(?<=\w)(?=_)/, '\w*?')}/
      @@golf_hash[k] = (methods + private_methods).sort.find{|e|r=~e}
    end
    t ? __send__(t, *a, &b) : super
  end

  def self.const_missing c
    r = /^#{c}/
    t = constants.sort.find{|e|r=~e} and return const_get(t)
    raise NameError, "uninitialized constant #{c}", caller(1)
  end

  def h(a='H', b='w', c='!')
    puts "#{a}ello, #{b}orld#{c}"
  end

  alias say puts
end

class Array
  alias to_s join
end

class FalseClass
  def to_s
    ""
  end
end

class Integer
  alias each times
  include Enumerable
end

class String
  alias / split
end
