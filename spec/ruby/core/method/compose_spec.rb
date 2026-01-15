require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../proc/shared/compose'

describe "Method#<<" do
  it "returns a Proc that is the composition of self and the passed Proc" do
    succ = MethodSpecs::Composition.new.method(:succ)
    upcase = proc { |s| s.upcase }

    (succ << upcase).call('Ruby').should == "RUBZ"
  end

  it "calls passed Proc with arguments and then calls self with result" do
    pow_2_proc = proc { |x| x * x }
    double_proc = proc { |x| x + x }

    pow_2_method = MethodSpecs::Composition.new.method(:pow_2)
    double_method = MethodSpecs::Composition.new.method(:double)

    (pow_2_method << double_proc).call(2).should == 16
    (double_method << pow_2_proc).call(2).should == 8
  end

  it "accepts any callable object" do
    inc = MethodSpecs::Composition.new.method(:inc)

    double = Object.new
    def double.call(n); n * 2; end

    (inc << double).call(3).should == 7
  end

  it_behaves_like :proc_compose, :<<, -> { MethodSpecs::Composition.new.method(:upcase) }

  describe "composition" do
    it "is a lambda" do
      pow_2 = MethodSpecs::Composition.new.method(:pow_2)
      double = proc { |x| x + x }

      (pow_2 << double).is_a?(Proc).should == true
      (pow_2 << double).should_not.lambda?
    end

    it "may accept multiple arguments" do
      inc = MethodSpecs::Composition.new.method(:inc)
      mul = proc { |n, m| n * m }

      (inc << mul).call(2, 3).should == 7
    end
  end
end

describe "Method#>>" do
  it "returns a Proc that is the composition of self and the passed Proc" do
    upcase = proc { |s| s.upcase }
    succ = MethodSpecs::Composition.new.method(:succ)

    (succ >> upcase).call('Ruby').should == "RUBZ"
  end

  it "calls passed Proc with arguments and then calls self with result" do
    pow_2_proc = proc { |x| x * x }
    double_proc = proc { |x| x + x }

    pow_2_method = MethodSpecs::Composition.new.method(:pow_2)
    double_method = MethodSpecs::Composition.new.method(:double)

    (pow_2_method >> double_proc).call(2).should == 8
    (double_method >> pow_2_proc).call(2).should == 16
  end

  it "accepts any callable object" do
    inc = MethodSpecs::Composition.new.method(:inc)

    double = Object.new
    def double.call(n); n * 2; end

    (inc >> double).call(3).should == 8
  end

  it_behaves_like :proc_compose, :>>, -> { MethodSpecs::Composition.new.method(:upcase) }

  describe "composition" do
    it "is a lambda" do
      pow_2 = MethodSpecs::Composition.new.method(:pow_2)
      double = proc { |x| x + x }

      (pow_2 >> double).is_a?(Proc).should == true
      (pow_2 >> double).should.lambda?
    end

    it "may accept multiple arguments" do
      mul = MethodSpecs::Composition.new.method(:mul)
      inc = proc { |n| n + 1 }

      (mul >> inc).call(2, 3).should == 7
    end
  end
end
