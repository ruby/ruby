require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/basicobject/send'

describe "Kernel#public_send" do
  it "invokes the named public method" do
    class KernelSpecs::Foo
      def bar
        'done'
      end
    end
    KernelSpecs::Foo.new.public_send(:bar).should == 'done'
  end

  it "invokes the named alias of a public method" do
    class KernelSpecs::Foo
      def bar
        'done'
      end
      alias :aka :bar
    end
    KernelSpecs::Foo.new.public_send(:aka).should == 'done'
  end

  it "raises a NoMethodError if the method is protected" do
    class KernelSpecs::Foo
      protected
      def bar
        'done'
      end
    end
    -> { KernelSpecs::Foo.new.public_send(:bar)}.should raise_error(NoMethodError)
  end

  it "raises a NoMethodError if the named method is private" do
    class KernelSpecs::Foo
      private
      def bar
        'done2'
      end
    end
    -> {
      KernelSpecs::Foo.new.public_send(:bar)
    }.should raise_error(NoMethodError)
  end

  context 'called from own public method' do
    before do
      class << @receiver = Object.new
        def call_protected_method
          public_send :protected_method
        end

        def call_private_method
          public_send :private_method
        end

        protected

        def protected_method
          raise 'Should not called'
        end

        private

        def private_method
          raise 'Should not called'
        end
      end
    end

    it "raises a NoMethodError if the method is protected" do
      -> { @receiver.call_protected_method }.should raise_error(NoMethodError)
    end

    it "raises a NoMethodError if the method is private" do
      -> { @receiver.call_private_method }.should raise_error(NoMethodError)
    end
  end

  it "raises a NoMethodError if the named method is an alias of a private method" do
    class KernelSpecs::Foo
      private
      def bar
        'done2'
      end
      alias :aka :bar
    end
    -> {
      KernelSpecs::Foo.new.public_send(:aka)
    }.should raise_error(NoMethodError)
  end

  it "raises a NoMethodError if the named method is an alias of a protected method" do
    class KernelSpecs::Foo
      protected
      def bar
        'done2'
      end
      alias :aka :bar
    end
    -> {
      KernelSpecs::Foo.new.public_send(:aka)
    }.should raise_error(NoMethodError)
  end

  it "includes `public_send` in the backtrace when passed not enough arguments" do
    -> { public_send() }.should raise_error(ArgumentError) { |e| e.backtrace[0].should =~ /[`'](?:Kernel#)?public_send'/ }
  end

  it "includes `public_send` in the backtrace when passed a single incorrect argument" do
    -> { public_send(Object.new) }.should raise_error(TypeError) { |e| e.backtrace[0].should =~ /[`'](?:Kernel#)?public_send'/ }
  end

  it_behaves_like :basicobject_send, :public_send
end
