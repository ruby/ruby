describe :instance_method, shared: true do
  ruby_version_is("2.7") do
    context("when second argument is falsy") do
      it "raises an error when the receiver does not own the method" do
        -> { Object.send(@method, :raise, false) }
          .should raise_error(NameError, "method `raise' is not directly defined on `Object'")
      end

      it "raises an error when the method is only defined in a prepended module" do
        klass = Class.new do
          prepend(Module.new { def foo; end })
        end

        klass.send(@method, :foo, true)
        -> { klass.send(@method, :foo, false) }
          .should raise_error(NameError, /\Amethod `foo' is not directly defined on `.*'\z/)
      end

      it "returns the method on the receiver when the method is shadowed by prepend" do
        klass = Class.new do
          mod = Module.new do
            def foo
              :from_prepend
            end
          end
          prepend(mod)

          def foo
            :from_klass
          end
        end

        instance = klass.new
        klass.send(@method, :foo, false).bind(instance).call.should == :from_klass
        klass.send(@method, :foo, nil).bind(instance).call.should == :from_klass
        klass.send(@method, :foo, true).bind(instance).call.should == :from_prepend
      end
    end
  end
end
