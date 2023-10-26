require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "main#public" do
  after :each do
    Object.send(:private, :main_private_method)
    Object.send(:private, :main_private_method2)
  end

  context "when single argument is passed and it is not an array" do
    it "sets the visibility of the given methods to public" do
      eval "public :main_private_method", TOPLEVEL_BINDING
      Object.should_not have_private_method(:main_private_method)
    end
  end

  context "when multiple arguments are passed" do
    it "sets the visibility of the given methods to public" do
      eval "public :main_private_method, :main_private_method2", TOPLEVEL_BINDING
      Object.should_not have_private_method(:main_private_method)
      Object.should_not have_private_method(:main_private_method2)
    end
  end

  context "when single argument is passed and is an array" do
    it "sets the visibility of the given methods to public" do
      eval "public [:main_private_method, :main_private_method2]", TOPLEVEL_BINDING
      Object.should_not have_private_method(:main_private_method)
      Object.should_not have_private_method(:main_private_method2)
    end
  end

  ruby_version_is ''...'3.1' do
    it "returns Object" do
      eval("public :main_private_method", TOPLEVEL_BINDING).should equal(Object)
    end
  end

  ruby_version_is '3.1' do
    it "returns argument" do
      eval("public :main_private_method", TOPLEVEL_BINDING).should equal(:main_private_method)
    end
  end


  it "raises a NameError when given an undefined name" do
    -> do
      eval "public :main_undefined_method", TOPLEVEL_BINDING
    end.should raise_error(NameError)
  end
end
