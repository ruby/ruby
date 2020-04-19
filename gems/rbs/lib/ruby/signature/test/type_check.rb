module Ruby
  module Signature
    module Test
      class TypeCheck
        attr_reader :self_class
        attr_reader :builder

        def initialize(self_class:, builder:)
          @self_class = self_class
          @builder = builder
        end

        def method_call(method_name, method_type, call, errors:)
          args(method_name, method_type, method_type.type, call.method_call, errors, type_error: Errors::ArgumentTypeError, argument_error: Errors::ArgumentError)
          self.return(method_name, method_type, method_type.type, call.method_call, errors, return_error: Errors::ReturnTypeError)

          if method_type.block
            case
            when !call.block_calls.empty?
              call.block_calls.each do |block_call|
                args(method_name, method_type, method_type.block.type, block_call, errors, type_error: Errors::BlockArgumentTypeError, argument_error: Errors::BlockArgumentError)
                self.return(method_name, method_type, method_type.block.type, block_call, errors, return_error: Errors::BlockReturnTypeError)
              end
            when !call.block_given
              # Block is not given
              if method_type.block.required
                errors << Errors::MissingBlockError.new(klass: self_class, method_name: method_name, method_type: method_type)
              end
            else
              # Block is given, but not yielded
            end
          else
            if call.block_given
              errors << Errors::UnexpectedBlockError.new(klass: self_class, method_name: method_name, method_type: method_type)
            end
          end

          errors
        end

        def args(method_name, method_type, fun, call, errors, type_error:, argument_error:)
          test = zip_args(call.arguments, fun) do |val, param|
            unless self.value(val, param.type)
              errors << type_error.new(klass: self_class,
                                       method_name: method_name,
                                       method_type: method_type,
                                       param: param,
                                       value: val)
            end
          end

          unless test
            errors << argument_error.new(klass: self_class,
                                         method_name: method_name,
                                         method_type: method_type)
          end
        end

        def return(method_name, method_type, fun, call, errors, return_error:)
          unless call.exception
            unless value(call.return_value, fun.return_type)
              errors << return_error.new(klass: self_class,
                                         method_name: method_name,
                                         method_type: method_type,
                                         type: fun.return_type,
                                         value: call.return_value)
            end
          end
        end

        def zip_keyword_args(hash, fun)
          fun.required_keywords.each do |name, param|
            if hash.key?(name)
              yield(hash[name], param)
            else
              return false
            end
          end

          fun.optional_keywords.each do |name, param|
            if hash.key?(name)
              yield(hash[name], param)
            end
          end

          hash.each do |name, value|
            next if fun.required_keywords.key?(name)
            next if fun.optional_keywords.key?(name)

            if fun.rest_keywords
              yield value, fun.rest_keywords
            else
              return false
            end
          end

          true
        end

        def keyword?(value)
          value.is_a?(Hash) && value.keys.all? {|key| key.is_a?(Symbol) }
        end

        def zip_args(args, fun, &block)
          case
          when args.empty?
            if fun.required_positionals.empty? && fun.trailing_positionals.empty? && fun.required_keywords.empty?
              true
            else
              false
            end
          when !fun.required_positionals.empty?
            yield_self do
              param, fun_ = fun.drop_head
              yield(args.first, param)
              zip_args(args.drop(1), fun_, &block)
            end
          when fun.has_keyword?
            yield_self do
              hash = args.last
              if keyword?(hash)
                zip_keyword_args(hash, fun, &block) &&
                  zip_args(args.take(args.size - 1),
                           fun.update(required_keywords: {}, optional_keywords: {}, rest_keywords: nil),
                           &block)
              else
                fun.required_keywords.empty? &&
                  zip_args(args,
                           fun.update(required_keywords: {}, optional_keywords: {}, rest_keywords: nil),
                           &block)
              end
            end
          when !fun.trailing_positionals.empty?
            yield_self do
              param, fun_ = fun.drop_tail
              yield(args.last, param)
              zip_args(args.take(args.size - 1), fun_, &block)
            end
          when !fun.optional_positionals.empty?
            yield_self do
              param, fun_ = fun.drop_head
              yield(args.first, param)
              zip_args(args.drop(1), fun_, &block)
            end
          when fun.rest_positionals
            yield_self do
              yield(args.first, fun.rest_positionals)
              zip_args(args.drop(1), fun, &block)
            end
          else
            false
          end
        end

        def value(val, type)
          case type
          when Types::Bases::Any
            true
          when Types::Bases::Bool
            true
          when Types::Bases::Top
            true
          when Types::Bases::Bottom
            false
          when Types::Bases::Void
            true
          when Types::Bases::Self
            Test.call(val, IS_AP, self_class)
          when Types::Bases::Nil
            Test.call(val, IS_AP, ::NilClass)
          when Types::Bases::Class
            Test.call(val, IS_AP, Class)
          when Types::Bases::Instance
            Test.call(val, IS_AP, self_class)
          when Types::ClassInstance
            klass = Object.const_get(type.name.to_s)
            case
            when klass == ::Array
              Test.call(val, IS_AP, klass) && val.all? {|v| value(v, type.args[0]) }
            when klass == ::Hash
              Test.call(val, IS_AP, klass) && val.all? {|k, v| value(k, type.args[0]) && value(v, type.args[1]) }
            when klass == ::Range
              Test.call(val, IS_AP, klass) && value(val.begin, type.args[0]) && value(val.end, type.args[0])
            when klass == ::Enumerator
              if Test.call(val, IS_AP, klass)
                case val.size
                when Float::INFINITY
                  values = []
                  ret = self
                  val.lazy.take(10).each do |*args|
                    values << args
                    nil
                  end
                else
                  values = []
                  ret = val.each do |*args|
                    values << args
                    nil
                  end
                end

                values.all? do |v|
                  if v.size == 1
                    # Only one block argument.
                    value(v[0], type.args[0]) || value(v, type.args[0])
                  else
                    value(v, type.args[0])
                  end
                end &&
                  if ret.equal?(self)
                    type.args[1].is_a?(Types::Bases::Bottom)
                  else
                    value(ret, type.args[1])
                  end
              end
            else
              Test.call(val, IS_AP, klass)
            end
          when Types::ClassSingleton
            klass = Object.const_get(type.name.to_s)
            val == klass
          when Types::Interface
            methods = Set.new(Test.call(val, METHODS))
            decl = builder.env.find_class(type.name)
            if (definition = builder.build_interface(type.name, decl))
              definition.methods.each_key.all? do |method_name|
                methods.member?(method_name)
              end
            end
          when Types::Variable
            true
          when Types::Literal
            val == type.literal
          when Types::Union
            type.types.any? {|type| value(val, type) }
          when Types::Intersection
            type.types.all? {|type| value(val, type) }
          when Types::Optional
            Test.call(val, IS_AP, ::NilClass) || value(val, type.type)
          when Types::Alias
            value(val, builder.expand_alias(type.name))
          when Types::Tuple
            Test.call(val, IS_AP, ::Array) &&
              type.types.map.with_index {|ty, index| value(val[index], ty) }.all?
          when Types::Record
            Test::call(val, IS_AP, ::Hash)
          when Types::Proc
            Test::call(val, IS_AP, ::Proc)
          else
            false
          end
        end
      end
    end
  end
end
