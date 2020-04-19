module Ruby
  module Signature
    module Test
      module Spy
        def self.singleton_method(object, method_name)
          spy = SingletonSpy.new(object: object, method_name: method_name)

          if block_given?
            begin
              spy.setup
              yield spy
            ensure
              spy.reset
            end
          else
            spy
          end
        end

        def self.instance_method(mod, method_name)
          spy = InstanceSpy.new(mod: mod, method_name: method_name)

          if block_given?
            begin
              spy.setup
              yield spy
            ensure
              spy.reset
            end
          else
            spy
          end
        end

        def self.wrap(object, method_name)
          spy = WrapSpy.new(object: object, method_name: method_name)

          if block_given?
            begin
              yield spy, spy.wrapped_object
            end
          else
            spy
          end
        end

        class SingletonSpy
          attr_accessor :callback
          attr_reader :method_name
          attr_reader :object

          def initialize(object:, method_name:)
            @object = object
            @method_name = method_name
            @callback = -> (_) { }
          end

          def setup
            spy = self

            object.singleton_class.class_eval do
              remove_method spy.method_name
              define_method spy.method_name, spy.spy()
            end
          end

          def spy()
            spy = self

            -> (*args, &block) do
              return_value = nil
              exception = nil
              block_calls = []

              spy_block = if block
                            Object.new.instance_eval do |fresh|
                              -> (*block_args) do
                                block_exn = nil
                                block_return = nil

                                begin
                                  block_return = if self.equal?(fresh)
                                                   # no instance eval
                                                   block.call(*block_args)
                                                 else
                                                   self.instance_exec(*block_args, &block)
                                                 end
                                rescue Exception => exn
                                  block_exn = exn
                                end

                                block_calls << ArgumentsReturn.new(
                                  arguments: block_args,
                                  return_value: block_return,
                                  exception: block_exn
                                )

                                if block_exn
                                  raise block_exn
                                else
                                  block_return
                                end
                              end.ruby2_keywords
                            end
                          end

              begin
                return_value = super(*args, &spy_block)
              rescue Exception => exn
                exception = exn
              end

              trace = CallTrace.new(
                method_name: spy.method_name,
                method_call: ArgumentsReturn.new(
                  arguments: args,
                  return_value: return_value,
                  exception: exception,
                ),
                block_calls: block_calls,
                block_given: block != nil
              )

              spy.callback.call(trace)

              if exception
                raise exception
              else
                return_value
              end
            end.ruby2_keywords
          end

          def reset
            if object.singleton_class.methods.include?(method_name)
              object.singleton_class.remove_method method_name
            end
          end
        end

        class InstanceSpy
          attr_accessor :callback
          attr_reader :mod
          attr_reader :method_name
          attr_reader :original_method

          def initialize(mod:, method_name:)
            @mod = mod
            @method_name = method_name
            @original_method = mod.instance_method(method_name)
            @callback = -> (_) { }
          end

          def setup
            spy = self

            mod.class_eval do
              remove_method spy.method_name
              define_method spy.method_name, spy.spy()
            end
          end

          def reset
            spy = self

            mod.class_eval do
              remove_method spy.method_name
              define_method spy.method_name, spy.original_method
            end
          end

          def spy
            spy = self

            -> (*args, &block) do
              return_value = nil
              exception = nil
              block_calls = []

              spy_block = if block
                            Object.new.instance_eval do |fresh|
                              -> (*block_args) do
                                block_exn = nil
                                block_return = nil

                                begin
                                  block_return = if self.equal?(fresh)
                                                   # no instance eval
                                                   block.call(*block_args)
                                                 else
                                                   self.instance_exec(*block_args, &block)
                                                 end
                                rescue Exception => exn
                                  block_exn = exn
                                end

                                block_calls << ArgumentsReturn.new(
                                  arguments: block_args,
                                  return_value: block_return,
                                  exception: block_exn
                                )

                                if block_exn
                                  raise block_exn
                                else
                                  block_return
                                end
                              end.ruby2_keywords
                            end
                          end

              begin
                return_value = spy.original_method.bind_call(self, *args, &spy_block)
              rescue Exception => exn
                exception = exn
              end

              trace = CallTrace.new(
                method_name: spy.method_name,
                method_call: ArgumentsReturn.new(
                  arguments: args,
                  return_value: return_value,
                  exception: exception,
                  ),
                block_calls: block_calls,
                block_given: block != nil
              )

              spy.callback.call(trace)

              if exception
                raise exception
              else
                return_value
              end
            end.ruby2_keywords
          end
        end

        class WrapSpy
          attr_accessor :callback
          attr_reader :object
          attr_reader :method_name

          def initialize(object:, method_name:)
            @callback = -> (_) { }
            @object = object
            @method_name = method_name
          end

          def wrapped_object
            spy = self

            Class.new(BasicObject) do
              define_method(:method_missing) do |name, *args, &block|
                spy.object.__send__(name, *args, &block)
              end

              define_method(spy.method_name, -> (*args, &block) {
                return_value = nil
                exception = nil
                block_calls = []

                spy_block = if block
                              Object.new.instance_eval do |fresh|
                                -> (*block_args) do
                                  block_exn = nil
                                  block_return = nil

                                  begin
                                    block_return = if self.equal?(fresh)
                                                     # no instance eval
                                                     block.call(*block_args)
                                                   else
                                                     self.instance_exec(*block_args, &block)
                                                   end
                                  rescue Exception => exn
                                    block_exn = exn
                                  end

                                  block_calls << ArgumentsReturn.new(
                                    arguments: block_args,
                                    return_value: block_return,
                                    exception: block_exn
                                  )

                                  if block_exn
                                    raise block_exn
                                  else
                                    block_return
                                  end
                                end.ruby2_keywords
                              end
                            end

                begin
                  return_value = spy.object.__send__(spy.method_name, *args, &spy_block)
                rescue ::Exception => exn
                  exception = exn
                end

                trace = CallTrace.new(
                  method_name: spy.method_name,
                  method_call: ArgumentsReturn.new(
                    arguments: args,
                    return_value: return_value,
                    exception: exception,
                    ),
                  block_calls: block_calls,
                  block_given: block != nil
                )

                spy.callback.call(trace)

                if exception
                  spy.object.__send__(:raise, exception)
                else
                  return_value
                end
              }.ruby2_keywords)
            end.new()
          end
        end
      end
    end
  end
end
