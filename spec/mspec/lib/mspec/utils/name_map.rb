class NameMap
  MAP = {
    '`'   => 'backtick',
    '+'   => 'plus',
    '-'   => 'minus',
    '+@'  => 'uplus',
    '-@'  => 'uminus',
    '*'   => 'multiply',
    '/'   => 'divide',
    '%'   => 'modulo',
    '<<'  => {'Integer' => 'left_shift',
              'IO'      => 'output',
              :default  => 'append' },
    '>>'  => 'right_shift',
    '<'   => 'lt',
    '<='  => 'lte',
    '>'   => 'gt',
    '>='  => 'gte',
    '='   => 'assignment',
    '=='  => 'equal_value',
    '===' => 'case_compare',
    '<=>' => 'comparison',
    '[]'  => 'element_reference',
    '[]=' => 'element_set',
    '**'  => 'exponent',
    '!'   => 'not',
    '~'   => {'Integer' => 'complement',
              :default  => 'match' },
    '!='  => 'not_equal',
    '!~'  => 'not_match',
    '=~'  => 'match',
    '&'   => {'Integer'    => 'bit_and',
              'Array'      => 'intersection',
              'Set'        => 'intersection',
              :default     => 'and' },
    '|'   => {'Integer'    => 'bit_or',
              'Array'      => 'union',
              'Set'        => 'union',
              :default     => 'or' },
    '^'   => {'Integer'    => 'bit_xor',
              'Set'        => 'exclusion',
              :default     => 'xor' },
  }

  EXCLUDED = %w[
    MSpecScript
    MkSpec
    MSpecOption
    MSpecOptions
    NameMap
    SpecVersion
  ]

  def initialize(filter=false)
    @seen = {}
    @filter = filter
  end

  def exception?(name)
    return false unless c = class_or_module(name)
    c == Errno or c.ancestors.include? Exception
  end

  def class_or_module(c)
    const = Object.const_get(c, false)
    filtered = @filter && EXCLUDED.include?(const.name)
    return const if Module === const and !filtered
  rescue NameError
  end

  def namespace(mod, const)
    return const.to_s if mod.nil? or %w[Object Class Module].include? mod
    "#{mod}::#{const}"
  end

  def map(hash, constants, mod=nil)
    @seen = {} unless mod

    constants.each do |const|
      name = namespace mod, const
      m = class_or_module name
      next unless m and !@seen[m]
      @seen[m] = true

      ms = m.methods(false).map { |x| x.to_s }
      hash["#{name}."] = ms.sort unless ms.empty?

      ms = m.public_instance_methods(false) +
           m.protected_instance_methods(false)
      ms.map! { |x| x.to_s }
      hash["#{name}#"] = ms.sort unless ms.empty?

      map hash, m.constants(false), name
    end

    hash
  end

  def dir_name(c, base)
    return File.join(base, 'exception') if exception? c

    c.split('::').inject(base) do |dir, name|
      name.gsub!(/Class/, '') unless name == 'Class'
      File.join dir, name.downcase
    end
  end

  def file_name(m, c)
    if MAP.key?(m)
      mapping = MAP[m]
      if mapping.is_a?(Hash)
        name = mapping[c.split('::').last] || mapping.fetch(:default)
      else
        name = mapping
      end
    else
      name = m.gsub(/[?!=]/, '')
    end
    "#{name}_spec.rb"
  end
end
