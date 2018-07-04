require_relative '../../spec_helper'
require_relative 'fixtures/classes'

EvalSpecs::A.new.c

describe "Kernel#eval" do
  it "is a private method" do
    Kernel.should have_private_instance_method(:eval)
  end

  it "is a module function" do
    Kernel.respond_to?(:eval).should == true
  end

  it "evaluates the code within" do
    eval("2 + 3").should == 5
  end

  it "coerces an object to string" do
    eval(EvalSpecs::CoercedObject.new).should == 5
  end

  it "evaluates within the scope of the eval" do
    EvalSpecs::A::B.name.should == "EvalSpecs::A::B"
  end

  it "evaluates such that consts are scoped to the class of the eval" do
    EvalSpecs::A::C.name.should == "EvalSpecs::A::C"
  end

  it "finds a local in an enclosing scope" do
    a = 1
    eval("a").should == 1
  end

  it "updates a local in an enclosing scope" do
    a = 1
    eval("a = 2")
    a.should == 2
  end

  it "updates a local in a surrounding block scope" do
    EvalSpecs.new.f do
      a = 1
      eval("a = 2")
      a.should == 2
    end
  end

  it "updates a local in a scope above a surrounding block scope" do
    a = 1
    EvalSpecs.new.f do
      eval("a = 2")
      a.should == 2
    end
    a.should == 2
  end

  it "updates a local in a scope above when modified in a nested block scope" do
    a = 1
    es = EvalSpecs.new
    eval("es.f { es.f { a = 2 } }")
    a.should == 2
  end

  it "finds locals in a nested eval" do
    eval('test = 10; eval("test")').should == 10
  end

  it "does not share locals across eval scopes" do
    code = fixture __FILE__, "eval_locals.rb"
    ruby_exe(code).chomp.should == "NameError"
  end

  it "doesn't accept a Proc object as a binding" do
    x = 1
    bind = proc {}

    lambda { eval("x", bind) }.should raise_error(TypeError)
  end

  it "does not make Proc locals visible to evaluated code" do
    bind = proc { inner = 4 }
    lambda { eval("inner", bind.binding) }.should raise_error(NameError)
  end

  # REWRITE ME: This obscures the real behavior of where locals are stored
  # in eval bindings.
  it "allows a binding to be captured inside an eval" do
    outer_binding = binding
    level1 = eval("binding", outer_binding)
    level2 = eval("binding", level1)

    eval("x = 2", outer_binding)
    eval("y = 3", level1)

    eval("w=1", outer_binding)
    eval("w", outer_binding).should == 1
    eval("w=1", level1).should == 1
    eval("w", level1).should == 1
    eval("w=1", level2).should == 1
    eval("w", level2).should == 1

    eval("x", outer_binding).should == 2
    eval("x=2", level1)
    eval("x", level1).should == 2
    eval("x=2", level2)
    eval("x", level2).should == 2

    eval("y=3", outer_binding)
    eval("y", outer_binding).should == 3
    eval("y=3", level1)
    eval("y", level1).should == 3
    eval("y=3", level2)
    eval("y", level2).should == 3
  end

  it "uses the same scope for local variables when given the same binding" do
    outer_binding = binding

    eval("if false; a = 1; end", outer_binding)
    eval("a", outer_binding).should be_nil
  end

  it "allows creating a new class in a binding" do
    bind = proc {}
    eval("class EvalBindingProcA; end; EvalBindingProcA.name", bind.binding).should =~ /EvalBindingProcA$/
  end

  it "allows creating a new class in a binding created by #eval" do
    bind = eval "binding"
    eval("class EvalBindingA; end; EvalBindingA.name", bind).should =~ /EvalBindingA$/
  end

  it "includes file and line information in syntax error" do
    expected = 'speccing.rb'
    lambda {
      eval('if true',TOPLEVEL_BINDING, expected)
    }.should raise_error(SyntaxError) { |e|
      e.message.should =~ /#{expected}:1:.+/
    }
  end

  it "evaluates string with given filename and negative linenumber" do
    expected_file = 'speccing.rb'
    lambda {
      eval('if true',TOPLEVEL_BINDING, expected_file, -100)
    }.should raise_error(SyntaxError) { |e|
      e.message.should =~ /#{expected_file}:-100:.+/
    }
  end

  it "sets constants at the toplevel from inside a block" do
    # The class Object bit is needed to workaround some mspec oddness
    class Object
      [1].each { eval "Const = 1"}
      Const.should == 1
      remove_const :Const
    end
  end

  it "uses the filename of the binding if none is provided" do
    eval("__FILE__").should == "(eval)"
    eval("__FILE__", binding).should == __FILE__
    eval("__FILE__", binding, "success").should == "success"
    eval("eval '__FILE__', binding").should == "(eval)"
    eval("eval '__FILE__', binding", binding).should == __FILE__
    eval("eval '__FILE__', binding", binding, 'success').should == 'success'
  end

  # Found via Rubinius bug github:#149
  it "does not alter the value of __FILE__ in the binding" do
    first_time =  EvalSpecs.call_eval
    second_time = EvalSpecs.call_eval

    # This bug is seen by calling the method twice and comparing the values
    # of __FILE__ each time. If the bug is present, calling eval will set the
    # value of __FILE__ to the eval's "filename" argument.

    second_time.should_not == "(eval)"
    first_time.should == second_time
  end

  it "can be aliased" do
    alias aliased_eval eval
    x = 2
    aliased_eval('x += 40')
    x.should == 42
  end

  # See http://jira.codehaus.org/browse/JRUBY-5163
  it "uses the receiver as self inside the eval" do
    eval("self").should equal(self)
    Kernel.eval("self").should equal(Kernel)
  end

  it "does not pass the block to the method being eval'ed" do
    lambda {
      eval('KernelSpecs::EvalTest.call_yield') { "content" }
    }.should raise_error(LocalJumpError)
  end

  it "returns from the scope calling #eval when evaluating 'return'" do
    lambda { eval("return :eval") }.call.should == :eval
  end

  it "unwinds through a Proc-style closure and returns from a lambda-style closure in the closure chain" do
    code = fixture __FILE__, "eval_return_with_lambda.rb"
    ruby_exe(code).chomp.should == "a,b,c,eval,f"
  end

  it "raises a LocalJumpError if there is no lambda-style closure in the chain" do
    code = fixture __FILE__, "eval_return_without_lambda.rb"
    ruby_exe(code).chomp.should == "a,b,c,e,LocalJumpError,f"
  end

  describe "with a magic encoding comment" do
    it "uses the magic comment encoding for the encoding of literal strings" do
      code = "# encoding: UTF-8\n'é'.encoding".b
      code.encoding.should == Encoding::BINARY
      eval(code).should == Encoding::UTF_8
    end

    it "uses the magic comment encoding for parsing constants" do
      code = <<CODE.b
# encoding: UTF-8
class EvalSpecs
  Vπ = 3.14
end
CODE
      code.encoding.should == Encoding::BINARY
      eval(code)
      EvalSpecs.constants(false).should include(:"Vπ")
      EvalSpecs::Vπ.should == 3.14
    end

    it "allows an emacs-style magic comment encoding" do
      code = <<CODE.b
# -*- encoding: UTF-8 -*-
class EvalSpecs
Vπemacs = 3.14
end
CODE
      code.encoding.should == Encoding::BINARY
      eval(code)
      EvalSpecs.constants(false).should include(:"Vπemacs")
      EvalSpecs::Vπemacs.should == 3.14
    end

    it "allows spaces before the magic encoding comment" do
      code = <<CODE.b
\t  \t  # encoding: UTF-8
class EvalSpecs
  Vπspaces = 3.14
end
CODE
      code.encoding.should == Encoding::BINARY
      eval(code)
      EvalSpecs.constants(false).should include(:"Vπspaces")
      EvalSpecs::Vπspaces.should == 3.14
    end

    it "allows a shebang line before the magic encoding comment" do
      code = <<CODE.b
#!/usr/bin/env ruby
# encoding: UTF-8
class EvalSpecs
  Vπshebang = 3.14
end
CODE
      code.encoding.should == Encoding::BINARY
      eval(code)
      EvalSpecs.constants(false).should include(:"Vπshebang")
      EvalSpecs::Vπshebang.should == 3.14
    end

    it "allows a shebang line and some spaces before the magic encoding comment" do
      code = <<CODE.b
#!/usr/bin/env ruby
  # encoding: UTF-8
class EvalSpecs
  Vπshebang_spaces = 3.14
end
CODE
      code.encoding.should == Encoding::BINARY
      eval(code)
      EvalSpecs.constants(false).should include(:"Vπshebang_spaces")
      EvalSpecs::Vπshebang_spaces.should == 3.14
    end

    it "allows a magic encoding comment and a subsequent frozen_string_literal magic comment" do
      # Make sure frozen_string_literal is not default true
      eval("'foo'".b).frozen?.should be_false

      code = <<CODE.b
# encoding: UTF-8
# frozen_string_literal: true
class EvalSpecs
  Vπstring = "frozen"
end
CODE
      code.encoding.should == Encoding::BINARY
      eval(code)
      EvalSpecs.constants(false).should include(:"Vπstring")
      EvalSpecs::Vπstring.should == "frozen"
      EvalSpecs::Vπstring.encoding.should == Encoding::UTF_8
      EvalSpecs::Vπstring.frozen?.should be_true
    end

    it "allows a magic encoding comment and a frozen_string_literal magic comment on the same line in emacs style" do
      code = <<CODE.b
# -*- encoding: UTF-8; frozen_string_literal: true -*-
class EvalSpecs
Vπsame_line = "frozen"
end
CODE
      code.encoding.should == Encoding::BINARY
      eval(code)
      EvalSpecs.constants(false).should include(:"Vπsame_line")
      EvalSpecs::Vπsame_line.should == "frozen"
      EvalSpecs::Vπsame_line.encoding.should == Encoding::UTF_8
      EvalSpecs::Vπsame_line.frozen?.should be_true
    end

    it "ignores the magic encoding comment if it is after a frozen_string_literal magic comment" do
      code = <<CODE.b
# frozen_string_literal: true
# encoding: UTF-8
class EvalSpecs
  Vπfrozen_first = "frozen"
end
CODE
      code.encoding.should == Encoding::BINARY
      eval(code)
      EvalSpecs.constants(false).should_not include(:"Vπfrozen_first")
      binary_constant = "Vπfrozen_first".b.to_sym
      EvalSpecs.constants(false).should include(binary_constant)
      value = EvalSpecs.const_get(binary_constant)
      value.should == "frozen"
      value.encoding.should == Encoding::BINARY
      value.frozen?.should be_true
    end
  end
end
