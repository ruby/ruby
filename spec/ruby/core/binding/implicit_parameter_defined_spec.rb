require_relative '../../spec_helper'

ruby_version_is "4.0" do
  eval <<-RUBY, binding, __FILE__, __LINE__ + 1 # use eval to avoid warnings on Ruby 3.3
  describe 'Binding#implicit_parameter_defined?' do
    it 'returns false when a numbered parameters or "it" does not exist' do
      binding.implicit_parameter_defined?(:it).should == false
      binding.implicit_parameter_defined?(:_1).should == false
    end

    it 'returns true when a numbered parameter exists' do
      proc { _1; binding.implicit_parameter_defined?(:_1) }.call.should == true
      proc { r = binding.implicit_parameter_defined?(:_1); _1; r }.call.should == true
    end

    it 'returns true for all numbered parameters up to the maximum referenced one' do
      _3
      binding.implicit_parameter_defined?(:_1).should == true
      binding.implicit_parameter_defined?(:_2).should == true
      binding.implicit_parameter_defined?(:_3).should == true
      binding.implicit_parameter_defined?(:_4).should == false
    end

    it 'returns true when "it" parameter exists' do
      proc { it; binding.implicit_parameter_defined?(:it) }.call.should == true
      proc { r = binding.implicit_parameter_defined?(:it); it; r }.call.should == true
    end

    it 'returns false when a numbered parameter is defined in a parent scope' do
      foo = _1
      -> {
        binding.implicit_parameter_defined?(:_1)
      }.call.should == false
    end

    it 'returns false when "it" parameter is defined in a parent scope' do
      foo = it
      -> {
        binding.implicit_parameter_defined?(:it)
      }.call.should == false
    end

    it 'returns false when a numbered parameter is defined in a nested scope' do
      foo = -> { _1 }
      binding.implicit_parameter_defined?(:_1).should == false
    end

    it 'returns false when "it" parameter is defined in a nested scope' do
      foo = -> { it }
      binding.implicit_parameter_defined?(:it).should == false
    end

    it 'allows usage of a String as a numbered parameter name' do
      _1
      binding.implicit_parameter_defined?('_1').should == true
    end

    it 'allows usage of a String as "it" parameter name' do
      it
      binding.implicit_parameter_defined?('it').should == true
    end

    it 'allows usage of an object responding to #to_str as the variable name' do
      foo  = _1
      name = mock(:obj)
      name.stub!(:to_str).and_return('_1')

      binding.implicit_parameter_defined?(name).should == true
    end

    it 'raises a NameError when given neither a numbered parameter nor "it" parameter' do
      -> {
        binding.implicit_parameter_defined?(:a)
      }.should.raise(NameError, "'a' is not an implicit parameter")
    end

    it 'raises a TypeError when given non-String/Symbol as the variable name' do
      -> {
        binding.implicit_parameter_defined?(1)
      }.should.raise(TypeError, '1 is not a symbol nor a string')
    end
  end
  RUBY
end
