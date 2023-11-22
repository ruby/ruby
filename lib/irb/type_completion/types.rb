# frozen_string_literal: true

require_relative 'methods'

module IRB
  module TypeCompletion
    module Types
      OBJECT_TO_TYPE_SAMPLE_SIZE = 50

      singleton_class.attr_reader :rbs_builder, :rbs_load_error

      def self.preload_in_thread
        return if @preload_started

        @preload_started = true
        Thread.new do
          load_rbs_builder
        end
      end

      def self.load_rbs_builder
        require 'rbs'
        require 'rbs/cli'
        loader = RBS::CLI::LibraryOptions.new.loader
        loader.add path: Pathname('sig')
        @rbs_builder = RBS::DefinitionBuilder.new env: RBS::Environment.from_loader(loader).resolve_type_names
      rescue LoadError, StandardError => e
        @rbs_load_error = e
        nil
      end

      def self.class_name_of(klass)
        klass = klass.superclass if klass.singleton_class?
        Methods::MODULE_NAME_METHOD.bind_call klass
      end

      def self.rbs_search_method(klass, method_name, singleton)
        klass.ancestors.each do |ancestor|
          name = class_name_of ancestor
          next unless name && rbs_builder
          type_name = RBS::TypeName(name).absolute!
          definition = (singleton ? rbs_builder.build_singleton(type_name) : rbs_builder.build_instance(type_name)) rescue nil
          method = definition.methods[method_name] if definition
          return method if method
        end
        nil
      end

      def self.method_return_type(type, method_name)
        receivers = type.types.map do |t|
          case t
          in SingletonType
            [t, t.module_or_class, true]
          in InstanceType
            [t, t.klass, false]
          end
        end
        types = receivers.flat_map do |receiver_type, klass, singleton|
          method = rbs_search_method klass, method_name, singleton
          next [] unless method
          method.method_types.map do |method|
            from_rbs_type(method.type.return_type, receiver_type, {})
          end
        end
        UnionType[*types]
      end

      def self.rbs_methods(type, method_name, args_types, kwargs_type, has_block)
        return [] unless rbs_builder

        receivers = type.types.map do |t|
          case t
          in SingletonType
            [t, t.module_or_class, true]
          in InstanceType
            [t, t.klass, false]
          end
        end
        has_splat = args_types.include?(nil)
        methods_with_score = receivers.flat_map do |receiver_type, klass, singleton|
          method = rbs_search_method klass, method_name, singleton
          next [] unless method
          method.method_types.map do |method_type|
            score = 0
            score += 2 if !!method_type.block == has_block
            reqs = method_type.type.required_positionals
            opts = method_type.type.optional_positionals
            rest = method_type.type.rest_positionals
            trailings = method_type.type.trailing_positionals
            keyreqs = method_type.type.required_keywords
            keyopts = method_type.type.optional_keywords
            keyrest = method_type.type.rest_keywords
            args = args_types
            if kwargs_type&.any? && keyreqs.empty? && keyopts.empty? && keyrest.nil?
              kw_value_type = UnionType[*kwargs_type.values]
              args += [InstanceType.new(Hash, K: SYMBOL, V: kw_value_type)]
            end
            if has_splat
              score += 1 if args.count(&:itself) <= reqs.size + opts.size + trailings.size
            elsif reqs.size + trailings.size <= args.size && (rest || args.size <= reqs.size + opts.size + trailings.size)
              score += 2
              centers = args[reqs.size...-trailings.size]
              given = args.first(reqs.size) + centers.take(opts.size) + args.last(trailings.size)
              expected = (reqs + opts.take(centers.size) + trailings).map(&:type)
              if rest
                given << UnionType[*centers.drop(opts.size)]
                expected << rest.type
              end
              if given.any?
                score += given.zip(expected).count do |t, e|
                  e = from_rbs_type e, receiver_type
                  intersect?(t, e) || (intersect?(STRING, e) && t.methods.include?(:to_str)) || (intersect?(INTEGER, e) && t.methods.include?(:to_int)) || (intersect?(ARRAY, e) && t.methods.include?(:to_ary))
                end.fdiv(given.size)
              end
            end
            [[method_type, given || [], expected || []], score]
          end
        end
        max_score = methods_with_score.map(&:last).max
        methods_with_score.select { _2 == max_score }.map(&:first)
      end

      def self.intersect?(a, b)
        atypes = a.types.group_by(&:class)
        btypes = b.types.group_by(&:class)
        if atypes[SingletonType] && btypes[SingletonType]
          aa, bb = [atypes, btypes].map {|types| types[SingletonType].map(&:module_or_class) }
          return true if (aa & bb).any?
        end

        aa, bb = [atypes, btypes].map {|types| (types[InstanceType] || []).map(&:klass) }
        (aa.flat_map(&:ancestors) & bb).any?
      end

      def self.type_from_object(object)
        case object
        when Array
          InstanceType.new Array, { Elem: union_type_from_objects(object) }
        when Hash
          InstanceType.new Hash, { K: union_type_from_objects(object.keys), V: union_type_from_objects(object.values) }
        when Module
          SingletonType.new object
        else
          klass = Methods::OBJECT_SINGLETON_CLASS_METHOD.bind_call(object) rescue Methods::OBJECT_CLASS_METHOD.bind_call(object)
          InstanceType.new klass
        end
      end

      def self.union_type_from_objects(objects)
        values = objects.size <= OBJECT_TO_TYPE_SAMPLE_SIZE ? objects : objects.sample(OBJECT_TO_TYPE_SAMPLE_SIZE)
        klasses = values.map { Methods::OBJECT_CLASS_METHOD.bind_call(_1) }
        UnionType[*klasses.uniq.map { InstanceType.new _1 }]
      end

      class SingletonType
        attr_reader :module_or_class
        def initialize(module_or_class)
          @module_or_class = module_or_class
        end
        def transform() = yield(self)
        def methods() = @module_or_class.methods
        def all_methods() = methods | Kernel.methods
        def constants() = @module_or_class.constants
        def types() = [self]
        def nillable?() = false
        def nonnillable() = self
        def inspect
          "#{module_or_class}.itself"
        end
      end

      class InstanceType
        attr_reader :klass, :params
        def initialize(klass, params = {})
          @klass = klass
          @params = params
        end
        def transform() = yield(self)
        def methods() = rbs_methods.select { _2.public? }.keys | @klass.instance_methods
        def all_methods() = rbs_methods.keys | @klass.instance_methods | @klass.private_instance_methods
        def constants() = []
        def types() = [self]
        def nillable?() = (@klass == NilClass)
        def nonnillable() = self
        def rbs_methods
          name = Types.class_name_of(@klass)
          return {} unless name && Types.rbs_builder

          type_name = RBS::TypeName(name).absolute!
          Types.rbs_builder.build_instance(type_name).methods rescue {}
        end
        def inspect
          if params.empty?
            inspect_without_params
          else
            params_string = "[#{params.map { "#{_1}: #{_2.inspect}" }.join(', ')}]"
            "#{inspect_without_params}#{params_string}"
          end
        end
        def inspect_without_params
          if klass == NilClass
            'nil'
          elsif klass == TrueClass
            'true'
          elsif klass == FalseClass
            'false'
          else
            klass.singleton_class? ? klass.superclass.to_s : klass.to_s
          end
        end
      end

      NIL = InstanceType.new NilClass
      OBJECT = InstanceType.new Object
      TRUE = InstanceType.new TrueClass
      FALSE = InstanceType.new FalseClass
      SYMBOL = InstanceType.new Symbol
      STRING = InstanceType.new String
      INTEGER = InstanceType.new Integer
      RANGE = InstanceType.new Range
      REGEXP = InstanceType.new Regexp
      FLOAT = InstanceType.new Float
      RATIONAL = InstanceType.new Rational
      COMPLEX = InstanceType.new Complex
      ARRAY = InstanceType.new Array
      HASH = InstanceType.new Hash
      CLASS = InstanceType.new Class
      MODULE = InstanceType.new Module
      PROC = InstanceType.new Proc

      class UnionType
        attr_reader :types

        def initialize(*types)
          @types = []
          singletons = []
          instances = {}
          collect = -> type do
            case type
            in UnionType
              type.types.each(&collect)
            in InstanceType
              params = (instances[type.klass] ||= {})
              type.params.each do |k, v|
                (params[k] ||= []) << v
              end
            in SingletonType
              singletons << type
            end
          end
          types.each(&collect)
          @types = singletons.uniq + instances.map do |klass, params|
            InstanceType.new(klass, params.transform_values { |v| UnionType[*v] })
          end
        end

        def transform(&block)
          UnionType[*types.map(&block)]
        end

        def nillable?
          types.any?(&:nillable?)
        end

        def nonnillable
          UnionType[*types.reject { _1.is_a?(InstanceType) && _1.klass == NilClass }]
        end

        def self.[](*types)
          type = new(*types)
          if type.types.empty?
            OBJECT
          elsif type.types.size == 1
            type.types.first
          else
            type
          end
        end

        def methods() = @types.flat_map(&:methods).uniq
        def all_methods() = @types.flat_map(&:all_methods).uniq
        def constants() = @types.flat_map(&:constants).uniq
        def inspect() = @types.map(&:inspect).join(' | ')
      end

      BOOLEAN = UnionType[TRUE, FALSE]

      def self.array_of(*types)
        type = types.size >= 2 ? UnionType[*types] : types.first || OBJECT
        InstanceType.new Array, Elem: type
      end

      def self.from_rbs_type(return_type, self_type, extra_vars = {})
        case return_type
        when RBS::Types::Bases::Self
          self_type
        when RBS::Types::Bases::Bottom, RBS::Types::Bases::Nil
          NIL
        when RBS::Types::Bases::Any, RBS::Types::Bases::Void
          OBJECT
        when RBS::Types::Bases::Class
          self_type.transform do |type|
            case type
            in SingletonType
              InstanceType.new(self_type.module_or_class.is_a?(Class) ? Class : Module)
            in InstanceType
              SingletonType.new type.klass
            end
          end
          UnionType[*types]
        when RBS::Types::Bases::Bool
          BOOLEAN
        when RBS::Types::Bases::Instance
          self_type.transform do |type|
            if type.is_a?(SingletonType) && type.module_or_class.is_a?(Class)
              InstanceType.new type.module_or_class
            else
              OBJECT
            end
          end
        when RBS::Types::Union
          UnionType[*return_type.types.map { from_rbs_type _1, self_type, extra_vars }]
        when RBS::Types::Proc
          PROC
        when RBS::Types::Tuple
          elem = UnionType[*return_type.types.map { from_rbs_type _1, self_type, extra_vars }]
          InstanceType.new Array, Elem: elem
        when RBS::Types::Record
          InstanceType.new Hash, K: SYMBOL, V: OBJECT
        when RBS::Types::Literal
          InstanceType.new return_type.literal.class
        when RBS::Types::Variable
          if extra_vars.key? return_type.name
            extra_vars[return_type.name]
          elsif self_type.is_a? InstanceType
            self_type.params[return_type.name] || OBJECT
          elsif self_type.is_a? UnionType
            types = self_type.types.filter_map do |t|
              t.params[return_type.name] if t.is_a? InstanceType
            end
            UnionType[*types]
          else
            OBJECT
          end
        when RBS::Types::Optional
          UnionType[from_rbs_type(return_type.type, self_type, extra_vars), NIL]
        when RBS::Types::Alias
          case return_type.name.name
          when :int
            INTEGER
          when :boolish
            BOOLEAN
          when :string
            STRING
          else
            # TODO: ???
            OBJECT
          end
        when RBS::Types::Interface
          # unimplemented
          OBJECT
        when RBS::Types::ClassInstance
          klass = return_type.name.to_namespace.path.reduce(Object) { _1.const_get _2 }
          if return_type.args
            args = return_type.args.map { from_rbs_type _1, self_type, extra_vars }
            names = rbs_builder.build_singleton(return_type.name).type_params
            params = names.map.with_index { [_1, args[_2] || OBJECT] }.to_h
          end
          InstanceType.new klass, params || {}
        end
      end

      def self.method_return_bottom?(method)
        method.type.return_type.is_a? RBS::Types::Bases::Bottom
      end

      def self.match_free_variables(vars, types, values)
        accumulator = {}
        types.zip values do |t, v|
          _match_free_variable(vars, t, v, accumulator) if v
        end
        accumulator.transform_values { UnionType[*_1] }
      end

      def self._match_free_variable(vars, rbs_type, value, accumulator)
        case [rbs_type, value]
        in [RBS::Types::Variable,]
          (accumulator[rbs_type.name] ||= []) << value if vars.include? rbs_type.name
        in [RBS::Types::ClassInstance, InstanceType]
          names = rbs_builder.build_singleton(rbs_type.name).type_params
          names.zip(rbs_type.args).each do |name, arg|
            v = value.params[name]
            _match_free_variable vars, arg, v, accumulator if v
          end
        in [RBS::Types::Tuple, InstanceType] if value.klass == Array
          v = value.params[:Elem]
          rbs_type.types.each do |t|
            _match_free_variable vars, t, v, accumulator
          end
        in [RBS::Types::Record, InstanceType] if value.klass == Hash
          # TODO
        in [RBS::Types::Interface,]
          definition = rbs_builder.build_interface rbs_type.name
          convert = {}
          definition.type_params.zip(rbs_type.args).each do |from, arg|
            convert[from] = arg.name if arg.is_a? RBS::Types::Variable
          end
          return if convert.empty?
          ac = {}
          definition.methods.each do |method_name, method|
            return_type = method_return_type value, method_name
            method.defs.each do |method_def|
              interface_return_type = method_def.type.type.return_type
              _match_free_variable convert, interface_return_type, return_type, ac
            end
          end
          convert.each do |from, to|
            values = ac[from]
            (accumulator[to] ||= []).concat values if values
          end
        else
        end
      end
    end
  end
end
