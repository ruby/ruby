module Ruby
  module Signature
    class InvalidTypeApplicationError < StandardError
      attr_reader :type_name
      attr_reader :args
      attr_reader :params
      attr_reader :location

      def initialize(type_name:, args:, params:, location:)
        @type_name = type_name
        @args = args
        @params = params
        @location = location
        super "#{Location.to_string location}: #{type_name} expects parameters [#{params.each.map(&:name).join(", ")}], but given args [#{args.join(", ")}]"
      end

      def self.check!(type_name:, args:, params:, location:)
        unless args.size == params.size
          raise new(type_name: type_name, args: args, params: params, location: location)
        end
      end
    end

    class InvalidExtensionParameterError < StandardError
      attr_reader :type_name
      attr_reader :extension_name
      attr_reader :location
      attr_reader :extension_params
      attr_reader :class_params

      def initialize(type_name:, extension_name:, extension_params:, class_params:, location:)
        @type_name = type_name
        @extension_name = extension_name
        @extension_params = extension_params
        @class_params = class_params
        @location = location

        super "#{Location.to_string location}: Expected #{class_params.size} parameters to #{type_name} (#{extension_name}) but has #{extension_params.size} parameters"
      end

      def self.check!(type_name:, extension_name:, extension_params:, class_params:, location:)
        unless extension_params.size == class_params.size
          raise new(type_name: type_name,
                    extension_name: extension_name,
                    extension_params: extension_params,
                    class_params: class_params,
                    location: location)
        end
      end
    end

    class RecursiveAncestorError < StandardError
      attr_reader :ancestors
      attr_reader :location

      def initialize(ancestors:, location:)
        last = case last = ancestors.last
               when Definition::Ancestor::Singleton
                 "singleton(#{last.name})"
               when Definition::Ancestor::Instance
                 if last.args.empty?
                   last.name.to_s
                 else
                   "#{last.name}[#{last.args.join(", ")}]"
                 end
               end

        super "#{Location.to_string location}: Detected recursive ancestors: #{last}"
      end

      def self.check!(self_ancestor, ancestors:, location:)
        case self_ancestor
        when Definition::Ancestor::Instance
          if ancestors.any? {|a| a.is_a?(Definition::Ancestor::Instance) && a.name == self_ancestor.name }
            raise new(ancestors: ancestors + [self_ancestor], location: location)
          end
        when Definition::Ancestor::Singleton
          if ancestors.include?(self_ancestor)
            raise new(ancestors: ancestors + [self_ancestor], location: location)
          end
        end
      end
    end

    class NoTypeFoundError < StandardError
      attr_reader :type_name
      attr_reader :location

      def initialize(type_name:, location:)
        @type_name = type_name
        @location = location

        super "#{Location.to_string location}: Could not find #{type_name}"
      end

      def self.check!(type_name, env:, location:)
        env.find_type_decl(type_name) or
          raise new(type_name: type_name, location: location)

        type_name
      end
    end

    class DuplicatedMethodDefinitionError < StandardError
      attr_reader :decl
      attr_reader :location

      def initialize(decl:, name:, location:)
        decl_str = case decl
                   when AST::Declarations::Interface, AST::Declarations::Class, AST::Declarations::Module
                     decl.name.to_s
                   when AST::Declarations::Extension
                     "#{decl.name} (#{decl.extension_name})"
                   end

        super "#{Location.to_string location}: #{decl_str} has duplicated method definition: #{name}"
      end

      def self.check!(decl:, methods:, name:, location:)
        if methods.key?(name)
          raise new(decl: decl, name: name, location: location)
        end
      end
    end

    class UnknownMethodAliasError < StandardError
      attr_reader :original_name
      attr_reader :aliased_name
      attr_reader :location

      def initialize(original_name:, aliased_name:, location:)
        @original_name = original_name
        @aliased_name = aliased_name
        @location = location

        super "#{Location.to_string location}: Unknown method alias name: #{original_name} => #{aliased_name}"
      end

      def self.check!(methods:, original_name:, aliased_name:, location:)
        unless methods.key?(original_name)
          raise new(original_name: original_name, aliased_name: aliased_name, location: location)
        end
      end
    end

    class DuplicatedDeclarationError < StandardError
      attr_reader :name
      attr_reader :decls

      def initialize(name, *decls)
        @name = name
        @decls = decls

        super "#{Location.to_string decls.last.location}: Duplicated declaration: #{name}"
      end
    end

    class InvalidVarianceAnnotationError < StandardError
      MethodTypeError = Struct.new(:method_name, :method_type, :param, keyword_init: true)
      InheritanceError = Struct.new(:super_class, :param, keyword_init: true)
      MixinError = Struct.new(:include_member, :param, keyword_init: true)

      attr_reader :decl
      attr_reader :errors

      def initialize(decl:, errors:)
        @decl = decl
        @errors = errors

        message = [
          "#{Location.to_string decl.location}: Invalid variance annotation: #{decl.name}"
        ]

        errors.each do |error|
          case error
          when MethodTypeError
            message << "  MethodTypeError (#{error.param.name}): on `#{error.method_name}` #{error.method_type.to_s} (#{error.method_type.location&.start_line})"
          when InheritanceError
            message << "  InheritanceError: #{error.super_class}"
          when MixinError
            message << "  MixinError: #{error.include_member.name} (#{error.include_member.location&.start_line})"
          end
        end

        super message.join("\n")
      end
    end
  end
end
