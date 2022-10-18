#![cfg(test)]
use crate::asm::{CodeBlock};
use crate::backend::ir::*;
use crate::cruby::*;
use crate::utils::c_callable;

#[test]
fn test_add() {
    let mut asm = Assembler::new();
    let out = asm.add(SP, Opnd::UImm(1));
    let _ = asm.add(out, Opnd::UImm(2));
}

#[test]
fn test_alloc_regs() {
    let mut asm = Assembler::new();

    // Get the first output that we're going to reuse later.
    let out1 = asm.add(EC, Opnd::UImm(1));

    // Pad some instructions in to make sure it can handle that.
    let _ = asm.add(EC, Opnd::UImm(2));

    // Get the second output we're going to reuse.
    let out2 = asm.add(EC, Opnd::UImm(3));

    // Pad another instruction.
    let _ =  asm.add(EC, Opnd::UImm(4));

    // Reuse both the previously captured outputs.
    let _ = asm.add(out1, out2);

    // Now get a third output to make sure that the pool has registers to
    // allocate now that the previous ones have been returned.
    let out3 = asm.add(EC, Opnd::UImm(5));
    let _ = asm.add(out3, Opnd::UImm(6));

    // Here we're going to allocate the registers.
    let result = asm.alloc_regs(Assembler::get_alloc_regs());

    // Now we're going to verify that the out field has been appropriately
    // updated for each of the instructions that needs it.
    let regs = Assembler::get_alloc_regs();
    let reg0 = regs[0];
    let reg1 = regs[1];

    match result.insns[0].out_opnd() {
        Some(Opnd::Reg(value)) => assert_eq!(value, &reg0),
        val => panic!("Unexpected register value {:?}", val),
    }

    match result.insns[2].out_opnd() {
        Some(Opnd::Reg(value)) => assert_eq!(value, &reg1),
        val => panic!("Unexpected register value {:?}", val),
    }

    match result.insns[5].out_opnd() {
        Some(Opnd::Reg(value)) => assert_eq!(value, &reg0),
        val => panic!("Unexpected register value {:?}", val),
    }
}

fn setup_asm() -> (Assembler, CodeBlock) {
    return (
        Assembler::new(),
        CodeBlock::new_dummy(1024)
    );
}

// Test full codegen pipeline
#[test]
fn test_compile()
{
    let (mut asm, mut cb) = setup_asm();
    let regs = Assembler::get_alloc_regs();

    let out = asm.add(Opnd::Reg(regs[0]), Opnd::UImm(2));
    let out2 = asm.add(out, Opnd::UImm(2));
    asm.store(Opnd::mem(64, SP, 0), out2);

    asm.compile_with_num_regs(&mut cb, 1);
}

// Test memory-to-memory move
#[test]
fn test_mov_mem2mem()
{
    let (mut asm, mut cb) = setup_asm();

    asm.comment("check that comments work too");
    asm.mov(Opnd::mem(64, SP, 0), Opnd::mem(64, SP, 8));

    asm.compile_with_num_regs(&mut cb, 1);
}

// Test load of register into new register
#[test]
fn test_load_reg()
{
    let (mut asm, mut cb) = setup_asm();

    let out = asm.load(SP);
    asm.mov(Opnd::mem(64, SP, 0), out);

    asm.compile_with_num_regs(&mut cb, 1);
}

// Test load of a GC'd value
#[test]
fn test_load_value()
{
    let (mut asm, mut cb) = setup_asm();

    let gcd_value = VALUE(0xFFFFFFFFFFFF00);
    assert!(!gcd_value.special_const_p());

    let out = asm.load(Opnd::Value(gcd_value));
    asm.mov(Opnd::mem(64, SP, 0), out);

    asm.compile_with_num_regs(&mut cb, 1);
}

// Multiple registers needed and register reuse
#[test]
fn test_reuse_reg()
{
    let (mut asm, mut cb) = setup_asm();

    let v0 = asm.add(Opnd::mem(64, SP, 0), Opnd::UImm(1));
    let v1 = asm.add(Opnd::mem(64, SP, 8), Opnd::UImm(1));

    let v2 = asm.add(v1, Opnd::UImm(1)); // Reuse v1 register
    let v3 = asm.add(v0, v2);

    asm.store(Opnd::mem(64, SP, 0), v2);
    asm.store(Opnd::mem(64, SP, 8), v3);

    asm.compile_with_num_regs(&mut cb, 2);
}

// 64-bit values can't be written directly to memory,
// need to be split into one or more register movs first
#[test]
fn test_store_u64()
{
    let (mut asm, mut cb) = setup_asm();
    asm.store(Opnd::mem(64, SP, 0), u64::MAX.into());

    asm.compile_with_num_regs(&mut cb, 1);
}

// Use instruction output as base register for memory operand
#[test]
fn test_base_insn_out()
{
    let (mut asm, mut cb) = setup_asm();

    // Forced register to be reused
    // This also causes the insn sequence to change length
    asm.mov(
        Opnd::mem(64, SP, 8),
        Opnd::mem(64, SP, 0)
    );

    // Load the pointer into a register
    let ptr_reg = asm.load(Opnd::const_ptr(4351776248 as *const u8));
    let counter_opnd = Opnd::mem(64, ptr_reg, 0);

    // Increment and store the updated value
    asm.incr_counter(counter_opnd, 1.into());

    asm.compile_with_num_regs(&mut cb, 2);
}

#[test]
fn test_c_call()
{
    c_callable! {
        fn dummy_c_fun(_v0: usize, _v1: usize) {}
    }

    let (mut asm, mut cb) = setup_asm();

    let ret_val = asm.ccall(
        dummy_c_fun as *const u8,
        vec![Opnd::mem(64, SP, 0), Opnd::UImm(1)]
    );

    // Make sure that the call's return value is usable
    asm.mov(Opnd::mem(64, SP, 0), ret_val);

    asm.compile_with_num_regs(&mut cb, 1);
}

#[test]
fn test_alloc_ccall_regs() {
    let mut asm = Assembler::new();
    let out1 = asm.ccall(0 as *const u8, vec![]);
    let out2 = asm.ccall(0 as *const u8, vec![out1]);
    asm.mov(EC, out2);
    let mut cb = CodeBlock::new_dummy(1024);
    asm.compile_with_regs(&mut cb, Assembler::get_alloc_regs());
}

#[test]
fn test_lea_ret()
{
    let (mut asm, mut cb) = setup_asm();

    let addr = asm.lea(Opnd::mem(64, SP, 0));
    asm.cret(addr);

    asm.compile_with_num_regs(&mut cb, 1);
}

#[test]
fn test_jcc_label()
{
    let (mut asm, mut cb) = setup_asm();

    let label = asm.new_label("foo");
    asm.cmp(EC, EC);
    asm.je(label);
    asm.write_label(label);

    asm.compile_with_num_regs(&mut cb, 1);
}

#[test]
fn test_jcc_ptr()
{
    let (mut asm, mut cb) = setup_asm();

    let side_exit = Target::CodePtr(((cb.get_write_ptr().raw_ptr() as usize + 4) as *mut u8).into());
    let not_mask = asm.not(Opnd::mem(32, EC, RUBY_OFFSET_EC_INTERRUPT_MASK));
    asm.test(
        Opnd::mem(32, EC, RUBY_OFFSET_EC_INTERRUPT_FLAG),
        not_mask,
    );
    asm.jnz(side_exit);

    asm.compile_with_num_regs(&mut cb, 2);
}

/// Direct jump to a stub e.g. for deferred compilation
#[test]
fn test_jmp_ptr()
{
    let (mut asm, mut cb) = setup_asm();

    let stub = Target::CodePtr(((cb.get_write_ptr().raw_ptr() as usize + 4) as *mut u8).into());
    asm.jmp(stub);

    asm.compile_with_num_regs(&mut cb, 0);
}

#[test]
fn test_jo()
{
    let (mut asm, mut cb) = setup_asm();

    let side_exit = Target::CodePtr(((cb.get_write_ptr().raw_ptr() as usize + 4) as *mut u8).into());

    let arg1 = Opnd::mem(64, SP, 0);
    let arg0 = Opnd::mem(64, SP, 8);

    let arg0_untag = asm.sub(arg0, Opnd::Imm(1));
    let out_val = asm.add(arg0_untag, arg1);
    asm.jo(side_exit);

    asm.mov(Opnd::mem(64, SP, 0), out_val);

    asm.compile_with_num_regs(&mut cb, 2);
}

#[test]
fn test_bake_string() {
    let (mut asm, mut cb) = setup_asm();

    asm.bake_string("Hello, world!");
    asm.compile_with_num_regs(&mut cb, 0);
}

#[test]
fn test_draining_iterator() {

    let mut asm = Assembler::new();

    let _ = asm.load(Opnd::None);
    asm.store(Opnd::None, Opnd::None);
    let _ = asm.add(Opnd::None, Opnd::None);

    let mut iter = asm.into_draining_iter();

    while let Some((index, insn)) = iter.next_unmapped() {
        match index {
            0 => assert!(matches!(insn, Insn::Load { .. })),
            1 => assert!(matches!(insn, Insn::Store { .. })),
            2 => assert!(matches!(insn, Insn::Add { .. })),
            _ => panic!("Unexpected instruction index"),
        };
    }
}

#[test]
fn test_lookback_iterator() {
    let mut asm = Assembler::new();

    let _ = asm.load(Opnd::None);
    asm.store(Opnd::None, Opnd::None);
    asm.store(Opnd::None, Opnd::None);

    let iter = asm.into_lookback_iter();

    while let Some((index, insn)) = iter.next_unmapped() {
        if index > 0 {
            let opnd_iter = iter.get_previous().unwrap().opnd_iter();
            assert_eq!(opnd_iter.take(1).next(), Some(&Opnd::None));
            assert!(matches!(insn, Insn::Store { .. }));
        }
    }
}

#[test]
fn test_cmp_8_bit() {
    let (mut asm, mut cb) = setup_asm();
    let reg = Assembler::get_alloc_regs()[0];
    asm.cmp(Opnd::Reg(reg).with_num_bits(8).unwrap(), Opnd::UImm(RUBY_SYMBOL_FLAG as u64));

    asm.compile_with_num_regs(&mut cb, 1);
}
