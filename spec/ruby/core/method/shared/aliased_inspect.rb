describe :method_to_s_aliased, shared: true do
  # @object converts a bound Method to either a Method (identity) or an
  # UnboundMethod (-> meth { meth.unbind }), so these expectations cover both
  # Method#to_s/#inspect and UnboundMethod#to_s/#inspect.

  it "shows the original name in parentheses for an aliased method" do
    klass = Class.new do
      def original_method; end
      alias_method :renamed_method, :original_method
    end
    @object.call(klass.new.method(:renamed_method)).send(@method).should.include? '#renamed_method(original_method)'
  end

  it "shows the source UnboundMethod's name in parentheses for a define_method'd method" do
    klass = Class.new { define_method(:renamed_is_a?, ::Kernel.instance_method(:is_a?)) }
    @object.call(klass.new.method(:renamed_is_a?)).send(@method).should.include? '#renamed_is_a?(is_a?)'
  end

  it "does not annotate a directly looked-up Kernel method with a shared internal name" do
    @object.call(Object.new.method(:is_a?)).send(@method).should_not.include? '(kind_of?)'
    @object.call(Object.new.method(:kind_of?)).send(@method).should_not.include? '(is_a?)'
  end

  it "shows the source name when aliasing a define_method'd Kernel method" do
    klass = Class.new do
      define_method(:my_is_a?, ::Kernel.instance_method(:is_a?))
      alias_method :renamed_is_a?, :my_is_a?
    end
    @object.call(klass.new.method(:renamed_is_a?)).send(@method).should.include? '#renamed_is_a?(is_a?)'
  end
end
