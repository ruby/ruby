class Object
  def method_missing m, *a, &b
    r = /^#{m}/
    t = (methods + private_methods).sort.find{|e|r=~e}
    t ? __send__(t, *a, &b) : super
  end

  def h(a='H', b='w', c='!')
    puts "#{a}ello, #{b}orld#{c}"
  end
end

class Integer
  def each(&b)
    times &b
  end

  include Enumerable
end
