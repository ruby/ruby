# frozen_string_literal: true

require 'set'
require_relative 'types'
require_relative 'scope'
require 'prism'

module IRB
  module TypeCompletion
    class TypeAnalyzer
      class DigTarget
        def initialize(parents, receiver, &block)
          @dig_ids = parents.to_h { [_1.__id__, true] }
          @target_id = receiver.__id__
          @block = block
        end

        def dig?(node) = @dig_ids[node.__id__]
        def target?(node) = @target_id == node.__id__
        def resolve(type, scope)
          @block.call type, scope
        end
      end

      OBJECT_METHODS = {
        to_s: Types::STRING,
        to_str: Types::STRING,
        to_a: Types::ARRAY,
        to_ary: Types::ARRAY,
        to_h: Types::HASH,
        to_hash: Types::HASH,
        to_i: Types::INTEGER,
        to_int: Types::INTEGER,
        to_f: Types::FLOAT,
        to_c: Types::COMPLEX,
        to_r: Types::RATIONAL
      }

      def initialize(dig_targets)
        @dig_targets = dig_targets
      end

      def evaluate(node, scope)
        method = "evaluate_#{node.type}"
        if respond_to? method
          result = send method, node, scope
        else
          result = Types::NIL
        end
        @dig_targets.resolve result, scope if @dig_targets.target? node
        result
      end

      def evaluate_program_node(node, scope)
        evaluate node.statements, scope
      end

      def evaluate_statements_node(node, scope)
        if node.body.empty?
          Types::NIL
        else
          node.body.map { evaluate _1, scope }.last
        end
      end

      def evaluate_def_node(node, scope)
        if node.receiver
          self_type = evaluate node.receiver, scope
        else
          current_self_types = scope.self_type.types
          self_types = current_self_types.map do |type|
            if type.is_a?(Types::SingletonType) && type.module_or_class.is_a?(Class)
              Types::InstanceType.new type.module_or_class
            else
              type
            end
          end
          self_type = Types::UnionType[*self_types]
        end
        if @dig_targets.dig?(node.body) || @dig_targets.dig?(node.parameters)
          params_table = node.locals.to_h { [_1.to_s, Types::NIL] }
          method_scope = Scope.new(
            scope,
            { **params_table, Scope::BREAK_RESULT => nil, Scope::NEXT_RESULT => nil, Scope::RETURN_RESULT => nil },
            self_type: self_type,
            trace_lvar: false,
            trace_ivar: false
          )
          if node.parameters
            # node.parameters is Prism::ParametersNode
            assign_parameters node.parameters, method_scope, [], {}
          end

          if @dig_targets.dig?(node.body)
            method_scope.conditional do |s|
              evaluate node.body, s
            end
          end
          method_scope.merge_jumps
          scope.update method_scope
        end
        Types::SYMBOL
      end

      def evaluate_integer_node(_node, _scope) = Types::INTEGER

      def evaluate_float_node(_node, _scope) = Types::FLOAT

      def evaluate_rational_node(_node, _scope) = Types::RATIONAL

      def evaluate_imaginary_node(_node, _scope) = Types::COMPLEX

      def evaluate_string_node(_node, _scope) = Types::STRING

      def evaluate_x_string_node(_node, _scope)
        Types::UnionType[Types::STRING, Types::NIL]
      end

      def evaluate_symbol_node(_node, _scope) = Types::SYMBOL

      def evaluate_regular_expression_node(_node, _scope) = Types::REGEXP

      def evaluate_string_concat_node(node, scope)
        evaluate node.left, scope
        evaluate node.right, scope
        Types::STRING
      end

      def evaluate_interpolated_string_node(node, scope)
        node.parts.each { evaluate _1, scope }
        Types::STRING
      end

      def evaluate_interpolated_x_string_node(node, scope)
        node.parts.each { evaluate _1, scope }
        Types::STRING
      end

      def evaluate_interpolated_symbol_node(node, scope)
        node.parts.each { evaluate _1, scope }
        Types::SYMBOL
      end

      def evaluate_interpolated_regular_expression_node(node, scope)
        node.parts.each { evaluate _1, scope }
        Types::REGEXP
      end

      def evaluate_embedded_statements_node(node, scope)
        node.statements ? evaluate(node.statements, scope) : Types::NIL
        Types::STRING
      end

      def evaluate_embedded_variable_node(node, scope)
        evaluate node.variable, scope
        Types::STRING
      end

      def evaluate_array_node(node, scope)
        Types.array_of evaluate_list_splat_items(node.elements, scope)
      end

      def evaluate_hash_node(node, scope) = evaluate_hash(node, scope)
      def evaluate_keyword_hash_node(node, scope) = evaluate_hash(node, scope)
      def evaluate_hash(node, scope)
        keys = []
        values = []
        node.elements.each do |assoc|
          case assoc
          when Prism::AssocNode
            keys << evaluate(assoc.key, scope)
            values << evaluate(assoc.value, scope)
          when Prism::AssocSplatNode
            next unless assoc.value # def f(**); {**}

            hash = evaluate assoc.value, scope
            unless hash.is_a?(Types::InstanceType) && hash.klass == Hash
              hash = method_call hash, :to_hash, [], nil, nil, scope
            end
            if hash.is_a?(Types::InstanceType) && hash.klass == Hash
              keys << hash.params[:K] if hash.params[:K]
              values << hash.params[:V] if hash.params[:V]
            end
          end
        end
        if keys.empty? && values.empty?
          Types::InstanceType.new Hash
        else
          Types::InstanceType.new Hash, K: Types::UnionType[*keys], V: Types::UnionType[*values]
        end
      end

      def evaluate_parentheses_node(node, scope)
        node.body ? evaluate(node.body, scope) : Types::NIL
      end

      def evaluate_constant_path_node(node, scope)
        type, = evaluate_constant_node_info node, scope
        type
      end

      def evaluate_self_node(_node, scope) = scope.self_type

      def evaluate_true_node(_node, _scope) = Types::TRUE

      def evaluate_false_node(_node, _scope) = Types::FALSE

      def evaluate_nil_node(_node, _scope) = Types::NIL

      def evaluate_source_file_node(_node, _scope) = Types::STRING

      def evaluate_source_line_node(_node, _scope) = Types::INTEGER

      def evaluate_source_encoding_node(_node, _scope) = Types::InstanceType.new(Encoding)

      def evaluate_numbered_reference_read_node(_node, _scope)
        Types::UnionType[Types::STRING, Types::NIL]
      end

      def evaluate_back_reference_read_node(_node, _scope)
        Types::UnionType[Types::STRING, Types::NIL]
      end

      def evaluate_reference_read(node, scope)
        scope[node.name.to_s] || Types::NIL
      end
      alias evaluate_constant_read_node evaluate_reference_read
      alias evaluate_global_variable_read_node evaluate_reference_read
      alias evaluate_local_variable_read_node evaluate_reference_read
      alias evaluate_class_variable_read_node evaluate_reference_read
      alias evaluate_instance_variable_read_node evaluate_reference_read


      def evaluate_call_node(node, scope)
        is_field_assign = node.name.match?(/[^<>=!\]]=\z/) || (node.name == :[]= && !node.call_operator)
        receiver_type = node.receiver ? evaluate(node.receiver, scope) : scope.self_type
        evaluate_method = lambda do |scope|
          args_types, kwargs_types, block_sym_node, has_block = evaluate_call_node_arguments node, scope

          if block_sym_node
            block_sym = block_sym_node.value
            if @dig_targets.target? block_sym_node
              # method(args, &:completion_target)
              call_block_proc = ->(block_args, _self_type) do
                block_receiver = block_args.first || Types::OBJECT
                @dig_targets.resolve block_receiver, scope
                Types::OBJECT
              end
            else
              call_block_proc = ->(block_args, _self_type) do
                block_receiver, *rest = block_args
                block_receiver ? method_call(block_receiver || Types::OBJECT, block_sym, rest, nil, nil, scope) : Types::OBJECT
              end
            end
          elsif node.block.is_a? Prism::BlockNode
            call_block_proc = ->(block_args, block_self_type) do
              scope.conditional do |s|
                numbered_parameters = node.block.locals.grep(/\A_[1-9]/).map(&:to_s)
                params_table = node.block.locals.to_h { [_1.to_s, Types::NIL] }
                table = { **params_table, Scope::BREAK_RESULT => nil, Scope::NEXT_RESULT => nil }
                block_scope = Scope.new s, table, self_type: block_self_type, trace_ivar: !block_self_type
                # TODO kwargs
                if node.block.parameters&.parameters
                  # node.block.parameters is Prism::BlockParametersNode
                  assign_parameters node.block.parameters.parameters, block_scope, block_args, {}
                elsif !numbered_parameters.empty?
                  assign_numbered_parameters numbered_parameters, block_scope, block_args, {}
                end
                result = node.block.body ? evaluate(node.block.body, block_scope) : Types::NIL
                block_scope.merge_jumps
                s.update block_scope
                nexts = block_scope[Scope::NEXT_RESULT]
                breaks = block_scope[Scope::BREAK_RESULT]
                if block_scope.terminated?
                  [Types::UnionType[*nexts], breaks]
                else
                  [Types::UnionType[result, *nexts], breaks]
                end
              end
            end
          elsif has_block
            call_block_proc = ->(_block_args, _self_type) { Types::OBJECT }
          end
          result = method_call receiver_type, node.name, args_types, kwargs_types, call_block_proc, scope
          if is_field_assign
            args_types.last || Types::NIL
          else
            result
          end
        end
        if node.call_operator == '&.'
          result = scope.conditional { evaluate_method.call _1 }
          if receiver_type.nillable?
            Types::UnionType[result, Types::NIL]
          else
            result
          end
        else
          evaluate_method.call scope
        end
      end

      def evaluate_and_node(node, scope) = evaluate_and_or(node, scope, and_op: true)
      def evaluate_or_node(node, scope) = evaluate_and_or(node, scope, and_op: false)
      def evaluate_and_or(node, scope, and_op:)
        left = evaluate node.left, scope
        right = scope.conditional { evaluate node.right, _1 }
        if and_op
          Types::UnionType[right, Types::NIL, Types::FALSE]
        else
          Types::UnionType[left, right]
        end
      end

      def evaluate_call_operator_write_node(node, scope) = evaluate_call_write(node, scope, :operator, node.write_name)
      def evaluate_call_and_write_node(node, scope) = evaluate_call_write(node, scope, :and, node.write_name)
      def evaluate_call_or_write_node(node, scope) = evaluate_call_write(node, scope, :or, node.write_name)
      def evaluate_index_operator_write_node(node, scope) = evaluate_call_write(node, scope, :operator, :[]=)
      def evaluate_index_and_write_node(node, scope) = evaluate_call_write(node, scope, :and, :[]=)
      def evaluate_index_or_write_node(node, scope) = evaluate_call_write(node, scope, :or, :[]=)
      def evaluate_call_write(node, scope, operator, write_name)
        receiver_type = evaluate node.receiver, scope
        if write_name == :[]=
          args_types, kwargs_types, block_sym_node, has_block = evaluate_call_node_arguments node, scope
        else
          args_types = []
        end
        if block_sym_node
          block_sym = block_sym_node.value
          call_block_proc = ->(block_args, _self_type) do
            block_receiver, *rest = block_args
            block_receiver ? method_call(block_receiver || Types::OBJECT, block_sym, rest, nil, nil, scope) : Types::OBJECT
          end
        elsif has_block
          call_block_proc = ->(_block_args, _self_type) { Types::OBJECT }
        end
        method = write_name.to_s.delete_suffix('=')
        left = method_call receiver_type, method, args_types, kwargs_types, call_block_proc, scope
        case operator
        when :and
          right = scope.conditional { evaluate node.value, _1 }
          Types::UnionType[right, Types::NIL, Types::FALSE]
        when :or
          right = scope.conditional { evaluate node.value, _1 }
          Types::UnionType[left, right]
        else
          right = evaluate node.value, scope
          method_call left, node.operator, [right], nil, nil, scope, name_match: false
        end
      end

      def evaluate_variable_operator_write(node, scope)
        left = scope[node.name.to_s] || Types::OBJECT
        right = evaluate node.value, scope
        scope[node.name.to_s] = method_call left, node.operator, [right], nil, nil, scope, name_match: false
      end
      alias evaluate_global_variable_operator_write_node evaluate_variable_operator_write
      alias evaluate_local_variable_operator_write_node evaluate_variable_operator_write
      alias evaluate_class_variable_operator_write_node evaluate_variable_operator_write
      alias evaluate_instance_variable_operator_write_node evaluate_variable_operator_write

      def evaluate_variable_and_write(node, scope)
        right = scope.conditional { evaluate node.value, scope }
        scope[node.name.to_s] = Types::UnionType[right, Types::NIL, Types::FALSE]
      end
      alias evaluate_global_variable_and_write_node evaluate_variable_and_write
      alias evaluate_local_variable_and_write_node evaluate_variable_and_write
      alias evaluate_class_variable_and_write_node evaluate_variable_and_write
      alias evaluate_instance_variable_and_write_node evaluate_variable_and_write

      def evaluate_variable_or_write(node, scope)
        left = scope[node.name.to_s] || Types::OBJECT
        right = scope.conditional { evaluate node.value, scope }
        scope[node.name.to_s] = Types::UnionType[left, right]
      end
      alias evaluate_global_variable_or_write_node evaluate_variable_or_write
      alias evaluate_local_variable_or_write_node evaluate_variable_or_write
      alias evaluate_class_variable_or_write_node evaluate_variable_or_write
      alias evaluate_instance_variable_or_write_node evaluate_variable_or_write

      def evaluate_constant_operator_write_node(node, scope)
        left = scope[node.name.to_s] || Types::OBJECT
        right = evaluate node.value, scope
        scope[node.name.to_s] = method_call left, node.operator, [right], nil, nil, scope, name_match: false
      end

      def evaluate_constant_and_write_node(node, scope)
        right = scope.conditional { evaluate node.value, scope }
        scope[node.name.to_s] = Types::UnionType[right, Types::NIL, Types::FALSE]
      end

      def evaluate_constant_or_write_node(node, scope)
        left = scope[node.name.to_s] || Types::OBJECT
        right = scope.conditional { evaluate node.value, scope }
        scope[node.name.to_s] = Types::UnionType[left, right]
      end

      def evaluate_constant_path_operator_write_node(node, scope)
        left, receiver, _parent_module, name = evaluate_constant_node_info node.target, scope
        right = evaluate node.value, scope
        value = method_call left, node.operator, [right], nil, nil, scope, name_match: false
        const_path_write receiver, name, value, scope
        value
      end

      def evaluate_constant_path_and_write_node(node, scope)
        _left, receiver, _parent_module, name = evaluate_constant_node_info node.target, scope
        right = scope.conditional { evaluate node.value, scope }
        value = Types::UnionType[right, Types::NIL, Types::FALSE]
        const_path_write receiver, name, value, scope
        value
      end

      def evaluate_constant_path_or_write_node(node, scope)
        left, receiver, _parent_module, name = evaluate_constant_node_info node.target, scope
        right = scope.conditional { evaluate node.value, scope }
        value = Types::UnionType[left, right]
        const_path_write receiver, name, value, scope
        value
      end

      def evaluate_constant_path_write_node(node, scope)
        receiver = evaluate node.target.parent, scope if node.target.parent
        value = evaluate node.value, scope
        const_path_write receiver, node.target.child.name.to_s, value, scope
        value
      end

      def evaluate_lambda_node(node, scope)
        local_table = node.locals.to_h { [_1.to_s, Types::OBJECT] }
        block_scope = Scope.new scope, { **local_table, Scope::BREAK_RESULT => nil, Scope::NEXT_RESULT => nil, Scope::RETURN_RESULT => nil }
        block_scope.conditional do |s|
          assign_parameters node.parameters.parameters, s, [], {} if node.parameters&.parameters
          evaluate node.body, s if node.body
        end
        block_scope.merge_jumps
        scope.update block_scope
        Types::PROC
      end

      def evaluate_reference_write(node, scope)
        scope[node.name.to_s] = evaluate node.value, scope
      end
      alias evaluate_constant_write_node evaluate_reference_write
      alias evaluate_global_variable_write_node evaluate_reference_write
      alias evaluate_local_variable_write_node evaluate_reference_write
      alias evaluate_class_variable_write_node evaluate_reference_write
      alias evaluate_instance_variable_write_node evaluate_reference_write

      def evaluate_multi_write_node(node, scope)
        evaluated_receivers = {}
        evaluate_multi_write_receiver node, scope, evaluated_receivers
        value = (
          if node.value.is_a? Prism::ArrayNode
            if node.value.elements.any?(Prism::SplatNode)
              evaluate node.value, scope
            else
              node.value.elements.map do |n|
                evaluate n, scope
              end
            end
          elsif node.value
            evaluate node.value, scope
          else
            Types::NIL
          end
        )
        evaluate_multi_write node, value, scope, evaluated_receivers
        value.is_a?(Array) ? Types.array_of(*value) : value
      end

      def evaluate_if_node(node, scope) = evaluate_if_unless(node, scope)
      def evaluate_unless_node(node, scope) = evaluate_if_unless(node, scope)
      def evaluate_if_unless(node, scope)
        evaluate node.predicate, scope
        Types::UnionType[*scope.run_branches(
          -> { node.statements ? evaluate(node.statements, _1) : Types::NIL },
          -> { node.consequent ? evaluate(node.consequent, _1) : Types::NIL }
        )]
      end

      def evaluate_else_node(node, scope)
        node.statements ? evaluate(node.statements, scope) : Types::NIL
      end

      def evaluate_while_until(node, scope)
        inner_scope = Scope.new scope, { Scope::BREAK_RESULT => nil }
        evaluate node.predicate, inner_scope
        if node.statements
          inner_scope.conditional do |s|
            evaluate node.statements, s
          end
        end
        inner_scope.merge_jumps
        scope.update inner_scope
        breaks = inner_scope[Scope::BREAK_RESULT]
        breaks ? Types::UnionType[breaks, Types::NIL] : Types::NIL
      end
      alias evaluate_while_node evaluate_while_until
      alias evaluate_until_node evaluate_while_until

      def evaluate_break_node(node, scope) = evaluate_jump(node, scope, :break)
      def evaluate_next_node(node, scope) = evaluate_jump(node, scope, :next)
      def evaluate_return_node(node, scope) = evaluate_jump(node, scope, :return)
      def evaluate_jump(node, scope, mode)
        internal_key = (
          case mode
          when :break
            Scope::BREAK_RESULT
          when :next
            Scope::NEXT_RESULT
          when :return
            Scope::RETURN_RESULT
          end
        )
        jump_value = (
          arguments = node.arguments&.arguments
          if arguments.nil? || arguments.empty?
            Types::NIL
          elsif arguments.size == 1 && !arguments.first.is_a?(Prism::SplatNode)
            evaluate arguments.first, scope
          else
            Types.array_of evaluate_list_splat_items(arguments, scope)
          end
        )
        scope.terminate_with internal_key, jump_value
        Types::NIL
      end

      def evaluate_yield_node(node, scope)
        evaluate_list_splat_items node.arguments.arguments, scope if node.arguments
        Types::OBJECT
      end

      def evaluate_redo_node(_node, scope)
        scope.terminate
        Types::NIL
      end

      def evaluate_retry_node(_node, scope)
        scope.terminate
        Types::NIL
      end

      def evaluate_forwarding_super_node(_node, _scope) = Types::OBJECT

      def evaluate_super_node(node, scope)
        evaluate_list_splat_items node.arguments.arguments, scope if node.arguments
        Types::OBJECT
      end

      def evaluate_begin_node(node, scope)
        return_type = node.statements ? evaluate(node.statements, scope) : Types::NIL
        if node.rescue_clause
          if node.else_clause
            return_types = scope.run_branches(
              ->{ evaluate node.rescue_clause, _1 },
              ->{ evaluate node.else_clause, _1 }
            )
          else
            return_types = [
              return_type,
              scope.conditional { evaluate node.rescue_clause, _1 }
            ]
          end
          return_type = Types::UnionType[*return_types]
        end
        if node.ensure_clause&.statements
          # ensure_clause is Prism::EnsureNode
          evaluate node.ensure_clause.statements, scope
        end
        return_type
      end

      def evaluate_rescue_node(node, scope)
        run_rescue = lambda do |s|
          if node.reference
            error_classes_type = evaluate_list_splat_items node.exceptions, s
            error_types = error_classes_type.types.filter_map do
              Types::InstanceType.new _1.module_or_class if _1.is_a?(Types::SingletonType)
            end
            error_types << Types::InstanceType.new(StandardError) if error_types.empty?
            error_type = Types::UnionType[*error_types]
            case node.reference
            when Prism::LocalVariableTargetNode, Prism::InstanceVariableTargetNode, Prism::ClassVariableTargetNode, Prism::GlobalVariableTargetNode, Prism::ConstantTargetNode
              s[node.reference.name.to_s] = error_type
            when Prism::CallNode
              evaluate node.reference, s
            end
          end
          node.statements ? evaluate(node.statements, s) : Types::NIL
        end
        if node.consequent # begin; rescue A; rescue B; end
          types = scope.run_branches(
            run_rescue,
            -> { evaluate node.consequent, _1 }
          )
          Types::UnionType[*types]
        else
          run_rescue.call scope
        end
      end

      def evaluate_rescue_modifier_node(node, scope)
        a = evaluate node.expression, scope
        b = scope.conditional { evaluate node.rescue_expression, _1 }
        Types::UnionType[a, b]
      end

      def evaluate_singleton_class_node(node, scope)
        klass_types = evaluate(node.expression, scope).types.filter_map do |type|
          Types::SingletonType.new type.klass if type.is_a? Types::InstanceType
        end
        klass_types = [Types::CLASS] if klass_types.empty?
        table = node.locals.to_h { [_1.to_s, Types::NIL] }
        sclass_scope = Scope.new(
          scope,
          { **table, Scope::BREAK_RESULT => nil, Scope::NEXT_RESULT => nil, Scope::RETURN_RESULT => nil },
          trace_ivar: false,
          trace_lvar: false,
          self_type: Types::UnionType[*klass_types]
        )
        result = node.body ? evaluate(node.body, sclass_scope) : Types::NIL
        scope.update sclass_scope
        result
      end

      def evaluate_class_node(node, scope) = evaluate_class_module(node, scope, true)
      def evaluate_module_node(node, scope) = evaluate_class_module(node, scope, false)
      def evaluate_class_module(node, scope, is_class)
        unless node.constant_path.is_a?(Prism::ConstantReadNode) || node.constant_path.is_a?(Prism::ConstantPathNode)
          # Incomplete class/module `class (statement[cursor_here])::Name; end`
          evaluate node.constant_path, scope
          return Types::NIL
        end
        const_type, _receiver, parent_module, name = evaluate_constant_node_info node.constant_path, scope
        if is_class
          select_class_type = -> { _1.is_a?(Types::SingletonType) && _1.module_or_class.is_a?(Class) }
          module_types = const_type.types.select(&select_class_type)
          module_types += evaluate(node.superclass, scope).types.select(&select_class_type) if node.superclass
          module_types << Types::CLASS if module_types.empty?
        else
          module_types = const_type.types.select { _1.is_a?(Types::SingletonType) && !_1.module_or_class.is_a?(Class) }
          module_types << Types::MODULE if module_types.empty?
        end
        return Types::NIL unless node.body

        table = node.locals.to_h { [_1.to_s, Types::NIL] }
        if !name.empty? && (parent_module.is_a?(Module) || parent_module.nil?)
          value = parent_module.const_get name if parent_module&.const_defined? name
          unless value
            value_type = scope[name]
            value = value_type.module_or_class if value_type.is_a? Types::SingletonType
          end

          if value.is_a? Module
            nesting = [value, []]
          else
            if parent_module
              nesting = [parent_module, [name]]
            else
              parent_nesting, parent_path = scope.module_nesting.first
              nesting = [parent_nesting, parent_path + [name]]
            end
            nesting_key = [nesting[0].__id__, nesting[1]].join('::')
            nesting_value = is_class ? Types::CLASS : Types::MODULE
          end
        else
          # parent_module == :unknown
          # TODO: dummy module
        end
        module_scope = Scope.new(
          scope,
          { **table, Scope::BREAK_RESULT => nil, Scope::NEXT_RESULT => nil, Scope::RETURN_RESULT => nil },
          trace_ivar: false,
          trace_lvar: false,
          self_type: Types::UnionType[*module_types],
          nesting: nesting
        )
        module_scope[nesting_key] = nesting_value if nesting_value
        result = evaluate(node.body, module_scope)
        scope.update module_scope
        result
      end

      def evaluate_for_node(node, scope)
        node.statements
        collection = evaluate node.collection, scope
        inner_scope = Scope.new scope, { Scope::BREAK_RESULT => nil }
        ary_type = method_call collection, :to_ary, [], nil, nil, nil, name_match: false
        element_types = ary_type.types.filter_map do |ary|
          ary.params[:Elem] if ary.is_a?(Types::InstanceType) && ary.klass == Array
        end
        element_type = Types::UnionType[*element_types]
        inner_scope.conditional do |s|
          evaluate_write node.index, element_type, s, nil
          evaluate node.statements, s if node.statements
        end
        inner_scope.merge_jumps
        scope.update inner_scope
        breaks = inner_scope[Scope::BREAK_RESULT]
        breaks ? Types::UnionType[breaks, collection] : collection
      end

      def evaluate_case_node(node, scope)
        target = evaluate(node.predicate, scope) if node.predicate
        # TODO
        branches = node.conditions.map do |condition|
          ->(s) { evaluate_case_match target, condition, s }
        end
        if node.consequent
          branches << ->(s) { evaluate node.consequent, s }
        elsif node.conditions.any? { _1.is_a? Prism::WhenNode }
          branches << ->(_s) { Types::NIL }
        end
        Types::UnionType[*scope.run_branches(*branches)]
      end

      def evaluate_match_required_node(node, scope)
        value_type = evaluate node.value, scope
        evaluate_match_pattern value_type, node.pattern, scope
        Types::NIL # void value
      end

      def evaluate_match_predicate_node(node, scope)
        value_type = evaluate node.value, scope
        scope.conditional { evaluate_match_pattern value_type, node.pattern, _1 }
        Types::BOOLEAN
      end

      def evaluate_range_node(node, scope)
        beg_type = evaluate node.left, scope if node.left
        end_type = evaluate node.right, scope if node.right
        elem = (Types::UnionType[*[beg_type, end_type].compact]).nonnillable
        Types::InstanceType.new Range, Elem: elem
      end

      def evaluate_defined_node(node, scope)
        scope.conditional { evaluate node.value, _1 }
        Types::UnionType[Types::STRING, Types::NIL]
      end

      def evaluate_flip_flop_node(node, scope)
        scope.conditional { evaluate node.left, _1 } if node.left
        scope.conditional { evaluate node.right, _1 } if node.right
        Types::BOOLEAN
      end

      def evaluate_multi_target_node(node, scope)
        # Raw MultiTargetNode, incomplete code like `a,b`, `*a`.
        evaluate_multi_write_receiver node, scope, nil
        Types::NIL
      end

      def evaluate_splat_node(node, scope)
        # Raw SplatNode, incomplete code like `*a.`
        evaluate_multi_write_receiver node.expression, scope, nil if node.expression
        Types::NIL
      end

      def evaluate_implicit_node(node, scope)
        evaluate node.value, scope
      end

      def evaluate_match_write_node(node, scope)
        # /(?<a>)(?<b>)/ =~ string
        evaluate node.call, scope
        node.locals.each { scope[_1.to_s] = Types::UnionType[Types::STRING, Types::NIL] }
        Types::BOOLEAN
      end

      def evaluate_match_last_line_node(_node, _scope)
        Types::BOOLEAN
      end

      def evaluate_interpolated_match_last_line_node(node, scope)
        node.parts.each { evaluate _1, scope }
        Types::BOOLEAN
      end

      def evaluate_pre_execution_node(node, scope)
        node.statements ? evaluate(node.statements, scope) : Types::NIL
      end

      def evaluate_post_execution_node(node, scope)
        node.statements && @dig_targets.dig?(node.statements) ? evaluate(node.statements, scope) : Types::NIL
      end

      def evaluate_alias_method_node(_node, _scope) = Types::NIL
      def evaluate_alias_global_variable_node(_node, _scope) = Types::NIL
      def evaluate_undef_node(_node, _scope) = Types::NIL
      def evaluate_missing_node(_node, _scope) = Types::NIL

      def evaluate_call_node_arguments(call_node, scope)
        # call_node.arguments is Prism::ArgumentsNode
        arguments = call_node.arguments&.arguments&.dup || []
        block_arg = call_node.block.expression if call_node.block.is_a?(Prism::BlockArgumentNode)
        kwargs = arguments.pop.elements if arguments.last.is_a?(Prism::KeywordHashNode)
        args_types = arguments.map do |arg|
          case arg
          when Prism::ForwardingArgumentsNode
            # `f(a, ...)` treat like splat
            nil
          when Prism::SplatNode
            evaluate arg.expression, scope if arg.expression
            nil # TODO: splat
          else
            evaluate arg, scope
          end
        end
        if kwargs
          kwargs_types = kwargs.map do |arg|
            case arg
            when Prism::AssocNode
              if arg.key.is_a?(Prism::SymbolNode)
                [arg.key.value, evaluate(arg.value, scope)]
              else
                evaluate arg.key, scope
                evaluate arg.value, scope
                nil
              end
            when Prism::AssocSplatNode
              evaluate arg.value, scope if arg.value
              nil
            end
          end.compact.to_h
        end
        if block_arg.is_a? Prism::SymbolNode
          block_sym_node = block_arg
        elsif block_arg
          evaluate block_arg, scope
        end
        [args_types, kwargs_types, block_sym_node, !!block_arg]
      end

      def const_path_write(receiver, name, value, scope)
        if receiver # receiver::A = value
          singleton_type = receiver.types.find { _1.is_a? Types::SingletonType }
          scope.set_const singleton_type.module_or_class, name, value if singleton_type
        else # ::A = value
          scope.set_const Object, name, value
        end
      end

      def assign_required_parameter(node, value, scope)
        case node
        when Prism::RequiredParameterNode
          scope[node.name.to_s] = value || Types::OBJECT
        when Prism::MultiTargetNode
          parameters = [*node.lefts, *node.rest, *node.rights]
          values = value ? sized_splat(value, :to_ary, parameters.size) : []
          parameters.zip values do |n, v|
            assign_required_parameter n, v, scope
          end
        when Prism::SplatNode
          splat_value = value ? Types.array_of(value) : Types::ARRAY
          assign_required_parameter node.expression, splat_value, scope if node.expression
        end
      end

      def evaluate_constant_node_info(node, scope)
        case node
        when Prism::ConstantPathNode
          name = node.child.name.to_s
          if node.parent
            receiver = evaluate node.parent, scope
            if receiver.is_a? Types::SingletonType
              parent_module = receiver.module_or_class
            end
          else
            parent_module = Object
          end
          if parent_module
            type = scope.get_const(parent_module, [name]) || Types::NIL
          else
            parent_module = :unknown
            type = Types::NIL
          end
        when Prism::ConstantReadNode
          name = node.name.to_s
          type = scope[name]
        end
        @dig_targets.resolve type, scope if @dig_targets.target? node
        [type, receiver, parent_module, name]
      end


      def assign_parameters(node, scope, args, kwargs)
        args = args.dup
        kwargs = kwargs.dup
        size = node.requireds.size + node.optionals.size + (node.rest ? 1 : 0) + node.posts.size
        args = sized_splat(args.first, :to_ary, size) if size >= 2 && args.size == 1
        reqs = args.shift node.requireds.size
        if node.rest
          # node.rest is Prism::RestParameterNode
          posts = []
          opts = args.shift node.optionals.size
          rest = args
        else
          posts = args.pop node.posts.size
          opts = args
          rest = []
        end
        node.requireds.zip reqs do |n, v|
          assign_required_parameter n, v, scope
        end
        node.optionals.zip opts do |n, v|
          # n is Prism::OptionalParameterNode
          values = [v]
          values << evaluate(n.value, scope) if n.value
          scope[n.name.to_s] = Types::UnionType[*values.compact]
        end
        node.posts.zip posts do |n, v|
          assign_required_parameter n, v, scope
        end
        if node.rest&.name
          # node.rest is Prism::RestParameterNode
          scope[node.rest.name.to_s] = Types.array_of(*rest)
        end
        node.keywords.each do |n|
          name = n.name.to_s.delete(':')
          values = [kwargs.delete(name)]
          # n is Prism::OptionalKeywordParameterNode (has n.value) or Prism::RequiredKeywordParameterNode (does not have n.value)
          values << evaluate(n.value, scope) if n.respond_to?(:value)
          scope[name] = Types::UnionType[*values.compact]
        end
        # node.keyword_rest is Prism::KeywordRestParameterNode or Prism::ForwardingParameterNode or Prism::NoKeywordsParameterNode
        if node.keyword_rest.is_a?(Prism::KeywordRestParameterNode) && node.keyword_rest.name
          scope[node.keyword_rest.name.to_s] = Types::InstanceType.new(Hash, K: Types::SYMBOL, V: Types::UnionType[*kwargs.values])
        end
        if node.block&.name
          # node.block is Prism::BlockParameterNode
          scope[node.block.name.to_s] = Types::PROC
        end
      end

      def assign_numbered_parameters(numbered_parameters, scope, args, _kwargs)
        return if numbered_parameters.empty?
        max_num = numbered_parameters.map { _1[1].to_i }.max
        if max_num == 1
          scope['_1'] = args.first || Types::NIL
        else
          args = sized_splat(args.first, :to_ary, max_num) if args.size == 1
          numbered_parameters.each do |name|
            index = name[1].to_i - 1
            scope[name] = args[index] || Types::NIL
          end
        end
      end

      def evaluate_case_match(target, node, scope)
        case node
        when Prism::WhenNode
          node.conditions.each { evaluate _1, scope }
          node.statements ? evaluate(node.statements, scope) : Types::NIL
        when Prism::InNode
          pattern = node.pattern
          if pattern.is_a?(Prism::IfNode) || pattern.is_a?(Prism::UnlessNode)
            cond_node = pattern.predicate
            pattern = pattern.statements.body.first
          end
          evaluate_match_pattern(target, pattern, scope)
          evaluate cond_node, scope if cond_node # TODO: conditional branch
          node.statements ? evaluate(node.statements, scope) : Types::NIL
        end
      end

      def evaluate_match_pattern(value, pattern, scope)
        # TODO: scope.terminate_with Scope::PATTERNMATCH_BREAK, Types::NIL
        case pattern
        when Prism::FindPatternNode
          # TODO
          evaluate_match_pattern Types::OBJECT, pattern.left, scope
          pattern.requireds.each { evaluate_match_pattern Types::OBJECT, _1, scope }
          evaluate_match_pattern Types::OBJECT, pattern.right, scope
        when Prism::ArrayPatternNode
          # TODO
          pattern.requireds.each { evaluate_match_pattern Types::OBJECT, _1, scope }
          evaluate_match_pattern Types::OBJECT, pattern.rest, scope if pattern.rest
          pattern.posts.each { evaluate_match_pattern Types::OBJECT, _1, scope }
          Types::ARRAY
        when Prism::HashPatternNode
          # TODO
          pattern.elements.each { evaluate_match_pattern Types::OBJECT, _1, scope }
          if pattern.respond_to?(:rest) && pattern.rest
            evaluate_match_pattern Types::OBJECT, pattern.rest, scope
          end
          Types::HASH
        when Prism::AssocNode
          evaluate_match_pattern value, pattern.value, scope if pattern.value
          Types::OBJECT
        when Prism::AssocSplatNode
          # TODO
          evaluate_match_pattern Types::HASH, pattern.value, scope
          Types::OBJECT
        when Prism::PinnedVariableNode
          evaluate pattern.variable, scope
        when Prism::PinnedExpressionNode
          evaluate pattern.expression, scope
        when Prism::LocalVariableTargetNode
          scope[pattern.name.to_s] = value
        when Prism::AlternationPatternNode
          Types::UnionType[evaluate_match_pattern(value, pattern.left, scope), evaluate_match_pattern(value, pattern.right, scope)]
        when Prism::CapturePatternNode
          capture_type = class_or_value_to_instance evaluate_match_pattern(value, pattern.value, scope)
          value = capture_type unless capture_type.types.empty? || capture_type.types == [Types::OBJECT]
          evaluate_match_pattern value, pattern.target, scope
        when Prism::SplatNode
          value = Types.array_of value
          evaluate_match_pattern value, pattern.expression, scope if pattern.expression
          value
        else
          # literal node
          type = evaluate(pattern, scope)
          class_or_value_to_instance(type)
        end
      end

      def class_or_value_to_instance(type)
        instance_types = type.types.map do |t|
          t.is_a?(Types::SingletonType) ? Types::InstanceType.new(t.module_or_class) : t
        end
        Types::UnionType[*instance_types]
      end

      def evaluate_write(node, value, scope, evaluated_receivers)
        case node
        when Prism::MultiTargetNode
          evaluate_multi_write node, value, scope, evaluated_receivers
        when Prism::CallNode
          evaluated_receivers&.[](node.receiver) || evaluate(node.receiver, scope) if node.receiver
        when Prism::SplatNode
          evaluate_write node.expression, Types.array_of(value), scope, evaluated_receivers if node.expression
        when Prism::LocalVariableTargetNode, Prism::GlobalVariableTargetNode, Prism::InstanceVariableTargetNode, Prism::ClassVariableTargetNode, Prism::ConstantTargetNode
          scope[node.name.to_s] = value
        when Prism::ConstantPathTargetNode
          receiver = evaluated_receivers&.[](node.parent) || evaluate(node.parent, scope) if node.parent
          const_path_write receiver, node.child.name.to_s, value, scope
          value
        end
      end

      def evaluate_multi_write(node, values, scope, evaluated_receivers)
        pre_targets = node.lefts
        splat_target = node.rest
        post_targets = node.rights
        size = pre_targets.size + (splat_target ? 1 : 0) + post_targets.size
        values = values.is_a?(Array) ? values.dup : sized_splat(values, :to_ary, size)
        pre_pairs = pre_targets.zip(values.shift(pre_targets.size))
        post_pairs = post_targets.zip(values.pop(post_targets.size))
        splat_pairs = splat_target ? [[splat_target, Types::UnionType[*values]]] : []
        (pre_pairs + splat_pairs + post_pairs).each do |target, value|
          evaluate_write target, value || Types::NIL, scope, evaluated_receivers
        end
      end

      def evaluate_multi_write_receiver(node, scope, evaluated_receivers)
        case node
        when Prism::MultiWriteNode, Prism::MultiTargetNode
          targets = [*node.lefts, *node.rest, *node.rights]
          targets.each { evaluate_multi_write_receiver _1, scope, evaluated_receivers }
        when Prism::CallNode
          if node.receiver
            receiver = evaluate(node.receiver, scope)
            evaluated_receivers[node.receiver] = receiver if evaluated_receivers
          end
          if node.arguments
            node.arguments.arguments&.each do |arg|
              if arg.is_a? Prism::SplatNode
                evaluate arg.expression, scope
              else
                evaluate arg, scope
              end
            end
          end
        when Prism::SplatNode
          evaluate_multi_write_receiver node.expression, scope, evaluated_receivers if node.expression
        end
      end

      def evaluate_list_splat_items(list, scope)
        items = list.flat_map do |node|
          if node.is_a? Prism::SplatNode
            next unless node.expression # def f(*); [*]

            splat = evaluate node.expression, scope
            array_elem, non_array = partition_to_array splat.nonnillable, :to_a
            [*array_elem, *non_array]
          else
            evaluate node, scope
          end
        end.compact.uniq
        Types::UnionType[*items]
      end

      def sized_splat(value, method, size)
        array_elem, non_array = partition_to_array value, method
        values = [Types::UnionType[*array_elem, *non_array]]
        values += [array_elem] * (size - 1) if array_elem && size >= 1
        values
      end

      def partition_to_array(value, method)
        arrays, non_arrays = value.types.partition { _1.is_a?(Types::InstanceType) && _1.klass == Array }
        non_arrays.select! do |type|
          to_array_result = method_call type, method, [], nil, nil, nil, name_match: false
          if to_array_result.is_a?(Types::InstanceType) && to_array_result.klass == Array
            arrays << to_array_result
            false
          else
            true
          end
        end
        array_elem = arrays.empty? ? nil : Types::UnionType[*arrays.map { _1.params[:Elem] || Types::OBJECT }]
        non_array = non_arrays.empty? ? nil : Types::UnionType[*non_arrays]
        [array_elem, non_array]
      end

      def method_call(receiver, method_name, args, kwargs, block, scope, name_match: true)
        methods = Types.rbs_methods receiver, method_name.to_sym, args, kwargs, !!block
        block_called = false
        type_breaks = methods.map do |method, given_params, method_params|
          receiver_vars = receiver.is_a?(Types::InstanceType) ? receiver.params : {}
          free_vars = method.type.free_variables - receiver_vars.keys.to_set
          vars = receiver_vars.merge Types.match_free_variables(free_vars, method_params, given_params)
          if block && method.block
            params_type = method.block.type.required_positionals.map do |func_param|
              Types.from_rbs_type func_param.type, receiver, vars
            end
            self_type = Types.from_rbs_type method.block.self_type, receiver, vars if method.block.self_type
            block_response, breaks = block.call params_type, self_type
            block_called = true
            vars.merge! Types.match_free_variables(free_vars - vars.keys.to_set, [method.block.type.return_type], [block_response])
          end
          if Types.method_return_bottom?(method)
            [nil, breaks]
          else
            [Types.from_rbs_type(method.type.return_type, receiver, vars || {}), breaks]
          end
        end
        block&.call [], nil unless block_called
        terminates = !type_breaks.empty? && type_breaks.map(&:first).all?(&:nil?)
        types = type_breaks.map(&:first).compact
        breaks = type_breaks.map(&:last).compact
        types << OBJECT_METHODS[method_name.to_sym] if name_match && OBJECT_METHODS.has_key?(method_name.to_sym)

        if method_name.to_sym == :new
          receiver.types.each do |type|
            if type.is_a?(Types::SingletonType) && type.module_or_class.is_a?(Class)
              types << Types::InstanceType.new(type.module_or_class)
            end
          end
        end
        scope&.terminate if terminates && breaks.empty?
        Types::UnionType[*types, *breaks]
      end

      def self.calculate_target_type_scope(binding, parents, target)
        dig_targets = DigTarget.new(parents, target) do |type, scope|
          return type, scope
        end
        program = parents.first
        scope = Scope.from_binding(binding, program.locals)
        new(dig_targets).evaluate program, scope
        [Types::NIL, scope]
      end
    end
  end
end
