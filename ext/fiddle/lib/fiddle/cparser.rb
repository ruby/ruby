# frozen_string_literal: false
module Fiddle
  # A mixin that provides methods for parsing C struct and prototype signatures.
  #
  # == Example
  #   require 'fiddle/import'
  #
  #   include Fiddle::CParser
  #     #=> Object
  #
  #   parse_ctype('int')
  #     #=> Fiddle::TYPE_INT
  #
  #   parse_struct_signature(['int i', 'char c'])
  #     #=> [[Fiddle::TYPE_INT, Fiddle::TYPE_CHAR], ["i", "c"]]
  #
  #   parse_signature('double sum(double, double)')
  #     #=> ["sum", Fiddle::TYPE_DOUBLE, [Fiddle::TYPE_DOUBLE, Fiddle::TYPE_DOUBLE]]
  #
  module CParser
    # Parses a C struct's members
    #
    # Example:
    #
    #   include Fiddle::CParser
    #     #=> Object
    #
    #   parse_struct_signature(['int i', 'char c'])
    #     #=> [[Fiddle::TYPE_INT, Fiddle::TYPE_CHAR], ["i", "c"]]
    #
    #   parse_struct_signature(['char buffer[80]'])
    #     #=> [[[Fiddle::TYPE_CHAR, 80]], ["buffer"]]
    #
    def parse_struct_signature(signature, tymap=nil)
      if signature.is_a?(String)
        signature = split_arguments(signature, /[,;]/)
      end
      mems = []
      tys  = []
      signature.each{|msig|
        msig = compact(msig)
        case msig
        when /^[\w\*\s]+[\*\s](\w+)$/
          mems.push($1)
          tys.push(parse_ctype(msig, tymap))
        when /^[\w\*\s]+\(\*(\w+)\)\(.*?\)$/
          mems.push($1)
          tys.push(parse_ctype(msig, tymap))
        when /^([\w\*\s]+[\*\s])(\w+)\[(\d+)\]$/
          mems.push($2)
          tys.push([parse_ctype($1.strip, tymap), $3.to_i])
        when /^([\w\*\s]+)\[(\d+)\](\w+)$/
          mems.push($3)
          tys.push([parse_ctype($1.strip, tymap), $2.to_i])
        else
          raise(RuntimeError,"can't parse the struct member: #{msig}")
        end
      }
      return tys, mems
    end

    # Parses a C prototype signature
    #
    # If Hash +tymap+ is provided, the return value and the arguments from the
    # +signature+ are expected to be keys, and the value will be the C type to
    # be looked up.
    #
    # Example:
    #
    #   include Fiddle::CParser
    #     #=> Object
    #
    #   parse_signature('double sum(double, double)')
    #     #=> ["sum", Fiddle::TYPE_DOUBLE, [Fiddle::TYPE_DOUBLE, Fiddle::TYPE_DOUBLE]]
    #
    #   parse_signature('void update(void (*cb)(int code))')
    #     #=> ["update", Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP]]
    #
    #   parse_signature('char (*getbuffer(void))[80]')
    #     #=> ["getbuffer", Fiddle::TYPE_VOIDP, []]
    #
    def parse_signature(signature, tymap=nil)
      tymap ||= {}
      case compact(signature)
      when /^(?:[\w\*\s]+)\(\*(\w+)\((.*?)\)\)(?:\[\w*\]|\(.*?\));?$/
        func, args = $1, $2
        return [func, TYPE_VOIDP, split_arguments(args).collect {|arg| parse_ctype(arg, tymap)}]
      when /^([\w\*\s]+[\*\s])(\w+)\((.*?)\);?$/
        ret, func, args = $1.strip, $2, $3
        return [func, parse_ctype(ret, tymap), split_arguments(args).collect {|arg| parse_ctype(arg, tymap)}]
      else
        raise(RuntimeError,"can't parse the function prototype: #{signature}")
      end
    end

    # Given a String of C type +ty+, returns the corresponding Fiddle constant.
    #
    # +ty+ can also accept an Array of C type Strings, and will be returned in
    # a corresponding Array.
    #
    # If Hash +tymap+ is provided, +ty+ is expected to be the key, and the
    # value will be the C type to be looked up.
    #
    # Example:
    #
    #   include Fiddle::CParser
    #     #=> Object
    #
    #   parse_ctype('int')
    #     #=> Fiddle::TYPE_INT
    #
    #   parse_ctype('double diff')
    #     #=> Fiddle::TYPE_DOUBLE
    #
    #   parse_ctype('unsigned char byte')
    #     #=> -Fiddle::TYPE_CHAR
    #
    #   parse_ctype('const char* const argv[]')
    #     #=> -Fiddle::TYPE_VOIDP
    #
    def parse_ctype(ty, tymap=nil)
      tymap ||= {}
      case ty
      when Array
        return [parse_ctype(ty[0], tymap), ty[1]]
      when 'void'
        return TYPE_VOID
      when /^(?:(?:signed\s+)?long\s+long(?:\s+int\s+)?|int64_t)(?:\s+\w+)?$/
        if( defined?(TYPE_LONG_LONG) )
          return TYPE_LONG_LONG
        else
          raise(RuntimeError, "unsupported type: #{ty}")
        end
      when /^(?:unsigned\s+long\s+long(?:\s+int\s+)?|uint64_t)(?:\s+\w+)?$/
        if( defined?(TYPE_LONG_LONG) )
          return -TYPE_LONG_LONG
        else
          raise(RuntimeError, "unsupported type: #{ty}")
        end
      when /^(?:signed\s+)?long(?:\s+int\s+)?(?:\s+\w+)?$/
        return TYPE_LONG
      when /^unsigned\s+long(?:\s+int\s+)?(?:\s+\w+)?$/
        return -TYPE_LONG
      when /^(?:signed\s+)?int(?:\s+\w+)?$/
        return TYPE_INT
      when /^(?:unsigned\s+int|uint)(?:\s+\w+)?$/
        return -TYPE_INT
      when /^(?:signed\s+)?short(?:\s+int\s+)?(?:\s+\w+)?$/
        return TYPE_SHORT
      when /^unsigned\s+short(?:\s+int\s+)?(?:\s+\w+)?$/
        return -TYPE_SHORT
      when /^(?:signed\s+)?char(?:\s+\w+)?$/
        return TYPE_CHAR
      when /^unsigned\s+char(?:\s+\w+)?$/
        return  -TYPE_CHAR
      when /^float(?:\s+\w+)?$/
        return TYPE_FLOAT
      when /^double(?:\s+\w+)?$/
        return TYPE_DOUBLE
      when /^size_t(?:\s+\w+)?$/
        return TYPE_SIZE_T
      when /^ssize_t(?:\s+\w+)?$/
        return TYPE_SSIZE_T
      when /^ptrdiff_t(?:\s+\w+)?$/
        return TYPE_PTRDIFF_T
      when /^intptr_t(?:\s+\w+)?$/
        return TYPE_INTPTR_T
      when /^uintptr_t(?:\s+\w+)?$/
        return TYPE_UINTPTR_T
      when /\*/, /\[[\s\d]*\]/
        return TYPE_VOIDP
      else
        ty = ty.split(' ', 2)[0]
        if( tymap[ty] )
          return parse_ctype(tymap[ty], tymap)
        else
          raise(DLError, "unknown type: #{ty}")
        end
      end
    end

    private

    def split_arguments(arguments, sep=',')
      return [] if arguments.strip == 'void'
      arguments.scan(/([\w\*\s]+\(\*\w*\)\(.*?\)|[\w\*\s\[\]]+)(?:#{sep}\s*|$)/).collect {|m| m[0]}
    end

    def compact(signature)
      signature.gsub(/\s+/, ' ').gsub(/\s*([\(\)\[\]\*,;])\s*/, '\1').strip
    end

  end
end
