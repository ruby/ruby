# frozen_string_literal: true
# TODO: Merge this to mjit.rb
if RubyVM::MJIT.enabled?
  begin
    require 'etc'
    require 'fiddle'
  rescue LoadError
    return # skip miniruby
  end

  if Fiddle::SIZEOF_VOIDP == 8
    require 'mjit/c_64'
  else
    require 'mjit/c_32'
  end

  class << RubyVM::MJIT::C
    def ROBJECT_EMBED_LEN_MAX
      Primitive.cexpr! 'INT2NUM(RBIMPL_EMBED_LEN_MAX_OF(VALUE))'
    end

    def cdhash_to_hash(cdhash_addr)
      Primitive.cdhash_to_hash(cdhash_addr)
    end

    def builtin_compiler(f, bf, index, stack_size, builtin_inline_p)
      Primitive.builtin_compile(f, bf.to_i, index, stack_size, builtin_inline_p)
    end

    def has_cache_for_send(cc, insn)
      Primitive.has_cache_for_send(cc.to_i, insn)
    end

    def rb_iseq_check(iseq)
      _iseq_addr = iseq.to_i
      iseq_addr = Primitive.cexpr! 'PTR2NUM((VALUE)rb_iseq_check((rb_iseq_t *)NUM2PTR(_iseq_addr)))'
      rb_iseq_t.new(iseq_addr)
    end

    def rb_iseq_path(iseq)
      _iseq_addr = iseq.to_i
      Primitive.cexpr! 'rb_iseq_path((rb_iseq_t *)NUM2PTR(_iseq_addr))'
    end

    def vm_ci_argc(ci)
      _ci_addr = ci.to_i
      Primitive.cexpr! 'UINT2NUM(vm_ci_argc((CALL_INFO)NUM2PTR(_ci_addr)))'
    end

    def vm_ci_flag(ci)
      _ci_addr = ci.to_i
      Primitive.cexpr! 'UINT2NUM(vm_ci_flag((CALL_INFO)NUM2PTR(_ci_addr)))'
    end

    def rb_splat_or_kwargs_p(ci)
      _ci_addr = ci.to_i
      Primitive.cexpr! 'RBOOL(rb_splat_or_kwargs_p((CALL_INFO)NUM2PTR(_ci_addr)))'
    end

    def fastpath_applied_iseq_p(ci, cc, iseq)
      _ci_addr = ci.to_i
      _cc_addr = cc.to_i
      _iseq_addr = iseq.to_i
      Primitive.cexpr! 'RBOOL(fastpath_applied_iseq_p((CALL_INFO)NUM2PTR(_ci_addr), (CALL_CACHE)NUM2PTR(_cc_addr), (rb_iseq_t *)NUM2PTR(_iseq_addr)))'
    end

    def mjit_opts
      addr = Primitive.cexpr! 'PTR2NUM((VALUE)&mjit_opts)'
      mjit_options.new(addr)
    end

    def mjit_call_attribute_sp_inc(insn, operands)
      _operands_addr = operands.to_i
      Primitive.cexpr! 'LONG2NUM(mjit_call_attribute_sp_inc(NUM2INT(insn), (VALUE *)NUM2PTR(_operands_addr)))'
    end

    def mjit_capture_cc_entries(compiled_body, captured_body)
      _compiled_body_addr = compiled_body.to_i
      _captured_body_addr = captured_body.to_i
      Primitive.cexpr! 'INT2NUM(mjit_capture_cc_entries((struct rb_iseq_constant_body *)NUM2PTR(_compiled_body_addr), (struct rb_iseq_constant_body *)NUM2PTR(_captured_body_addr)))'
    end

    #const struct rb_iseq_constant_body *body, union iseq_inline_storage_entry *is_entries
    def mjit_capture_is_entries(body, is_entries)
      _body_addr = body.to_i
      _is_entries_addr = is_entries.to_i
      Primitive.cstmt! %{
        mjit_capture_is_entries((struct rb_iseq_constant_body *)NUM2PTR(_body_addr), (union iseq_inline_storage_entry *)NUM2PTR(_is_entries_addr));
        return Qnil;
      }
    end

    # Convert encoded VM pointers to insn BINs.
    def rb_vm_insn_decode(encoded)
      Primitive.cexpr! 'INT2NUM(rb_vm_insn_decode(NUM2PTR(encoded)))'
    end

    # Convert insn BINs to encoded VM pointers. This one is not used by the compiler, but useful for debugging.
    def rb_vm_insn_encode(bin)
      Primitive.cexpr! 'PTR2NUM((VALUE)rb_vm_get_insns_address_table()[NUM2INT(bin)])'
    end

    def insn_may_depend_on_sp_or_pc(insn, opes)
      _opes_addr = opes.to_i
      Primitive.cexpr! 'RBOOL(insn_may_depend_on_sp_or_pc(NUM2INT(insn), (VALUE *)NUM2PTR(_opes_addr)))'
    end

    # Convert Integer VALUE to an actual Ruby object
    def to_ruby(value)
      Primitive.cexpr! '(VALUE)NUM2PTR(value)'
    end

    # Convert RubyVM::InstructionSequence to C.rb_iseq_t. Not used by the compiler, but useful for debugging.
    def rb_iseqw_to_iseq(iseqw)
      iseq_addr = Primitive.cexpr! 'PTR2NUM((VALUE)rb_iseqw_to_iseq(iseqw))'
      rb_iseq_t.new(iseq_addr)
    end

    # TODO: remove this after migration
    def fprintf(f, str)
      Primitive.cstmt! %{
        fprintf((FILE *)NUM2PTR(f), "%s", RSTRING_PTR(str));
        return Qnil;
      }
    end

    def rb_cFalseClass; Primitive.cexpr! 'PTR2NUM(rb_cFalseClass)' end
    def rb_cNilClass;   Primitive.cexpr! 'PTR2NUM(rb_cNilClass)'   end
    def rb_cTrueClass;  Primitive.cexpr! 'PTR2NUM(rb_cTrueClass)'  end
    def rb_cInteger;    Primitive.cexpr! 'PTR2NUM(rb_cInteger)'    end
    def rb_cSymbol;     Primitive.cexpr! 'PTR2NUM(rb_cSymbol)'     end
    def rb_cFloat;      Primitive.cexpr! 'PTR2NUM(rb_cFloat)'      end
  end

  require "mjit/compiler"
end
