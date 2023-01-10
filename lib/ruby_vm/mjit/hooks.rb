module RubyVM::MJIT::Hooks # :nodoc: all
  C = RubyVM::MJIT.const_get(:C, false)

  def self.on_bop_redefined(_redefined_flag, _bop)
    C.mjit_cancel_all("BOP is redefined")
  end

  def self.on_cme_invalidate(_cme)
    # to be used later
  end

  def self.on_ractor_spawn
    C.mjit_cancel_all("Ractor is spawned")
  end

  def self.on_constant_state_changed(_id)
    # to be used later
  end

  def self.on_constant_ic_update(_iseq, _ic, _insn_idx)
    # to be used later
  end

  def self.on_tracing_invalidate_all(new_iseq_events)
    # Stop calling all JIT-ed code. We can't rewrite existing JIT-ed code to trace_ insns for now.
    # :class events are triggered only in ISEQ_TYPE_CLASS, but mjit_target_iseq_p ignores such iseqs.
    # Thus we don't need to cancel JIT-ed code for :class events.
    if new_iseq_events != C.RUBY_EVENT_CLASS
      C.mjit_cancel_all("TracePoint is enabled")
    end
  end
end
