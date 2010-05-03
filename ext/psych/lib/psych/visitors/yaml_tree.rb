module Psych
  module Visitors
    class YAMLTree < Psych::Visitors::Visitor
      attr_reader :tree

      def initialize options = {}
        super()
        @tree  = Nodes::Stream.new
        @stack = []
        @st    = {}
        @ss    = ScalarScanner.new

        @dispatch_cache = Hash.new do |h,klass|
          method = "visit_#{(klass.name || '').split('::').join('_')}"

          method = respond_to?(method) ? method : h[klass.superclass]

          raise(TypeError, "Can't dump #{target.class}") unless method

          h[klass] = method
        end
      end

      def << object
        doc = create_document
        @stack << doc
        @tree.children << doc
        accept object
      end

      def accept target
        # return any aliases we find
        if node = @st[target.object_id]
          node.anchor = target.object_id.to_s
          return append Nodes::Alias.new target.object_id.to_s
        end

        if target.respond_to?(:to_yaml)
          loc = target.method(:to_yaml).source_location.first
          if loc !~ /(syck\/rubytypes.rb|psych\/core_ext.rb)/
            unless target.respond_to?(:encode_with)
              if $VERBOSE
                warn "implementing to_yaml is deprecated, please implement \"encode_with\""
              end

              target.to_yaml(:nodump => true)
            end
          end
        end

        if target.respond_to?(:encode_with)
          dump_coder target
        else
          send(@dispatch_cache[target.class], target)
        end
      end

      def visit_Psych_Omap o
        seq = create_sequence(nil, '!omap', false)
        register(o, seq)

        @stack.push append seq
        o.each { |k,v| visit_Hash k => v }
        @stack.pop
      end

      def visit_Object o
        tag = Psych.dump_tags[o.class]
        unless tag
          klass = o.class == Object ? nil : o.class.name
          tag   = ['!ruby/object', klass].compact.join(':')
        end

        map = append create_mapping(nil, tag, false)
        register(o, map)

        @stack.push map
        dump_ivars(o, map)
        @stack.pop
      end

      def visit_Struct o
        tag = ['!ruby/struct', o.class.name].compact.join(':')

        map = register(o, create_mapping(nil, tag, false))

        @stack.push append map

        o.members.each do |member|
          map.children <<  create_scalar("#{member}")
          accept o[member]
        end

        dump_ivars(o, map)

        @stack.pop
      end

      def visit_Exception o
        tag = ['!ruby/exception', o.class.name].join ':'

        map = append create_mapping(nil, tag, false)

        @stack.push map

        {
          'message'   => private_iv_get(o, 'mesg'),
          'backtrace' => private_iv_get(o, 'backtrace'),
        }.each do |k,v|
          next unless v
          map.children << create_scalar(k)
          accept v
        end

        dump_ivars(o, map)

        @stack.pop
      end

      def visit_Regexp o
        append create_scalar(o.inspect, nil, '!ruby/regexp', false)
      end

      def visit_Time o
        formatted = o.strftime("%Y-%m-%d %H:%M:%S")
        if o.utc?
          formatted += ".%06dZ" % [o.usec]
        else
          formatted += ".%06d %+.2d:00" % [o.usec, o.gmt_offset / 3600]
        end

        append create_scalar formatted
      end

      def visit_Rational o
        map = append create_mapping(nil, '!ruby/object:Rational', false)
        [
          'denominator', o.denominator.to_s,
          'numerator', o.numerator.to_s
        ].each do |m|
          map.children << create_scalar(m)
        end
      end

      def visit_Complex o
        map = append create_mapping(nil, '!ruby/object:Complex', false)

        ['real', o.real.to_s, 'image', o.imag.to_s].each do |m|
          map.children << create_scalar(m)
        end
      end

      def visit_Integer o
        append Nodes::Scalar.new o.to_s
      end
      alias :visit_TrueClass :visit_Integer
      alias :visit_FalseClass :visit_Integer
      alias :visit_Date :visit_Integer

      def visit_Float o
        if o.nan?
          append Nodes::Scalar.new '.nan'
        elsif o.infinite?
          append Nodes::Scalar.new(o.infinite? > 0 ? '.inf' : '-.inf')
        else
          append Nodes::Scalar.new o.to_s
        end
      end

      def visit_String o
        plain = false
        quote = false
        style = Nodes::Scalar::ANY

        if o.index("\x00") || o.count("^ -~\t\r\n").fdiv(o.length) > 0.3
          str   = [o].pack('m').chomp
          tag   = '!binary' # FIXME: change to below when syck is removed
          #tag   = 'tag:yaml.org,2002:binary'
          style = Nodes::Scalar::LITERAL
        else
          str   = o
          tag   = nil
          quote = !(String === @ss.tokenize(o))
          plain = !quote
        end

        ivars = find_ivars o

        scalar = create_scalar str, nil, tag, plain, quote, style

        if ivars.empty?
          append scalar
        else
          mapping = append create_mapping(nil, '!str', false)

          mapping.children << create_scalar('str')
          mapping.children << scalar

          @stack.push mapping
          dump_ivars o, mapping
          @stack.pop
        end
      end

      def visit_Class o
        raise TypeError, "can't dump anonymous class #{o.class}"
      end

      def visit_Range o
        @stack.push append create_mapping(nil, '!ruby/range', false)
        ['begin', o.begin, 'end', o.end, 'excl', o.exclude_end?].each do |m|
          accept m
        end
        @stack.pop
      end

      def visit_Hash o
        @stack.push append register(o, create_mapping)

        o.each do |k,v|
          accept k
          accept v
        end

        @stack.pop
      end

      def visit_Psych_Set o
        @stack.push append register(o, create_mapping(nil, '!set', false))

        o.each do |k,v|
          accept k
          accept v
        end

        @stack.pop
      end

      def visit_Array o
        @stack.push append register(o, create_sequence)
        o.each { |c| accept c }
        @stack.pop
      end

      def visit_NilClass o
        append create_scalar('', nil, 'tag:yaml.org,2002:null', false)
      end

      def visit_Symbol o
        append create_scalar ":#{o}"
      end

      private
      # FIXME: remove this method once "to_yaml_properties" is removed
      def find_ivars target
        loc = target.method(:to_yaml_properties).source_location.first
        unless loc.start_with?(Psych::DEPRECATED) || loc.end_with?('rubytypes.rb')
          if $VERBOSE
            warn "#{loc}: to_yaml_properties is deprecated, please implement \"encode_with(coder)\""
          end
          return target.to_yaml_properties
        end

        target.instance_variables
      end

      def append o
        @stack.last.children << o
        o
      end

      def register target, yaml_obj
        @st[target.object_id] = yaml_obj
        yaml_obj
      end

      def dump_coder o
        tag = Psych.dump_tags[o.class]
        unless tag
          klass = o.class == Object ? nil : o.class.name
          tag   = ['!ruby/object', klass].compact.join(':')
        end

        c = Psych::Coder.new(tag)
        o.encode_with(c)
        emit_coder c
      end

      def emit_coder c
        case c.type
        when :scalar
          append create_scalar(c.scalar, nil, c.tag, c.tag.nil?)
        when :seq
          @stack.push append create_sequence(nil, c.tag, c.tag.nil?)
          c.seq.each do |thing|
            accept thing
          end
          @stack.pop
        when :map
          map = append create_mapping(nil, c.tag, c.implicit, c.style)
          @stack.push map
          c.map.each do |k,v|
            map.children << create_scalar(k)
            accept v
          end
          @stack.pop
        end
      end

      def dump_ivars target, map
        ivars = find_ivars target

        ivars.each do |iv|
          map.children << create_scalar("#{iv.to_s.sub(/^@/, '')}")
          accept target.instance_variable_get(iv)
        end
      end

      def create_document version = [], tag_directives = [], implicit = false
        Nodes::Document.new version, tag_directives, implicit
      end

      def create_mapping anchor = nil, tag = nil, implicit = true, style = Psych::Nodes::Mapping::BLOCK
        Nodes::Mapping.new anchor, tag, implicit, style
      end

      def create_scalar value, anchor = nil, tag = nil, plain = true, quoted = false, style = Nodes::Scalar::ANY
        Nodes::Scalar.new(value, anchor, tag, plain, quoted, style)
      end

      def create_sequence anchor = nil, tag = nil, implicit = true, style = Nodes::Sequence::BLOCK
        Nodes::Sequence.new(anchor, tag, implicit, style)
      end
    end
  end
end
