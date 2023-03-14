extern crate gimli;
extern crate object;

use gimli::write::Writer;
use crate::codegen::CodePtr;
use crate::cruby::{rb_yjit_register_unwind_info, rb_yjit_deregister_unwind_info};
use std::collections::HashMap;
use std::rc::Rc;
use std::cell::RefCell;
use std::ops::Range;

/// CStackSetupRule defines the expectations a block of YJIT code makes about
/// the state of the C stack when it's called.
#[derive(Copy, Clone, Debug, Eq, PartialEq, Hash)]
pub enum CStackSetupRule {
    /// Blocks that have the CalledFromC CIE are YJIT entry points; they are called
    /// directly from the CRuby code. That means the stack will be set up as per the
    /// normal platform ABI for function entry.
    CalledFromC,

    /// Blocks that have the NormalJumpFromJITCode CIE are targets of jumps from YJIT
    /// generated code; the C-stack setup has already been done by an entry point. That
    /// means the stack has been set up by gen_entry_prologue, including the frame setup
    /// and the saving of the callee-saved registers used for CFP, EP, and SP.
    NormalJumpFromJITCode,

    /// Don't generate any CFI
    None,
}

/// A CFIDirective represents the effect an instruction has on the rules used to unwind
/// the stack.
/// Mirrors https://sourceware.org/binutils/docs/as/CFI-directives.html#g_t_002ecfi_005fstartproc-_005bsimple_005d
#[derive(Copy, Clone, Debug)]
#[allow(dead_code)]
pub enum CFIDirective {
    /// .cfi_startproc - marks the beginning of a block of code with unwind rules
    StartProc(CStackSetupRule),

    /// .cfi_endproc - marks the end of a block of code with unwind rules
    EndProc(),

    /// .cfi_def_cfa - defines the CFA (canonical frame address) as *reg + offset
    DefCFA(platform::Reg, i32),

    /// .cfi_def_cfa_register - changes the CFA register, keeping the same offset
    DefCFARegister(platform::Reg),

    /// .cfi_def_cfa_offset - changes the CFA offset, keeping the same register
    DefCFAOffset(i32),

    /// .cfi_adjust_cfa_offset - adds to the current CFA offset
    AdjustCFAOffset(i32),

    /// .cfi_offset - the value of reg in the previous frame can be found at CFA + i32
    Offset(platform::Reg, i32),

    ///.cfi_rel_offset - the value of reg in the previous frame can be found at *(CFA register) + i32
    RelOffset(platform::Reg, i32),

    /// .cfi_restore - reset the rule for reg to what it was when .cfi_startproc was used
    Restore(platform::Reg),

    // This is not a real CFI directive that GNU assembler supports,
    // but rather a signal that this "FDE" is actually split across pages
    // and needs to be two FDE's. The DWARF standard specifies that FDE's
    // must be contiguous, but YJIT can generate blocks that span two pages
    // with a jump instruction connecting them. 
    Split(CodePtr)
}

/// A CFIDirective for an instruction at a particular address
#[derive(Copy, Clone, Debug)]
pub struct CFIDirectiveWithAddr {
    /// The address being annotated
    pub addr: CodePtr,

    /// The CFI directive
    pub directive: CFIDirective,
}

/// An UnwindInfoManager which looks after the unwind info for the all the YJIT
/// generated code in the proces. It's a singleton registered on the CodegenGlobals.
pub struct UnwindInfoManager {
    /// A list of all DWARF CIEs for this architecture, one per stack rule.
    /// This is set up at boot and never changed.
    cies: HashMap<CStackSetupRule, gimli::write::CieId>,

    /// The frame table holds all of the DWARF CIEs and FDEs we generate
    frame_table: gimli::write::FrameTable,

    /// This is the index of the first entry in the frame table that we have _NOT_
    /// yet emitted to the .eh_frame section in active_object/standby_object.
    next_fde_ix: usize,

    /// The raw bytes of a real ELF/MachO/etc object containing the .eh_frame
    /// section which has the unwind info for this process. The active_object is
    /// currently registered with the runtime as providing the info.
    active_object: Vec<u8>,

    /// The standby_object is where we build up an appropriate ELF/MachO/etc object
    /// before promoting it to the active_object.
    standby_object: Vec<u8>,

    /// This is the range of bytes inside the standby_object that contains the
    /// .eh_frame section data
    unwind_info_section_range: Range<usize>,

    /// This is the range of bytes inside the standby_object that contains the
    /// free space at the end of the .eh_frame section data. This "free space"
    /// includes the terminating zero-length FDE
    unwind_info_section_free_space_range: Range<usize>,

    /// Whether or not we have actually registered active_object with the runtime
    handler_registered: bool,

    /// When this flag is set, we will stop attempting to write FDEs into the empty
    /// space inside the standby_object's .eh_frame section, and instead regenerate
    /// an entirely new object. This gets set when code objects are freed, since
    /// we have no other way to remove their unwind info.
    object_invalidated: bool,
}

/// An implementation of Gimli's EndianWriter interface which can append to a slice.
struct DwarfSliceWriter<'a, TEndian: gimli::Endianity> {
    buf: &'a mut[u8],
    endian: TEndian,
    ix: usize,
}

impl<'a, TEndian> DwarfSliceWriter<'a, TEndian>
where
    TEndian: gimli::Endianity
{
    fn new(buf: &'a mut[u8], endian: TEndian) -> Self {
        Self { buf, endian, ix: 0 }
    }
}

impl<'a, TEndian> gimli::write::Writer for DwarfSliceWriter<'a, TEndian>
where
    TEndian: gimli::Endianity,
{
    type Endian = TEndian;

    fn endian(&self) -> Self::Endian {
        self.endian
    }

    fn len(&self) -> usize {
        self.ix
    }

    fn write(&mut self, bytes: &[u8]) -> gimli::write::Result<()> {
        let target_slice = &mut self.buf[self.ix..];
        if target_slice.len() < bytes.len() {
            return Err(gimli::write::Error::LengthOutOfBounds);
        }
        target_slice[..bytes.len()].copy_from_slice(bytes);
        self.ix += bytes.len();
        Ok(())
    }

    fn write_at(&mut self, offset: usize, bytes: &[u8]) -> gimli::write::Result<()> {
        let target_slice = &mut self.buf[offset..];
        if offset > target_slice.len() {
            return Err(gimli::write::Error::OffsetOutOfBounds);
        }
        if target_slice.len() < bytes.len() {
            return Err(gimli::write::Error::LengthOutOfBounds);
        }
        target_slice[..bytes.len()].copy_from_slice(bytes);
        Ok(())
    }

}

impl UnwindInfoManager {
    /// Constructs a new unwind info manager
    pub fn new() -> Self {
        let mut frame_table = gimli::write::FrameTable::default();
        let mut cies = HashMap::<CStackSetupRule, gimli::write::CieId>::new();
        for (stack_rule, cie) in platform::cies_for_all_stack_rules().into_iter() {
            cies.insert(stack_rule, frame_table.add_cie(cie));
        }

        Self {
            cies,
            frame_table,
            next_fde_ix: 0,
            active_object: Vec::new(),
            standby_object: Vec::new(),
            unwind_info_section_range: 0..0,
            unwind_info_section_free_space_range: 0..0,
            handler_registered: false,
            object_invalidated: true,
        }
    }

    /// Called with a slice of CFIDirectiveWithAddr to add unwind info for newly-generated
    /// blocks to the standby_object. The directives list can actually refer to multiple blocks,
    /// with matching StartProc/EndProc directives.
    pub fn add_unwind_info(&mut self, directives: &[CFIDirectiveWithAddr]) {
        struct FDEState {
            start_addr: CodePtr,
            end_addr: Option<CodePtr>,
            stack_rule: CStackSetupRule,
            current_cfa_offset: i32,
            insns: Vec::<(CodePtr, gimli::write::CallFrameInstruction)>,
        }

        fn new_fde_state(stack_rule: CStackSetupRule, start_addr: CodePtr) -> Rc<RefCell<FDEState>> {
            Rc::new(RefCell::new(FDEState {
                start_addr,
                end_addr: None,
                stack_rule,
                current_cfa_offset: 0,
                insns: Vec::new(),
            }))
        }

        // There may be more than one FDE generated, either because there are multiple blocks
        // described in directives, or because this block is split across pages.
        let mut fde_vec = Vec::<Rc<RefCell<FDEState>>>::new();
        let mut current_fde = Option::<Rc<RefCell<FDEState>>>::None;

        for i in directives.iter() {
            match i.directive {
                CFIDirective::StartProc(stack_rule) => {
                    if current_fde.is_some() {
                        panic!("CFI StartProc called twice")
                    }
                    let state = new_fde_state(stack_rule, i.addr);
                    fde_vec.push(state.clone());
                    current_fde.replace(state);
                },
                CFIDirective::EndProc() => {
                    let mut state = current_fde.as_mut().take().expect("CFI StartProc not called").borrow_mut();
                    state.end_addr.replace(i.addr);
                },
                CFIDirective::DefCFA(reg, cfa_offset) => {
                    let mut state = current_fde.as_mut().expect("CFI StartProc not called").borrow_mut();
                    state.insns.push((i.addr, gimli::write::CallFrameInstruction::Cfa(
                        gimli::Register(reg.reg_no.into()), cfa_offset,
                    )));
                    state.current_cfa_offset = cfa_offset;
                },
                CFIDirective::DefCFAOffset(cfa_offset) => {
                    let mut state = current_fde.as_mut().expect("CFI StartProc not called").borrow_mut();
                    state.insns.push((i.addr, gimli::write::CallFrameInstruction::CfaOffset(
                        cfa_offset,
                    )));
                    state.current_cfa_offset = cfa_offset;
                },
                CFIDirective::DefCFARegister(reg) => {
                    let mut state = current_fde.as_mut().expect("CFI StartProc not called").borrow_mut();
                    state.insns.push((i.addr, gimli::write::CallFrameInstruction::CfaRegister(
                        gimli::Register(reg.reg_no.into())
                    )));
                },
                CFIDirective::AdjustCFAOffset(cfa_offset_adj) => {
                    let mut state = current_fde.as_mut().expect("CFI StartProc not called").borrow_mut();
                    state.current_cfa_offset += cfa_offset_adj;
                    let o = state.current_cfa_offset;
                    state.insns.push((i.addr, gimli::write::CallFrameInstruction::CfaOffset(o)));
                },
                CFIDirective::Offset(reg, cfa_offset) => {
                    let mut state = current_fde.as_mut().expect("CFI StartProc not called").borrow_mut();
                    state.insns.push((i.addr, gimli::write::CallFrameInstruction::Offset(
                        gimli::Register(reg.reg_no.into()), cfa_offset,
                    )));
                },
                CFIDirective::RelOffset(reg, cfa_offset_rel) => {
                    let mut state = current_fde.as_mut().expect("CFI StartProc not called").borrow_mut();
                    let o = state.current_cfa_offset + cfa_offset_rel;
                    state.insns.push((i.addr, gimli::write::CallFrameInstruction::Offset(
                        gimli::Register(reg.reg_no.into()), o,
                    )));
                }
                CFIDirective::Restore(reg) => {
                    let mut state = current_fde.as_mut().expect("CFI StartProc not called").borrow_mut();
                    state.insns.push((i.addr, gimli::write::CallFrameInstruction::Restore(
                        gimli::Register(reg.reg_no.into())
                    )));
                }
                CFIDirective::Split(from) => {
                    let mut old_state = current_fde.as_mut().take().expect("CFI StartProc not called").borrow_mut();
                    // Mark old state as finished at the given address
                    old_state.end_addr.replace(from);
                    // Create a new state for the new page.
                    // Give it the same stack rule as the original, because we're _also_ going to copy the instructions over...
                    // That way, we don't need to worry if we've split a cpush/cpop pair across a page boundary, for example.
                    let new_state = new_fde_state(old_state.stack_rule, i.addr);
                    for (_, insn) in old_state.insns.iter() {
                        new_state.borrow_mut().insns.push((i.addr, insn.clone()));
                    }
                    new_state.borrow_mut().current_cfa_offset = old_state.current_cfa_offset;

                    std::mem::drop(old_state);
                    fde_vec.push(new_state.clone());
                    current_fde.replace(new_state);
                }
            };
        }
        
        for state_ref in fde_vec.into_iter() {
            let state = state_ref.borrow();

            if state.stack_rule == CStackSetupRule::None {
                continue;
            }

            let start_addr_num = state.start_addr.into_u64();
            let end_addr_num = state.end_addr.expect("CFI EndProc not used").into_u64();
            let length = (end_addr_num - start_addr_num) as u32;
            if length == 0 {
                // Don't generate a FDE for an empty block
                continue;
            }

            let mut fde = gimli::write::FrameDescriptionEntry::new(
                gimli::write::Address::Constant(state.start_addr.into_u64()), length
            );
            for (addr, insn) in state.insns.iter() {
                fde.add_instruction((addr.into_u64() - start_addr_num) as u32, insn.clone())
            }
            let cie_ix = self.cies.get(&state.stack_rule).expect("CIE table not filled!").clone();
            self.frame_table.add_fde(cie_ix, fde);
        }
    }

    /// Sets standby_object to a new object containing all .eh_frame data in the frame table
    fn flush_to_new_object(&mut self) {
        let mut obj = object::write::Object::new(
            platform::OBJECT_FORMAT,
            platform::OBJECT_ARCHITECTURE,
            platform::OBJECT_ENDIANNESS,
        );
        let eh_frame_section_id = obj.add_section(
            "".as_bytes().to_vec(),
            platform::UNWIND_SECTION_NAME.as_bytes().to_vec(),
            object::SectionKind::ReadOnlyData,
        );

        let mut eh_frame_section = gimli::write::EhFrame(
            gimli::write::EndianVec::new(platform::DwarfEndianness::default())
        );
        self.next_fde_ix = self.frame_table.write_eh_frame_from(&mut eh_frame_section, 0).unwrap();

        obj.section_mut(eh_frame_section_id).append_data(eh_frame_section.slice(), 8);
        // _also_ append this-much-again empty data, for growth. Also the first zero is the "empty FDE"
        // at the end of the eh_frame section, which signals its termination.
        let grow_by = std::cmp::max(eh_frame_section.len(), 2048);
        obj.section_mut(eh_frame_section_id).append_data(vec![0; grow_by].as_slice(), 1);

        self.standby_object = obj.write().unwrap();

        // Where is the eh_frame in this final data, and where does it end?
        let reparsed_object = object::File::parse(self.standby_object.as_slice()).unwrap();
        let reparsed_object_section = object::read::Object::section_by_name(
            &reparsed_object, platform::UNWIND_SECTION_NAME
        ).unwrap();
        let eh_frame_range = object::read::ObjectSection::file_range(&reparsed_object_section).unwrap();
        self.unwind_info_section_range = Range {
            start: (eh_frame_range.0) as usize,
            end: (eh_frame_range.0 as usize) + (eh_frame_range.1 as usize),
        };
        self.unwind_info_section_free_space_range = Range {
            start: (eh_frame_range.0 as usize) + eh_frame_section.len(),
            // chomp off one u32 at the end of this "free" space range, which is thus a terminator.
            end: (eh_frame_range.0 as usize) + (eh_frame_range.1 as usize) - std::mem::size_of::<u32>(),
        };
        self.object_invalidated = false;
    }

    /// Attempts to append new FDEs from the frame table to the existing .eh_frame section
    /// in the standby object, if they fit.
    fn flush_into_existing_object(&mut self) -> Result<Range<usize>, ()> {
        // If we haven't got an existing object, make this fail. Note that even if we're writing zero FDE's, we want
        // to make sure the object exists so we have something valid to register.
        if self.standby_object.len() == 0 || self.object_invalidated {
            return Err(())
        }

        let initial_free_space_start = self.unwind_info_section_free_space_range.start;
        let eh_frame_slice = &mut self.standby_object[self.unwind_info_section_free_space_range.clone()];
        let mut eh_frame_section = gimli::write::EhFrame(
            DwarfSliceWriter::new(eh_frame_slice, platform::DwarfEndianness::default())
        );
        let next_ix = self.frame_table.write_eh_frame_from(&mut eh_frame_section, self.next_fde_ix);
        match next_ix {
            Ok(ix) => {
                self.next_fde_ix = ix;
                self.unwind_info_section_free_space_range.start += eh_frame_section.0.ix;
                Ok(initial_free_space_start..self.unwind_info_section_free_space_range.start)
            }
            Err(_) => {
                // Means it didn't fit - we'll need to construct a new object.
                Err(())
            }
        }
    }

    /// Swaps the active and standby objects, registering the new unwind info added
    /// through add_unwind_info with the runtime.
    pub fn flush_and_register(&mut self) {
        // Save this so we can find the right offset to deregister the currently-active eh_frame section.
        let original_unwind_info_section_range = self.unwind_info_section_range.clone();

        // Write new FDE's into the standby object (possibly re-creating it if it needed
        // to be grown)
        let range_to_copy =  match self.flush_into_existing_object() {
            Ok(invalidate_range) => {
                // It fit - we'll copy the given range into the other buffer.
                Option::Some(invalidate_range)
            }
            Err(()) => {
                // It did not fit - generate a whole new object, and copy it _all_ over.
                self.flush_to_new_object();
                Option::<Range<usize>>::None
            }
        };

        // Register the _new_ copy.
        unsafe {
            // Saftey: these two pointers alias each other, but the C side does not actually
            // write to them.
            let obj_ptr = self.standby_object.as_mut_ptr();
            let obj_size = self.standby_object.len() as u64;
            let eh_frame_ptr = self.standby_object[self.unwind_info_section_range.clone()].as_mut_ptr();
            rb_yjit_register_unwind_info(obj_ptr, obj_size, eh_frame_ptr);
        }

        // FROM THIS MOMENT - the meaning of active/standby is flipped.
        std::mem::swap(&mut self.active_object, &mut self.standby_object);

        // and un-register the _old_ copy
        if self.handler_registered {
            unsafe {
                let obj_ptr = self.standby_object.as_mut_ptr();
                let obj_size = self.standby_object.len() as u64;
                let eh_frame_ptr = self.standby_object[original_unwind_info_section_range].as_mut_ptr();
                rb_yjit_deregister_unwind_info(obj_ptr, obj_size, eh_frame_ptr);
            }
        }

        // Copy from new -> old now.
        match range_to_copy {
            Some(range) => {
                self.standby_object[range.clone()].copy_from_slice(&self.active_object[range]);
            }
            None => {
                self.standby_object = self.active_object.clone();
            }
        };

        self.handler_registered = true;
    }

    /// Remove all unwind info for blocks that overlap the provided range; called to remove
    /// blocks from the unwind info during code GC.
    pub fn free_info_for_range(&mut self, free_range: Range<CodePtr>) {
        let free_range_u64 = free_range.start.into_u64()..free_range.end.into_u64();
        self.frame_table.retain_fdes(|_, fde| {
            if let gimli::write::Address::Constant(fde_addr) = fde.address() {
                let fde_addr_range = fde_addr..(fde_addr + (fde.length() as u64));
                // Does fde_addr_range NOT overlap with the free_range?
                !(fde_addr_range.start <= free_range_u64.end && fde_addr_range.end >= free_range_u64.start)
            } else {
                // We don't use non-constant addresses at all.
                unreachable!();
            }
        });
        // We'll definitely need to make a new object.
        self.next_fde_ix = 0;
        self.object_invalidated = true;
    }
}


// Platform-specific parts of the unwinder
#[cfg(target_arch = "aarch64")]
mod arm64 {
    use super::*;

    pub type Reg = crate::backend::arm64::Reg;
    pub type DwarfEndianness = gimli::LittleEndian;
    pub const OBJECT_ARCHITECTURE : object::Architecture = object::Architecture::Aarch64;
    pub const OBJECT_ENDIANNESS : object::Endianness = object::Endianness::Little;

    pub fn cies_for_all_stack_rules() -> HashMap<CStackSetupRule, gimli::write::CommonInformationEntry> {
        let mut r = HashMap::<CStackSetupRule, gimli::write::CommonInformationEntry>::new();

        let encoding = gimli::Encoding {
            address_size: 8,
            format: gimli::Format::Dwarf32,
            version: 1,
        };
        let code_alignment_factor = 4;
        let data_alignment_factor = -8;
        let return_address_register = gimli::Register(30);

        let mut cie_called_from_c = gimli::write::CommonInformationEntry::new(
            encoding, code_alignment_factor, data_alignment_factor, return_address_register,
        );
        cie_called_from_c.fde_address_encoding = gimli::DW_EH_PE_absptr;
        cie_called_from_c.add_instruction(
            gimli::write::CallFrameInstruction::Cfa(
                gimli::Register(31), initial_cfa_offset_for_rule(CStackSetupRule::CalledFromC)
            )
        );
        cie_called_from_c.add_instruction(
            gimli::write::CallFrameInstruction::SameValue(gimli::Register(29))
        );
        cie_called_from_c.add_instruction(
            gimli::write::CallFrameInstruction::SameValue(gimli::Register(30))
        );

        let mut cie_normal_jump_from_yjit = gimli::write::CommonInformationEntry::new(
            encoding, code_alignment_factor, data_alignment_factor, return_address_register,
        );
        cie_normal_jump_from_yjit.fde_address_encoding = gimli::DW_EH_PE_absptr;
        cie_normal_jump_from_yjit.add_instruction(
            gimli::write::CallFrameInstruction::Cfa(
                gimli::Register(31), initial_cfa_offset_for_rule(CStackSetupRule::NormalJumpFromJITCode)
            )
        );
        cie_normal_jump_from_yjit.add_instruction(
            gimli::write::CallFrameInstruction::Offset(
                gimli::Register(29), -16
            )
        );
        cie_normal_jump_from_yjit.add_instruction(
            gimli::write::CallFrameInstruction::Offset(
                gimli::Register(30), -8
            )
        );

        r.insert(CStackSetupRule::CalledFromC, cie_called_from_c);
        r.insert(CStackSetupRule::NormalJumpFromJITCode, cie_normal_jump_from_yjit);
        r
    }

    pub fn initial_cfa_offset_for_rule(rule: CStackSetupRule) -> i32 {
        match rule {
            CStackSetupRule::CalledFromC => 0,
            // Entry prologue code looks like this on aarch64:
            // stp x29, x30, [sp, #-0x10]!
            // mov x29, sp
            // str x19, [sp, #-0x10]!
            // str x20, [sp, #-0x10]!
            // str x21, [sp, #-0x10]!
            // Yes, we use 16 bytes of stack space each to store the 8-byte registers
            // x19, x20, and x21.
            CStackSetupRule::NormalJumpFromJITCode => 64,
            CStackSetupRule::None => 0,
        }
    }
}

#[cfg(target_arch = "x86_64")]
mod x86_64 {
    use super::*;

    pub type Reg = crate::backend::x86_64::Reg;
    pub type DwarfEndianness = gimli::LittleEndian;
    pub const OBJECT_ARCHITECTURE : object::Architecture = object::Architecture::X86_64;
    pub const OBJECT_ENDIANNESS : object::Endianness = object::Endianness::Little;

    pub fn cies_for_all_stack_rules() -> HashMap<CStackSetupRule, gimli::write::CommonInformationEntry> {
        panic!("implement me");
    }

    pub fn initial_cfa_offset_for_rule(rule: CStackSetupRule) -> i32 {
        panic!("implement me");
    }
}

#[cfg(any(target_os = "linux", target_os = "freebsd", target_os = "openbsd", target_os = "netbsd"))]
mod elf {
    pub const OBJECT_FORMAT : object::BinaryFormat = object::BinaryFormat::Elf;
    pub const UNWIND_SECTION_NAME : &str = ".eh_frame";
}

#[cfg(target_os = "macos")]
mod macho {
    pub const OBJECT_FORMAT : object::BinaryFormat = object::BinaryFormat::MachO;
    pub const UNWIND_SECTION_NAME : &str = "__eh_frame";
}

mod platform {
    #[cfg(target_arch = "aarch64")]
    pub use super::arm64::*;

    #[cfg(target_arch = "x86_64")]
    pub use super::x86_64::*;

    #[cfg(any(target_os = "linux", target_os = "freebsd", target_os = "openbsd", target_os = "netbsd"))]
    pub use super::elf::*;

    #[cfg(target_os = "macos")]
    pub use super::macho::*;
}