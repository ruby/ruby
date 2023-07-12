require_relative '../../spec_helper'

describe "Symbol#to_proc" do
  it "returns a new Proc" do
    proc = :to_s.to_proc
    proc.should be_kind_of(Proc)
  end

  it "sends self to arguments passed when calling #call on the Proc" do
    obj = mock("Receiving #to_s")
    obj.should_receive(:to_s).and_return("Received #to_s")
    :to_s.to_proc.call(obj).should == "Received #to_s"
  end

  it "returns a Proc with #lambda? true" do
    pr = :to_s.to_proc
    pr.should.lambda?
  end

  it "produces a Proc with arity -2" do
    pr = :to_s.to_proc
    pr.arity.should == -2
  end

  it "produces a Proc that always returns [[:req], [:rest]] for #parameters" do
    pr = :to_s.to_proc
    pr.parameters.should == [[:req], [:rest]]
  end

  ruby_version_is "3.2" do
    it "only calls public methods" do
      body = proc do
        public def pub; @a << :pub end
        protected def pro; @a << :pro end
        private def pri; @a << :pri end
        attr_reader :a
      end

      @a = []
      singleton_class.class_eval(&body)
      tap(&:pub)
      proc{tap(&:pro)}.should raise_error(NoMethodError, /protected method `pro' called/)
      proc{tap(&:pri)}.should raise_error(NoMethodError, /private method `pri' called/)
      @a.should == [:pub]

      @a = []
      c = Class.new(&body)
      o = c.new
      o.instance_variable_set(:@a, [])
      o.tap(&:pub)
      proc{tap(&:pro)}.should raise_error(NoMethodError, /protected method `pro' called/)
      proc{o.tap(&:pri)}.should raise_error(NoMethodError, /private method `pri' called/)
      o.a.should == [:pub]
    end
  end

  it "raises an ArgumentError when calling #call on the Proc without receiver" do
    -> {
      :object_id.to_proc.call
    }.should raise_error(ArgumentError, /no receiver given|wrong number of arguments \(given 0, expected 1\+\)/)
  end

  it "passes along the block passed to Proc#call" do
    klass = Class.new do
      def m
        yield
      end

      def to_proc
        :m.to_proc.call(self) { :value }
      end
    end
    klass.new.to_proc.should == :value
  end

  it "produces a proc with source location nil" do
    pr = :to_s.to_proc
    pr.source_location.should == nil
  end
end
