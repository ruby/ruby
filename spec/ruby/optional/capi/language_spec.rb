require_relative 'spec_helper'

load_extension("language")

describe "C language construct" do
  before :each do
    @s = CApiLanguageSpecs.new
  end

  describe "switch (VALUE)" do
    it "works for Qtrue" do
      @s.switch(true).should == :true
    end

    it "works for Qfalse" do
      @s.switch(false).should == :false
    end

    it "works for Qnil" do
      @s.switch(nil).should == :nil
    end

    it "works for Qundef" do
      @s.switch(:undef).should == :undef
    end

    it "works for the default case" do
      @s.switch(Object.new).should == :default
    end
  end

  describe "local variable assignment with the same name as a global" do
    it "works for rb_mProcess" do
      @s.global_local_var.should.equal?(Process)
    end
  end
end
