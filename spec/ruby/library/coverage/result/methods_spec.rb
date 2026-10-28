require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require 'coverage'

describe "Coverage.result with methods: true" do
  before :all do
    @file = fixture __dir__, 'sign.rb'
    @sign = [CoverageSpecs.singleton_class, :sign, 2, 2, 4, 5]
  end

  after :each do
    Coverage.result if Coverage.running?
  end

  it "returns only the methods of each file" do
    Coverage.start(methods: true)
    load @file
    result = Coverage.result

    result[@file].should == {
      methods: { @sign => 0 }
    }
  end

  it "returns the methods after the lines when both are enabled" do
    Coverage.start(lines: true, methods: true)
    load @file
    result = Coverage.result

    result[@file].should == {
      lines: [1, 1, 0, nil, nil],
      methods: { @sign => 0 }
    }
  end

  it "returns the methods after the oneshot lines when both are enabled" do
    Coverage.start(oneshot_lines: true, methods: true)
    load @file
    result = Coverage.result

    result[@file].should == {
      oneshot_lines: [1, 2],
      methods: { @sign => 0 }
    }
  end

  it "returns the counts so far when passed clear: true" do
    Coverage.start(methods: true)
    load @file
    2.times { CoverageSpecs.sign(1) }
    result = Coverage.result(stop: false, clear: true)

    result[@file][:methods].should == { @sign => 2 }
  end

  it "sets the counts to 0 when passed clear: true" do
    Coverage.start(methods: true)
    load @file
    CoverageSpecs.sign(1)
    Coverage.result(stop: false, clear: true)

    Coverage.peek_result[@file][:methods].should == { @sign => 0 }
  end

  it "reports each method by its owner, name and position with how many times it was called" do
    result = CoverageSpecs.method_coverage(<<~'RUBY')
      class CoverageSpecs::Plain
        def called(a, b = 1, *c, d:, **e, &f); end
        def uncalled; end
      end
      2.times { CoverageSpecs::Plain.new.called(1, d: 2) }
    RUBY

    result.should == {
      [CoverageSpecs::Plain, :called, 2, 2, 2, 44] => 2,
      [CoverageSpecs::Plain, :uncalled, 3, 2, 3, 19] => 0
    }
  end

  it "reports a method of several lines from its def to its end" do
    result = CoverageSpecs.method_coverage(<<~'RUBY')
      class CoverageSpecs::SeveralLines
        def several_lines(a,
                          b)
        end
      end
    RUBY

    result.should == {
      [CoverageSpecs::SeveralLines, :several_lines, 2, 2, 4, 5] => 0
    }
  end

  it "reports a singleton method under the singleton class" do
    result = CoverageSpecs.method_coverage(<<~'RUBY')
      class CoverageSpecs::Singleton
        def self.with_self; end
        class << self
          def in_singleton_class; end
        end
      end
      CoverageSpecs::Singleton.with_self
      CoverageSpecs::Singleton.in_singleton_class
    RUBY

    result.should == {
      [CoverageSpecs::Singleton.singleton_class, :with_self, 2, 2, 2, 25] => 1,
      [CoverageSpecs::Singleton.singleton_class, :in_singleton_class, 4, 4, 4, 31] => 1
    }
  end

  it "reports a module function under both the module and its singleton class" do
    result = CoverageSpecs.method_coverage(<<~'RUBY')
      module CoverageSpecs::Functions
        def function; end
        module_function :function
      end
      CoverageSpecs::Functions.function
    RUBY

    result.should == {
      [CoverageSpecs::Functions, :function, 2, 2, 2, 19] => 0,
      [CoverageSpecs::Functions.singleton_class, :function, 2, 2, 2, 19] => 1
    }
  end

  it "reports a method of a class with a prepended module under the class" do
    result = CoverageSpecs.method_coverage(<<~'RUBY')
      class CoverageSpecs::Prepended
        prepend Module.new
        def prepended; end
      end
      CoverageSpecs::Prepended.new.prepended
    RUBY

    result.should == {
      [CoverageSpecs::Prepended, :prepended, 3, 2, 3, 20] => 1
    }
  end

  it "counts a call through an alias as a call of the original method" do
    result = CoverageSpecs.method_coverage(<<~'RUBY')
      class CoverageSpecs::Aliased
        def original; end
        alias aliased original
      end
      CoverageSpecs::Aliased.new.original
      2.times { CoverageSpecs::Aliased.new.aliased }
    RUBY

    result.should == {
      [CoverageSpecs::Aliased, :original, 2, 2, 2, 19] => 3
    }
  end

  it "counts a call of a method made private in a subclass as a call of the inherited method" do
    result = CoverageSpecs.method_coverage(<<~'RUBY')
      class CoverageSpecs::Parent
        def inherited; end
      end
      class CoverageSpecs::Child < CoverageSpecs::Parent
        private :inherited
      end
      CoverageSpecs::Child.new.send(:inherited)
    RUBY

    result.should == {
      [CoverageSpecs::Parent, :inherited, 2, 2, 2, 20] => 1
    }
  end

  it "reports a method defined from an UnboundMethod under its original name" do
    result = CoverageSpecs.method_coverage(<<~'RUBY')
      class CoverageSpecs::Original
        def original; end
      end
      class CoverageSpecs::Renamed < CoverageSpecs::Original
        define_method(:renamed, instance_method(:original))
      end
      CoverageSpecs::Renamed.new.renamed
    RUBY

    result.should == {
      [CoverageSpecs::Original, :original, 2, 2, 2, 19] => 0,
      [CoverageSpecs::Renamed, :original, 2, 2, 2, 19] => 1
    }
  end

  it "counts the calls of a method defined by an eval that is not measured" do
    result = CoverageSpecs.method_coverage(<<~'RUBY')
      class CoverageSpecs::Evaled
        class_eval <<-INNER, __FILE__, __LINE__ + 1
          def from_eval(x); x; end
        INNER
      end
      3.times { CoverageSpecs::Evaled.new.from_eval(1) }
    RUBY

    result.should == {
      [CoverageSpecs::Evaled, :from_eval, 3, 4, 3, 28] => 3
    }
  end

  it "counts a call that raises in the body of the method" do
    result = CoverageSpecs.method_coverage(<<~'RUBY')
      class CoverageSpecs::Raising
        def raising; raise "in the body"; end
      end
      begin
        CoverageSpecs::Raising.new.raising
      rescue RuntimeError
      end
    RUBY

    result.should == {
      [CoverageSpecs::Raising, :raising, 2, 2, 2, 39] => 1
    }
  end

  it "does not count a call that raises an ArgumentError for its arguments" do
    result = CoverageSpecs.method_coverage(<<~'RUBY')
      class CoverageSpecs::Strict
        def positional(a); end
        def keyword(a:); end
      end
      begin
        CoverageSpecs::Strict.new.positional(1, 2)
      rescue ArgumentError
      end
      begin
        CoverageSpecs::Strict.new.keyword
      rescue ArgumentError
      end
    RUBY

    result.should == {
      [CoverageSpecs::Strict, :positional, 2, 2, 2, 24] => 0,
      [CoverageSpecs::Strict, :keyword, 3, 2, 3, 22] => 0
    }
  end

  it "does not count a call that raises while evaluating a default argument" do
    result = CoverageSpecs.method_coverage(<<~'RUBY')
      class CoverageSpecs::Default
        def default(a = raise("in the default")); end
      end
      begin
        CoverageSpecs::Default.new.default
      rescue RuntimeError
      end
    RUBY

    result.should == {
      [CoverageSpecs::Default, :default, 2, 2, 2, 47] => 0
    }
  end
end
