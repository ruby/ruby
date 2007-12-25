class Object
  def method_missing m, *a, &b
    r = /^#{m}/
    t = (methods + private_methods).sort.find{|e|r=~e}
    t ? __send__(t, *a, &b) : super
  end
end
