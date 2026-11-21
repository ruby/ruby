require_relative '../../spec_helper'

ruby_version_is "4.0" do
  eval <<-RUBY, binding, __FILE__, __LINE__ + 1 # use eval to avoid warnings on Ruby 3.3
  describe 'Binding#implicit_parameters' do
    it 'returns an Array' do
      binding.implicit_parameters.should.is_a?(Array)
    end

    it 'includes "it" parameter when defined in the current scope' do
      a = it
      binding.implicit_parameters.should == [:it]
    end

    it 'includes numbered parameters when defined in the current scope' do
      a = _1
      binding.implicit_parameters.should == [:_1]
    end

    it 'includes all the numbered parameter names up to the maximum referenced one' do
      proc { _3; binding.implicit_parameters }.call(:a, :b, :c, :d).should == [:_1, :_2, :_3]
    end

    it 'returns [] when neither "it" parameter nor numbered parameters are defined in the current scope' do
      a = 1
      binding.implicit_parameters.should == []
    end

    it "includes implicit parameters defined after calling binding.implicit_parameters" do
      proc {
        r = binding.implicit_parameters
        a = it
        r
      }.call.should == [:it]

      proc {
        r = binding.implicit_parameters
        a = _1
        r
      }.call.should == [:_1]
    end

    it 'ignores "it" parameter defined in a parent scope' do
      foo = it
      proc { binding.implicit_parameters }.call.should == []
    end

    it 'ignores numbered parameters defined in a parent scope' do
      foo = _1
      proc { binding.implicit_parameters }.call.should == []
    end

    it 'ignores "it" parameter defined in a nested scope' do
      foo = -> { it }
      binding.implicit_parameters.should == []
    end

    it 'ignores numbered parameters defined in a nested scope' do
      foo = -> { _1 }
      binding.implicit_parameters.should == []
    end
  end
  RUBY
end
