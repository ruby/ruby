# frozen_string_literal: true

require 'prism'
require 'irb/completion'
require_relative 'type_analyzer'

module IRB
  module TypeCompletion
    class Completor < BaseCompletor # :nodoc:
      HIDDEN_METHODS = %w[Namespace TypeName] # defined by rbs, should be hidden

      class << self
        attr_accessor :last_completion_error
      end

      def inspect
        name = 'TypeCompletion::Completor'
        prism_info = "Prism: #{Prism::VERSION}"
        if Types.rbs_builder
          "#{name}(#{prism_info}, RBS: #{RBS::VERSION})"
        elsif Types.rbs_load_error
          "#{name}(#{prism_info}, RBS: #{Types.rbs_load_error.inspect})"
        else
          "#{name}(#{prism_info}, RBS: loading)"
        end
      end

      def completion_candidates(preposing, target, _postposing, bind:)
        @preposing = preposing
        verbose, $VERBOSE = $VERBOSE, nil
        code = "#{preposing}#{target}"
        @result = analyze code, bind
        name, candidates = candidates_from_result(@result)

        all_symbols_pattern = /\A[ -\/:-@\[-`\{-~]*\z/
        candidates.map(&:to_s).select { !_1.match?(all_symbols_pattern) && _1.start_with?(name) }.uniq.sort.map do
          target + _1[name.size..]
        end
      rescue SyntaxError, StandardError => e
        Completor.last_completion_error = e
        handle_error(e)
        []
      ensure
        $VERBOSE = verbose
      end

      def doc_namespace(preposing, matched, postposing, bind:)
        name = matched[/[a-zA-Z_0-9]*[!?=]?\z/]
        method_doc = -> type do
          type = type.types.find { _1.all_methods.include? name.to_sym }
          case type
          when Types::SingletonType
            "#{Types.class_name_of(type.module_or_class)}.#{name}"
          when Types::InstanceType
            "#{Types.class_name_of(type.klass)}##{name}"
          end
        end
        call_or_const_doc = -> type do
          if name =~ /\A[A-Z]/
            type = type.types.grep(Types::SingletonType).find { _1.module_or_class.const_defined?(name) }
            type.module_or_class == Object ? name : "#{Types.class_name_of(type.module_or_class)}::#{name}" if type
          else
            method_doc.call(type)
          end
        end

        value_doc = -> type do
          return unless type
          type.types.each do |t|
            case t
            when Types::SingletonType
              return Types.class_name_of(t.module_or_class)
            when Types::InstanceType
              return Types.class_name_of(t.klass)
            end
          end
          nil
        end

        case @result
        in [:call_or_const, type, _name, _self_call]
          call_or_const_doc.call type
        in [:const, type, _name, scope]
          if type
            call_or_const_doc.call type
          else
            value_doc.call scope[name]
          end
        in [:gvar, _name, scope]
          value_doc.call scope["$#{name}"]
        in [:ivar, _name, scope]
          value_doc.call scope["@#{name}"]
        in [:cvar, _name, scope]
          value_doc.call scope["@@#{name}"]
        in [:call, type, _name, _self_call]
          method_doc.call type
        in [:lvar_or_method, _name, scope]
          if scope.local_variables.include?(name)
            value_doc.call scope[name]
          else
            method_doc.call scope.self_type
          end
        else
        end
      end

      def candidates_from_result(result)
        candidates = case result
        in [:require, name]
          retrieve_files_to_require_from_load_path
        in [:require_relative, name]
          retrieve_files_to_require_relative_from_current_dir
        in [:call_or_const, type, name, self_call]
          ((self_call ? type.all_methods : type.methods).map(&:to_s) - HIDDEN_METHODS) | type.constants
        in [:const, type, name, scope]
          if type
            scope_constants = type.types.flat_map do |t|
              scope.table_module_constants(t.module_or_class) if t.is_a?(Types::SingletonType)
            end
            (scope_constants.compact | type.constants.map(&:to_s)).sort
          else
            scope.constants.sort | ReservedWords
          end
        in [:ivar, name, scope]
          ivars = scope.instance_variables.sort
          name == '@' ? ivars + scope.class_variables.sort : ivars
        in [:cvar, name, scope]
          scope.class_variables
        in [:gvar, name, scope]
          scope.global_variables
        in [:symbol, name]
          Symbol.all_symbols.map { _1.inspect[1..] }
        in [:call, type, name, self_call]
          (self_call ? type.all_methods : type.methods).map(&:to_s) - HIDDEN_METHODS
        in [:lvar_or_method, name, scope]
          scope.self_type.all_methods.map(&:to_s) | scope.local_variables | ReservedWords
        else
          []
        end
        [name || '', candidates]
      end

      def analyze(code, binding = Object::TOPLEVEL_BINDING)
        # Workaround for https://github.com/ruby/prism/issues/1592
        return if code.match?(/%[qQ]\z/)

        ast = Prism.parse(code, scopes: [binding.local_variables]).value
        name = code[/(@@|@|\$)?\w*[!?=]?\z/]
        *parents, target_node = find_target ast, code.bytesize - name.bytesize
        return unless target_node

        calculate_scope = -> { TypeAnalyzer.calculate_target_type_scope(binding, parents, target_node).last }
        calculate_type_scope = ->(node) { TypeAnalyzer.calculate_target_type_scope binding, [*parents, target_node], node }

        case target_node
        when Prism::StringNode, Prism::InterpolatedStringNode
          call_node, args_node = parents.last(2)
          return unless call_node.is_a?(Prism::CallNode) && call_node.receiver.nil?
          return unless args_node.is_a?(Prism::ArgumentsNode) && args_node.arguments.size == 1

          case call_node.name
          when :require
            [:require, name.rstrip]
          when :require_relative
            [:require_relative, name.rstrip]
          end
        when Prism::SymbolNode
          if parents.last.is_a? Prism::BlockArgumentNode # method(&:target)
            receiver_type, _scope = calculate_type_scope.call target_node
            [:call, receiver_type, name, false]
          else
            [:symbol, name] unless name.empty?
          end
        when Prism::CallNode
          return [:lvar_or_method, name, calculate_scope.call] if target_node.receiver.nil?

          self_call = target_node.receiver.is_a? Prism::SelfNode
          op = target_node.call_operator
          receiver_type, _scope = calculate_type_scope.call target_node.receiver
          receiver_type = receiver_type.nonnillable if op == '&.'
          [op == '::' ? :call_or_const : :call, receiver_type, name, self_call]
        when Prism::LocalVariableReadNode, Prism::LocalVariableTargetNode
          [:lvar_or_method, name, calculate_scope.call]
        when Prism::ConstantReadNode, Prism::ConstantTargetNode
          if parents.last.is_a? Prism::ConstantPathNode
            path_node = parents.last
            if path_node.parent # A::B
              receiver, scope = calculate_type_scope.call(path_node.parent)
              [:const, receiver, name, scope]
            else # ::A
              scope = calculate_scope.call
              [:const, Types::SingletonType.new(Object), name, scope]
            end
          else
            [:const, nil, name, calculate_scope.call]
          end
        when Prism::GlobalVariableReadNode, Prism::GlobalVariableTargetNode
          [:gvar, name, calculate_scope.call]
        when Prism::InstanceVariableReadNode, Prism::InstanceVariableTargetNode
          [:ivar, name, calculate_scope.call]
        when Prism::ClassVariableReadNode, Prism::ClassVariableTargetNode
          [:cvar, name, calculate_scope.call]
        end
      end

      def find_target(node, position)
        location = (
          case node
          when Prism::CallNode
            node.message_loc
          when Prism::SymbolNode
            node.value_loc
          when Prism::StringNode
            node.content_loc
          when Prism::InterpolatedStringNode
            node.closing_loc if node.parts.empty?
          end
        )
        return [node] if location&.start_offset == position

        node.compact_child_nodes.each do |n|
          match = find_target(n, position)
          next unless match
          match.unshift node
          return match
        end

        [node] if node.location.start_offset == position
      end

      def handle_error(e)
      end
    end
  end
end
