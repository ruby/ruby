require 'psych/scalar_scanner'

module Psych
  module Visitors
    ###
    # This class walks a YAML AST, converting each node to ruby
    class ToRuby < Psych::Visitors::Visitor
      def initialize
        super
        @st = {}
        @ss = ScalarScanner.new
        @domain_types = Psych.domain_types
      end

      def accept target
        result = super
        return result if @domain_types.empty? || !target.tag

        key = target.tag.sub(/^[!\/]*/, '').sub(/(,\d+)\//, '\1:')
        key = "tag:#{key}" unless key =~ /^(tag:|x-private)/

        if @domain_types.key? key
          value, block = @domain_types[key]
          return block.call value, result
        end

        result
      end

      def visit_Psych_Nodes_Scalar o
        @st[o.anchor] = o.value if o.anchor

        if klass = Psych.load_tags[o.tag]
          instance = klass.allocate

          if instance.respond_to?(:init_with)
            coder = Psych::Coder.new(o.tag)
            coder.scalar = o.value
            instance.init_with coder
          end

          return instance
        end

        return o.value if o.quoted
        return @ss.tokenize(o.value) unless o.tag

        case o.tag
        when '!binary', 'tag:yaml.org,2002:binary'
          o.value.unpack('m').first
        when '!str', 'tag:yaml.org,2002:str'
          o.value
        when "!ruby/object:DateTime"
          require 'date'
          @ss.parse_time(o.value).to_datetime
        when "!ruby/object:Complex"
          Complex(o.value)
        when "!ruby/object:Rational"
          Rational(o.value)
        when "tag:yaml.org,2002:float", "!float"
          Float(@ss.tokenize(o.value))
        when "!ruby/regexp"
          o.value =~ /^\/(.*)\/([mix]*)$/
          source  = $1
          options = 0
          lang    = nil
          ($2 || '').split('').each do |option|
            case option
            when 'x' then options |= Regexp::EXTENDED
            when 'i' then options |= Regexp::IGNORECASE
            when 'm' then options |= Regexp::MULTILINE
            else lang = option
            end
          end
          Regexp.new(*[source, options, lang].compact)
        when "!ruby/range"
          args = o.value.split(/([.]{2,3})/, 2).map { |s|
            accept Nodes::Scalar.new(s)
          }
          args.push(args.delete_at(1) == '...')
          Range.new(*args)
        when /^!ruby\/sym(bol)?:?(.*)?$/
          o.value.to_sym
        else
          @ss.tokenize o.value
        end
      end

      def visit_Psych_Nodes_Sequence o
        if klass = Psych.load_tags[o.tag]
          instance = klass.allocate

          if instance.respond_to?(:init_with)
            coder = Psych::Coder.new(o.tag)
            coder.seq = o.children.map { |c| accept c }
            instance.init_with coder
          end

          return instance
        end

        case o.tag
        when '!omap', 'tag:yaml.org,2002:omap'
          map = Psych::Omap.new
          @st[o.anchor] = map if o.anchor
          o.children.each { |a|
            map[accept(a.children.first)] = accept a.children.last
          }
          map
        else
          list = []
          @st[o.anchor] = list if o.anchor
          o.children.each { |c| list.push accept c }
          list
        end
      end

      def visit_Psych_Nodes_Mapping o
        return revive(Psych.load_tags[o.tag], o) if Psych.load_tags[o.tag]

        case o.tag
        when '!str', 'tag:yaml.org,2002:str'
          members = Hash[*o.children.map { |c| accept c }]
          string = members.delete 'str'
          init_with(string, members.map { |k,v| [k.to_s.sub(/^@/, ''),v] }, o)
        when /^!ruby\/struct:?(.*)?$/
          klass = resolve_class($1)

          if klass
            s = klass.allocate
            @st[o.anchor] = s if o.anchor

            members = {}
            struct_members = s.members.map { |x| x.to_sym }
            o.children.each_slice(2) do |k,v|
              member = accept(k)
              value  = accept(v)
              if struct_members.include?(member.to_sym)
                s.send("#{member}=", value)
              else
                members[member.to_s.sub(/^@/, '')] = value
              end
            end
            init_with(s, members, o)
          else
            members = o.children.map { |c| accept c }
            h = Hash[*members]
            Struct.new(*h.map { |k,v| k.to_sym }).new(*h.map { |k,v| v })
          end

        when '!ruby/range'
          h = Hash[*o.children.map { |c| accept c }]
          Range.new(h['begin'], h['end'], h['excl'])

        when /^!ruby\/exception:?(.*)?$/
          h = Hash[*o.children.map { |c| accept c }]

          e = build_exception((resolve_class($1) || Exception),
                              h.delete('message'))
          init_with(e, h, o)

        when '!set', 'tag:yaml.org,2002:set'
          set = Psych::Set.new
          @st[o.anchor] = set if o.anchor
          o.children.each_slice(2) do |k,v|
            set[accept(k)] = accept(v)
          end
          set

        when '!ruby/object:Complex'
          h = Hash[*o.children.map { |c| accept c }]
          Complex(h['real'], h['image'])

        when '!ruby/object:Rational'
          h = Hash[*o.children.map { |c| accept c }]
          Rational(h['numerator'], h['denominator'])

        when /^!ruby\/object:?(.*)?$/
          name = $1 || 'Object'
          obj = revive((resolve_class(name) || Object), o)
          @st[o.anchor] = obj if o.anchor
          obj
        else
          hash = {}
          @st[o.anchor] = hash if o.anchor

          o.children.each_slice(2) { |k,v|
            key = accept(k)

            if key == '<<' && Nodes::Alias === v
              hash.merge! accept(v)
            else
              hash[key] = accept(v)
            end

          }
          hash
        end
      end

      def visit_Psych_Nodes_Document o
        accept o.root
      end

      def visit_Psych_Nodes_Stream o
        o.children.map { |c| accept c }
      end

      def visit_Psych_Nodes_Alias o
        @st[o.anchor]
      end

      private
      def revive klass, node
        s = klass.allocate
        h = Hash[*node.children.map { |c| accept c }]
        init_with(s, h, node)
      end

      def init_with o, h, node
        c = Psych::Coder.new(node.tag)
        c.map = h

        if o.respond_to?(:init_with)
          o.init_with c
        elsif o.respond_to?(:yaml_initialize)
          if $VERBOSE
            "Implementing #{o.class}#yaml_initialize is deprecated, please implement \"init_with(coder)\""
          end
          o.yaml_initialize c.tag, c.map
        else
          h.each { |k,v| o.instance_variable_set(:"@#{k}", v) }
        end
        o
      end

      # Convert +klassname+ to a Class
      def resolve_class klassname
        return nil unless klassname and not klassname.empty?

        name    = klassname
        retried = false

        begin
          path2class(name)
        rescue ArgumentError, NameError => ex
          unless retried
            name    = "Struct::#{name}"
            retried = ex
            retry
          end
          raise retried
        end
      end
    end
  end
end
