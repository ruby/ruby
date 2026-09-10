//! Linux perf(1) [annotations](https://github.com/torvalds/linux/blob/v7.2/tools/perf/Documentation/jit-interface.txt) that help to symbolicate generated code.

use std::cell::RefCell;
use std::rc::Rc;

use crate::asm::CodeBlock;
use crate::cruby::{IseqPtr, iseq_get_location};
use crate::backend::lir::{Assembler, Insn as LirInsn};
use crate::hir::Insn;
use crate::options::{get_option, PerfMap};
use crate::options::debug;
use crate::virtualmem::CodePtr;

type SymbolRange = Rc<RefCell<Option<(CodePtr, String)>>>;

/// Register a non-empty code range under `symbol_name` in the perf map.
pub(crate) fn register_range(cb: &CodeBlock, symbol_name: String, start: CodePtr, end: CodePtr) {
    let start_ptr = start.raw_addr(cb);
    let end_ptr = end.raw_addr(cb);
    if start_ptr < end_ptr {
        register(symbol_name, start_ptr, end_ptr - start_ptr);
    }
}

/// Register the code emitted from `start` through the current write pointer
/// under `symbol_name` in the perf map, if perf output is enabled.
pub(crate) fn register_current_code_range(cb: &CodeBlock, symbol_name: &str, start: CodePtr) {
    if get_option!(perf).is_some() {
        register_range(cb, symbol_name.to_string(), start, cb.get_write_ptr());
    }
}

/// Register an ISEQ code range when ISEQ perf output is enabled.
pub(crate) fn register_current_iseq_range(cb: &CodeBlock, iseq: IseqPtr, start: CodePtr) {
    if get_option!(perf) == Some(PerfMap::ISEQ) {
        register_range(cb, iseq_get_location(iseq, 0), start, cb.get_write_ptr());
    }
}

/// Start a HIR symbol range when HIR perf output is enabled.
pub(crate) fn hir_symbol_range_start(asm: &mut Assembler, insn: &Insn) -> Option<SymbolRange> {
    let symbol_range = new_hir_symbol_range()?;
    let insn_name = format!("{insn}");
    Some(install_symbol_range_start(asm, symbol_range, insn_name.split_whitespace().next().unwrap()))
}

/// Mark the start of a symbol range when HIR perf output is enabled.
/// Returns None otherwise.
pub(crate) fn symbol_range_start(asm: &mut Assembler, symbol_name: &str) -> Option<SymbolRange> {
    let symbol_range = new_hir_symbol_range()?;
    Some(install_symbol_range_start(asm, symbol_range, symbol_name))
}

/// Mark the end of a symbol range via pos_marker.
pub(crate) fn symbol_range_end(asm: &mut Assembler, symbol_range: &SymbolRange) {
    asm.pos_marker(symbol_range_end_marker(symbol_range));
}

/// Mark the end of a symbol range at the end of the current LIR block.
/// A terminator jump can be removed when it targets the next linear block.
/// This can leave an empty range. `register_range` skips that entry.
pub(crate) fn symbol_range_end_at_block_end(asm: &mut Assembler, symbol_range: &SymbolRange) {
    asm.pos_marker_at_block_end(symbol_range_end_marker(symbol_range));
}

/// Push instructions and register their code range when HIR perf output is enabled.
pub(crate) fn push_insns_with_hir_symbol(
    insns: &mut Vec<LirInsn>,
    symbol_name: &str,
    push_insns: impl FnOnce(&mut Vec<LirInsn>),
) {
    let Some(symbol_range) = symbol_range_start_for_insns(insns, symbol_name) else {
        push_insns(insns);
        return;
    };

    push_insns(insns);
    insns.push(LirInsn::PosMarker(Rc::new(symbol_range_end_marker(&symbol_range))));
}

/// Write an entry to the perf map in /tmp.
fn register(symbol_name: String, start_ptr: usize, code_size: usize) {
    use std::io::Write;
    let perf_map = format!("/tmp/perf-{}.map", std::process::id());
    let Ok(file) = std::fs::OpenOptions::new().create(true).append(true).open(&perf_map) else {
        debug!("Failed to open perf map file: {perf_map}");
        return;
    };
    let mut file = std::io::BufWriter::new(file);
    let Ok(_) = writeln!(file, "{start_ptr:#x} {code_size:#x} ZJIT: {symbol_name}") else {
        debug!("Failed to write {symbol_name} to perf map file: {perf_map}");
        return;
    };
}

fn new_hir_symbol_range() -> Option<SymbolRange> {
    (get_option!(perf) == Some(PerfMap::HIR)).then(|| Rc::new(RefCell::new(None)))
}

fn symbol_range_start_for_insns(insns: &mut Vec<LirInsn>, symbol_name: &str) -> Option<SymbolRange> {
    let symbol_range = new_hir_symbol_range()?;
    insns.push(LirInsn::PosMarker(Rc::new(symbol_range_start_marker(&symbol_range, symbol_name.to_string()))));
    Some(symbol_range)
}

fn install_symbol_range_start(
    asm: &mut Assembler,
    symbol_range: SymbolRange,
    symbol_name: &str,
) -> SymbolRange {
    asm.pos_marker(symbol_range_start_marker(&symbol_range, symbol_name.to_string()));
    symbol_range
}

fn symbol_range_start_marker(
    symbol_range: &SymbolRange,
    symbol_name: String,
) -> impl Fn(CodePtr, &CodeBlock) + 'static {
    let current = symbol_range.clone();
    move |start, _| {
        let mut current = current.borrow_mut();
        assert!(current.is_none(), "perf symbol range already open");
        *current = Some((start, symbol_name.clone()));
    }
}

fn symbol_range_end_marker(symbol_range: &SymbolRange) -> impl Fn(CodePtr, &CodeBlock) + 'static {
    let current = symbol_range.clone();
    move |end, cb| {
        if let Some((start, name)) = current.borrow_mut().take() {
            register_range(cb, name, start, end);
        }
    }
}
