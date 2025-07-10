// We use the YARV bytecode constants which have a CRuby-style name
#![allow(non_upper_case_globals)]

use crate::{cruby::*, gc::get_or_create_iseq_payload, hir_type::{types::{Empty, Fixnum}, Type}};

/// Ephemeral state for profiling runtime information
struct Profiler {
    cfp: CfpPtr,
    iseq: IseqPtr,
    insn_idx: usize,
}

impl Profiler {
    fn new(ec: EcPtr) -> Self {
        let cfp = unsafe { get_ec_cfp(ec) };
        let iseq = unsafe { get_cfp_iseq(cfp) };
        Profiler {
            cfp,
            iseq,
            insn_idx: unsafe { get_cfp_pc(cfp).offset_from(get_iseq_body_iseq_encoded(iseq)) as usize },
        }
    }

    // Get an instruction operand that sits next to the opcode at PC.
    fn insn_opnd(&self, idx: usize) -> VALUE {
        unsafe { get_cfp_pc(self.cfp).add(1 + idx).read() }
    }

    // Peek at the nth topmost value on the Ruby stack.
    // Returns the topmost value when n == 0.
    fn peek_at_stack(&self, n: isize) -> VALUE {
        unsafe {
            let sp: *mut VALUE = get_cfp_sp(self.cfp);
            *(sp.offset(-1 - n))
        }
    }
}

/// API called from zjit_* instruction. opcode is the bare (non-zjit_*) instruction.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_profile_insn(opcode: ruby_vminsn_type, ec: EcPtr) {
    with_vm_lock(src_loc!(), || {
        let mut profiler = Profiler::new(ec);
        profile_operands(&mut profiler);
    });
}

/// Profile the Type of top-`n` stack operands
fn profile_operands(profiler: &mut Profiler) {
    let profile = &mut get_or_create_iseq_payload(profiler.iseq).profile;
    let types = &mut profile.opnd_types[profiler.insn_idx];
    let n = types.len();
    for i in 0..n {
        let opnd_type = Type::from_value(profiler.peek_at_stack((n - i - 1) as isize));
        types[i] = types[i].union(opnd_type);
    }
}

#[derive(Debug)]
pub struct IseqProfile {
    /// Type information of YARV instruction operands, indexed by the instruction index
    opnd_types: Vec<Vec<Type>>,
}

/// Get YARV instruction argument
fn get_arg(pc: *const VALUE, arg_idx: isize) -> VALUE {
    unsafe { *(pc.offset(arg_idx + 1)) }
}

impl IseqProfile {
    pub fn new(iseq: IseqPtr) -> Self {
        // Pre-size all the operand slots in the opnd_types table so profiling is as fast as possible
        let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
        let mut opnd_types = vec![vec![]; iseq_size as usize];
        let mut insn_idx = 0;
        while insn_idx < iseq_size {
            // Get the current pc and opcode
            let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx) };

            // try_into() call below is unfortunate. Maybe pick i32 instead of usize for opcodes.
            let opcode: ruby_vminsn_type = unsafe { rb_iseq_opcode_at_pc(iseq, pc) }
                .try_into()
                .unwrap();
            let n = match opcode {
                YARVINSN_zjit_opt_nil_p => 1,
                YARVINSN_zjit_opt_plus  => 2,
                YARVINSN_zjit_opt_minus => 2,
                YARVINSN_zjit_opt_mult  => 2,
                YARVINSN_zjit_opt_div   => 2,
                YARVINSN_zjit_opt_mod   => 2,
                YARVINSN_zjit_opt_eq    => 2,
                YARVINSN_zjit_opt_neq   => 2,
                YARVINSN_zjit_opt_lt    => 2,
                YARVINSN_zjit_opt_le    => 2,
                YARVINSN_zjit_opt_gt    => 2,
                YARVINSN_zjit_opt_ge    => 2,
                YARVINSN_zjit_opt_and   => 2,
                YARVINSN_zjit_opt_or    => 2,
                YARVINSN_zjit_opt_send_without_block => {
                    let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                    let argc = unsafe { vm_ci_argc((*cd).ci) };
                    argc + 1
                }
                _ => 0,  // Don't profile
            };
            opnd_types[insn_idx as usize].resize(n as usize, Empty);
            insn_idx += insn_len(opcode as usize);
        }
        Self { opnd_types }
    }

    /// Get profiled operand types for a given instruction index
    pub fn get_operand_types(&self, insn_idx: usize) -> Option<&[Type]> {
        self.opnd_types.get(insn_idx).map(|v| &**v)
    }

    /// Return true if top-two stack operands are Fixnums
    pub fn have_two_fixnums(&self, insn_idx: usize) -> bool {
        match self.get_operand_types(insn_idx) {
            Some([left, right]) => left.is_subtype(Fixnum) && right.is_subtype(Fixnum),
            _ => false,
        }
    }

    /// Run a given callback with every object in IseqProfile
    pub fn each_object(&self, callback: impl Fn(VALUE)) {
        for types in &self.opnd_types {
            for opnd_type in types {
                if let Some(object) = opnd_type.ruby_object() {
                    callback(object);
                }
            }
        }
    }
}
