require_relative '../spec_helper'
require_relative 'fixtures/defined'

describe "The defined? keyword for literals" do
  it "returns 'self' for self" do
    ret = defined?(self)
    ret.should == "self"
    ret.frozen?.should == true
  end

  it "returns 'nil' for nil" do
    ret = defined?(nil)
    ret.should == "nil"
    ret.frozen?.should == true
  end

  it "returns 'true' for true" do
    ret = defined?(true)
    ret.should == "true"
    ret.frozen?.should == true
  end

  it "returns 'false' for false" do
    ret = defined?(false)
    ret.should == "false"
    ret.frozen?.should == true
  end

  describe "for a literal Array" do

    it "returns 'expression' if each element is defined" do
      ret = defined?([Object, Array])
      ret.should == "expression"
      ret.frozen?.should == true
    end

    it "returns nil if one element is not defined" do
      ret = defined?([NonExistentConstant, Array])
      ret.should == nil
    end

    it "returns nil if all elements are not defined" do
      ret = defined?([NonExistentConstant, AnotherNonExistentConstant])
      ret.should == nil
    end

  end
end

describe "The defined? keyword when called with a method name" do
  before :each do
    ScratchPad.clear
  end

  it "does not call the method" do
    defined?(DefinedSpecs.side_effects).should == "method"
    ScratchPad.recorded.should != :defined_specs_side_effects
  end

  it "does not execute the arguments" do
    defined?(DefinedSpecs.any_args(DefinedSpecs.side_effects)).should == "method"
    ScratchPad.recorded.should != :defined_specs_side_effects
  end

  describe "without a receiver" do
    it "returns 'method' if the method is defined" do
      ret = defined?(puts)
      ret.should == "method"
      ret.frozen?.should == true
    end

    it "returns nil if the method is not defined" do
      defined?(defined_specs_undefined_method).should be_nil
    end

    it "returns 'method' if the method is defined and private" do
      obj = DefinedSpecs::Basic.new
      obj.private_method_defined.should == "method"
    end

    it "returns 'method' if the predicate method is defined and private" do
      obj = DefinedSpecs::Basic.new
      obj.private_predicate_defined.should == "method"
    end
  end

  describe "having a module as receiver" do
    it "returns 'method' if the method is defined" do
      defined?(Kernel.puts).should == "method"
    end

    it "returns nil if the method is private" do
      defined?(Object.print).should be_nil
    end

    it "returns nil if the method is protected" do
      defined?(DefinedSpecs::Basic.new.protected_method).should be_nil
    end

    it "returns nil if the method is not defined" do
      defined?(Kernel.defined_specs_undefined_method).should be_nil
    end

    it "returns nil if the class is not defined" do
      defined?(DefinedSpecsUndefined.puts).should be_nil
    end

    it "returns nil if the subclass is not defined" do
      defined?(DefinedSpecs::Undefined.puts).should be_nil
    end
  end

  describe "having a local variable as receiver" do
    it "returns 'method' if the method is defined" do
      obj = DefinedSpecs::Basic.new
      defined?(obj.a_defined_method).should == "method"
    end

    it "returns 'method' for []=" do
      a = []
      defined?(a[0] = 1).should == "method"
    end

    it "returns nil if the method is not defined" do
      obj = DefinedSpecs::Basic.new
      defined?(obj.an_undefined_method).should be_nil
    end

    it "returns nil if the variable does not exist" do
      defined?(nonexistent_local_variable.some_method).should be_nil
    end

    it "calls #respond_to_missing?" do
      obj = mock("respond_to_missing object")
      obj.should_receive(:respond_to_missing?).and_return(true)
      defined?(obj.something_undefined).should == "method"
    end
  end

  describe "having an instance variable as receiver" do
    it "returns 'method' if the method is defined" do
      @defined_specs_obj = DefinedSpecs::Basic.new
      defined?(@defined_specs_obj.a_defined_method).should == "method"
    end

    it "returns nil if the method is not defined" do
      @defined_specs_obj = DefinedSpecs::Basic.new
      defined?(@defined_specs_obj.an_undefined_method).should be_nil
    end

    it "returns nil if the variable does not exist" do
      defined?(@nonexistent_instance_variable.some_method).should be_nil
    end
  end

  describe "having a global variable as receiver" do
    it "returns 'method' if the method is defined" do
      $defined_specs_obj = DefinedSpecs::Basic.new
      defined?($defined_specs_obj.a_defined_method).should == "method"
    end

    it "returns nil if the method is not defined" do
      $defined_specs_obj = DefinedSpecs::Basic.new
      defined?($defined_specs_obj.an_undefined_method).should be_nil
    end

    it "returns nil if the variable does not exist" do
      defined?($nonexistent_global_variable.some_method).should be_nil
    end
  end

  describe "having a method call as a receiver" do
    it "returns nil if evaluating the receiver raises an exception" do
      defined?(DefinedSpecs.exception_method / 2).should be_nil
      ScratchPad.recorded.should == :defined_specs_exception
    end

    it "returns nil if the method is not defined on the object the receiver returns" do
      defined?(DefinedSpecs.side_effects / 2).should be_nil
      ScratchPad.recorded.should == :defined_specs_side_effects
    end

    it "returns 'method' if the method is defined on the object the receiver returns" do
      defined?(DefinedSpecs.fixnum_method / 2).should == "method"
      ScratchPad.recorded.should == :defined_specs_fixnum_method
    end
  end

  describe "having a throw in the receiver" do
    it "escapes defined? and performs the throw semantics as normal" do
      defined_returned = false
      catch(:out) {
        # NOTE: defined? behaves differently if it is called in a void context, see below
        defined?(throw(:out, 42).foo).should == :unreachable
        defined_returned = true
      }.should == 42
      defined_returned.should == false
    end
  end

  describe "in a void context" do
    it "does not execute the receiver" do
      ScratchPad.record :not_executed
      defined?(DefinedSpecs.side_effects / 2)
      ScratchPad.recorded.should == :not_executed
    end

    it "warns about the void context when parsing it" do
      -> {
        eval "defined?(DefinedSpecs.side_effects / 2); 42"
      }.should complain(/warning: possibly useless use of defined\? in void context/, verbose: true)
    end
  end
end

describe "The defined? keyword for an expression" do
  before :each do
    ScratchPad.clear
  end

  it "returns 'assignment' for assigning a local variable" do
    ret = defined?(x = 2)
    ret.should == "assignment"
    ret.frozen?.should == true
  end

  it "returns 'assignment' for assigning an instance variable" do
    defined?(@defined_specs_x = 2).should == "assignment"
  end

  it "returns 'assignment' for assigning a global variable" do
    defined?($defined_specs_x = 2).should == "assignment"
  end

  it "returns 'assignment' for assigning a class variable" do
    defined?(@@defined_specs_x = 2).should == "assignment"
  end

  it "returns 'assignment' for assigning a constant" do
    defined?(A = 2).should == "assignment"
  end

  it "returns 'assignment' for assigning a fully qualified constant" do
    defined?(Object::A = 2).should == "assignment"
  end

  it "returns 'assignment' for assigning multiple variables" do
    defined?((a, b = 1, 2)).should == "assignment"
  end

  it "returns 'assignment' for an expression with '%='" do
    defined?(x %= 2).should == "assignment"
  end

  it "returns 'assignment' for an expression with '/='" do
    defined?(x /= 2).should == "assignment"
  end

  it "returns 'assignment' for an expression with '-='" do
    defined?(x -= 2).should == "assignment"
  end

  it "returns 'assignment' for an expression with '+='" do
    defined?(a += 1).should == "assignment"
    defined?(@a += 1).should == "assignment"
    defined?(@@a += 1).should == "assignment"
    defined?($a += 1).should == "assignment"
    defined?(A += 1).should == "assignment"
    # fully qualified constant check is moved out into a separate test case
    defined?(a.b += 1).should == "assignment"
    defined?(a[:b] += 1).should == "assignment"
  end

  # https://bugs.ruby-lang.org/issues/20111
  ruby_version_is ""..."3.4" do
    it "returns 'expression' for an assigning a fully qualified constant with '+='" do
      defined?(Object::A += 1).should == "expression"
    end
  end

  ruby_version_is "3.4" do
    it "returns 'assignment' for an assigning a fully qualified constant with '+='" do
      defined?(Object::A += 1).should == "assignment"
    end
  end

  it "returns 'assignment' for an expression with '*='" do
    defined?(x *= 2).should == "assignment"
  end

  it "returns 'assignment' for an expression with '|='" do
    defined?(x |= 2).should == "assignment"
  end

  it "returns 'assignment' for an expression with '&='" do
    defined?(x &= 2).should == "assignment"
  end

  it "returns 'assignment' for an expression with '^='" do
    defined?(x ^= 2).should == "assignment"
  end

  it "returns 'assignment' for an expression with '~='" do
    defined?(x = 2).should == "assignment"
  end

  it "returns 'assignment' for an expression with '<<='" do
    defined?(x <<= 2).should == "assignment"
  end

  it "returns 'assignment' for an expression with '>>='" do
    defined?(x >>= 2).should == "assignment"
  end

  context "||=" do
    it "returns 'assignment' for assigning a local variable with '||='" do
      defined?(a ||= true).should == "assignment"
    end

    it "returns 'assignment' for assigning an instance variable with '||='" do
      defined?(@a ||= true).should == "assignment"
    end

    it "returns 'assignment' for assigning a class variable with '||='" do
      defined?(@@a ||= true).should == "assignment"
    end

    it "returns 'assignment' for assigning a global variable with '||='" do
      defined?($a ||= true).should == "assignment"
    end

    it "returns 'assignment' for assigning a constant with '||='" do
      defined?(A ||= true).should == "assignment"
    end

    # https://bugs.ruby-lang.org/issues/20111
    ruby_version_is ""..."3.4" do
      it "returns 'expression' for assigning a fully qualified constant with '||='" do
        defined?(Object::A ||= true).should == "expression"
      end
    end

    ruby_version_is "3.4" do
      it "returns 'assignment' for assigning a fully qualified constant with '||='" do
        defined?(Object::A ||= true).should == "assignment"
      end
    end

    it "returns 'assignment' for assigning an attribute with '||='" do
      defined?(a.b ||= true).should == "assignment"
    end

    it "returns 'assignment' for assigning a referenced element with '||='" do
      defined?(a[:b] ||= true).should == "assignment"
    end
  end

  context "&&=" do
    it "returns 'assignment' for assigning a local variable with '&&='" do
      defined?(a &&= true).should == "assignment"
    end

    it "returns 'assignment' for assigning an instance variable with '&&='" do
      defined?(@a &&= true).should == "assignment"
    end

    it "returns 'assignment' for assigning a class variable with '&&='" do
      defined?(@@a &&= true).should == "assignment"
    end

    it "returns 'assignment' for assigning a global variable with '&&='" do
      defined?($a &&= true).should == "assignment"
    end

    it "returns 'assignment' for assigning a constant with '&&='" do
      defined?(A &&= true).should == "assignment"
    end

    # https://bugs.ruby-lang.org/issues/20111
    ruby_version_is ""..."3.4" do
      it "returns 'expression' for assigning a fully qualified constant with '&&='" do
        defined?(Object::A &&= true).should == "expression"
      end
    end

    ruby_version_is "3.4" do
      it "returns 'assignment' for assigning a fully qualified constant with '&&='" do
        defined?(Object::A &&= true).should == "assignment"
      end
    end

    it "returns 'assignment' for assigning an attribute with '&&='" do
      defined?(a.b &&= true).should == "assignment"
    end

    it "returns 'assignment' for assigning a referenced element with '&&='" do
      defined?(a[:b] &&= true).should == "assignment"
    end
  end

  it "returns 'assignment' for an expression with '**='" do
    defined?(x **= 2).should == "assignment"
  end

  it "returns nil for an expression with == and an undefined method" do
    defined?(defined_specs_undefined_method == 2).should be_nil
  end

  it "returns nil for an expression with != and an undefined method" do
    defined?(defined_specs_undefined_method != 2).should be_nil
  end

  it "returns nil for an expression with !~ and an undefined method" do
    defined?(defined_specs_undefined_method !~ 2).should be_nil
  end

  it "returns 'method' for an expression with '=='" do
    x = 42
    defined?(x == 2).should == "method"
  end

  it "returns 'method' for an expression with '!='" do
    x = 42
    defined?(x != 2).should == "method"
  end

  it "returns 'method' for an expression with '!~'" do
    x = 42
    defined?(x !~ 2).should == "method"
  end

  describe "with logical connectives" do
    it "returns nil for an expression with '!' and an undefined method" do
      defined?(!defined_specs_undefined_method).should be_nil
    end

    it "returns nil for an expression with '!' and an unset class variable" do
      @result = eval("class singleton_class::A; defined?(!@@doesnt_exist) end", binding, __FILE__, __LINE__)
      @result.should be_nil
    end

    it "returns nil for an expression with 'not' and an undefined method" do
      defined?(not defined_specs_undefined_method).should be_nil
    end

    it "returns nil for an expression with 'not' and an unset class variable" do
      @result = eval("class singleton_class::A; defined?(not @@doesnt_exist) end", binding, __FILE__, __LINE__)
      @result.should be_nil
    end

    it "does not propagate an exception raised by a method in a 'not' expression" do
      defined?(not DefinedSpecs.exception_method).should be_nil
      ScratchPad.recorded.should == :defined_specs_exception
    end

    it "returns 'expression' for an expression with '&&/and' and an unset global variable" do
      defined?($defined_specs_undefined_global_variable && true).should == "expression"
      defined?(true && $defined_specs_undefined_global_variable).should == "expression"
      defined?($defined_specs_undefined_global_variable and true).should == "expression"
    end

    it "returns 'expression' for an expression with '&&/and' and an unset instance variable" do
      defined?(@defined_specs_undefined_instance_variable && true).should == "expression"
      defined?(true && @defined_specs_undefined_instance_variable).should == "expression"
      defined?(@defined_specs_undefined_instance_variable and true).should == "expression"
    end

    it "returns 'expression' for an expression '&&/and' regardless of its truth value" do
      defined?(true && false).should == "expression"
      defined?(true and false).should == "expression"
    end

    it "returns 'expression' for an expression with '||/or' and an unset global variable" do
      defined?($defined_specs_undefined_global_variable || true).should == "expression"
      defined?(true || $defined_specs_undefined_global_variable).should == "expression"
      defined?($defined_specs_undefined_global_variable or true).should == "expression"
    end

    it "returns 'expression' for an expression with '||/or' and an unset instance variable" do
      defined?(@defined_specs_undefined_instance_variable || true).should == "expression"
      defined?(true || @defined_specs_undefined_instance_variable).should == "expression"
      defined?(@defined_specs_undefined_instance_variable or true).should == "expression"
    end

    it "returns 'expression' for an expression '||/or' regardless of its truth value" do
      defined?(true || false).should == "expression"
      defined?(true or false).should == "expression"
    end

    it "returns nil for an expression with '!' and an unset global variable" do
      defined?(!$defined_specs_undefined_global_variable).should be_nil
    end

    it "returns nil for an expression with '!' and an unset instance variable" do
      defined?(!@defined_specs_undefined_instance_variable).should be_nil
    end

    it "returns 'method' for a 'not' expression with a method" do
      defined?(not DefinedSpecs.side_effects).should == "method"
    end

    it "calls a method in a 'not' expression and returns 'method'" do
      defined?(not DefinedSpecs.side_effects).should == "method"
      ScratchPad.recorded.should == :defined_specs_side_effects
    end

    it "returns nil for an expression with 'not' and an unset global variable" do
      defined?(not $defined_specs_undefined_global_variable).should be_nil
    end

    it "returns nil for an expression with 'not' and an unset instance variable" do
      defined?(not @defined_specs_undefined_instance_variable).should be_nil
    end

    it "returns 'expression' for an expression with '&&/and' and an undefined method" do
      defined?(defined_specs_undefined_method && true).should == "expression"
      defined?(defined_specs_undefined_method and true).should == "expression"
    end

    it "returns 'expression' for an expression with '&&/and' and an unset class variable" do
      defined?(@@defined_specs_undefined_class_variable && true).should == "expression"
      defined?(@@defined_specs_undefined_class_variable and true).should == "expression"
    end

    it "does not call a method in an '&&' expression and returns 'expression'" do
      defined?(DefinedSpecs.side_effects && true).should == "expression"
      ScratchPad.recorded.should be_nil
    end

    it "does not call a method in an 'and' expression and returns 'expression'" do
      defined?(DefinedSpecs.side_effects and true).should == "expression"
      ScratchPad.recorded.should be_nil
    end

    it "returns 'expression' for an expression with '||/or' and an undefined method" do
      defined?(defined_specs_undefined_method || true).should == "expression"
      defined?(defined_specs_undefined_method or true).should == "expression"
    end

    it "returns 'expression' for an expression with '||/or' and an unset class variable" do
      defined?(@@defined_specs_undefined_class_variable || true).should == "expression"
      defined?(@@defined_specs_undefined_class_variable or true).should == "expression"
    end

    it "does not call a method in an '||' expression and returns 'expression'" do
      defined?(DefinedSpecs.side_effects || true).should == "expression"
      ScratchPad.recorded.should be_nil
    end

    it "does not call a method in an 'or' expression and returns 'expression'" do
      defined?(DefinedSpecs.side_effects or true).should == "expression"
      ScratchPad.recorded.should be_nil
    end
  end

  it "returns 'expression' when passed a String" do
    defined?("garble gooble gable").should == "expression"
  end

  describe "with a dynamic String" do
    it "returns 'expression' when the String contains a literal" do
      defined?("garble #{42}").should == "expression"
    end

    it "returns 'expression' when the String contains a call to a defined method" do
      defined?("garble #{DefinedSpecs.side_effects}").should == "expression"
    end

    it "returns 'expression' when the String contains a call to an undefined method" do
      defined?("garble #{DefinedSpecs.undefined_method}").should == "expression"
    end

    it "does not call the method in the String" do
      defined?("garble #{DefinedSpecs.dynamic_string}").should == "expression"
      ScratchPad.recorded.should be_nil
    end
  end

  describe "with a dynamic Regexp" do
    it "returns 'expression' when the Regexp contains a literal" do
      defined?(/garble #{42}/).should == "expression"
    end

    it "returns 'expression' when the Regexp contains a call to a defined method" do
      defined?(/garble #{DefinedSpecs.side_effects}/).should == "expression"
    end

    it "returns 'expression' when the Regexp contains a call to an undefined method" do
      defined?(/garble #{DefinedSpecs.undefined_method}/).should == "expression"
    end

    it "does not call the method in the Regexp" do
      defined?(/garble #{DefinedSpecs.dynamic_string}/).should == "expression"
      ScratchPad.recorded.should be_nil
    end
  end

  it "returns 'expression' when passed a Fixnum literal" do
    defined?(42).should == "expression"
  end

  it "returns 'expression' when passed a Bignum literal" do
    defined?(0xdead_beef_deed_feed).should == "expression"
  end

  it "returns 'expression' when passed a Float literal" do
    defined?(1.5).should == "expression"
  end

  it "returns 'expression' when passed a Range literal" do
    defined?(0..2).should == "expression"
  end

  it "returns 'expression' when passed a Regexp literal" do
    defined?(/undefined/).should == "expression"
  end

  it "returns 'expression' when passed an Array literal" do
    defined?([1, 2]).should == "expression"
  end

  it "returns 'expression' when passed a Hash literal" do
    defined?({a: :b}).should == "expression"
  end

  it "returns 'expression' when passed a Symbol literal" do
    defined?(:defined_specs).should == "expression"
  end
end

describe "The defined? keyword for variables" do
  it "returns 'local-variable' when called with the name of a local variable" do
    ret = DefinedSpecs::Basic.new.local_variable_defined
    ret.should == "local-variable"
    ret.frozen?.should == true
  end

  it "returns 'local-variable' when called with the name of a local variable assigned to nil" do
    DefinedSpecs::Basic.new.local_variable_defined_nil.should == "local-variable"
  end

  it "returns nil for an instance variable that has not been read" do
    DefinedSpecs::Basic.new.instance_variable_undefined.should be_nil
  end

  it "returns nil for an instance variable that has been read but not assigned to" do
    DefinedSpecs::Basic.new.instance_variable_read.should be_nil
  end

  it "returns 'instance-variable' for an instance variable that has been assigned" do
    ret = DefinedSpecs::Basic.new.instance_variable_defined
    ret.should == "instance-variable"
    ret.frozen?.should == true
  end

  it "returns 'instance-variable' for an instance variable that has been assigned to nil" do
    DefinedSpecs::Basic.new.instance_variable_defined_nil.should == "instance-variable"
  end

  it "returns nil for a global variable that has not been read" do
    DefinedSpecs::Basic.new.global_variable_undefined.should be_nil
  end

  it "returns nil for a global variable that has been read but not assigned to" do
    DefinedSpecs::Basic.new.global_variable_read.should be_nil
  end

  it "returns 'global-variable' for a global variable that has been assigned nil" do
    ret = DefinedSpecs::Basic.new.global_variable_defined_as_nil
    ret.should == "global-variable"
    ret.frozen?.should == true
  end

  # MRI appears to special case defined? for $! and $~ in that it returns
  # 'global-variable' even when they are not set (or they are always "set"
  # but the value may be nil). In other words, 'defined?($~)' will return
  # 'global-variable' even if no match has been done.

  it "returns 'global-variable' for $!" do
    defined?($!).should == "global-variable"
  end

  it "returns 'global-variable for $~" do
    defined?($~).should == "global-variable"
  end

  describe "when a String does not match a Regexp" do
    before :each do
      "mis-matched" =~ /z(z)z/
    end

    it "returns 'global-variable' for $~" do
      defined?($~).should == "global-variable"
    end

    it "returns nil for $&" do
      defined?($&).should be_nil
    end

    it "returns nil for $`" do
      defined?($`).should be_nil
    end

    it "returns nil for $'" do
      defined?($').should be_nil
    end

    it "returns nil for $+" do
      defined?($+).should be_nil
    end

    it "returns nil for any last match global" do
      defined?($1).should be_nil
      defined?($4).should be_nil
      defined?($7).should be_nil
      defined?($10).should be_nil
      defined?($200).should be_nil
    end
  end

  describe "when a String matches a Regexp" do
    before :each do
      "mis-matched" =~ /s(-)m(.)/
    end

    it "returns 'global-variable' for $~" do
      defined?($~).should == "global-variable"
    end

    it "returns 'global-variable' for $&" do
      defined?($&).should == "global-variable"
    end

    it "returns 'global-variable' for $`" do
      defined?($`).should == "global-variable"
    end

    it "returns 'global-variable' for $'" do
      defined?($').should == "global-variable"
    end

    it "returns 'global-variable' for $+" do
      defined?($+).should == "global-variable"
    end

    it "returns 'global-variable' for the capture references" do
      defined?($1).should == "global-variable"
      defined?($2).should == "global-variable"
    end

    it "returns nil for non-captures" do
      defined?($4).should be_nil
      defined?($7).should be_nil
      defined?($10).should be_nil
      defined?($200).should be_nil
    end
  end

  describe "when a Regexp does not match a String" do
    before :each do
      /z(z)z/ =~ "mis-matched"
    end

    it "returns 'global-variable' for $~" do
      defined?($~).should == "global-variable"
    end

    it "returns nil for $&" do
      defined?($&).should be_nil
    end

    it "returns nil for $`" do
      defined?($`).should be_nil
    end

    it "returns nil for $'" do
      defined?($').should be_nil
    end

    it "returns nil for $+" do
      defined?($+).should be_nil
    end

    it "returns nil for any last match global" do
      defined?($1).should be_nil
      defined?($4).should be_nil
      defined?($7).should be_nil
      defined?($10).should be_nil
      defined?($200).should be_nil
    end
  end

  describe "when a Regexp matches a String" do
    before :each do
      /s(-)m(.)/ =~ "mis-matched"
    end

    it "returns 'global-variable' for $~" do
      defined?($~).should == "global-variable"
    end

    it "returns 'global-variable' for $&" do
      defined?($&).should == "global-variable"
    end

    it "returns 'global-variable' for $`" do
      defined?($`).should == "global-variable"
    end

    it "returns 'global-variable' for $'" do
      defined?($').should == "global-variable"
    end

    it "returns 'global-variable' for $+" do
      defined?($+).should == "global-variable"
    end

    it "returns 'global-variable' for the capture references" do
      defined?($1).should == "global-variable"
      defined?($2).should == "global-variable"
    end

    it "returns nil for non-captures" do
      defined?($4).should be_nil
      defined?($7).should be_nil
      defined?($10).should be_nil
      defined?($200).should be_nil
    end
  end
  it "returns 'global-variable' for a global variable that has been assigned" do
    DefinedSpecs::Basic.new.global_variable_defined.should == "global-variable"
  end

  it "returns nil for a class variable that has not been read" do
    DefinedSpecs::Basic.new.class_variable_undefined.should be_nil
  end

  # There is no spec for a class variable that is read before being assigned
  # to because setting up the code for this raises a NameError before you
  # get to the defined? call so it really has nothing to do with 'defined?'.

  it "returns 'class variable' when called with the name of a class variable" do
    ret = DefinedSpecs::Basic.new.class_variable_defined
    ret.should == "class variable"
    ret.frozen?.should == true
  end

  it "returns 'local-variable' when called with the name of a block local" do
    block = Proc.new { |xxx| defined?(xxx) }
    block.call(1).should == "local-variable"
  end
end

describe "The defined? keyword for a simple constant" do
  it "returns 'constant' when the constant is defined" do
    ret = defined?(DefinedSpecs)
    ret.should == "constant"
    ret.frozen?.should == true
  end

  it "returns nil when the constant is not defined" do
    defined?(DefinedSpecsUndefined).should be_nil
  end

  it "does not call Object.const_missing if the constant is not defined" do
    Object.should_not_receive(:const_missing)
    defined?(DefinedSpecsUndefined).should be_nil
  end

  it "returns 'constant' for an included module" do
    DefinedSpecs::Child.module_defined.should == "constant"
  end

  it "returns 'constant' for a constant defined in an included module" do
    DefinedSpecs::Child.module_constant_defined.should == "constant"
  end
end

describe "The defined? keyword for a top-level constant" do
  it "returns 'constant' when passed the name of a top-level constant" do
    defined?(::DefinedSpecs).should == "constant"
  end

  it "returns nil if the constant is not defined" do
    defined?(::DefinedSpecsUndefined).should be_nil
  end

  it "does not call Object.const_missing if the constant is not defined" do
    Object.should_not_receive(:const_missing)
    defined?(::DefinedSpecsUndefined).should be_nil
  end
end

describe "The defined? keyword for a scoped constant" do
  it "returns 'constant' when the scoped constant is defined" do
    defined?(DefinedSpecs::Basic).should == "constant"
  end

  it "returns nil when the scoped constant is not defined" do
    defined?(DefinedSpecs::Undefined).should be_nil
  end

  it "returns nil when the constant is not defined and the outer module implements .const_missing" do
    defined?(DefinedSpecs::ModuleWithConstMissing::Undefined).should be_nil
  end

  it "does not call .const_missing if the constant is not defined" do
    DefinedSpecs.should_not_receive(:const_missing)
    defined?(DefinedSpecs::UnknownChild).should be_nil
  end

  it "returns nil when an undefined constant is scoped to a defined constant" do
    defined?(DefinedSpecs::Child::Undefined).should be_nil
  end

  it "returns nil when a constant is scoped to an undefined constant" do
    Object.should_not_receive(:const_missing)
    defined?(Undefined::Object).should be_nil
  end

  it "returns nil when the undefined constant is scoped to an undefined constant" do
    defined?(DefinedSpecs::Undefined::Undefined).should be_nil
  end

  it "returns nil when a constant is defined on top-level but not on the module" do
    defined?(DefinedSpecs::String).should be_nil
  end

  it "returns nil when a constant is defined on top-level but not on the class" do
    defined?(DefinedSpecs::Basic::String).should be_nil
  end

  it "returns 'constant' if the scoped-scoped constant is defined" do
    defined?(DefinedSpecs::Child::A).should == "constant"
  end
end

describe "The defined? keyword for a top-level scoped constant" do
  it "returns 'constant' when the scoped constant is defined" do
    defined?(::DefinedSpecs::Basic).should == "constant"
  end

  it "returns nil when the scoped constant is not defined" do
    defined?(::DefinedSpecs::Undefined).should be_nil
  end

  it "returns nil when an undefined constant is scoped to a defined constant" do
    defined?(::DefinedSpecs::Child::Undefined).should be_nil
  end

  it "returns nil when the undefined constant is scoped to an undefined constant" do
    defined?(::DefinedSpecs::Undefined::Undefined).should be_nil
  end

  it "returns 'constant' if the scoped-scoped constant is defined" do
    defined?(::DefinedSpecs::Child::A).should == "constant"
  end
end

describe "The defined? keyword for a self-send method call scoped constant" do
  it "returns nil if the constant is not defined in the scope of the method's value" do
    defined?(defined_specs_method::Undefined).should be_nil
  end

  it "returns 'constant' if the constant is defined in the scope of the method's value" do
    defined?(defined_specs_method::Basic).should == "constant"
  end

  it "returns nil if the last constant is not defined in the scope chain" do
    defined?(defined_specs_method::Basic::Undefined).should be_nil
  end

  it "returns nil if the middle constant is not defined in the scope chain" do
    defined?(defined_specs_method::Undefined::Undefined).should be_nil
  end

  it "returns 'constant' if all the constants in the scope chain are defined" do
    defined?(defined_specs_method::Basic::A).should == "constant"
  end
end

describe "The defined? keyword for a receiver method call scoped constant" do
  it "returns nil if the constant is not defined in the scope of the method's value" do
    defined?(defined_specs_receiver.defined_method::Undefined).should be_nil
  end

  it "returns 'constant' if the constant is defined in the scope of the method's value" do
    defined?(defined_specs_receiver.defined_method::Basic).should == "constant"
  end

  it "returns nil if the last constant is not defined in the scope chain" do
    defined?(defined_specs_receiver.defined_method::Basic::Undefined).should be_nil
  end

  it "returns nil if the middle constant is not defined in the scope chain" do
    defined?(defined_specs_receiver.defined_method::Undefined::Undefined).should be_nil
  end

  it "returns 'constant' if all the constants in the scope chain are defined" do
    defined?(defined_specs_receiver.defined_method::Basic::A).should == "constant"
  end
end

describe "The defined? keyword for a module method call scoped constant" do
  it "returns nil if the constant is not defined in the scope of the method's value" do
    defined?(DefinedSpecs.defined_method::Undefined).should be_nil
  end

  it "returns 'constant' if the constant scoped by the method's value is defined" do
    defined?(DefinedSpecs.defined_method::Basic).should == "constant"
  end

  it "returns nil if the last constant in the scope chain is not defined" do
    defined?(DefinedSpecs.defined_method::Basic::Undefined).should be_nil
  end

  it "returns nil if the middle constant in the scope chain is not defined" do
    defined?(DefinedSpecs.defined_method::Undefined::Undefined).should be_nil
  end

  it "returns 'constant' if all the constants in the scope chain are defined" do
    defined?(DefinedSpecs.defined_method::Basic::A).should == "constant"
  end

  it "returns nil if the outer scope constant in the receiver is not defined" do
    defined?(Undefined::DefinedSpecs.defined_method::Basic).should be_nil
  end

  it "returns nil if the scoped constant in the receiver is not defined" do
    defined?(DefinedSpecs::Undefined.defined_method::Basic).should be_nil
  end

  it "returns 'constant' if all the constants in the receiver are defined" do
    defined?(Object::DefinedSpecs.defined_method::Basic).should == "constant"
  end

  it "returns 'constant' if all the constants in the receiver and scope chain are defined" do
    defined?(Object::DefinedSpecs.defined_method::Basic::A).should == "constant"
  end
end

describe "The defined? keyword for a variable scoped constant" do
  after :all do
    if Object.class_variable_defined? :@@defined_specs_obj
      Object.__send__(:remove_class_variable, :@@defined_specs_obj)
    end
  end

  it "returns nil if the instance scoped constant is not defined" do
    @defined_specs_obj = DefinedSpecs::Basic
    defined?(@defined_specs_obj::Undefined).should be_nil
  end

  it "returns 'constant' if the constant is defined in the scope of the instance variable" do
    @defined_specs_obj = DefinedSpecs::Basic
    defined?(@defined_specs_obj::A).should == "constant"
  end

  it "returns nil if the global scoped constant is not defined" do
    $defined_specs_obj = DefinedSpecs::Basic
    defined?($defined_specs_obj::Undefined).should be_nil
  end

  it "returns 'constant' if the constant is defined in the scope of the global variable" do
    $defined_specs_obj = DefinedSpecs::Basic
    defined?($defined_specs_obj::A).should == "constant"
  end

  it "returns nil if the class scoped constant is not defined" do
    eval(<<-END, binding, __FILE__, __LINE__)
      class singleton_class::A
        @@defined_specs_obj = DefinedSpecs::Basic
        defined?(@@defined_specs_obj::Undefined).should be_nil
      end
    END
  end

  it "returns 'constant' if the constant is defined in the scope of the class variable" do
    eval(<<-END, binding, __FILE__, __LINE__)
      class singleton_class::A
        @@defined_specs_obj = DefinedSpecs::Basic
        defined?(@@defined_specs_obj::A).should == "constant"
      end
    END
  end

  it "returns nil if the local scoped constant is not defined" do
    defined_specs_obj = DefinedSpecs::Basic
    defined?(defined_specs_obj::Undefined).should be_nil
  end

  it "returns 'constant' if the constant is defined in the scope of the local variable" do
    defined_specs_obj = DefinedSpecs::Basic
    defined?(defined_specs_obj::A).should == "constant"
  end
end

describe "The defined? keyword for a self:: scoped constant" do
  it "returns 'constant' for a constant explicitly scoped to self:: when set" do
    defined?(DefinedSpecs::SelfScoped).should == "constant"
  end

  it "returns 'constant' for a constant explicitly scoped to self:: in subclass's metaclass" do
    DefinedSpecs::Child.parent_constant_defined.should == "constant"
  end
end

describe "The defined? keyword for yield" do
  it "returns nil if no block is passed to a method not taking a block parameter" do
    DefinedSpecs::Basic.new.no_yield_block.should be_nil
  end

  it "returns nil if no block is passed to a method taking a block parameter" do
    DefinedSpecs::Basic.new.no_yield_block_parameter.should be_nil
  end

  it "returns 'yield' if a block is passed to a method not taking a block parameter" do
    ret = DefinedSpecs::Basic.new.yield_block
    ret.should == "yield"
    ret.frozen?.should == true
  end

  it "returns 'yield' if a block is passed to a method taking a block parameter" do
    DefinedSpecs::Basic.new.yield_block_parameter.should == "yield"
  end

  it "returns 'yield' when called within a block" do
    def yielder
      yield
    end

    def call_defined
      yielder { defined?(yield) }
    end

    call_defined() { }.should == "yield"
  end
end

describe "The defined? keyword for super" do
  it "returns nil when a superclass undef's the method" do
    DefinedSpecs::ClassWithoutMethod.new.test.should be_nil
  end

  describe "for a method taking no arguments" do
    it "returns nil when no superclass method exists" do
      DefinedSpecs::Super.new.no_super_method_no_args.should be_nil
    end

    it "returns nil from a block when no superclass method exists" do
      DefinedSpecs::Super.new.no_super_method_block_no_args.should be_nil
    end

    it "returns nil from a #define_method when no superclass method exists" do
      DefinedSpecs::Super.new.no_super_define_method_no_args.should be_nil
    end

    it "returns nil from a block in a #define_method when no superclass method exists" do
      DefinedSpecs::Super.new.no_super_define_method_block_no_args.should be_nil
    end

    it "returns 'super' when a superclass method exists" do
      ret = DefinedSpecs::Super.new.method_no_args
      ret.should == "super"
      ret.frozen?.should == true
    end

    it "returns 'super' from a block when a superclass method exists" do
      DefinedSpecs::Super.new.method_block_no_args.should == "super"
    end

    it "returns 'super' from a #define_method when a superclass method exists" do
      DefinedSpecs::Super.new.define_method_no_args.should == "super"
    end

    it "returns 'super' from a block in a #define_method when a superclass method exists" do
      DefinedSpecs::Super.new.define_method_block_no_args.should == "super"
    end

    it "returns 'super' when the method exists in a supermodule" do
      DefinedSpecs::SuperWithIntermediateModules.new.method_no_args.should == "super"
    end
  end

  describe "for a method taking arguments" do
    it "returns nil when no superclass method exists" do
      DefinedSpecs::Super.new.no_super_method_args.should be_nil
    end

    it "returns nil from a block when no superclass method exists" do
      DefinedSpecs::Super.new.no_super_method_block_args.should be_nil
    end

    it "returns nil from a #define_method when no superclass method exists" do
      DefinedSpecs::Super.new.no_super_define_method_args.should be_nil
    end

    it "returns nil from a block in a #define_method when no superclass method exists" do
      DefinedSpecs::Super.new.no_super_define_method_block_args.should be_nil
    end

    it "returns 'super' when a superclass method exists" do
      DefinedSpecs::Super.new.method_args.should == "super"
    end

    it "returns 'super' from a block when a superclass method exists" do
      DefinedSpecs::Super.new.method_block_args.should == "super"
    end

    it "returns 'super' from a #define_method when a superclass method exists" do
      DefinedSpecs::Super.new.define_method_args.should == "super"
    end

    it "returns 'super' from a block in a #define_method when a superclass method exists" do
      DefinedSpecs::Super.new.define_method_block_args.should == "super"
    end
  end

  describe "within an included module's method" do
    it "returns 'super' when a superclass method exists in the including hierarchy" do
      DefinedSpecs::Child.new.defined_super.should == "super"
    end
  end
end


describe "The defined? keyword for instance variables" do
  it "returns 'instance-variable' if assigned" do
    @assigned_ivar = "some value"
    defined?(@assigned_ivar).should == "instance-variable"
  end

  it "returns nil if not assigned" do
    defined?(@unassigned_ivar).should be_nil
  end
end

describe "The defined? keyword for pseudo-variables" do
  it "returns 'expression' for __FILE__" do
    defined?(__FILE__).should == "expression"
  end

  it "returns 'expression' for __LINE__" do
    defined?(__LINE__).should == "expression"
  end

  it "returns 'expression' for __ENCODING__" do
    defined?(__ENCODING__).should == "expression"
  end
end

describe "The defined? keyword for conditional expressions" do
  it "returns 'expression' for an 'if' conditional" do
    defined?(if x then 'x' else '' end).should == "expression"
  end

  it "returns 'expression' for an 'unless' conditional" do
    defined?(unless x then '' else 'x' end).should == "expression"
  end

  it "returns 'expression' for ternary expressions" do
    defined?(x ? 'x' : '').should == "expression"
  end
end

describe "The defined? keyword for case expressions" do
  it "returns 'expression'" do
    defined?(case x; when 'x'; 'y' end).should == "expression"
  end
end

describe "The defined? keyword for loop expressions" do
  it "returns 'expression' for a 'for' expression" do
    defined?(for n in 1..3 do true end).should == "expression"
  end

  it "returns 'expression' for a 'while' expression" do
    defined?(while x do y end).should == "expression"
  end

  it "returns 'expression' for an 'until' expression" do
    defined?(until x do y end).should == "expression"
  end

  it "returns 'expression' for a 'break' expression" do
    defined?(break).should == "expression"
  end

  it "returns 'expression' for a 'next' expression" do
    defined?(next).should == "expression"
  end

  it "returns 'expression' for a 'redo' expression" do
    defined?(redo).should == "expression"
  end

  it "returns 'expression' for a 'retry' expression" do
    defined?(retry).should == "expression"
  end
end

describe "The defined? keyword for return expressions" do
  it "returns 'expression'" do
    defined?(return).should == "expression"
  end
end

describe "The defined? keyword for exception expressions" do
  it "returns 'expression'" do
    defined?(begin 1 end).should == "expression"
  end
end
