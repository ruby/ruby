require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "4.0" do
  eval <<-RUBY, binding, __FILE__, __LINE__ + 1 # use eval to avoid warnings on Ruby 3.3
  describe 'Binding#implicit_parameter_get' do
    it 'reads a numbered parameter value when it exists' do
      -> { _1; binding.implicit_parameter_get(:_1) }.call(:a).should == :a
      -> { r = binding.implicit_parameter_get(:_1); _1; r }.call(:a).should == :a
    end

    it 'reads any numbered parameter value up to the maximum referenced one' do
      proc {
        _3
        [
          binding.implicit_parameter_get(:_1),
          binding.implicit_parameter_get(:_2),
          binding.implicit_parameter_get(:_3)
        ]
      }.call(:a, :b, :c, :d).should == [:a, :b, :c]
    end

    it 'reads "it" parameter value when it exists' do
      -> { it; binding.implicit_parameter_get(:it) }.call(:a).should == :a
      -> { r = binding.implicit_parameter_get(:it); it; r }.call(:a).should == :a
    end

    it 'raises a NameError for not existing numbered parameter' do
      proc { binding.implicit_parameter_get(:_1) }.should.raise(NameError, /implicit parameter '_1' is not defined for/)
    end

    it 'raises a NameError for not existing "it" parameter' do
      proc { binding.implicit_parameter_get(:it) }.should.raise(NameError, /implicit parameter 'it' is not defined for/)
    end

    it 'raises a NameError when a numbered parameter is defined in a parent scope' do
      proc {
        foo = _1
        proc { binding.implicit_parameter_get(:_1) }.call
      }.should.raise(NameError, /implicit parameter '_1' is not defined for/)
    end

    it 'raises a NameError when "it" parameter is defined in a parent scope' do
      proc {
        foo = it
        proc { binding.implicit_parameter_get(:it) }.call
      }.should.raise(NameError, /implicit parameter 'it' is not defined for/)
    end

    it 'raises a NameError when a numbered parameter is defined in a nested scope' do
      proc {
        foo = -> { _1 }
        binding.implicit_parameter_get(:_1)
      }.should.raise(NameError, /implicit parameter '_1' is not defined for/)
    end

    it 'raises a NameError when "it" parameter is defined in a nested scope' do
      proc {
        foo = -> { it }
        binding.implicit_parameter_get(:it)
      }.should.raise(NameError, /implicit parameter 'it' is not defined for/)
    end

    it 'allows usage of a String as a numbered parameter name' do
      -> { _1; binding.implicit_parameter_get('_1') }.call(:a).should == :a
    end

    it 'allows usage of a String as "it" parameter name' do
      -> { it; binding.implicit_parameter_get('it') }.call(:a).should == :a
    end

    it 'allows usage of an object responding to #to_str as the variable name' do
      name = mock(:obj)
      name.stub!(:to_str).and_return('_1')

      -> { _1; binding.implicit_parameter_get(name) }.call(:a).should == :a
    end

    it 'raises a NameError when given neither a numbered parameter nor "it" parameter' do
      -> { binding.implicit_parameter_get(:a) }.should.raise(NameError, "'a' is not an implicit parameter")
    end

    it 'raises a TypeError when given non-String/Symbol as the variable name' do
      -> {
        binding.implicit_parameter_get(1)
      }.should.raise(TypeError, '1 is not a symbol nor a string')
    end
  end
  RUBY
end
