module RubyVM::RJIT
  # Represent the type of a value (local/stack/self) in RJIT
  Type = Data.define(:type) do
    # Returns a boolean representing whether the value is truthy if known, otherwise nil
    def known_truthy
      case self
      in Type::Nil | Type::False
        false
      in Type::UnknownHeap
        true
      in Type::Unknown | Type::UnknownImm
        nil
      else
        true
      end
    end

    def diff(dst)
      if self == dst
        return TypeDiff::Compatible[0]
      end

      return TypeDiff::Incompatible
    end

    def upgrade(new_type)
      assert(new_type.diff(self) != TypeDiff::Incompatible)
      new_type
    end

    private

    def assert(cond)
      unless cond
        raise "'#{cond.inspect}' was not true"
      end
    end
  end

  # This returns an appropriate Type based on a known value
  class << Type
    def from(val)
      if C::SPECIAL_CONST_P(val)
        if fixnum?(val)
          Type::Fixnum
        elsif val.nil?
          Type::Nil
        elsif val == true
          Type::True
        elsif val == false
          Type::False
        elsif static_symbol?(val)
          Type::ImmSymbol
        elsif flonum?(val)
          Type::Flonum
        else
          raise "Illegal value: #{val.inspect}"
        end
      else
        val_class = C.to_value(C.rb_class_of(val))
        if val_class == C.rb_cString
          return Type::CString
        end
        if val_class == C.rb_cArray
          return Type::CArray
        end
        if C.to_value(val) == C.rb_block_param_proxy
          return Type::BlockParamProxy
        end
        case C::BUILTIN_TYPE(val)
        in C::RUBY_T_ARRAY
          Type::TArray
        in C::RUBY_T_HASH
          Type::Hash
        in C::RUBY_T_STRING
          Type::TString
        else
          Type::UnknownHeap
        end
      end
    end

    private

    def fixnum?(obj)
      (C.to_value(obj) & C::RUBY_FIXNUM_FLAG) == C::RUBY_FIXNUM_FLAG
    end

    def flonum?(obj)
      (C.to_value(obj) & C::RUBY_FLONUM_MASK) == C::RUBY_FLONUM_FLAG
    end

    def static_symbol?(obj)
      (C.to_value(obj) & 0xff) == C::RUBY_SYMBOL_FLAG
    end
  end

  # List of types
  Type::Unknown     = Type[:Unknown]
  Type::UnknownImm  = Type[:UnknownImm]
  Type::UnknownHeap = Type[:UnknownHeap]
  Type::Nil         = Type[:Nil]
  Type::True        = Type[:True]
  Type::False       = Type[:False]
  Type::Fixnum      = Type[:Fixnum]
  Type::Flonum      = Type[:Flonum]
  Type::Hash        = Type[:Hash]
  Type::ImmSymbol   = Type[:ImmSymbol]
  Type::HeapSymbol  = Type[:HeapSymbol]

  Type::TString = Type[:TString] # An object with the T_STRING flag set, possibly an rb_cString
  Type::CString = Type[:CString] # An un-subclassed string of type rb_cString (can have instance vars in some cases)
  Type::TArray  = Type[:TArray]  # An object with the T_ARRAY flag set, possibly an rb_cArray
  Type::CArray  = Type[:CArray]  # An un-subclassed string of type rb_cArray (can have instance vars in some cases)

  Type::BlockParamProxy = Type[:BlockParamProxy] # A special sentinel value indicating the block parameter should be read from

  module TypeDiff
    Compatible = Data.define(:diversion) # The smaller, the more compatible.
    Incompatible = :Incompatible
  end
end
