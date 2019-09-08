
puts <<EOS
/* -*- c -*- */
#if 1 /* enable or disable this optimization */

/* DO NOT EDIT THIS FILE DIRECTLY
 *
 * This file is generated by tool/mk_call_iseq_optimized.rb
 */

EOS

P = (0..3)
L = (0..5)

def fname param, local
  "vm_call_iseq_setup_normal_0start_#{param}params_#{local}locals"
end

P.each{|param|
  L.each{|local|
    puts <<EOS
static VALUE
#{fname(param, local)}(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    RB_DEBUG_COUNTER_INC(ccf_iseq_fix);
    return vm_call_iseq_setup_normal(ec, cfp, calling, cc->me, 0, #{param}, #{local}, 0);
}

EOS
    #
  }
}

puts <<EOS
/* vm_call_iseq_handlers[param][local] */
static const vm_call_handler vm_call_iseq_handlers[][#{L.to_a.size}] = {
#{P.map{|param| '{' + L.map{|local| fname(param, local)}.join(",\n ") + '}'}.join(",\n")}
};

static inline vm_call_handler
vm_call_iseq_setup_func(const struct rb_call_info *ci, const int param_size, const int local_size)
{
    if (UNLIKELY(ci->flag & VM_CALL_TAILCALL)) {
	return &vm_call_iseq_setup_tailcall_0start;
    }
    else if (0) { /* to disable optimize */
        return &vm_call_iseq_setup_normal_0start;
    }
    else {
	if (param_size <= #{P.end} &&
	    local_size <= #{L.end}) {
	    VM_ASSERT(local_size >= 0);
	    return vm_call_iseq_handlers[param_size][local_size];
	}
	return &vm_call_iseq_setup_normal_0start;
    }
}

#else


static inline vm_call_handler
vm_call_iseq_setup_func(const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    if (UNLIKELY(ci->flag & VM_CALL_TAILCALL)) {
	return &vm_call_iseq_setup_tailcall_0start;
    }
    else {
        return &vm_call_iseq_setup_normal_0start;
    }
}
#endif
EOS
