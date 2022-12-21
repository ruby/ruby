use crate::asm::*;
use crate::backend::ir::*;
use crate::codegen::*;
use crate::virtualmem::CodePtr;
use crate::cruby::*;
use crate::options::*;
use crate::stats::*;
use crate::utils::*;
#[cfg(feature="disasm")]
use crate::disasm::*;
use core::ffi::c_void;
use std::cell::*;
use std::collections::HashSet;
use std::hash::{Hash, Hasher};
use std::mem;
use std::rc::{Rc};
use YARVOpnd::*;
use TempMapping::*;
use crate::invariants::block_assumptions_free;

// Maximum number of temp value types we keep track of
pub const MAX_TEMP_TYPES: usize = 8;

// Maximum number of local variable types we keep track of
const MAX_LOCAL_TYPES: usize = 8;

// Represent the type of a value (local/stack/self) in YJIT
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Type {
    Unknown,
    UnknownImm,
    UnknownHeap,
    Nil,
    True,
    False,
    Fixnum,
    Flonum,
    Array,
    Hash,
    ImmSymbol,

    #[allow(unused)]
    HeapSymbol,

    TString, // An object with the T_STRING flag set, possibly an rb_cString
    CString, // An un-subclassed string of type rb_cString (can have instance vars in some cases)

    BlockParamProxy, // A special sentinel value indicating the block parameter should be read from
                     // the current surrounding cfp
}

// Default initialization
impl Default for Type {
    fn default() -> Self {
        Type::Unknown
    }
}

impl Type {
    /// This returns an appropriate Type based on a known value
    pub fn from(val: VALUE) -> Type {
        if val.special_const_p() {
            if val.fixnum_p() {
                Type::Fixnum
            } else if val.nil_p() {
                Type::Nil
            } else if val == Qtrue {
                Type::True
            } else if val == Qfalse {
                Type::False
            } else if val.static_sym_p() {
                Type::ImmSymbol
            } else if val.flonum_p() {
                Type::Flonum
            } else {
                unreachable!("Illegal value: {:?}", val)
            }
        } else {
            // Core.rs can't reference rb_cString because it's linked by Rust-only tests.
            // But CString vs TString is only an optimisation and shouldn't affect correctness.
            #[cfg(not(test))]
            if val.class_of() == unsafe { rb_cString } {
                return Type::CString;
            }
            // We likewise can't reference rb_block_param_proxy, but it's again an optimisation;
            // we can just treat it as a normal Object.
            #[cfg(not(test))]
            if val == unsafe { rb_block_param_proxy } {
                return Type::BlockParamProxy;
            }
            match val.builtin_type() {
                RUBY_T_ARRAY => Type::Array,
                RUBY_T_HASH => Type::Hash,
                RUBY_T_STRING => Type::TString,
                _ => Type::UnknownHeap,
            }
        }
    }

    /// Check if the type is an immediate
    pub fn is_imm(&self) -> bool {
        match self {
            Type::UnknownImm => true,
            Type::Nil => true,
            Type::True => true,
            Type::False => true,
            Type::Fixnum => true,
            Type::Flonum => true,
            Type::ImmSymbol => true,
            _ => false,
        }
    }

    /// Returns true when the type is not specific.
    pub fn is_unknown(&self) -> bool {
        match self {
            Type::Unknown | Type::UnknownImm | Type::UnknownHeap => true,
            _ => false,
        }
    }

    /// Returns true when we know the VALUE is a specific handle type,
    /// such as a static symbol ([Type::ImmSymbol], i.e. true from RB_STATIC_SYM_P()).
    /// Opposite of [Self::is_unknown].
    pub fn is_specific(&self) -> bool {
        !self.is_unknown()
    }

    /// Check if the type is a heap object
    pub fn is_heap(&self) -> bool {
        match self {
            Type::UnknownHeap => true,
            Type::Array => true,
            Type::Hash => true,
            Type::HeapSymbol => true,
            Type::TString => true,
            Type::CString => true,
            _ => false,
        }
    }

    /// Returns an Option with the T_ value type if it is known, otherwise None
    pub fn known_value_type(&self) -> Option<ruby_value_type> {
        match self {
            Type::Nil => Some(RUBY_T_NIL),
            Type::True => Some(RUBY_T_TRUE),
            Type::False => Some(RUBY_T_FALSE),
            Type::Fixnum => Some(RUBY_T_FIXNUM),
            Type::Flonum => Some(RUBY_T_FLOAT),
            Type::Array => Some(RUBY_T_ARRAY),
            Type::Hash => Some(RUBY_T_HASH),
            Type::ImmSymbol | Type::HeapSymbol => Some(RUBY_T_SYMBOL),
            Type::TString | Type::CString => Some(RUBY_T_STRING),
            Type::Unknown | Type::UnknownImm | Type::UnknownHeap => None,
            Type::BlockParamProxy => None,
        }
    }

    /// Returns an Option with the class if it is known, otherwise None
    pub fn known_class(&self) -> Option<VALUE> {
        unsafe {
            match self {
                Type::Nil => Some(rb_cNilClass),
                Type::True => Some(rb_cTrueClass),
                Type::False => Some(rb_cFalseClass),
                Type::Fixnum => Some(rb_cInteger),
                Type::Flonum => Some(rb_cFloat),
                Type::ImmSymbol | Type::HeapSymbol => Some(rb_cSymbol),
                Type::CString => Some(rb_cString),
                _ => None,
            }
        }
    }

    /// Returns an Option with the exact value if it is known, otherwise None
    #[allow(unused)] // not yet used
    pub fn known_exact_value(&self) -> Option<VALUE> {
        match self {
            Type::Nil => Some(Qnil),
            Type::True => Some(Qtrue),
            Type::False => Some(Qfalse),
            _ => None,
        }
    }

    /// Returns an Option boolean representing whether the value is truthy if known, otherwise None
    pub fn known_truthy(&self) -> Option<bool> {
        match self {
            Type::Nil => Some(false),
            Type::False => Some(false),
            Type::UnknownHeap => Some(true),
            Type::Unknown | Type::UnknownImm => None,
            _ => Some(true)
        }
    }

    /// Returns an Option boolean representing whether the value is equal to nil if known, otherwise None
    pub fn known_nil(&self) -> Option<bool> {
        match (self, self.known_truthy()) {
            (Type::Nil, _) => Some(true),
            (Type::False, _) => Some(false), // Qfalse is not nil
            (_, Some(true))  => Some(false), // if truthy, can't be nil
            (_, _) => None // otherwise unknown
        }
    }

    /// Compute a difference between two value types
    /// Returns 0 if the two are the same
    /// Returns > 0 if different but compatible
    /// Returns usize::MAX if incompatible
    pub fn diff(self, dst: Self) -> usize {
        // Perfect match, difference is zero
        if self == dst {
            return 0;
        }

        // Any type can flow into an unknown type
        if dst == Type::Unknown {
            return 1;
        }

        // A CString is also a TString.
        if self == Type::CString && dst == Type::TString {
            return 1;
        }

        // Specific heap type into unknown heap type is imperfect but valid
        if self.is_heap() && dst == Type::UnknownHeap {
            return 1;
        }

        // Specific immediate type into unknown immediate type is imperfect but valid
        if self.is_imm() && dst == Type::UnknownImm {
            return 1;
        }

        // Incompatible types
        return usize::MAX;
    }

    /// Upgrade this type into a more specific compatible type
    /// The new type must be compatible and at least as specific as the previously known type.
    fn upgrade(&mut self, src: Self) {
        // Here we're checking that src is more specific than self
        assert!(src.diff(*self) != usize::MAX);
        *self = src;
    }
}

// Potential mapping of a value on the temporary stack to
// self, a local variable or constant so that we can track its type
#[derive(Copy, Clone, Eq, PartialEq, Debug)]
pub enum TempMapping {
    MapToStack, // Normal stack value
    MapToSelf,  // Temp maps to the self operand
    MapToLocal(u8), // Temp maps to a local variable with index
                //ConstMapping,         // Small constant (0, 1, 2, Qnil, Qfalse, Qtrue)
}

impl Default for TempMapping {
    fn default() -> Self {
        MapToStack
    }
}

// Operand to a YARV bytecode instruction
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum YARVOpnd {
    // The value is self
    SelfOpnd,

    // Temporary stack operand with stack index
    StackOpnd(u16),
}

/// Code generation context
/// Contains information we can use to specialize/optimize code
/// There are a lot of context objects so we try to keep the size small.
#[derive(Clone, Default, PartialEq, Debug)]
pub struct Context {
    // Number of values currently on the temporary stack
    stack_size: u16,

    // Offset of the JIT SP relative to the interpreter SP
    // This represents how far the JIT's SP is from the "real" SP
    sp_offset: i16,

    // Depth of this block in the sidechain (eg: inline-cache chain)
    chain_depth: u8,

    // Local variable types we keep track of
    local_types: [Type; MAX_LOCAL_TYPES],

    // Temporary variable types we keep track of
    temp_types: [Type; MAX_TEMP_TYPES],

    // Type we track for self
    self_type: Type,

    // Mapping of temp stack entries to types we track
    temp_mapping: [TempMapping; MAX_TEMP_TYPES],
}

/// Tuple of (iseq, idx) used to identify basic blocks
/// There are a lot of blockid objects so we try to keep the size small.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
#[repr(packed)]
pub struct BlockId {
    /// Instruction sequence
    pub iseq: IseqPtr,

    /// Index in the iseq where the block starts
    pub idx: u32,
}

/// Branch code shape enumeration
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum BranchShape {
    Next0,   // Target 0 is next
    Next1,   // Target 1 is next
    Default, // Neither target is next
}

// Branch code generation function signature
type BranchGenFn =
    fn(cb: &mut Assembler, target0: CodePtr, target1: Option<CodePtr>, shape: BranchShape) -> ();

/// A place that a branch could jump to
#[derive(Debug)]
struct BranchTarget {
    address: Option<CodePtr>,
    id: BlockId,
    ctx: Context,
    block: Option<BlockRef>,
}

/// Store info about an outgoing branch in a code segment
/// Note: care must be taken to minimize the size of branch objects
struct Branch {
    // Block this is attached to
    block: BlockRef,

    // Positions where the generated code starts and ends
    start_addr: Option<CodePtr>,
    end_addr: Option<CodePtr>, // exclusive

    // Branch target blocks and their contexts
    targets: [Option<Box<BranchTarget>>; 2],

    // Branch code generation function
    gen_fn: BranchGenFn,

    // Shape of the branch
    shape: BranchShape,
}

impl std::fmt::Debug for Branch {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // TODO: expand this if needed. #[derive(Debug)] on Branch gave a
        // strange error related to BranchGenFn
        formatter
            .debug_struct("Branch")
            .field("start", &self.start_addr)
            .field("end", &self.end_addr)
            .field("targets", &self.targets)
            .finish()
    }
}

impl Branch {
    // Compute the size of the branch code
    fn code_size(&self) -> usize {
        (self.end_addr.unwrap().raw_ptr() as usize) - (self.start_addr.unwrap().raw_ptr() as usize)
    }

    /// Get the address of one of the branch destination
    fn get_target_address(&self, target_idx: usize) -> Option<CodePtr> {
        self.targets[target_idx].as_ref().and_then(|target| target.address)
    }
}

// In case a block is invalidated, this helps to remove all pointers to the block.
pub type CmePtr = *const rb_callable_method_entry_t;

/// Basic block version
/// Represents a portion of an iseq compiled with a given context
/// Note: care must be taken to minimize the size of block_t objects
#[derive(Debug)]
pub struct Block {
    // Bytecode sequence (iseq, idx) this is a version of
    blockid: BlockId,

    // Index one past the last instruction for this block in the iseq
    end_idx: u32,

    // Context at the start of the block
    // This should never be mutated
    ctx: Context,

    // Positions where the generated code starts and ends
    start_addr: Option<CodePtr>,
    end_addr: Option<CodePtr>,

    // List of incoming branches (from predecessors)
    // These are reference counted (ownership shared between predecessor and successors)
    incoming: Vec<BranchRef>,

    // NOTE: we might actually be able to store the branches here without refcounting
    // however, using a RefCell makes it easy to get a pointer to Branch objects
    //
    // List of outgoing branches (to successors)
    outgoing: Vec<BranchRef>,

    // FIXME: should these be code pointers instead?
    // Offsets for GC managed objects in the mainline code block
    gc_obj_offsets: Vec<u32>,

    // CME dependencies of this block, to help to remove all pointers to this
    // block in the system.
    cme_dependencies: Vec<CmePtr>,

    // Code address of an exit for `ctx` and `blockid`.
    // Used for block invalidation.
    pub entry_exit: Option<CodePtr>,
}

/// Reference-counted pointer to a block that can be borrowed mutably.
/// Wrapped so we could implement [Hash] and [Eq] for use with stdlib collections.
#[derive(Debug)]
pub struct BlockRef(Rc<RefCell<Block>>);

/// Reference-counted pointer to a branch that can be borrowed mutably
type BranchRef = Rc<RefCell<Branch>>;

/// List of block versions for a given blockid
type VersionList = Vec<BlockRef>;

/// Map from iseq indices to lists of versions for that given blockid
/// An instance of this is stored on each iseq
type VersionMap = Vec<VersionList>;

impl BlockRef {
    /// Constructor
    pub fn new(rc: Rc<RefCell<Block>>) -> Self {
        Self(rc)
    }

    /// Borrow the block through [RefCell].
    pub fn borrow(&self) -> Ref<'_, Block> {
        self.0.borrow()
    }

    /// Borrow the block for mutation through [RefCell].
    pub fn borrow_mut(&self) -> RefMut<'_, Block> {
        self.0.borrow_mut()
    }
}

impl Clone for BlockRef {
    /// Clone the [Rc]
    fn clone(&self) -> Self {
        Self(self.0.clone())
    }
}

impl Hash for BlockRef {
    /// Hash the reference by hashing the pointer
    fn hash<H: Hasher>(&self, state: &mut H) {
        let rc_ptr = Rc::as_ptr(&self.0);
        rc_ptr.hash(state);
    }
}

impl PartialEq for BlockRef {
    /// Equality defined by allocation identity
    fn eq(&self, other: &Self) -> bool {
        Rc::ptr_eq(&self.0, &other.0)
    }
}

/// It's comparison by identity so all the requirements are statisfied
impl Eq for BlockRef {}

/// This is all the data YJIT stores on an iseq
/// This will be dynamically allocated by C code
/// C code should pass an &mut IseqPayload to us
/// when calling into YJIT
#[derive(Default)]
pub struct IseqPayload {
    // Basic block versions
    version_map: VersionMap,

    // Indexes of code pages used by this this ISEQ
    pub pages: HashSet<usize>,

    // Blocks that are invalidated but are not yet deallocated.
    // The code GC will free them later.
    pub dead_blocks: Vec<BlockRef>,
}

impl IseqPayload {
    /// Remove all block versions from the payload and then return them as an iterator
    pub fn take_all_blocks(&mut self) -> impl Iterator<Item = BlockRef> {
        // Empty the blocks
        let version_map = mem::take(&mut self.version_map);

        // Turn it into an iterator that owns the blocks and return
        version_map.into_iter().flatten()
    }
}

/// Get the payload for an iseq. For safety it's up to the caller to ensure the returned `&mut`
/// upholds aliasing rules and that the argument is a valid iseq.
pub fn get_iseq_payload(iseq: IseqPtr) -> Option<&'static mut IseqPayload> {
    let payload = unsafe { rb_iseq_get_yjit_payload(iseq) };
    let payload: *mut IseqPayload = payload.cast();
    unsafe { payload.as_mut() }
}

/// Get the payload object associated with an iseq. Create one if none exists.
pub fn get_or_create_iseq_payload(iseq: IseqPtr) -> &'static mut IseqPayload {
    type VoidPtr = *mut c_void;

    let payload_non_null = unsafe {
        let payload = rb_iseq_get_yjit_payload(iseq);
        if payload.is_null() {
            // Increment the compiled iseq count
            incr_counter!(compiled_iseq_count);

            // Allocate a new payload with Box and transfer ownership to the GC.
            // We drop the payload with Box::from_raw when the GC frees the iseq and calls us.
            // NOTE(alan): Sometimes we read from an iseq without ever writing to it.
            // We allocate in those cases anyways.
            let new_payload = Box::into_raw(Box::new(IseqPayload::default()));
            rb_iseq_set_yjit_payload(iseq, new_payload as VoidPtr);

            new_payload
        } else {
            payload as *mut IseqPayload
        }
    };

    // SAFETY: we should have the VM lock and all other Ruby threads should be asleep. So we have
    // exclusive mutable access.
    // Hmm, nothing seems to stop calling this on the same
    // iseq twice, though, which violates aliasing rules.
    unsafe { payload_non_null.as_mut() }.unwrap()
}

/// Iterate over all existing ISEQs
pub fn for_each_iseq<F: FnMut(IseqPtr)>(mut callback: F) {
    unsafe extern "C" fn callback_wrapper(iseq: IseqPtr, data: *mut c_void) {
        let callback: &mut &mut dyn FnMut(IseqPtr) -> bool = std::mem::transmute(&mut *data);
        callback(iseq);
    }
    let mut data: &mut dyn FnMut(IseqPtr) = &mut callback;
    unsafe { rb_yjit_for_each_iseq(Some(callback_wrapper), (&mut data) as *mut _ as *mut c_void) };
}

/// Iterate over all on-stack ISEQs
pub fn for_each_on_stack_iseq<F: FnMut(IseqPtr)>(mut callback: F) {
    unsafe extern "C" fn callback_wrapper(iseq: IseqPtr, data: *mut c_void) {
        let callback: &mut &mut dyn FnMut(IseqPtr) -> bool = std::mem::transmute(&mut *data);
        callback(iseq);
    }
    let mut data: &mut dyn FnMut(IseqPtr) = &mut callback;
    unsafe { rb_jit_cont_each_iseq(Some(callback_wrapper), (&mut data) as *mut _ as *mut c_void) };
}

/// Iterate over all on-stack ISEQ payloads
pub fn for_each_on_stack_iseq_payload<F: FnMut(&IseqPayload)>(mut callback: F) {
    for_each_on_stack_iseq(|iseq| {
        if let Some(iseq_payload) = get_iseq_payload(iseq) {
            callback(iseq_payload);
        }
    });
}

/// Iterate over all NOT on-stack ISEQ payloads
pub fn for_each_off_stack_iseq_payload<F: FnMut(&mut IseqPayload)>(mut callback: F) {
    let mut on_stack_iseqs: Vec<IseqPtr> = vec![];
    for_each_on_stack_iseq(|iseq| {
        on_stack_iseqs.push(iseq);
    });
    for_each_iseq(|iseq| {
        if !on_stack_iseqs.contains(&iseq) {
            if let Some(iseq_payload) = get_iseq_payload(iseq) {
                callback(iseq_payload);
            }
        }
    })
}

/// Free the per-iseq payload
#[no_mangle]
pub extern "C" fn rb_yjit_iseq_free(payload: *mut c_void) {
    let payload = {
        if payload.is_null() {
            // Nothing to free.
            return;
        } else {
            payload as *mut IseqPayload
        }
    };

    // Take ownership of the payload with Box::from_raw().
    // It drops right before this function returns.
    // SAFETY: We got the pointer from Box::into_raw().
    let payload = unsafe { Box::from_raw(payload) };

    // Increment the freed iseq count
    incr_counter!(freed_iseq_count);

    // Free all blocks in the payload
    for versions in &payload.version_map {
        for block in versions {
            free_block(block);
        }
    }
}

/// GC callback for marking GC objects in the the per-iseq payload.
#[no_mangle]
pub extern "C" fn rb_yjit_iseq_mark(payload: *mut c_void) {
    let payload = if payload.is_null() {
        // Nothing to mark.
        return;
    } else {
        // SAFETY: It looks like the GC takes the VM lock while marking
        // so we should be satisfying aliasing rules here.
        unsafe { &*(payload as *const IseqPayload) }
    };

    // For marking VALUEs written into the inline code block.
    // We don't write VALUEs in the outlined block.
    let cb: &CodeBlock = CodegenGlobals::get_inline_cb();

    for versions in &payload.version_map {
        for block in versions {
            let block = block.borrow();

            unsafe { rb_gc_mark_movable(block.blockid.iseq.into()) };

            // Mark method entry dependencies
            for &cme_dep in &block.cme_dependencies {
                unsafe { rb_gc_mark_movable(cme_dep.into()) };
            }

            // Mark outgoing branch entries
            for branch in &block.outgoing {
                let branch = branch.borrow();
                for target in branch.targets.iter().flatten() {
                    unsafe { rb_gc_mark_movable(target.id.iseq.into()) };
                }
            }

            // Walk over references to objects in generated code.
            for offset in &block.gc_obj_offsets {
                let value_address: *const u8 = cb.get_ptr(offset.as_usize()).raw_ptr();
                // Creating an unaligned pointer is well defined unlike in C.
                let value_address = value_address as *const VALUE;

                // SAFETY: these point to YJIT's code buffer
                unsafe {
                    let object = value_address.read_unaligned();
                    rb_gc_mark_movable(object);
                };
            }
        }
    }
}

/// GC callback for updating GC objects in the the per-iseq payload.
/// This is a mirror of [rb_yjit_iseq_mark].
#[no_mangle]
pub extern "C" fn rb_yjit_iseq_update_references(payload: *mut c_void) {
    let payload = if payload.is_null() {
        // Nothing to update.
        return;
    } else {
        // SAFETY: It looks like the GC takes the VM lock while updating references
        // so we should be satisfying aliasing rules here.
        unsafe { &*(payload as *const IseqPayload) }
    };

    // Evict other threads from generated code since we are about to patch them.
    // Also acts as an assert that we hold the VM lock.
    unsafe { rb_vm_barrier() };

    // For updating VALUEs written into the inline code block.
    let cb = CodegenGlobals::get_inline_cb();

    for versions in &payload.version_map {
        for block in versions {
            let mut block = block.borrow_mut();

            block.blockid.iseq = unsafe { rb_gc_location(block.blockid.iseq.into()) }.as_iseq();

            // Update method entry dependencies
            for cme_dep in &mut block.cme_dependencies {
                *cme_dep = unsafe { rb_gc_location((*cme_dep).into()) }.as_cme();
            }

            // Update outgoing branch entries
            for branch in &block.outgoing {
                let mut branch = branch.borrow_mut();
                for target in branch.targets.iter_mut().flatten() {
                    target.id.iseq = unsafe { rb_gc_location(target.id.iseq.into()) }.as_iseq();
                }
            }

            // Walk over references to objects in generated code.
            for offset in &block.gc_obj_offsets {
                let offset_to_value = offset.as_usize();
                let value_code_ptr = cb.get_ptr(offset_to_value);
                let value_ptr: *const u8 = value_code_ptr.raw_ptr();
                // Creating an unaligned pointer is well defined unlike in C.
                let value_ptr = value_ptr as *mut VALUE;

                // SAFETY: these point to YJIT's code buffer
                let object = unsafe { value_ptr.read_unaligned() };
                let new_addr = unsafe { rb_gc_location(object) };

                // Only write when the VALUE moves, to be copy-on-write friendly.
                if new_addr != object {
                    for (byte_idx, &byte) in new_addr.as_u64().to_le_bytes().iter().enumerate() {
                        let byte_code_ptr = value_code_ptr.add_bytes(byte_idx);
                        cb.write_mem(byte_code_ptr, byte)
                            .expect("patching existing code should be within bounds");
                    }
                }
            }
        }
    }

    // Note that we would have returned already if YJIT is off.
    cb.mark_all_executable();

    CodegenGlobals::get_outlined_cb()
        .unwrap()
        .mark_all_executable();
}

/// Get all blocks for a particular place in an iseq.
fn get_version_list(blockid: BlockId) -> Option<&'static mut VersionList> {
    let insn_idx = blockid.idx.as_usize();
    match get_iseq_payload(blockid.iseq) {
        Some(payload) if insn_idx < payload.version_map.len() => {
            Some(payload.version_map.get_mut(insn_idx).unwrap())
        },
        _ => None
    }
}

/// Get or create all blocks for a particular place in an iseq.
fn get_or_create_version_list(blockid: BlockId) -> &'static mut VersionList {
    let payload = get_or_create_iseq_payload(blockid.iseq);
    let insn_idx = blockid.idx.as_usize();

    // Expand the version map as necessary
    if insn_idx >= payload.version_map.len() {
        payload
            .version_map
            .resize(insn_idx + 1, VersionList::default());
    }

    return payload.version_map.get_mut(insn_idx).unwrap();
}

/// Take all of the blocks for a particular place in an iseq
pub fn take_version_list(blockid: BlockId) -> VersionList {
    let insn_idx = blockid.idx.as_usize();
    match get_iseq_payload(blockid.iseq) {
        Some(payload) if insn_idx < payload.version_map.len() => {
            mem::take(&mut payload.version_map[insn_idx])
        },
        _ => VersionList::default(),
    }
}

/// Count the number of block versions matching a given blockid
fn get_num_versions(blockid: BlockId) -> usize {
    let insn_idx = blockid.idx.as_usize();
    match get_iseq_payload(blockid.iseq) {
        Some(payload) => {
            payload
                .version_map
                .get(insn_idx)
                .map(|versions| versions.len())
                .unwrap_or(0)
        }
        None => 0,
    }
}

/// Get or create a list of block versions generated for an iseq
/// This is used for disassembly (see disasm.rs)
pub fn get_or_create_iseq_block_list(iseq: IseqPtr) -> Vec<BlockRef> {
    let payload = get_or_create_iseq_payload(iseq);

    let mut blocks = Vec::<BlockRef>::new();

    // For each instruction index
    for insn_idx in 0..payload.version_map.len() {
        let version_list = &payload.version_map[insn_idx];

        // For each version at this instruction index
        for version in version_list {
            // Clone the block ref and add it to the list
            blocks.push(version.clone());
        }
    }

    return blocks;
}

/// Retrieve a basic block version for an (iseq, idx) tuple
/// This will return None if no version is found
fn find_block_version(blockid: BlockId, ctx: &Context) -> Option<BlockRef> {
    let versions = match get_version_list(blockid) {
        Some(versions) => versions,
        None => return None,
    };

    // Best match found
    let mut best_version: Option<BlockRef> = None;
    let mut best_diff = usize::MAX;

    // For each version matching the blockid
    for blockref in versions.iter_mut() {
        let block = blockref.borrow();
        let diff = ctx.diff(&block.ctx);

        // Note that we always prefer the first matching
        // version found because of inline-cache chains
        if diff < best_diff {
            best_version = Some(blockref.clone());
            best_diff = diff;
        }
    }

    // If greedy versioning is enabled
    if get_option!(greedy_versioning) {
        // If we're below the version limit, don't settle for an imperfect match
        if versions.len() + 1 < get_option!(max_versions) && best_diff > 0 {
            return None;
        }
    }

    return best_version;
}

/// Produce a generic context when the block version limit is hit for a blockid
pub fn limit_block_versions(blockid: BlockId, ctx: &Context) -> Context {
    // Guard chains implement limits separately, do nothing
    if ctx.chain_depth > 0 {
        return ctx.clone();
    }

    // If this block version we're about to add will hit the version limit
    if get_num_versions(blockid) + 1 >= get_option!(max_versions) {
        // Produce a generic context that stores no type information,
        // but still respects the stack_size and sp_offset constraints.
        // This new context will then match all future requests.
        let mut generic_ctx = Context::default();
        generic_ctx.stack_size = ctx.stack_size;
        generic_ctx.sp_offset = ctx.sp_offset;

        debug_assert_ne!(
            usize::MAX,
            ctx.diff(&generic_ctx),
            "should substitute a compatible context",
        );

        return generic_ctx;
    }

    return ctx.clone();
}

/// Keep track of a block version. Block should be fully constructed.
/// Uses `cb` for running write barriers.
fn add_block_version(blockref: &BlockRef, cb: &CodeBlock) {
    let block = blockref.borrow();

    // Function entry blocks must have stack size 0
    assert!(!(block.blockid.idx == 0 && block.ctx.stack_size > 0));

    let version_list = get_or_create_version_list(block.blockid);

    version_list.push(blockref.clone());
    version_list.shrink_to_fit();

    // By writing the new block to the iseq, the iseq now
    // contains new references to Ruby objects. Run write barriers.
    let iseq: VALUE = block.blockid.iseq.into();
    for &dep in block.iter_cme_deps() {
        obj_written!(iseq, dep.into());
    }

    // Run write barriers for all objects in generated code.
    for offset in &block.gc_obj_offsets {
        let value_address: *const u8 = cb.get_ptr(offset.as_usize()).raw_ptr();
        // Creating an unaligned pointer is well defined unlike in C.
        let value_address: *const VALUE = value_address.cast();

        let object = unsafe { value_address.read_unaligned() };
        obj_written!(iseq, object);
    }

    incr_counter!(compiled_block_count);

    // Mark code pages for code GC
    let iseq_payload = get_iseq_payload(block.blockid.iseq).unwrap();
    for page in cb.addrs_to_pages(block.start_addr.unwrap(), block.end_addr.unwrap()) {
        iseq_payload.pages.insert(page);
    }
}

/// Remove a block version from the version map of its parent ISEQ
fn remove_block_version(blockref: &BlockRef) {
    let block = blockref.borrow();
    let version_list = match get_version_list(block.blockid) {
        Some(version_list) => version_list,
        None => return,
    };

    // Retain the versions that are not this one
    version_list.retain(|other| blockref != other);
}

//===========================================================================
// I put the implementation of traits for core.rs types below
// We can move these closer to the above structs later if we want.
//===========================================================================

impl Block {
    pub fn new(blockid: BlockId, ctx: &Context) -> BlockRef {
        let block = Block {
            blockid,
            end_idx: 0,
            ctx: ctx.clone(),
            start_addr: None,
            end_addr: None,
            incoming: Vec::new(),
            outgoing: Vec::new(),
            gc_obj_offsets: Vec::new(),
            cme_dependencies: Vec::new(),
            entry_exit: None,
        };

        // Wrap the block in a reference counted refcell
        // so that the block ownership can be shared
        BlockRef::new(Rc::new(RefCell::new(block)))
    }

    pub fn get_blockid(&self) -> BlockId {
        self.blockid
    }

    pub fn get_end_idx(&self) -> u32 {
        self.end_idx
    }

    pub fn get_ctx(&self) -> Context {
        self.ctx.clone()
    }

    #[allow(unused)]
    pub fn get_start_addr(&self) -> Option<CodePtr> {
        self.start_addr
    }

    #[allow(unused)]
    pub fn get_end_addr(&self) -> Option<CodePtr> {
        self.end_addr
    }

    /// Get an immutable iterator over cme dependencies
    pub fn iter_cme_deps(&self) -> std::slice::Iter<'_, CmePtr> {
        self.cme_dependencies.iter()
    }

    /// Set the starting address in the generated code for the block
    /// This can be done only once for a block
    pub fn set_start_addr(&mut self, addr: CodePtr) {
        assert!(self.start_addr.is_none());
        self.start_addr = Some(addr);
    }

    /// Set the end address in the generated for the block
    /// This can be done only once for a block
    pub fn set_end_addr(&mut self, addr: CodePtr) {
        // The end address can only be set after the start address is set
        assert!(self.start_addr.is_some());

        // TODO: assert constraint that blocks can shrink but not grow in length
        self.end_addr = Some(addr);
    }

    /// Set the index of the last instruction in the block
    /// This can be done only once for a block
    pub fn set_end_idx(&mut self, end_idx: u32) {
        assert!(self.end_idx == 0);
        self.end_idx = end_idx;
    }

    pub fn add_gc_obj_offsets(self: &mut Block, gc_offsets: Vec<u32>) {
        for offset in gc_offsets {
            self.gc_obj_offsets.push(offset);
            incr_counter!(num_gc_obj_refs);
        }
        self.gc_obj_offsets.shrink_to_fit();
    }

    /// Instantiate a new CmeDependency struct and add it to the list of
    /// dependencies for this block.
    pub fn add_cme_dependency(&mut self, callee_cme: CmePtr) {
        self.cme_dependencies.push(callee_cme);
        self.cme_dependencies.shrink_to_fit();
    }

    // Push an incoming branch ref and shrink the vector
    fn push_incoming(&mut self, branch: BranchRef) {
        self.incoming.push(branch);
        self.incoming.shrink_to_fit();
    }

    // Push an outgoing branch ref and shrink the vector
    fn push_outgoing(&mut self, branch: BranchRef) {
        self.outgoing.push(branch);
        self.outgoing.shrink_to_fit();
    }

    // Compute the size of the block code
    pub fn code_size(&self) -> usize {
        (self.end_addr.unwrap().raw_ptr() as usize) - (self.start_addr.unwrap().raw_ptr() as usize)
    }
}

impl Context {
    pub fn get_stack_size(&self) -> u16 {
        self.stack_size
    }

    pub fn get_sp_offset(&self) -> i16 {
        self.sp_offset
    }

    pub fn set_sp_offset(&mut self, offset: i16) {
        self.sp_offset = offset;
    }

    pub fn get_chain_depth(&self) -> u8 {
        self.chain_depth
    }

    pub fn reset_chain_depth(&mut self) {
        self.chain_depth = 0;
    }

    pub fn increment_chain_depth(&mut self) {
        self.chain_depth += 1;
    }

    /// Get an operand for the adjusted stack pointer address
    pub fn sp_opnd(&self, offset_bytes: isize) -> Opnd {
        let offset = ((self.sp_offset as isize) * (SIZEOF_VALUE as isize)) + offset_bytes;
        let offset = offset as i32;
        return Opnd::mem(64, SP, offset);
    }

    /// Push one new value on the temp stack with an explicit mapping
    /// Return a pointer to the new stack top
    pub fn stack_push_mapping(&mut self, (mapping, temp_type): (TempMapping, Type)) -> Opnd {
        // If type propagation is disabled, store no types
        if get_option!(no_type_prop) {
            return self.stack_push_mapping((mapping, Type::Unknown));
        }

        let stack_size: usize = self.stack_size.into();

        // Keep track of the type and mapping of the value
        if stack_size < MAX_TEMP_TYPES {
            self.temp_mapping[stack_size] = mapping;
            self.temp_types[stack_size] = temp_type;

            if let MapToLocal(idx) = mapping {
                assert!((idx as usize) < MAX_LOCAL_TYPES);
            }
        }

        self.stack_size += 1;
        self.sp_offset += 1;

        // SP points just above the topmost value
        let offset = ((self.sp_offset as i32) - 1) * (SIZEOF_VALUE as i32);
        return Opnd::mem(64, SP, offset);
    }

    /// Push one new value on the temp stack
    /// Return a pointer to the new stack top
    pub fn stack_push(&mut self, val_type: Type) -> Opnd {
        return self.stack_push_mapping((MapToStack, val_type));
    }

    /// Push the self value on the stack
    pub fn stack_push_self(&mut self) -> Opnd {
        return self.stack_push_mapping((MapToSelf, Type::Unknown));
    }

    /// Push a local variable on the stack
    pub fn stack_push_local(&mut self, local_idx: usize) -> Opnd {
        if local_idx >= MAX_LOCAL_TYPES {
            return self.stack_push(Type::Unknown);
        }

        return self.stack_push_mapping((MapToLocal(local_idx as u8), Type::Unknown));
    }

    // Pop N values off the stack
    // Return a pointer to the stack top before the pop operation
    pub fn stack_pop(&mut self, n: usize) -> Opnd {
        assert!(n <= self.stack_size.into());

        // SP points just above the topmost value
        let offset = ((self.sp_offset as i32) - 1) * (SIZEOF_VALUE as i32);
        let top = Opnd::mem(64, SP, offset);

        // Clear the types of the popped values
        for i in 0..n {
            let idx: usize = (self.stack_size as usize) - i - 1;

            if idx < MAX_TEMP_TYPES {
                self.temp_types[idx] = Type::Unknown;
                self.temp_mapping[idx] = MapToStack;
            }
        }

        self.stack_size -= n as u16;
        self.sp_offset -= n as i16;

        return top;
    }

    pub fn shift_stack(&mut self, argc: usize) {
        assert!(argc < self.stack_size.into());

        let method_name_index = (self.stack_size - argc as u16 - 1) as usize;

        for i in method_name_index..(self.stack_size - 1) as usize {

            if i + 1 < MAX_TEMP_TYPES {
                self.temp_types[i] = self.temp_types[i + 1];
                self.temp_mapping[i] = self.temp_mapping[i + 1];
            }
        }
        self.stack_pop(1);
    }

    /// Get an operand pointing to a slot on the temp stack
    pub fn stack_opnd(&self, idx: i32) -> Opnd {
        // SP points just above the topmost value
        let offset = ((self.sp_offset as i32) - 1 - idx) * (SIZEOF_VALUE as i32);
        let opnd = Opnd::mem(64, SP, offset);
        return opnd;
    }

    /// Get the type of an instruction operand
    pub fn get_opnd_type(&self, opnd: YARVOpnd) -> Type {
        match opnd {
            SelfOpnd => self.self_type,
            StackOpnd(idx) => {
                let idx = idx as u16;
                assert!(idx < self.stack_size);
                let stack_idx: usize = (self.stack_size - 1 - idx).into();

                // If outside of tracked range, do nothing
                if stack_idx >= MAX_TEMP_TYPES {
                    return Type::Unknown;
                }

                let mapping = self.temp_mapping[stack_idx];

                match mapping {
                    MapToSelf => self.self_type,
                    MapToStack => self.temp_types[(self.stack_size - 1 - idx) as usize],
                    MapToLocal(idx) => {
                        assert!((idx as usize) < MAX_LOCAL_TYPES);
                        return self.local_types[idx as usize];
                    }
                }
            }
        }
    }

    /// Get the currently tracked type for a local variable
    pub fn get_local_type(&self, idx: usize) -> Type {
        *self.local_types.get(idx).unwrap_or(&Type::Unknown)
    }

    /// Upgrade (or "learn") the type of an instruction operand
    /// This value must be compatible and at least as specific as the previously known type.
    /// If this value originated from self, or an lvar, the learned type will be
    /// propagated back to its source.
    pub fn upgrade_opnd_type(&mut self, opnd: YARVOpnd, opnd_type: Type) {
        // If type propagation is disabled, store no types
        if get_option!(no_type_prop) {
            return;
        }

        match opnd {
            SelfOpnd => self.self_type.upgrade(opnd_type),
            StackOpnd(idx) => {
                let idx = idx as u16;
                assert!(idx < self.stack_size);
                let stack_idx = (self.stack_size - 1 - idx) as usize;

                // If outside of tracked range, do nothing
                if stack_idx >= MAX_TEMP_TYPES {
                    return;
                }

                let mapping = self.temp_mapping[stack_idx];

                match mapping {
                    MapToSelf => self.self_type.upgrade(opnd_type),
                    MapToStack => self.temp_types[stack_idx].upgrade(opnd_type),
                    MapToLocal(idx) => {
                        let idx = idx as usize;
                        assert!(idx < MAX_LOCAL_TYPES);
                        self.local_types[idx].upgrade(opnd_type);
                    }
                }
            }
        }
    }

    /*
    Get both the type and mapping (where the value originates) of an operand.
    This is can be used with stack_push_mapping or set_opnd_mapping to copy
    a stack value's type while maintaining the mapping.
    */
    pub fn get_opnd_mapping(&self, opnd: YARVOpnd) -> (TempMapping, Type) {
        let opnd_type = self.get_opnd_type(opnd);

        match opnd {
            SelfOpnd => (MapToSelf, opnd_type),
            StackOpnd(idx) => {
                let idx = idx as u16;
                assert!(idx < self.stack_size);
                let stack_idx = (self.stack_size - 1 - idx) as usize;

                if stack_idx < MAX_TEMP_TYPES {
                    (self.temp_mapping[stack_idx], opnd_type)
                } else {
                    // We can't know the source of this stack operand, so we assume it is
                    // a stack-only temporary. type will be UNKNOWN
                    assert!(opnd_type == Type::Unknown);
                    (MapToStack, opnd_type)
                }
            }
        }
    }

    /// Overwrite both the type and mapping of a stack operand.
    pub fn set_opnd_mapping(&mut self, opnd: YARVOpnd, (mapping, opnd_type): (TempMapping, Type)) {
        match opnd {
            SelfOpnd => unreachable!("self always maps to self"),
            StackOpnd(idx) => {
                assert!(idx < self.stack_size);
                let stack_idx = (self.stack_size - 1 - idx) as usize;

                // If type propagation is disabled, store no types
                if get_option!(no_type_prop) {
                    return;
                }

                // If outside of tracked range, do nothing
                if stack_idx >= MAX_TEMP_TYPES {
                    return;
                }

                self.temp_mapping[stack_idx] = mapping;

                // Only used when mapping == MAP_STACK
                self.temp_types[stack_idx] = opnd_type;
            }
        }
    }

    /// Set the type of a local variable
    pub fn set_local_type(&mut self, local_idx: usize, local_type: Type) {
        let ctx = self;

        // If type propagation is disabled, store no types
        if get_option!(no_type_prop) {
            return;
        }

        if local_idx >= MAX_LOCAL_TYPES {
            return;
        }

        // If any values on the stack map to this local we must detach them
        for (i, mapping) in ctx.temp_mapping.iter_mut().enumerate() {
            *mapping = match *mapping {
                MapToStack => MapToStack,
                MapToSelf => MapToSelf,
                MapToLocal(idx) => {
                    if idx as usize == local_idx {
                        ctx.temp_types[i] = ctx.local_types[idx as usize];
                        MapToStack
                    } else {
                        MapToLocal(idx)
                    }
                }
            }
        }

        ctx.local_types[local_idx] = local_type;
    }

    /// Erase local variable type information
    /// eg: because of a call we can't track
    pub fn clear_local_types(&mut self) {
        // When clearing local types we must detach any stack mappings to those
        // locals. Even if local values may have changed, stack values will not.
        for (i, mapping) in self.temp_mapping.iter_mut().enumerate() {
            *mapping = match *mapping {
                MapToStack => MapToStack,
                MapToSelf => MapToSelf,
                MapToLocal(idx) => {
                    self.temp_types[i] = self.local_types[idx as usize];
                    MapToStack
                }
            }
        }

        // Clear the local types
        self.local_types = [Type::default(); MAX_LOCAL_TYPES];
    }

    /// Compute a difference score for two context objects
    /// Returns 0 if the two contexts are the same
    /// Returns > 0 if different but compatible
    /// Returns usize::MAX if incompatible
    pub fn diff(&self, dst: &Context) -> usize {
        // Self is the source context (at the end of the predecessor)
        let src = self;

        // Can only lookup the first version in the chain
        if dst.chain_depth != 0 {
            return usize::MAX;
        }

        // Blocks with depth > 0 always produce new versions
        // Sidechains cannot overlap
        if src.chain_depth != 0 {
            return usize::MAX;
        }

        if dst.stack_size != src.stack_size {
            return usize::MAX;
        }

        if dst.sp_offset != src.sp_offset {
            return usize::MAX;
        }

        // Difference sum
        let mut diff = 0;

        // Check the type of self
        let self_diff = src.self_type.diff(dst.self_type);

        if self_diff == usize::MAX {
            return usize::MAX;
        }

        diff += self_diff;

        // For each local type we track
        for i in 0..src.local_types.len() {
            let t_src = src.local_types[i];
            let t_dst = dst.local_types[i];
            let temp_diff = t_src.diff(t_dst);

            if temp_diff == usize::MAX {
                return usize::MAX;
            }

            diff += temp_diff;
        }

        // For each value on the temp stack
        for i in 0..src.stack_size {
            let (src_mapping, src_type) = src.get_opnd_mapping(StackOpnd(i));
            let (dst_mapping, dst_type) = dst.get_opnd_mapping(StackOpnd(i));

            // If the two mappings aren't the same
            if src_mapping != dst_mapping {
                if dst_mapping == MapToStack {
                    // We can safely drop information about the source of the temp
                    // stack operand.
                    diff += 1;
                } else {
                    return usize::MAX;
                }
            }

            let temp_diff = src_type.diff(dst_type);

            if temp_diff == usize::MAX {
                return usize::MAX;
            }

            diff += temp_diff;
        }

        return diff;
    }
}

impl BlockId {
    /// Print Ruby source location for debugging
    #[cfg(debug_assertions)]
    #[allow(dead_code)]
    pub fn dump_src_loc(&self) {
        unsafe { rb_yjit_dump_iseq_loc(self.iseq, self.idx) }
    }
}

/// See [gen_block_series_body]. This simply counts compilation failures.
fn gen_block_series(
    blockid: BlockId,
    start_ctx: &Context,
    ec: EcPtr,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> Option<BlockRef> {
    let result = gen_block_series_body(blockid, start_ctx, ec, cb, ocb);
    if result.is_none() {
        incr_counter!(compilation_failure);
    }

    result
}

/// Immediately compile a series of block versions at a starting point and
/// return the starting block.
fn gen_block_series_body(
    blockid: BlockId,
    start_ctx: &Context,
    ec: EcPtr,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> Option<BlockRef> {
    // Keep track of all blocks compiled in this batch
    const EXPECTED_BATCH_SIZE: usize = 4;
    let mut batch = Vec::with_capacity(EXPECTED_BATCH_SIZE);

    // Generate code for the first block
    let first_block = gen_single_block(blockid, start_ctx, ec, cb, ocb).ok()?;
    batch.push(first_block.clone()); // Keep track of this block version

    // Add the block version to the VersionMap for this ISEQ
    add_block_version(&first_block, cb);

    // Loop variable
    let mut last_blockref = first_block.clone();
    loop {
        // Get the last outgoing branch from the previous block.
        let last_branchref = {
            let last_block = last_blockref.borrow();
            match last_block.outgoing.last() {
                Some(branch) => branch.clone(),
                None => {
                    break;
                } // If last block has no branches, stop.
            }
        };
        let mut last_branch = last_branchref.borrow_mut();

        // gen_direct_jump() can request a block to be placed immediately after by
        // leaving a single target that has a `None` address.
        let mut last_target = match &mut last_branch.targets {
            [Some(last_target), None] if last_target.address.is_none() => last_target,
            _ => break
        };

        incr_counter!(block_next_count);

        // Get id and context for the new block
        let requested_id = last_target.id;
        let requested_ctx = &last_target.ctx;

        // Generate new block using context from the last branch.
        let result = gen_single_block(requested_id, requested_ctx, ec, cb, ocb);

        // If the block failed to compile
        if result.is_err() {
            // Remove previously compiled block
            // versions from the version map
            mem::drop(last_branch); // end borrow
            for blockref in &batch {
                free_block(blockref);
                remove_block_version(blockref);
            }

            // Stop compiling
            return None;
        }

        let new_blockref = result.unwrap();

        // Add the block version to the VersionMap for this ISEQ
        add_block_version(&new_blockref, cb);

        // Connect the last branch and the new block
        last_target.block = Some(new_blockref.clone());
        last_target.address = new_blockref.borrow().start_addr;
        new_blockref
            .borrow_mut()
            .push_incoming(last_branchref.clone());

        // Track the block
        batch.push(new_blockref.clone());

        // Repeat with newest block
        last_blockref = new_blockref;
    }

    #[cfg(feature = "disasm")]
    {
        // If dump_iseq_disasm is active, see if this iseq's location matches the given substring.
        // If so, we print the new blocks to the console.
        if let Some(substr) = get_option_ref!(dump_iseq_disasm).as_ref() {
            let iseq_location = iseq_get_location(blockid.iseq);
            if iseq_location.contains(substr) {
                let last_block = last_blockref.borrow();
                let blockid_idx = blockid.idx;
                println!("Compiling {} block(s) for {}, ISEQ offsets [{}, {})", batch.len(), iseq_location, blockid_idx, last_block.end_idx);
                print!("{}", disasm_iseq_insn_range(blockid.iseq, blockid.idx, last_block.end_idx));
            }
        }
    }

    Some(first_block)
}

/// Generate a block version that is an entry point inserted into an iseq
/// NOTE: this function assumes that the VM lock has been taken
pub fn gen_entry_point(iseq: IseqPtr, ec: EcPtr) -> Option<CodePtr> {
    // Compute the current instruction index based on the current PC
    let insn_idx: u32 = unsafe {
        let pc_zero = rb_iseq_pc_at_idx(iseq, 0);
        let ec_pc = get_cfp_pc(get_ec_cfp(ec));
        ec_pc.offset_from(pc_zero).try_into().ok()?
    };

    // The entry context makes no assumptions about types
    let blockid = BlockId {
        iseq,
        idx: insn_idx,
    };

    // Get the inline and outlined code blocks
    let cb = CodegenGlobals::get_inline_cb();
    let ocb = CodegenGlobals::get_outlined_cb();

    // Write the interpreter entry prologue. Might be NULL when out of memory.
    let code_ptr = gen_entry_prologue(cb, iseq, insn_idx);

    // Try to generate code for the entry block
    let block = gen_block_series(blockid, &Context::default(), ec, cb, ocb);

    cb.mark_all_executable();
    ocb.unwrap().mark_all_executable();

    match block {
        // Compilation failed
        None => {
            // Trigger code GC. This entry point will be recompiled later.
            cb.code_gc();
            return None;
        }

        // If the block contains no Ruby instructions
        Some(block) => {
            let block = block.borrow();
            if block.end_idx == insn_idx {
                return None;
            }
        }
    }

    // Compilation successful and block not empty
    return code_ptr;
}

/// Generate code for a branch, possibly rewriting and changing the size of it
fn regenerate_branch(cb: &mut CodeBlock, branch: &mut Branch) {
    // FIXME
    /*
    if (branch->start_addr < cb_get_ptr(cb, yjit_codepage_frozen_bytes)) {
        // Generating this branch would modify frozen bytes. Do nothing.
        return;
    }
    */

    let mut block = branch.block.borrow_mut();
    let branch_terminates_block = branch.end_addr == block.end_addr;

    // Generate the branch
    let mut asm = Assembler::new();
    asm.comment("regenerate_branch");
    (branch.gen_fn)(
        &mut asm,
        branch.get_target_address(0).unwrap(),
        branch.get_target_address(1),
        branch.shape,
    );

    // Rewrite the branch
    let old_write_pos = cb.get_write_pos();
    let old_dropped_bytes = cb.has_dropped_bytes();
    cb.set_write_ptr(branch.start_addr.unwrap());
    cb.set_dropped_bytes(false);
    asm.compile(cb);

    branch.end_addr = Some(cb.get_write_ptr());

    // The block may have shrunk after the branch is rewritten
    if branch_terminates_block {
        // Adjust block size
        block.end_addr = branch.end_addr;
    }

    // cb.write_pos is both a write cursor and a marker for the end of
    // everything written out so far. Leave cb->write_pos at the end of the
    // block before returning. This function only ever bump or retain the end
    // of block marker since that's what the majority of callers want. When the
    // branch sits at the very end of the codeblock and it shrinks after
    // regeneration, it's up to the caller to drop bytes off the end to
    // not leave a gap and implement branch->shape.
    if old_write_pos > cb.get_write_pos() {
        // We rewound cb->write_pos to generate the branch, now restore it.
        cb.set_pos(old_write_pos);
        cb.set_dropped_bytes(old_dropped_bytes);
    } else {
        // The branch sits at the end of cb and consumed some memory.
        // Keep cb.write_pos.
    }
}

/// Create a new outgoing branch entry for a block
fn make_branch_entry(block: &BlockRef, gen_fn: BranchGenFn) -> BranchRef {
    let branch = Branch {
        // Block this is attached to
        block: block.clone(),

        // Positions where the generated code starts and ends
        start_addr: None,
        end_addr: None,

        // Branch target blocks and their contexts
        targets: [None, None],

        // Branch code generation function
        gen_fn: gen_fn,

        // Shape of the branch
        shape: BranchShape::Default,
    };

    // Add to the list of outgoing branches for the block
    let branchref = Rc::new(RefCell::new(branch));
    block.borrow_mut().push_outgoing(branchref.clone());
    incr_counter!(compiled_branch_count);

    return branchref;
}

c_callable! {
    /// Generated code calls this function with the SysV calling convention.
    /// See [set_branch_target].
    fn branch_stub_hit(
        branch_ptr: *const c_void,
        target_idx: u32,
        ec: EcPtr,
    ) -> *const u8 {
        with_vm_lock(src_loc!(), || {
            branch_stub_hit_body(branch_ptr, target_idx, ec)
        })
    }
}

/// Called by the generated code when a branch stub is executed
/// Triggers compilation of branches and code patching
fn branch_stub_hit_body(branch_ptr: *const c_void, target_idx: u32, ec: EcPtr) -> *const u8 {
    if get_option!(dump_insns) {
        println!("branch_stub_hit");
    }

    assert!(!branch_ptr.is_null());

    //branch_ptr is actually:
    //branch_ptr: *const RefCell<Branch>
    let branch_rc = unsafe { BranchRef::from_raw(branch_ptr as *const RefCell<Branch>) };

    // We increment the strong count because we want to keep the reference owned
    // by the branch stub alive. Return branch stubs can be hit multiple times.
    unsafe { Rc::increment_strong_count(branch_ptr) };

    let mut branch = branch_rc.borrow_mut();
    let branch_size_on_entry = branch.code_size();

    let target_idx: usize = target_idx.as_usize();
    let target = branch.targets[target_idx].as_ref().unwrap();
    let target_id = target.id;
    let target_ctx = target.ctx.clone();

    let target_branch_shape = match target_idx {
        0 => BranchShape::Next0,
        1 => BranchShape::Next1,
        _ => unreachable!("target_idx < 2 must always hold"),
    };

    let cb = CodegenGlobals::get_inline_cb();
    let ocb = CodegenGlobals::get_outlined_cb();

    // If this branch has already been patched, return the dst address
    // Note: ractors can cause the same stub to be hit multiple times
    if target.block.is_some() {
        return target.address.unwrap().raw_ptr();
    }

    let (cfp, original_interp_sp) = unsafe {
        let cfp = get_ec_cfp(ec);
        let original_interp_sp = get_cfp_sp(cfp);

        let running_iseq = rb_cfp_get_iseq(cfp);
        let reconned_pc = rb_iseq_pc_at_idx(running_iseq, target_id.idx);
        let reconned_sp = original_interp_sp.offset(target_ctx.sp_offset.into());

        assert_eq!(running_iseq, target_id.iseq as _, "each stub expects a particular iseq");

        // Update the PC in the current CFP, because it may be out of sync in JITted code
        rb_set_cfp_pc(cfp, reconned_pc);

        // :stub-sp-flush:
        // Generated code do stack operations without modifying cfp->sp, while the
        // cfp->sp tells the GC what values on the stack to root. Generated code
        // generally takes care of updating cfp->sp when it calls runtime routines that
        // could trigger GC, but it's inconvenient to do it before calling this function.
        // So we do it here instead.
        rb_set_cfp_sp(cfp, reconned_sp);

        (cfp, original_interp_sp)
    };

    // Try to find an existing compiled version of this block
    let mut block = find_block_version(target_id, &target_ctx);

    // If this block hasn't yet been compiled
    if block.is_none() {
        let branch_old_shape = branch.shape;
        let mut branch_modified = false;

        // If the new block can be generated right after the branch (at cb->write_pos)
        if Some(cb.get_write_ptr()) == branch.end_addr {
            // This branch should be terminating its block
            assert!(branch.end_addr == branch.block.borrow().end_addr);

            // Change the branch shape to indicate the target block will be placed next
            branch.shape = target_branch_shape;

            // Rewrite the branch with the new, potentially more compact shape
            regenerate_branch(cb, &mut branch);
            branch_modified = true;

            // Ensure that the branch terminates the codeblock just like
            // before entering this if block. This drops bytes off the end
            // in case we shrank the branch when regenerating.
            cb.set_write_ptr(branch.end_addr.unwrap());
        }

        // Compile the new block version
        drop(branch); // Stop mutable RefCell borrow since GC might borrow branch for marking
        block = gen_block_series(target_id, &target_ctx, ec, cb, ocb);
        branch = branch_rc.borrow_mut();

        if block.is_none() && branch_modified {
            // We couldn't generate a new block for the branch, but we modified the branch.
            // Restore the branch by regenerating it.
            branch.shape = branch_old_shape;
            regenerate_branch(cb, &mut branch);
        }
    }

    // Finish building the new block
    let dst_addr = match block {
        Some(block_rc) => {
            let mut block: RefMut<_> = block_rc.borrow_mut();

            // Branch shape should reflect layout
            assert!(!(branch.shape == target_branch_shape && block.start_addr != branch.end_addr));

            // Add this branch to the list of incoming branches for the target
            block.push_incoming(branch_rc.clone());

            // Update the branch target address
            let target = branch.targets[target_idx].as_mut().unwrap();
            let dst_addr = block.start_addr;
            target.address = dst_addr;

            // Mark this branch target as patched (no longer a stub)
            target.block = Some(block_rc.clone());

            // Rewrite the branch with the new jump target address
            mem::drop(block); // end mut borrow
            regenerate_branch(cb, &mut branch);

            // Restore interpreter sp, since the code hitting the stub expects the original.
            unsafe { rb_set_cfp_sp(cfp, original_interp_sp) };

            block_rc.borrow().start_addr.unwrap()
        }
        None => {
            // Code GC needs to borrow blocks for invalidation, so their mutable
            // borrows must be dropped first.
            drop(block);
            drop(branch);
            // Trigger code GC. The whole ISEQ will be recompiled later.
            // We shouldn't trigger it in the middle of compilation in branch_stub_hit
            // because incomplete code could be used when cb.dropped_bytes is flipped
            // by code GC. So this place, after all compilation, is the safest place
            // to hook code GC on branch_stub_hit.
            cb.code_gc();
            branch = branch_rc.borrow_mut();

            // Failed to service the stub by generating a new block so now we
            // need to exit to the interpreter at the stubbed location. We are
            // intentionally *not* restoring original_interp_sp. At the time of
            // writing, reconstructing interpreter state only involves setting
            // cfp->sp and cfp->pc. We set both before trying to generate the
            // block. All there is left to do to exit is to pop the native
            // frame. We do that in code_for_exit_from_stub.
            CodegenGlobals::get_stub_exit_code()
        }
    };

    ocb.unwrap().mark_all_executable();
    cb.mark_all_executable();

    let new_branch_size = branch.code_size();
    assert!(
        new_branch_size <= branch_size_on_entry,
        "branch stubs should never enlarge branches (start_addr: {:?}, old_size: {}, new_size: {})",
        branch.start_addr.unwrap().raw_ptr(), branch_size_on_entry, new_branch_size,
    );

    // Return a pointer to the compiled block version
    dst_addr.raw_ptr()
}

/// Set up a branch target at an index with a block version or a stub
fn set_branch_target(
    target_idx: u32,
    target: BlockId,
    ctx: &Context,
    branchref: &BranchRef,
    branch: &mut Branch,
    ocb: &mut OutlinedCb,
) {
    let maybe_block = find_block_version(target, ctx);

    // If the block already exists
    if let Some(blockref) = maybe_block {
        let mut block = blockref.borrow_mut();

        // Add an incoming branch into this block
        block.push_incoming(branchref.clone());

        // Fill out the target with this block
        branch.targets[target_idx.as_usize()] = Some(Box::new(BranchTarget {
            block: Some(blockref.clone()),
            address: block.start_addr,
            id: target,
            ctx: ctx.clone(),
        }));

        return;
    }

    let ocb = ocb.unwrap();

    // Generate an outlined stub that will call branch_stub_hit()
    let stub_addr = ocb.get_write_ptr();

    // Get a raw pointer to the branch. We clone and then decrement the strong count which overall
    // balances the strong count. We do this so that we're passing the result of [Rc::into_raw] to
    // [Rc::from_raw] as required.
    // We make sure the block housing the branch is still alive when branch_stub_hit() is running.
    let branch_ptr: *const RefCell<Branch> = BranchRef::into_raw(branchref.clone());
    unsafe { BranchRef::decrement_strong_count(branch_ptr) };

    let mut asm = Assembler::new();
    asm.comment("branch stub hit");

    // Set up the arguments unique to this stub for:
    // branch_stub_hit(branch_ptr, target_idx, ec)
    asm.mov(C_ARG_OPNDS[0], Opnd::const_ptr(branch_ptr as *const u8));
    asm.mov(C_ARG_OPNDS[1], target_idx.into());

    // Jump to trampoline to call branch_stub_hit()
    // Not really a side exit, just don't need a padded jump here.
    asm.jmp(CodegenGlobals::get_branch_stub_hit_trampoline().as_side_exit());

    asm.compile(ocb);

    if ocb.has_dropped_bytes() {
        // No space
    } else {
        // Fill the branch target with a stub
        branch.targets[target_idx.as_usize()] = Some(Box::new(BranchTarget {
            block: None, // no block yet
            address: Some(stub_addr),
            id: target,
            ctx: ctx.clone(),
        }));
    }
}

pub fn gen_branch_stub_hit_trampoline(ocb: &mut OutlinedCb) -> CodePtr {
    let ocb = ocb.unwrap();
    let code_ptr = ocb.get_write_ptr();
    let mut asm = Assembler::new();

    // For `branch_stub_hit(branch_ptr, target_idx, ec)`,
    // `branch_ptr` and `target_idx` is different for each stub,
    // but the call and what's after is the same. This trampoline
    // is the unchanging part.
    // Since this trampoline is static, it allows code GC inside
    // branch_stub_hit() to free stubs without problems.
    asm.comment("branch_stub_hit() trampoline");
    let jump_addr = asm.ccall(
        branch_stub_hit as *mut u8,
        vec![
            C_ARG_OPNDS[0],
            C_ARG_OPNDS[1],
            EC,
        ]
    );

    // Jump to the address returned by the branch_stub_hit() call
    asm.jmp_opnd(jump_addr);

    asm.compile(ocb);

    code_ptr
}

impl Assembler
{
    // Mark the start position of a patchable branch in the machine code
    fn mark_branch_start(&mut self, branchref: &BranchRef)
    {
        // We need to create our own branch rc object
        // so that we can move the closure below
        let branchref = branchref.clone();

        self.pos_marker(move |code_ptr| {
            let mut branch = branchref.borrow_mut();
            branch.start_addr = Some(code_ptr);
        });
    }

    // Mark the end position of a patchable branch in the machine code
    fn mark_branch_end(&mut self, branchref: &BranchRef)
    {
        // We need to create our own branch rc object
        // so that we can move the closure below
        let branchref = branchref.clone();

        self.pos_marker(move |code_ptr| {
            let mut branch = branchref.borrow_mut();
            branch.end_addr = Some(code_ptr);
        });
    }
}

pub fn gen_branch(
    jit: &JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    target0: BlockId,
    ctx0: &Context,
    target1: Option<BlockId>,
    ctx1: Option<&Context>,
    gen_fn: BranchGenFn,
) {
    let branchref = make_branch_entry(&jit.get_block(), gen_fn);
    let branch = &mut branchref.borrow_mut();

    // Get the branch targets or stubs
    set_branch_target(0, target0, ctx0, &branchref, branch, ocb);
    if let Some(ctx) = ctx1 {
        set_branch_target(1, target1.unwrap(), ctx, &branchref, branch, ocb);
        if branch.targets[1].is_none() {
            return; // avoid unwrap() in gen_fn()
        }
    }

    // Call the branch generation function
    asm.mark_branch_start(&branchref);
    if let Some(dst_addr) = branch.get_target_address(0) {
        gen_fn(asm, dst_addr, branch.get_target_address(1), BranchShape::Default);
    }
    asm.mark_branch_end(&branchref);
}

fn gen_jump_branch(
    asm: &mut Assembler,
    target0: CodePtr,
    _target1: Option<CodePtr>,
    shape: BranchShape,
) {
    if shape == BranchShape::Next1 {
        panic!("Branch shape Next1 not allowed in gen_jump_branch!");
    }

    if shape == BranchShape::Default {
        asm.jmp(target0.into());
    }
}

pub fn gen_direct_jump(jit: &JITState, ctx: &Context, target0: BlockId, asm: &mut Assembler) {
    let branchref = make_branch_entry(&jit.get_block(), gen_jump_branch);
    let mut branch = branchref.borrow_mut();

    let mut new_target = BranchTarget {
        block: None,
        address: None,
        ctx: ctx.clone(),
        id: target0,
    };

    let maybe_block = find_block_version(target0, ctx);

    // If the block already exists
    if let Some(blockref) = maybe_block {
        let mut block = blockref.borrow_mut();

        block.push_incoming(branchref.clone());

        new_target.address = block.start_addr;
        new_target.block = Some(blockref.clone());
        branch.shape = BranchShape::Default;

        // Call the branch generation function
        asm.comment("gen_direct_jmp: existing block");
        asm.mark_branch_start(&branchref);
        gen_jump_branch(asm, new_target.address.unwrap(), None, BranchShape::Default);
        asm.mark_branch_end(&branchref);
    } else {
        // This None target address signals gen_block_series() to compile the
        // target block right after this one (fallthrough).
        new_target.address = None;
        branch.shape = BranchShape::Next0;

        // The branch is effectively empty (a noop)
        asm.comment("gen_direct_jmp: fallthrough");
        asm.mark_branch_start(&branchref);
        asm.mark_branch_end(&branchref);
    }

    branch.targets[0] = Some(Box::new(new_target));
}

/// Create a stub to force the code up to this point to be executed
pub fn defer_compilation(
    jit: &JITState,
    cur_ctx: &Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) {
    if cur_ctx.chain_depth != 0 {
        panic!("Double defer!");
    }

    let mut next_ctx = cur_ctx.clone();

    if next_ctx.chain_depth == u8::MAX {
        panic!("max block version chain depth reached!");
    }
    next_ctx.chain_depth += 1;

    let block_rc = jit.get_block();
    let branch_rc = make_branch_entry(&jit.get_block(), gen_jump_branch);
    let mut branch = branch_rc.borrow_mut();
    let block = block_rc.borrow();

    let blockid = BlockId {
        iseq: block.blockid.iseq,
        idx: jit.get_insn_idx(),
    };
    set_branch_target(0, blockid, &next_ctx, &branch_rc, &mut branch, ocb);

    // Call the branch generation function
    asm.mark_branch_start(&branch_rc);
    if let Some(dst_addr) = branch.get_target_address(0) {
        gen_jump_branch(asm, dst_addr, None, BranchShape::Default);
    }
    asm.mark_branch_end(&branch_rc);

    incr_counter!(defer_count);
}

fn remove_from_graph(blockref: &BlockRef) {
    let block = blockref.borrow();

    // Remove this block from the predecessor's targets
    for pred_branchref in &block.incoming {
        // Branch from the predecessor to us
        let mut pred_branch = pred_branchref.borrow_mut();

        // If this is us, nullify the target block
        for pred_succ in pred_branch.targets.iter_mut().flatten() {
            if pred_succ.block.as_ref() == Some(blockref) {
                pred_succ.block = None;
            }
        }
    }

    // For each outgoing branch
    for out_branchref in &block.outgoing {
        let out_branch = out_branchref.borrow();

        // For each successor block
        for out_target in out_branch.targets.iter().flatten() {
            if let Some(succ_blockref) = &out_target.block {
                // Remove outgoing branch from the successor's incoming list
                let mut succ_block = succ_blockref.borrow_mut();
                succ_block
                    .incoming
                    .retain(|succ_incoming| !Rc::ptr_eq(succ_incoming, out_branchref));
            }
        }
    }
}

/// Remove most references to a block to deallocate it.
/// Does not touch references from iseq payloads.
pub fn free_block(blockref: &BlockRef) {
    block_assumptions_free(blockref);

    remove_from_graph(blockref);

    // Branches have a Rc pointing at the block housing them.
    // Break the cycle.
    blockref.borrow_mut().incoming.clear();
    blockref.borrow_mut().outgoing.clear();

    // No explicit deallocation here as blocks are ref-counted.
}

// Some runtime checks for integrity of a program location
pub fn verify_blockid(blockid: BlockId) {
    unsafe {
        assert!(rb_IMEMO_TYPE_P(blockid.iseq.into(), imemo_iseq) != 0);
        assert!(blockid.idx < get_iseq_encoded_size(blockid.iseq));
    }
}

// Invalidate one specific block version
pub fn invalidate_block_version(blockref: &BlockRef) {
    //ASSERT_vm_locking();

    // TODO: want to assert that all other ractors are stopped here. Can't patch
    // machine code that some other thread is running.

    let block = blockref.borrow();
    let mut cb = CodegenGlobals::get_inline_cb();
    let ocb = CodegenGlobals::get_outlined_cb();

    verify_blockid(block.blockid);

    #[cfg(feature = "disasm")]
    {
        // If dump_iseq_disasm is specified, print to console that blocks for matching ISEQ names were invalidated.
        if let Some(substr) = get_option_ref!(dump_iseq_disasm).as_ref() {
            let iseq_location = iseq_get_location(block.blockid.iseq);
            if iseq_location.contains(substr) {
                let blockid_idx = block.blockid.idx;
                println!("Invalidating block from {}, ISEQ offsets [{}, {})", iseq_location, blockid_idx, block.end_idx);
            }
        }
    }

    // Remove this block from the version array
    remove_block_version(blockref);

    // Get a pointer to the generated code for this block
    let block_start = block.start_addr;

    // Make the the start of the block do an exit. This handles OOM situations
    // and some cases where we can't efficiently patch incoming branches.
    // Do this first, since in case there is a fallthrough branch into this
    // block, the patching loop below can overwrite the start of the block.
    // In those situations, there is hopefully no jumps to the start of the block
    // after patching as the start of the block would be in the middle of something
    // generated by branch_t::gen_fn.
    let block_entry_exit = block
        .entry_exit
        .expect("invalidation needs the entry_exit field");
    {
        let block_start = block
            .start_addr
            .expect("invalidation needs constructed block");
        let block_end = block
            .end_addr
            .expect("invalidation needs constructed block");

        if block_start == block_entry_exit {
            // Some blocks exit on entry. Patching a jump to the entry at the
            // entry makes an infinite loop.
        } else {
            // TODO(alan)
            // if (block.start_addr >= cb_get_ptr(cb, yjit_codepage_frozen_bytes)) // Don't patch frozen code region

            // Patch in a jump to block.entry_exit.

            let cur_pos = cb.get_write_ptr();
            let cur_dropped_bytes = cb.has_dropped_bytes();
            cb.set_write_ptr(block_start);

            let mut asm = Assembler::new();
            asm.jmp(block_entry_exit.as_side_exit());
            cb.set_dropped_bytes(false);
            asm.compile(&mut cb);

            assert!(
                cb.get_write_ptr() <= block_end,
                "invalidation wrote past end of block (code_size: {:?}, new_size: {})",
                block.code_size(),
                cb.get_write_ptr().into_i64() - block_start.into_i64(),
            );
            cb.set_write_ptr(cur_pos);
            cb.set_dropped_bytes(cur_dropped_bytes);
        }
    }

    // For each incoming branch
    for branchref in &block.incoming {
        let mut branch = branchref.borrow_mut();
        let target_idx = if branch.get_target_address(0) == block_start {
            0
        } else {
            1
        };

        // Assert that the incoming branch indeed points to the block being invalidated
        let incoming_target = branch.targets[target_idx].as_ref().unwrap();
        assert_eq!(block_start, incoming_target.address);
        assert_eq!(blockref, incoming_target.block.as_ref().unwrap());

        // TODO(alan):
        // Don't patch frozen code region
        // if (branch.start_addr < cb_get_ptr(cb, yjit_codepage_frozen_bytes)) {
        //     continue;
        // }

        // Create a stub for this branch target or rewire it to a valid block
        set_branch_target(target_idx as u32, block.blockid, &block.ctx, branchref, &mut branch, ocb);

        if branch.targets[target_idx].is_none() {
            // We were unable to generate a stub (e.g. OOM). Use the block's
            // exit instead of a stub for the block. It's important that we
            // still patch the branch in this situation so stubs are unique
            // to branches. Think about what could go wrong if we run out of
            // memory in the middle of this loop.
            branch.targets[target_idx] = Some(Box::new(BranchTarget {
                block: None,
                address: block.entry_exit,
                id: block.blockid,
                ctx: block.ctx.clone(),
            }));
        }

        // Check if the invalidated block immediately follows
        let target_next = block.start_addr == branch.end_addr;

        if target_next {
            // The new block will no longer be adjacent.
            // Note that we could be enlarging the branch and writing into the
            // start of the block being invalidated.
            branch.shape = BranchShape::Default;
        }

        // Rewrite the branch with the new jump target address
        let old_branch_size = branch.code_size();
        regenerate_branch(cb, &mut branch);

        if target_next && branch.end_addr > block.end_addr {
            panic!("yjit invalidate rewrote branch past end of invalidated block: {:?} (code_size: {})", branch, block.code_size());
        }
        if !target_next && branch.code_size() > old_branch_size {
            panic!(
                "invalidated branch grew in size (start_addr: {:?}, old_size: {}, new_size: {})",
                branch.start_addr.unwrap().raw_ptr(), old_branch_size, branch.code_size()
            );
        }
    }

    // Clear out the JIT func so that we can recompile later and so the
    // interpreter will run the iseq.
    //
    // Only clear the jit_func when we're invalidating the JIT entry block.
    // We only support compiling iseqs from index 0 right now.  So entry
    // points will always have an instruction index of 0.  We'll need to
    // change this in the future when we support optional parameters because
    // they enter the function with a non-zero PC
    if block.blockid.idx == 0 {
        // TODO:
        // We could reset the exec counter to zero in rb_iseq_reset_jit_func()
        // so that we eventually compile a new entry point when useful
        unsafe { rb_iseq_reset_jit_func(block.blockid.iseq) };
    }

    // FIXME:
    // Call continuation addresses on the stack can also be atomically replaced by jumps going to the stub.

    delayed_deallocation(blockref);

    ocb.unwrap().mark_all_executable();
    cb.mark_all_executable();

    incr_counter!(invalidation_count);
}

// We cannot deallocate blocks immediately after invalidation since there
// could be stubs waiting to access branch pointers. Return stubs can do
// this since patching the code for setting up return addresses does not
// affect old return addresses that are already set up to use potentially
// invalidated branch pointers. Example:
//   def foo(n)
//     if n == 2
//       return 1.times { Object.define_method(:foo) {} }
//     end
//
//     foo(n + 1)
//   end
//   p foo(1)
pub fn delayed_deallocation(blockref: &BlockRef) {
    block_assumptions_free(blockref);

    // We do this another time when we deem that it's safe
    // to deallocate in case there is another Ractor waiting to acquire the
    // VM lock inside branch_stub_hit().
    remove_from_graph(blockref);

    let payload = get_iseq_payload(blockref.borrow().blockid.iseq).unwrap();
    payload.dead_blocks.push(blockref.clone());
}

#[cfg(test)]
mod tests {
    use crate::core::*;

    #[test]
    fn types() {
        // Valid src => dst
        assert_eq!(Type::Unknown.diff(Type::Unknown), 0);
        assert_eq!(Type::UnknownImm.diff(Type::UnknownImm), 0);
        assert_ne!(Type::UnknownImm.diff(Type::Unknown), usize::MAX);
        assert_ne!(Type::Fixnum.diff(Type::Unknown), usize::MAX);
        assert_ne!(Type::Fixnum.diff(Type::UnknownImm), usize::MAX);

        // Invalid src => dst
        assert_eq!(Type::Unknown.diff(Type::UnknownImm), usize::MAX);
        assert_eq!(Type::Unknown.diff(Type::Fixnum), usize::MAX);
        assert_eq!(Type::Fixnum.diff(Type::UnknownHeap), usize::MAX);
    }

    #[test]
    fn context() {
        // Valid src => dst
        assert_eq!(Context::default().diff(&Context::default()), 0);

        // Try pushing an operand and getting its type
        let mut ctx = Context::default();
        ctx.stack_push(Type::Fixnum);
        let top_type = ctx.get_opnd_type(StackOpnd(0));
        assert!(top_type == Type::Fixnum);

        // TODO: write more tests for Context type diff
    }
}
