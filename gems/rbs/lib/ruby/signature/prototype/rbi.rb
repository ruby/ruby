module Ruby
  module Signature
    module Prototype
      class RBI
        attr_reader :decls
        attr_reader :modules
        attr_reader :last_sig

        def initialize
          @decls = []

          @modules = []
        end

        def parse(string)
          comments = Ripper.lex(string).yield_self do |tokens|
            tokens.each.with_object({}) do |token, hash|
              if token[1] == :on_comment
                line = token[0][0]
                body = token[2][2..]

                body = "\n" if body.empty?

                comment = AST::Comment.new(string: body, location: nil)
                if (prev_comment = hash[line - 1])
                  hash[line - 1] = nil
                  hash[line] = AST::Comment.new(string: prev_comment.string + comment.string,
                                                location: nil)
                else
                  hash[line] = comment
                end
              end
            end
          end
          process RubyVM::AbstractSyntaxTree.parse(string), comments: comments
        end

        def nested_name(name)
          (current_namespace + const_to_name(name).to_namespace).to_type_name.relative!
        end

        def current_namespace
          modules.inject(Namespace.empty) do |parent, mod|
            parent + mod.name.to_namespace
          end
        end

        def push_class(name, super_class, comment:)
          modules.push AST::Declarations::Class.new(
            name: nested_name(name),
            super_class: super_class && AST::Declarations::Class::Super.new(name: const_to_name(super_class), args: []),
            type_params: AST::Declarations::ModuleTypeParams.empty,
            members: [],
            annotations: [],
            location: nil,
            comment: comment
          )

          decls << modules.last

          yield
        ensure
          modules.pop
        end

        def push_module(name, comment:)
          modules.push AST::Declarations::Module.new(
            name: nested_name(name),
            type_params: AST::Declarations::ModuleTypeParams.empty,
            members: [],
            annotations: [],
            location: nil,
            self_type: nil,
            comment: comment
          )

          decls << modules.last

          yield
        ensure
          modules.pop
        end

        def current_module
          modules.last
        end

        def push_sig(node)
          @last_sig ||= []
          @last_sig << node
        end

        def pop_sig
          @last_sig.tap do
            @last_sig = nil
          end
        end

        def join_comments(nodes, comments)
          cs = nodes.map {|node| comments[node.first_lineno - 1] }.compact
          AST::Comment.new(string: cs.map(&:string).join("\n"), location: nil)
        end

        def process(node, outer: [], comments:)
          case node.type
          when :CLASS
            comment = comments[node.first_lineno - 1]
            push_class node.children[0], node.children[1], comment: comment do
              process node.children[2], outer: outer + [node], comments: comments
            end
          when :MODULE
            comment = comments[node.first_lineno - 1]
            push_module node.children[0], comment: comment do
              process node.children[1], outer: outer + [node], comments: comments
            end
          when :FCALL
            case node.children[0]
            when :include
              each_arg node.children[1] do |arg|
                if arg.type == :CONST || arg.type == :COLON2 || arg.type == :COLON3
                  name = const_to_name(arg)
                  include_member = AST::Members::Include.new(
                    name: name,
                    args: [],
                    annotations: [],
                    location: nil,
                    comment: nil
                  )
                  current_module.members << include_member
                end
              end
            when :extend
              each_arg node.children[1] do |arg|
                if arg.type == :CONST || arg.type == :COLON2
                  name = const_to_name(arg)
                  unless name.to_s == "T::Generic" || name.to_s == "T::Sig"
                    member = AST::Members::Extend.new(
                      name: name,
                      args: [],
                      annotations: [],
                      location: nil,
                      comment: nil
                    )
                    current_module.members << member
                  end
                end
              end
            when :sig
              push_sig outer.last.children.last.children.last
            when :alias_method
              new, old = each_arg(node.children[1]).map {|x| x.children[0] }
              current_module.members << AST::Members::Alias.new(
                new_name: new,
                old_name: old,
                location: nil,
                annotations: [],
                kind: :instance,
                comment: nil
              )
            end
          when :DEFS
            sigs = pop_sig

            if sigs
              comment = join_comments(sigs, comments)

              args = node.children[2]
              types = sigs.map {|sig| method_type(args, sig, variables: current_module.type_params) }

              current_module.members << AST::Members::MethodDefinition.new(
                name: node.children[1],
                location: nil,
                annotations: [],
                types: types,
                kind: :singleton,
                comment: comment,
                attributes: []
              )
            end

          when :DEFN
            sigs = pop_sig

            if sigs
              comment = join_comments(sigs, comments)

              args = node.children[1]
              types = sigs.map {|sig| method_type(args, sig, variables: current_module.type_params) }

              current_module.members << AST::Members::MethodDefinition.new(
                name: node.children[0],
                location: nil,
                annotations: [],
                types: types,
                kind: :instance,
                comment: comment,
                attributes: []
              )
            end

          when :CDECL
            if (send = node.children.last) && send.type == :FCALL && send.children[0] == :type_member
              unless each_arg(send.children[1]).any? {|node|
                node.type == :HASH &&
                  each_arg(node.children[0]).each_slice(2).any? {|a, _| a.type == :LIT && a.children[0] == :fixed }
              }
                if (a0 = each_arg(send.children[1]).to_a[0])&.type == :LIT
                  variance = case a0.children[0]
                             when :out
                               :covariant
                             when :in
                               :contravariant
                             end
                end

                current_module.type_params.add(
                  AST::Declarations::ModuleTypeParams::TypeParam.new(name: node.children[0],
                                                                     variance: variance || :invariant,
                                                                     skip_validation: false))
              end
            else
              name = node.children[0].yield_self do |n|
                if n.is_a?(Symbol)
                  TypeName.new(namespace: current_namespace, name: n)
                else
                  const_to_name(n)
                end
              end
              value_node = node.children.last
              type = if value_node.type == :CALL && value_node.children[1] == :let
                       type_node = each_arg(value_node.children[2]).to_a[1]
                       type_of type_node, variables: current_module&.type_params || []
                     else
                       Types::Bases::Any.new(location: nil)
                     end
              decls << AST::Declarations::Constant.new(
                name: name,
                type: type,
                location: nil,
                comment: nil
              )
            end
          when :ALIAS
            current_module.members << AST::Members::Alias.new(
              new_name: node.children[0].children[0],
              old_name: node.children[1].children[0],
              location: nil,
              annotations: [],
              kind: :instance,
              comment: nil
            )
          else
            each_child node do |child|
              process child, outer: outer + [node], comments: comments
            end
          end
        end

        def method_type(args_node, type_node, variables:)
          if type_node
            if type_node.type == :CALL
              method_type = method_type(args_node, type_node.children[0], variables: variables)
            else
              method_type = MethodType.new(
                type: Types::Function.empty(Types::Bases::Any.new(location: nil)),
                block: nil,
                location: nil,
                type_params: []
              )
            end

            name, args = case type_node.type
                         when :CALL
                           [
                             type_node.children[1],
                             type_node.children[2]
                           ]
                         when :FCALL, :VCALL
                           [
                             type_node.children[0],
                             type_node.children[1]
                           ]
                         end

            case name
            when :returns
              return_type = each_arg(args).to_a[0]
              method_type.update(type: method_type.type.with_return_type(type_of(return_type, variables: variables)))
            when :params
              if args_node
                parse_params(args_node, args, method_type, variables: variables)
              else
                vars = (node_to_hash(each_arg(args).to_a[0]) || {}).transform_values {|value| type_of(value, variables: variables) }

                required_positionals = vars.map do |name, type|
                  Types::Function::Param.new(name: name, type: type)
                end

                method_type.update(type: method_type.type.update(required_positionals: required_positionals))
              end
            when :type_parameters
              type_params = []

              each_arg args do |node|
                if node.type == :LIT
                  type_params << node.children[0]
                end
              end

              method_type.update(type_params: type_params)
            when :void
              method_type.update(type: method_type.type.with_return_type(Types::Bases::Void.new(location: nil)))
            when :proc
              method_type
            else
              method_type
            end
          end
        end

        def parse_params(args_node, args, method_type, variables:)
          vars = (node_to_hash(each_arg(args).to_a[0]) || {}).transform_values {|value| type_of(value, variables: variables) }

          required_positionals = []
          optional_positionals = []
          rest_positionals = nil
          trailing_positionals = []
          required_keywords = {}
          optional_keywords = {}
          rest_keywords = nil

          var_names = args_node.children[0]
          pre_num, _pre_init, opt, _first_post, post_num, _post_init, rest, kw, kwrest, block = args_node.children[1].children

          pre_num.times.each do |i|
            name = var_names[i]
            type = vars[name] || Types::Bases::Any.new(location: nil)
            required_positionals << Types::Function::Param.new(type: type, name: name)
          end

          index = pre_num
          while opt
            name = var_names[index]
            if (type = vars[name])
              optional_positionals << Types::Function::Param.new(type: type, name: name)
            end
            index += 1
            opt = opt.children[1]
          end

          if rest
            name = var_names[index]
            if (type = vars[name])
              rest_positionals = Types::Function::Param.new(type: type, name: name)
            end
            index += 1
          end

          post_num.times do |i|
            name = var_names[i+index]
            if (type = vars[name])
              trailing_positionals << Types::Function::Param.new(type: type, name: name)
            end
            index += 1
          end

          while kw
            name, value = kw.children[0].children
            if (type = vars[name])
              if value
                optional_keywords[name] = Types::Function::Param.new(type: type, name: name)
              else
                required_keywords[name] = Types::Function::Param.new(type: type, name: name)
              end
            end

            kw = kw.children[1]
          end

          if kwrest
            name = kwrest.children[0]
            if (type = vars[name])
              rest_keywords = Types::Function::Param.new(type: type, name: name)
            end
          end

          method_block = nil
          if block
            if (type = vars[block])
              if type.is_a?(Types::Proc)
                method_block = MethodType::Block.new(required: true, type: type.type)
              elsif type.is_a?(Types::Bases::Any)
                method_block = MethodType::Block.new(
                  required: true,
                  type: Types::Function.empty(Types::Bases::Any.new(location: nil))
                )
              # Handle an optional block like `T.nilable(T.proc.void)`.
              elsif type.is_a?(Types::Optional) && type.type.is_a?(Types::Proc)
                method_block = MethodType::Block.new(required: false, type: type.type.type)
              else
                STDERR.puts "Unexpected block type: #{type}"
                PP.pp args_node, STDERR
                method_block = MethodType::Block.new(
                  required: true,
                  type: Types::Function.empty(Types::Bases::Any.new(location: nil))
                )
              end
            end
          end

          method_type.update(
            type: method_type.type.update(
              required_positionals: required_positionals,
              optional_positionals: optional_positionals,
              rest_positionals: rest_positionals,
              trailing_positionals: trailing_positionals,
              required_keywords: required_keywords,
              optional_keywords: optional_keywords,
              rest_keywords: rest_keywords
            ),
            block: method_block
          )
        end

        def type_of(type_node, variables:)
          type = type_of0(type_node, variables: variables)

          case
          when type.is_a?(Types::ClassInstance) && type.name.name == BuiltinNames::BasicObject.name.name
            Types::Bases::Any.new(location: nil)
          when type.is_a?(Types::ClassInstance) && type.name.to_s == "T::Boolean"
            Types::Bases::Bool.new(location: nil)
          else
            type
          end
        end

        def type_of0(type_node, variables:)
          case
          when type_node.type == :CONST
            if variables.each.include?(type_node.children[0])
              Types::Variable.new(name: type_node.children[0], location: nil)
            else
              Types::ClassInstance.new(name: const_to_name(type_node), args: [], location: nil)
            end
          when type_node.type == :COLON2
            Types::ClassInstance.new(name: const_to_name(type_node), args: [], location: nil)
          when call_node?(type_node, name: :[], receiver: -> (_) { true })
            type = type_of(type_node.children[0], variables: variables)
            each_arg(type_node.children[2]) do |arg|
              type.args << type_of(arg, variables: variables)
            end

            type
          when call_node?(type_node, name: :type_parameter)
            name = each_arg(type_node.children[2]).to_a[0].children[0]
            Types::Variable.new(name: name, location: nil)
          when call_node?(type_node, name: :any)
            types = each_arg(type_node.children[2]).to_a.map {|node| type_of(node, variables: variables) }
            Types::Union.new(types: types, location: nil)
          when call_node?(type_node, name: :all)
            types = each_arg(type_node.children[2]).to_a.map {|node| type_of(node, variables: variables) }
            Types::Intersection.new(types: types, location: nil)
          when call_node?(type_node, name: :untyped)
            Types::Bases::Any.new(location: nil)
          when call_node?(type_node, name: :nilable)
            type = type_of each_arg(type_node.children[2]).to_a[0], variables: variables
            Types::Optional.new(type: type, location: nil)
          when call_node?(type_node, name: :self_type)
            Types::Bases::Self.new(location: nil)
          when call_node?(type_node, name: :attached_class)
            Types::Bases::Instance.new(location: nil)
          when call_node?(type_node, name: :noreturn)
            Types::Bases::Bottom.new(location: nil)
          when call_node?(type_node, name: :class_of)
            type = type_of each_arg(type_node.children[2]).to_a[0], variables: variables
            case type
            when Types::ClassInstance
              Types::ClassSingleton.new(name: type.name, location: nil)
            else
              STDERR.puts "Unexpected type for `class_of`: #{type}"
              Types::Bases::Any.new(location: nil)
            end
          when type_node.type == :ARRAY, type_node.type == :LIST
            types = each_arg(type_node).map {|node| type_of(node, variables: variables) }
            Types::Tuple.new(types: types, location: nil)
          else
            if proc_type?(type_node)
              Types::Proc.new(type: method_type(nil, type_node, variables: variables).type, location: nil)
            else
              STDERR.puts "Unexpected type_node:"
              PP.pp type_node, STDERR
              Types::Bases::Any.new(location: nil)
            end
          end
        end

        def proc_type?(type_node)
          if call_node?(type_node, name: :proc)
            true
          else
            type_node.type == :CALL && proc_type?(type_node.children[0])
          end

        end

        def call_node?(node, name:, receiver: -> (node) { node.type == :CONST && node.children[0] == :T }, args: -> (node) { true })
          node.type == :CALL && receiver[node.children[0]] && name == node.children[1] && args[node.children[2]]
        end

        def const_to_name(node)
          case node.type
          when :CONST
            TypeName.new(name: node.children[0], namespace: Namespace.empty)
          when :COLON2
            if node.children[0]
              if node.children[0].type == :COLON3
                namespace = Namespace.root
              else
                namespace = const_to_name(node.children[0]).to_namespace
              end
            else
              namespace = Namespace.empty
            end

            type_name = TypeName.new(name: node.children[1], namespace: namespace)

            case type_name.to_s
            when "T::Array"
              BuiltinNames::Array.name
            when "T::Hash"
              BuiltinNames::Hash.name
            when "T::Range"
              BuiltinNames::Range.name
            when "T::Enumerator"
              BuiltinNames::Enumerator.name
            when "T::Enumerable"
              BuiltinNames::Enumerable.name
            when "T::Set"
              BuiltinNames::Set.name
            else
              type_name
            end
          when :COLON3
            TypeName.new(name: node.children[0], namespace: Namespace.root)
          else
            raise "Unexpected node type: #{node.type}"
          end
        end

        def each_arg(array, &block)
          if block_given?
            if array&.type == :ARRAY || array&.type == :LIST
              array.children.each do |arg|
                if arg
                  yield arg
                end
              end
            end
          else
            enum_for :each_arg, array
          end
        end

        def each_child(node)
          node.children.each do |child|
            if child.is_a?(RubyVM::AbstractSyntaxTree::Node)
              yield child
            end
          end
        end

        def node_to_hash(node)
          if node&.type == :HASH
            hash = {}

            each_arg(node.children[0]).each_slice(2) do |var, type|
              if var.type == :LIT && type
                hash[var.children[0]] = type
              end
            end

            hash
          end
        end
      end
    end
  end
end
