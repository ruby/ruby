require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "main#private" do
  after :each do
    Object.send(:public, :main_public_method)
    Object.send(:public, :main_public_method2)
  end

  context "when single argument is passed and it is not an array" do
    it "sets the visibility of the given methods to private" do
      eval "private :main_public_method", TOPLEVEL_BINDING
      Object.should have_private_method(:main_public_method)
    end
  end

  context "when multiple arguments are passed" do
    it "sets the visibility of the given methods to private" do
      eval "private :main_public_method, :main_public_method2", TOPLEVEL_BINDING
      Object.should have_private_method(:main_public_method)
      Object.should have_private_method(:main_public_method2)
    end
  end

  ruby_version_is "3.0" do
    context "when single argument is passed and is an array" do
      it "sets the visibility of the given methods to private" do
        eval "private [:main_public_method, :main_public_method2]", TOPLEVEL_BINDING
        Object.should have_private_method(:main_public_method)
        Object.should have_private_method(:main_public_method2)
      end
    end
  end

  it "returns Object" do
    eval("private :main_public_method", TOPLEVEL_BINDING).should equal(Object)
  end

  it "raises a NameError when at least one of given method names is undefined" do
    -> do
      eval "private :main_public_method, :main_undefined_method", TOPLEVEL_BINDING
    end.should raise_error(NameError)
  end
end
