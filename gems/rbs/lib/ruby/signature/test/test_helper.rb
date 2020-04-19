module Ruby
  module Signature
    module Test
      module TypeAssertions
        module ClassMethods
          attr_reader :target

          def library(*libs)
            @libs = libs
            @env = nil
            @target = nil
          end

          def env
            @env ||= begin
                       loader = Ruby::Signature::EnvironmentLoader.new
                       (@libs || []).each do |lib|
                         loader.add library: lib
                       end

                       Ruby::Signature::Environment.new.tap do |env|
                         loader.load(env: env)
                       end
                     end
          end

          def builder
            @builder ||= DefinitionBuilder.new(env: env)
          end

          def testing(type_or_string)
            type = case type_or_string
                   when String
                     Ruby::Signature::Parser.parse_type(type_or_string, variables: [])
                   else
                     type_or_string
                   end

            definition = case type
                         when Types::ClassInstance
                           builder.build_instance(type.name)
                         when Types::ClassSingleton
                           builder.build_singleton(type.name)
                         else
                           raise "Test target should be class instance or class singleton: #{type}"
                         end

            @target = [type, definition]
          end
        end

        def self.included(base)
          base.extend ClassMethods
        end

        def env
          self.class.env
        end

        def builder
          self.class.builder
        end

        def targets
          @targets ||= []
        end

        def target
          targets.last || self.class.target
        end

        def testing(type_or_string)
          type = case type_or_string
                 when String
                   Ruby::Signature::Parser.parse_type(type_or_string, variables: [])
                 else
                   type_or_string
                 end

          definition = case type
                       when Types::ClassInstance
                         builder.build_instance(type.name)
                       when Types::ClassSingleton
                         builder.build_singleton(type.name)
                       else
                         raise "Test target should be class instance or class singleton: #{type}"
                       end

          targets.push [type, definition]

          if block_given?
            begin
              yield
            ensure
              targets.pop
            end
          else
            [type, definition]
          end
        end

        ruby2_keywords def assert_send_type(method_type, receiver, method, *args, &block)
          trace = []
          spy = Spy.wrap(receiver, method)
          spy.callback = -> (result) { trace << result }

          exception = nil

          begin
            spy.wrapped_object.__send__(method, *args, &block)
          rescue => exn
            exception = exn
          end

          mt = case method_type
               when String
                 Ruby::Signature::Parser.parse_method_type(method_type, variables: [])
               when Ruby::Signature::MethodType
                 method_type
               end

          typecheck = TypeCheck.new(self_class: receiver.class, builder: builder)
          errors = typecheck.method_call(method, mt, trace.last, errors: [])

          assert_empty errors.map {|x| Ruby::Signature::Test::Errors.to_string(x) }, "Call trace does not match with given method type: #{trace.last.inspect}"

          type, definition = target
          method_types = case
                         when definition.instance_type?
                           subst = Substitution.build(definition.declaration.type_params.each.map(&:name),
                                                      type.args)
                           definition.methods[method].method_types.map do |method_type|
                             method_type.sub(subst)
                           end
                         when definition.class_type?
                           definition.methods[method].method_types
                         end

          all_errors = method_types.map {|t| typecheck.method_call(method, t, trace.last, errors: []) }
          assert all_errors.any? {|es| es.empty? }, "Call trace does not match one of method definitions:\n  #{trace.last.inspect}\n  #{method_types.join(" | ")}"

          if exception
            raise exception
          end
        end

        ruby2_keywords def refute_send_type(method_type, receiver, method, *args, &block)
          trace = []
          spy = Spy.wrap(receiver, method)
          spy.callback = -> (result) { trace << result }

          exception = nil
          begin
            spy.wrapped_object.__send__(method, *args, &block)
          rescue Exception => exn
            exception = exn
          end

          mt = case method_type
               when String
                 Ruby::Signature::Parser.parse_method_type(method_type, variables: [])
               when Ruby::Signature::MethodType
                 method_type
               end

          mt = mt.update(block: if mt.block
                                  MethodType::Block.new(
                                    type: mt.block.type.with_return_type(Types::Bases::Any.new(location: nil)),
                                    required: mt.block.required
                                  )
                                end,
                         type: mt.type.with_return_type(Types::Bases::Any.new(location: nil)))

          typecheck = TypeCheck.new(self_class: receiver.class, builder: builder)
          errors = typecheck.method_call(method, mt, trace.last, errors: [])

          assert_operator exception, :is_a?, ::Exception
          assert_empty errors.map {|x| Ruby::Signature::Test::Errors.to_string(x) }

          exception
        end
      end
    end
  end
end
