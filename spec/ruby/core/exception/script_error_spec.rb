require_relative '../../spec_helper'

describe "ScriptError" do
   it "is a superclass of LoadError" do
     ScriptError.should be_ancestor_of(LoadError)
   end

   it "is a superclass of NotImplementedError" do
     ScriptError.should be_ancestor_of(NotImplementedError)
   end

   it "is a superclass of SyntaxError" do
     ScriptError.should be_ancestor_of(SyntaxError)
   end
end
