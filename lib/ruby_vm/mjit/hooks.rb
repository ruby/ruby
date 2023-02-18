module RubyVM::MJIT
  module Hooks # :nodoc: all
    def self.on_bop_redefined(_redefined_flag, _bop)
      # C.mjit_cancel_all("BOP is redefined")
    end

    def self.on_cme_invalidate(cme)
      cme = C.rb_callable_method_entry_struct.new(cme)
      Invariants.on_cme_invalidate(cme)
    end

    def self.on_ractor_spawn
      # C.mjit_cancel_all("Ractor is spawned")
    end

    def self.on_constant_state_changed(_id)
      # to be used later
    end

    def self.on_constant_ic_update(iseq, ic, insn_idx)
      iseq = C.rb_iseq_t.new(iseq)
      ic = C.IC.new(ic)
      Invariants.on_constant_ic_update(iseq, ic, insn_idx)
    end

    def self.on_tracing_invalidate_all(_new_iseq_events)
      Invariants.on_tracing_invalidate_all
    end
  end
end
