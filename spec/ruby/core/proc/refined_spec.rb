require_relative '../../spec_helper'
require_relative 'fixtures/refined'

ruby_version_is "4.1" do
  describe "Proc#refined" do
    it "returns a new Proc with the refinements of the given module activated inside its body" do
      pr = -> s { s.shout }
      refined = pr.refined(ProcRefinedSpecs::StringShout)
      refined.should.instance_of?(Proc)
      refined.should_not.equal?(pr)
      refined.call("hi").should == "HI!"
    end

    it "does not change the receiver" do
      pr = -> s { s.shout }
      pr.refined(ProcRefinedSpecs::StringShout)
      -> { pr.call("hi") }.should.raise(NoMethodError)
    end

    it "activates the refinements of all the given modules" do
      pr = -> s { [s.shout, s.quiet] }
      refined = pr.refined(ProcRefinedSpecs::StringShout, ProcRefinedSpecs::StringQuiet)
      refined.call("Hi").should == ["hi", "..."]
    end

    it "gives precedence to the module applied last for the same refined method, as with nested using" do
      pr = -> s { s.shout }
      pr.refined(ProcRefinedSpecs::StringShout, ProcRefinedSpecs::StringQuiet).call("Hi").should == "hi"
      pr.refined(ProcRefinedSpecs::StringQuiet, ProcRefinedSpecs::StringShout).call("Hi").should == "HI!"
    end

    it "shares the closure environment with the receiver" do
      counter = 0
      pr = -> { counter += 1 }
      refined = pr.refined(ProcRefinedSpecs::StringShout)
      refined.call
      pr.call
      counter.should == 2
    end

    it "preserves lambda-ness and arity" do
      l = -> s { s }.refined(ProcRefinedSpecs::StringShout)
      l.should.lambda?
      l.arity.should == 1

      pr = proc { |s| s }.refined(ProcRefinedSpecs::StringShout)
      pr.should_not.lambda?
    end

    it "preserves the class of a Proc subclass instance" do
      subclass = Class.new(Proc)
      refined = subclass.new { |s| s.shout }.refined(ProcRefinedSpecs::StringShout)
      refined.should.instance_of?(subclass)
      refined.call("hi").should == "HI!"
    end

    it "does not copy singleton methods of the receiver" do
      pr = -> s { s.shout }
      def pr.tag; :orig; end
      refined = pr.refined(ProcRefinedSpecs::StringShout)
      refined.should_not.respond_to?(:tag)
      refined.call("hi").should == "HI!"
    end

    it "keeps the refinements active in blocks nested inside the body" do
      pr = -> a { a.map { |s| s.shout } }
      pr.refined(ProcRefinedSpecs::StringShout).call(%w[a b]).should == ["A!", "B!"]
    end

    it "keeps the refinements active in methods defined inside the body" do
      pr = -> {
        obj = Object.new
        def obj.shout_hi
          "hi".shout
        end
        obj.shout_hi
      }
      pr.refined(ProcRefinedSpecs::StringShout).call.should == "HI!"
    end

    it "keeps the refinements active in instance methods defined inside the body" do
      pr = -> {
        Class.new {
          def shout_hi
            "hi".shout
          end
        }.new.shout_hi
      }
      pr.refined(ProcRefinedSpecs::StringShout).call.should == "HI!"
    end

    it "keeps the refinements active in a class body opened with the class keyword inside the body" do
      pr = -> {
        class ProcRefinedSpecs::ClassBody
          def shout_hi
            "hi".shout
          end
        end
        ProcRefinedSpecs::ClassBody.new.shout_hi
      }
      pr.refined(ProcRefinedSpecs::StringShout).call.should == "HI!"
    ensure
      ProcRefinedSpecs.send(:remove_const, :ClassBody) if ProcRefinedSpecs.const_defined?(:ClassBody)
    end

    it "applies the refinements to Symbol#to_proc blocks created inside the body" do
      pr = -> a { a.map(&:shout) }
      pr.refined(ProcRefinedSpecs::StringShout).call(%w[a b]).should == ["A!", "B!"]
      -> { pr.call(%w[a b]) }.should.raise(NoMethodError)
    end

    it "applies the refinements to operators and element access" do
      refined = -> a, b { [a + b, a < b] }.refined(ProcRefinedSpecs::Operators)
      refined.call(1, 2).should == ["plus(1,2)", "lt"]
      -> a { a[0] }.refined(ProcRefinedSpecs::Operators).call([9]).should == "at0"
      -> h { h["x"] }.refined(ProcRefinedSpecs::Operators).call({ "x" => 1 }).should == "aref(x)"
      -> a, b { a + b }.call(1, 2).should == 3
    end

    it "keeps the refinements active when called via instance_eval, instance_exec and class_eval" do
      pr = proc { "hi".shout }
      refined = pr.refined(ProcRefinedSpecs::StringShout)
      Object.new.instance_eval(&refined).should == "HI!"
      Object.new.instance_exec(&refined).should == "HI!"
      Class.new.class_eval(&refined).should == "HI!"
    end

    it "raises ArgumentError when called with no modules" do
      -> { -> {}.refined }.should.raise(ArgumentError)
    end

    it "raises TypeError when called with a non-Module argument" do
      -> { -> {}.refined(42) }.should.raise(TypeError)
      -> { -> {}.refined(String) }.should.raise(TypeError)
    end

    it "raises ArgumentError for a Proc not created from a Ruby block" do
      -> { :upcase.to_proc.refined(ProcRefinedSpecs::StringShout) }.should.raise(ArgumentError)
      method_proc = "hi".method(:upcase).to_proc
      -> { method_proc.refined(ProcRefinedSpecs::StringShout) }.should.raise(ArgumentError)
    end

    it "raises ArgumentError for a Proc that already has refinements applied" do
      refined = -> s { s.shout }.refined(ProcRefinedSpecs::StringShout)
      -> { refined.refined(ProcRefinedSpecs::StringQuiet) }.should.raise(ArgumentError)
    end

    it "keeps the refinements on dup and clone" do
      refined = -> s { s.shout }.refined(ProcRefinedSpecs::StringShout)
      refined.dup.call("hi").should == "HI!"
      refined.clone.call("hi").should == "HI!"
      -> { refined.dup.refined(ProcRefinedSpecs::StringQuiet) }.should.raise(ArgumentError)
      -> { refined.clone.refined(ProcRefinedSpecs::StringQuiet) }.should.raise(ArgumentError)
    end

    it "raises ArgumentError when the result is passed to define_method" do
      refined = -> s { s.shout }.refined(ProcRefinedSpecs::StringShout)
      -> { Class.new { define_method(:m, refined) } }.should.raise(ArgumentError)
      -> { Object.new.define_singleton_method(:m, refined) }.should.raise(ArgumentError)
    end

    it "raises RuntimeError when the body calls using" do
      mod = Module.new { refine(String) { def whisper; downcase; end } }
      pr = proc { using mod }
      refined = pr.refined(ProcRefinedSpecs::StringShout)
      -> { Module.new.module_eval(&refined) }.should.raise(RuntimeError)
    end

    it "allows calling refine inside the body" do
      pr = -> s {
        Module.new { refine(String) { def whisper; downcase; end } }
        s.shout
      }
      pr.refined(ProcRefinedSpecs::StringShout).call("hi").should == "HI!"
    end
  end
end
