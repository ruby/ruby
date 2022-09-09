class Data
  def self.define(a, *attrs)
    attrs.unshift(a)
    Class.new(self) do
      attr_reader(*attrs)
      args = attrs.map {|a|", #{a}: __shift_keyword(__args, :#{a})"}.join('')
      inits = attrs.map {|a|"@#{a}=#{a}"}.join(';')
      line, code = __LINE__, <<-CODE # For old baseruby, do not use <<~CODE
        def initialize(*__args#{args})
          __arity_error(__args.size, #{attrs.size}) unless __args.empty?
          #{inits}
        end
        def hash
          [#{['self.class', attrs].join(', @')}].hash
        end
        def eql?(other)
          self.class == other.class#{attrs.map {|a| %[ && @#{a} == other.#{a}]}.join('')}
        end
        alias == eql?
      CODE
      warn code if $DEBUG
      class_eval(code, __FILE__, line)
    end
  end

  private

  def __shift_keyword(args, name)
    if args.empty?
      raise ArgumentError, "missing argument #{name}"
    end
    args.shift
  end

  def __arity_error(args, attrs)
    raise ArgumentError, "wrong number of arguments (given #{args + attrs}, expected #{attrs})"
  end
end
