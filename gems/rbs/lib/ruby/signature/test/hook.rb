require "ruby/signature"
require "pp"

module Ruby
  module Signature
    module Test
      class Hook
        class Error < Exception
          attr_reader :errors

          def initialize(errors)
            @errors = errors
            super "Type error detected: [#{errors.map {|e| Errors.to_string(e) }.join(", ")}]"
          end
        end

        attr_reader :env
        attr_reader :logger

        attr_reader :instance_module
        attr_reader :instance_methods
        attr_reader :singleton_module
        attr_reader :singleton_methods

        attr_reader :klass
        attr_reader :errors

        def builder
          @builder ||= DefinitionBuilder.new(env: env)
        end

        def typecheck
          @typecheck ||= TypeCheck.new(self_class: klass, builder: builder)
        end

        def initialize(env, klass, logger:, raise_on_error: false)
          @env = env
          @logger = logger
          @klass = klass

          @instance_module = Module.new
          @instance_methods = []

          @singleton_module = Module.new
          @singleton_methods = []

          @errors = []

          @raise_on_error = raise_on_error
        end

        def raise_on_error!(error = true)
          @raise_on_error = error
          self
        end

        def raise_on_error?
          @raise_on_error
        end

        def prepend!
          klass.prepend @instance_module
          klass.singleton_class.prepend @singleton_module

          if block_given?
            yield
            disable
          end

          self
        end

        def self.install(env, klass, logger:)
          new(env, klass, logger: logger).prepend!
        end

        def refinement
          klass = self.klass
          instance_module = self.instance_module
          singleton_module = self.singleton_module

          Module.new do
            refine klass do
              prepend instance_module
            end

            refine klass.singleton_class do
              prepend singleton_module
            end
          end
        end

        def verify_all
          type_name = Namespace.parse(klass.name).to_type_name.absolute!

          builder.build_instance(type_name).tap do |definition|
            definition.methods.each do |name, method|
              if method.defined_in.name.absolute! == type_name
                unless method.annotations.any? {|a| a.string == "rbs:test:skip" }
                  logger.info "Installing a hook on #{type_name}##{name}: #{method.method_types.join(" | ")}"
                  verify instance_method: name, types: method.method_types
                else
                  logger.info "Skipping test of #{type_name}##{name}"
                end
              end
            end
          end

          builder.build_singleton(type_name).tap do |definition|
            definition.methods.each do |name, method|
              if method.defined_in&.name&.absolute! == type_name || name == :new
                unless method.annotations.any? {|a| a.string == "rbs:test:skip" }
                  logger.info "Installing a hook on #{type_name}.#{name}: #{method.method_types.join(" | ")}"
                  verify singleton_method: name, types: method.method_types
                else
                  logger.info "Skipping test of #{type_name}.#{name}"
                end
              end
            end
          end

          self
        end

        def delegation(name, method_types, method_name)
          hook = self

          -> (*args, &block) do
            hook.logger.debug { "#{method_name} receives arguments: #{hook.inspect_(args)}" }

            block_calls = []

            if block
              original_block = block

              block = hook.call(Object.new, INSTANCE_EVAL) do |fresh_obj|
                ->(*as) do
                  hook.logger.debug { "#{method_name} receives block arguments: #{hook.inspect_(as)}" }

                  ret = if self.equal?(fresh_obj)
                          original_block[*as]
                        else
                          hook.call(self, INSTANCE_EXEC, *as, &original_block)
                        end

                  block_calls << ArgumentsReturn.new(
                    arguments: as,
                    return_value: ret,
                    exception: nil
                  )

                  hook.logger.debug { "#{method_name} returns from block: #{hook.inspect_(ret)}" }

                  ret
                end.ruby2_keywords
              end
            end

            method = hook.call(self, METHOD, name)
            klass = hook.call(self, CLASS)
            singleton_klass = begin
              hook.call(self, SINGLETON_CLASS)
            rescue TypeError
              nil
            end
            prepended = klass.ancestors.include?(hook.instance_module) || singleton_klass&.ancestors&.include?(hook.singleton_module)
            result = if prepended
                       method.super_method.call(*args, &block)
                     else
                       # Using refinement
                       method.call(*args, &block)
                     end

            hook.logger.debug { "#{method_name} returns: #{hook.inspect_(result)}" }

            call = CallTrace.new(method_call: ArgumentsReturn.new(arguments: args, return_value: result, exception: nil),
                                 block_calls: block_calls,
                                 block_given: block != nil)

            method_type_errors = method_types.map do |method_type|
              hook.typecheck.method_call(method_name, method_type, call, errors: [])
            end

            new_errors = []

            if method_type_errors.none?(&:empty?)
              if (best_errors = hook.find_best_errors(method_type_errors))
                new_errors.push(*best_errors)
              else
                new_errors << Errors::UnresolvedOverloadingError.new(
                  klass: hook.klass,
                  method_name: method_name,
                  method_types: method_types
                )
              end
            end

            unless new_errors.empty?
              new_errors.each do |error|
                hook.logger.error Errors.to_string(error)
              end

              hook.errors.push(*new_errors)

              if hook.raise_on_error?
                raise Error.new(new_errors)
              end
            end

            result
          end.ruby2_keywords
        end

        def verify(instance_method: nil, singleton_method: nil, types:)
          method_types = types.map do |type|
            case type
            when String
              Parser.parse_method_type(type)
            else
              type
            end
          end

          case
          when instance_method
            instance_methods << instance_method
            call(self.instance_module, DEFINE_METHOD, instance_method, &delegation(instance_method, method_types, "##{instance_method}"))
          when singleton_method
            call(self.singleton_module, DEFINE_METHOD, singleton_method, &delegation(singleton_method, method_types, ".#{singleton_method}"))
          end

          self
        end

        def find_best_errors(errorss)
          if errorss.size == 1
            errorss[0]
          else
            no_arity_errors = errorss.select do |errors|
              errors.none? do |error|
                error.is_a?(Errors::ArgumentError) ||
                  error.is_a?(Errors::BlockArgumentError) ||
                  error.is_a?(Errors::MissingBlockError) ||
                  error.is_a?(Errors::UnexpectedBlockError)
              end
            end

            unless no_arity_errors.empty?
              # Choose a error set which doesn't include arity error
              return no_arity_errors[0] if no_arity_errors.size == 1
            end
          end
        end

        def self.backtrace(skip: 2)
          raise
        rescue => exn
          exn.backtrace.drop(skip)
        end

        def run
          yield
          self
        ensure
          disable
        end

        def call(receiver, method, *args, &block)
          method.bind(receiver).call(*args, &block)
        end

        def inspect_(obj)
          Hook.inspect_(obj)
        end

        def self.inspect_(obj)
          obj.inspect
        rescue
          INSPECT.bind(obj).call()
        end

        def disable
          self.instance_module.remove_method(*instance_methods)
          self.singleton_module.remove_method(*singleton_methods)
          self
        end
      end
    end
  end
end
