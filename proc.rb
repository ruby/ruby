class Proc
  #
  # call-seq:
  #    prc.parameters(lambda: nil)  -> array
  #
  # Returns the parameter information of this proc.  If the lambda
  # keyword is provided and not nil, treats the proc as a lambda if
  # true and as a non-lambda if false.
  #
  #    prc = proc{|x, y=42, *other|}
  #    prc.parameters  #=> [[:opt, :x], [:opt, :y], [:rest, :other]]
  #    prc = lambda{|x, y=42, *other|}
  #    prc.parameters  #=> [[:req, :x], [:opt, :y], [:rest, :other]]
  #    prc = proc{|x, y=42, *other|}
  #    prc.parameters(lambda: true)  #=> [[:req, :x], [:opt, :y], [:rest, :other]]
  #    prc = lambda{|x, y=42, *other|}
  #    prc.parameters(lambda: false) #=> [[:opt, :x], [:opt, :y], [:rest, :other]]
  #
  def parameters(lambda: nil)
    Primitive.rb_proc_parameters(Primitive.arg!(:lambda))
  end
end
