SCRIPT_LINES__={}

class Object
  def method_missing m, *a, &b
    r = /^#{m}/
    t = (methods + private_methods).sort.find{|e|r=~e}
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

  def quine(src = $0)
    SCRIPT_LINES__[src].join
  end

  alias say puts
end

class Integer
  alias each times
  include Enumerable
end
