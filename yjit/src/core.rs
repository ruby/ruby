//! Code versioning, retained live control flow graph mutations, type tracking, etc.

// So we can comment on individual uses of `unsafe` in `unsafe` functions
#![warn(unsafe_op_in_unsafe_fn)]

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
use std::fmt;
use std::mem;
use std::mem::transmute;
use std::ops::Range;
use std::rc::Rc;
use mem::MaybeUninit;
use std::ptr;
use ptr::NonNull;
use YARVOpnd::*;
use TempMappingKind::*;
use crate::invariants::*;

// Maximum number of temp value types we keep track of
pub const MAX_TEMP_TYPES: usize = 8;

// Maximum number of local variable types we keep track of
const MAX_LOCAL_TYPES: usize = 8;

/// An index into `ISEQ_BODY(iseq)->iseq_encoded`. Points
/// to a YARV instruction or an instruction operand.
pub type IseqIdx = u16;

// Represent the type of a value (local/stack/self) in YJIT
#[derive(Copy, Clone, Hash, PartialEq, Eq, Debug)]
#[repr(u8)]
pub enum Type {
    Unknown = 0,
    UnknownImm,
    UnknownHeap,
    Nil,
    True,
    False,
    Fixnum,
    Flonum,
    ImmSymbol,

    TString, // An object with the T_STRING flag set, possibly an rb_cString
    CString, // An object that at one point had its class field equal rb_cString (creating a singleton class changes it)
    TArray, // An object with the T_ARRAY flag set, possibly an rb_cArray
    CArray, // An object that at one point had its class field equal rb_cArray (creating a singleton class changes it)
    THash, // An object with the T_HASH flag set, possibly an rb_cHash
    CHash, // An object that at one point had its class field equal rb_cHash (creating a singleton class changes it)

    BlockParamProxy, // A special sentinel value indicating the block parameter should be read from
                     // the current surrounding cfp

    // The context currently relies on types taking at most 4 bits (max value 15)
    // to encode, so if we add any more, we will need to refactor the context.
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
            match val.class_of() {
                class if class == unsafe { rb_cArray }  => return Type::CArray,
                class if class == unsafe { rb_cHash }   => return Type::CHash,
                class if class == unsafe { rb_cString } => return Type::CString,
                _ => {}
            }
            // We likewise can't reference rb_block_param_proxy, but it's again an optimisation;
            // we can just treat it as a normal Object.
            #[cfg(not(test))]
            if val == unsafe { rb_block_param_proxy } {
                return Type::BlockParamProxy;
            }
            match val.builtin_type() {
                RUBY_T_ARRAY => Type::TArray,
                RUBY_T_HASH => Type::THash,
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
            Type::TArray => true,
            Type::CArray => true,
            Type::THash => true,
            Type::CHash => true,
            Type::TString => true,
            Type::CString => true,
            Type::BlockParamProxy => true,
            _ => false,
        }
    }

    /// Check if it's a T_ARRAY object (both TArray and CArray are T_ARRAY)
    pub fn is_array(&self) -> bool {
        matches!(self, Type::TArray | Type::CArray)
    }

    /// Check if it's a T_HASH object (both THash and CHash are T_HASH)
    pub fn is_hash(&self) -> bool {
        matches!(self, Type::THash | Type::CHash)
    }

    /// Check if it's a T_STRING object (both TString and CString are T_STRING)
    pub fn is_string(&self) -> bool {
        matches!(self, Type::TString | Type::CString)
    }

    /// Returns an Option with the T_ value type if it is known, otherwise None
    pub fn known_value_type(&self) -> Option<ruby_value_type> {
        match self {
            Type::Nil => Some(RUBY_T_NIL),
            Type::True => Some(RUBY_T_TRUE),
            Type::False => Some(RUBY_T_FALSE),
            Type::Fixnum => Some(RUBY_T_FIXNUM),
            Type::Flonum => Some(RUBY_T_FLOAT),
            Type::TArray | Type::CArray => Some(RUBY_T_ARRAY),
            Type::THash | Type::CHash => Some(RUBY_T_HASH),
            Type::ImmSymbol => Some(RUBY_T_SYMBOL),
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
                Type::ImmSymbol => Some(rb_cSymbol),
                Type::CArray => Some(rb_cArray),
                Type::CHash => Some(rb_cHash),
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
    pub fn diff(self, dst: Self) -> TypeDiff {
        // Perfect match, difference is zero
        if self == dst {
            return TypeDiff::Compatible(0);
        }

        // Any type can flow into an unknown type
        if dst == Type::Unknown {
            return TypeDiff::Compatible(1);
        }

        // A CArray is also a TArray.
        if self == Type::CArray && dst == Type::TArray {
            return TypeDiff::Compatible(1);
        }

        // A CHash is also a THash.
        if self == Type::CHash && dst == Type::THash {
            return TypeDiff::Compatible(1);
        }

        // A CString is also a TString.
        if self == Type::CString && dst == Type::TString {
            return TypeDiff::Compatible(1);
        }

        // Specific heap type into unknown heap type is imperfect but valid
        if self.is_heap() && dst == Type::UnknownHeap {
            return TypeDiff::Compatible(1);
        }

        // Specific immediate type into unknown immediate type is imperfect but valid
        if self.is_imm() && dst == Type::UnknownImm {
            return TypeDiff::Compatible(1);
        }

        // Incompatible types
        return TypeDiff::Incompatible;
    }

    /// Upgrade this type into a more specific compatible type
    /// The new type must be compatible and at least as specific as the previously known type.
    fn upgrade(&mut self, new_type: Self) {
        // We can only upgrade to a type that is more specific
        assert!(new_type.diff(*self) != TypeDiff::Incompatible);
        *self = new_type;
    }
}

#[derive(Debug, Eq, PartialEq)]
pub enum TypeDiff {
    // usize == 0: Same type
    // usize >= 1: Different but compatible. The smaller, the more compatible.
    Compatible(usize),
    Incompatible,
}

#[derive(Copy, Clone, Eq, Hash, PartialEq, Debug)]
#[repr(u8)]
pub enum TempMappingKind
{
    MapToStack = 0,
    MapToSelf = 1,
    MapToLocal = 2,
}

// Potential mapping of a value on the temporary stack to
// self, a local variable or constant so that we can track its type
//
// The highest two bits represent TempMappingKind, and the rest of
// the bits are used differently across different kinds.
// * MapToStack: The lowest 5 bits are used for mapping Type.
// * MapToSelf: The remaining bits are not used; the type is stored in self_type.
// * MapToLocal: The lowest 3 bits store the index of a local variable.
#[derive(Copy, Clone, Eq, Hash, PartialEq, Debug)]
pub struct TempMapping(u8);

impl TempMapping {
    pub fn map_to_stack(t: Type) -> TempMapping
    {
        let kind_bits = TempMappingKind::MapToStack as u8;
        let type_bits = t as u8;
        assert!(type_bits <= 0b11111);
        let bits = (kind_bits << 6) | (type_bits & 0b11111);
        TempMapping(bits)
    }

    pub fn map_to_self() -> TempMapping
    {
        let kind_bits = TempMappingKind::MapToSelf as u8;
        let bits = kind_bits << 6;
        TempMapping(bits)
    }

    pub fn map_to_local(local_idx: u8) -> TempMapping
    {
        let kind_bits = TempMappingKind::MapToLocal as u8;
        assert!(local_idx <= 0b111);
        let bits = (kind_bits << 6) | (local_idx & 0b111);
        TempMapping(bits)
    }

    pub fn without_type(&self) -> TempMapping
    {
        if self.get_kind() != TempMappingKind::MapToStack {
            return *self;
        }

        TempMapping::map_to_stack(Type::Unknown)
    }

    pub fn get_kind(&self) -> TempMappingKind
    {
        // Take the two highest bits
        let TempMapping(bits) = self;
        let kind_bits = bits >> 6;
        assert!(kind_bits <= 2);
        unsafe { transmute::<u8, TempMappingKind>(kind_bits) }
    }

    pub fn get_type(&self) -> Type
    {
        assert!(self.get_kind() == TempMappingKind::MapToStack);

        // Take the 5 lowest bits
        let TempMapping(bits) = self;
        let type_bits = bits & 0b11111;
        unsafe { transmute::<u8, Type>(type_bits) }
    }

    pub fn get_local_idx(&self) -> u8
    {
        assert!(self.get_kind() == TempMappingKind::MapToLocal);

        // Take the 3 lowest bits
        let TempMapping(bits) = self;
        bits & 0b111
    }
}

impl Default for TempMapping {
    fn default() -> Self {
        TempMapping::map_to_stack(Type::Unknown)
    }
}

// Operand to a YARV bytecode instruction
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum YARVOpnd {
    // The value is self
    SelfOpnd,

    // Temporary stack operand with stack index
    StackOpnd(u8),
}

impl From<Opnd> for YARVOpnd {
    fn from(value: Opnd) -> Self {
        match value {
            Opnd::Stack { idx, .. } => StackOpnd(idx.try_into().unwrap()),
            _ => unreachable!("{:?} cannot be converted to YARVOpnd", value)
        }
    }
}

/// Maximum index of stack temps that could be in a register
pub const MAX_REG_TEMPS: u8 = 8;

/// Bitmap of which stack temps are in a register
#[derive(Copy, Clone, Default, Eq, Hash, PartialEq, Debug)]
pub struct RegTemps(u8);

impl RegTemps {
    pub fn get(&self, index: u8) -> bool {
        assert!(index < MAX_REG_TEMPS);
        (self.0 >> index) & 1 == 1
    }

    pub fn set(&mut self, index: u8, value: bool) {
        assert!(index < MAX_REG_TEMPS);
        if value {
            self.0 = self.0 | (1 << index);
        } else {
            self.0 = self.0 & !(1 << index);
        }
    }

    pub fn as_u8(&self) -> u8 {
        self.0
    }

    /// Return true if there's a register that conflicts with a given stack_idx.
    pub fn conflicts_with(&self, stack_idx: u8) -> bool {
        let mut other_idx = stack_idx as usize % get_option!(num_temp_regs);
        while other_idx < MAX_REG_TEMPS as usize {
            if stack_idx as usize != other_idx && self.get(other_idx as u8) {
                return true;
            }
            other_idx += get_option!(num_temp_regs);
        }
        false
    }
}

/// Bits for chain_depth_return_landing_defer
const RETURN_LANDING_BIT: u8 = 0b10000000;
const DEFER_BIT: u8          = 0b01000000;
const CHAIN_DEPTH_MASK: u8   = 0b00111111; // 63

/// Code generation context
/// Contains information we can use to specialize/optimize code
/// There are a lot of context objects so we try to keep the size small.
#[derive(Copy, Clone, Default, Eq, Hash, PartialEq, Debug)]
#[repr(packed)]
pub struct Context {
    // Number of values currently on the temporary stack
    stack_size: u8,

    // Offset of the JIT SP relative to the interpreter SP
    // This represents how far the JIT's SP is from the "real" SP
    sp_offset: i8,

    /// Bitmap of which stack temps are in a register
    reg_temps: RegTemps,

    /// Fields packed into u8
    /// - 1st bit from the left: Whether this code is the target of a JIT-to-JIT Ruby return ([Self::is_return_landing])
    /// - 2nd bit from the left: Whether the compilation of this code has been deferred ([Self::is_deferred])
    /// - Last 6 bits (max: 63): Depth of this block in the sidechain (eg: inline-cache chain)
    chain_depth_and_flags: u8,

    // Type we track for self
    self_type: Type,

    // Local variable types we keep track of
    // We store 8 local types, requiring 4 bits each, for a total of 32 bits
    local_types: u32,

    // Temp mapping kinds we track
    // 8 temp mappings * 2 bits, total 16 bits
    temp_mapping_kind: u16,

    // Stack slot type/local_idx we track
    // 8 temp types * 4 bits, total 32 bits
    temp_payload: u32,

    /// A pointer to a block ISEQ supplied by the caller. 0 if not inlined.
    /// Not using IseqPtr to satisfy Default trait, and not using Option for #[repr(packed)]
    /// TODO: This could be u16 if we have a global or per-ISEQ HashMap to convert IseqPtr
    /// to serial indexes. We're thinking of overhauling Context structure in Ruby 3.4 which
    /// could allow this to consume no bytes, so we're leaving this as is.
    inline_block: u64,
}

/// Tuple of (iseq, idx) used to identify basic blocks
/// There are a lot of blockid objects so we try to keep the size small.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
#[repr(packed)]
pub struct BlockId {
    /// Instruction sequence
    pub iseq: IseqPtr,

    /// Index in the iseq where the block starts
    pub idx: u16,
}

/// Branch code shape enumeration
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum BranchShape {
    Next0,   // Target 0 is next
    Next1,   // Target 1 is next
    Default, // Neither target is next
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum BranchGenFn {
    BranchIf(Cell<BranchShape>),
    BranchNil(Cell<BranchShape>),
    BranchUnless(Cell<BranchShape>),
    JumpToTarget0(Cell<BranchShape>),
    JNZToTarget0,
    JZToTarget0,
    JBEToTarget0,
    JBToTarget0,
    JOMulToTarget0,
    JITReturn,
}

impl BranchGenFn {
    pub fn call(&self, asm: &mut Assembler, target0: Target, target1: Option<Target>) {
        match self {
            BranchGenFn::BranchIf(shape) => {
                match shape.get() {
                    BranchShape::Next0 => asm.jz(target1.unwrap()),
                    BranchShape::Next1 => asm.jnz(target0),
                    BranchShape::Default => {
                        asm.jnz(target0);
                        asm.jmp(target1.unwrap());
                    }
                }
            }
            BranchGenFn::BranchNil(shape) => {
                match shape.get() {
                    BranchShape::Next0 => asm.jne(target1.unwrap()),
                    BranchShape::Next1 => asm.je(target0),
                    BranchShape::Default => {
                        asm.je(target0);
                        asm.jmp(target1.unwrap());
                    }
                }
            }
            BranchGenFn::BranchUnless(shape) => {
                match shape.get() {
                    BranchShape::Next0 => asm.jnz(target1.unwrap()),
                    BranchShape::Next1 => asm.jz(target0),
                    BranchShape::Default => {
                        asm.jz(target0);
                        asm.jmp(target1.unwrap());
                    }
                }
            }
            BranchGenFn::JumpToTarget0(shape) => {
                if shape.get() == BranchShape::Next1 {
                    panic!("Branch shape Next1 not allowed in JumpToTarget0!");
                }
                if shape.get() == BranchShape::Default {
                    asm.jmp(target0);
                }
            }
            BranchGenFn::JNZToTarget0 => {
                asm.jnz(target0)
            }
            BranchGenFn::JZToTarget0 => {
                asm.jz(target0)
            }
            BranchGenFn::JBEToTarget0 => {
                asm.jbe(target0)
            }
            BranchGenFn::JBToTarget0 => {
                asm.jb(target0)
            }
            BranchGenFn::JOMulToTarget0 => {
                asm.jo_mul(target0)
            }
            BranchGenFn::JITReturn => {
                asm_comment!(asm, "update cfp->jit_return");
                let jit_return = RUBY_OFFSET_CFP_JIT_RETURN - RUBY_SIZEOF_CONTROL_FRAME as i32;
                let raw_ptr = asm.lea_jump_target(target0);
                asm.mov(Opnd::mem(64, CFP, jit_return), raw_ptr);
            }
        }
    }

    pub fn get_shape(&self) -> BranchShape {
        match self {
            BranchGenFn::BranchIf(shape) |
            BranchGenFn::BranchNil(shape) |
            BranchGenFn::BranchUnless(shape) |
            BranchGenFn::JumpToTarget0(shape) => shape.get(),
            BranchGenFn::JNZToTarget0 |
            BranchGenFn::JZToTarget0 |
            BranchGenFn::JBEToTarget0 |
            BranchGenFn::JBToTarget0 |
            BranchGenFn::JOMulToTarget0 |
            BranchGenFn::JITReturn => BranchShape::Default,
        }
    }

    pub fn set_shape(&self, new_shape: BranchShape) {
        match self {
            BranchGenFn::BranchIf(shape) |
            BranchGenFn::BranchNil(shape) |
            BranchGenFn::BranchUnless(shape) => {
                shape.set(new_shape);
            }
            BranchGenFn::JumpToTarget0(shape) => {
                if new_shape == BranchShape::Next1 {
                    panic!("Branch shape Next1 not allowed in JumpToTarget0!");
                }
                shape.set(new_shape);
            }
            BranchGenFn::JNZToTarget0 |
            BranchGenFn::JZToTarget0 |
            BranchGenFn::JBEToTarget0 |
            BranchGenFn::JBToTarget0 |
            BranchGenFn::JOMulToTarget0 |
            BranchGenFn::JITReturn => {
                assert_eq!(new_shape, BranchShape::Default);
            }
        }
    }
}

/// A place that a branch could jump to
#[derive(Debug, Clone)]
enum BranchTarget {
    Stub(Box<BranchStub>), // Not compiled yet
    Block(BlockRef),       // Already compiled
}

impl BranchTarget {
    fn get_address(&self) -> Option<CodePtr> {
        match self {
            BranchTarget::Stub(stub) => stub.address,
            BranchTarget::Block(blockref) => Some(unsafe { blockref.as_ref() }.start_addr),
        }
    }

    fn get_blockid(&self) -> BlockId {
        match self {
            BranchTarget::Stub(stub) => BlockId { iseq: stub.iseq.get(), idx: stub.iseq_idx },
            BranchTarget::Block(blockref) => unsafe { blockref.as_ref() }.get_blockid(),
        }
    }

    fn get_ctx(&self) -> Context {
        match self {
            BranchTarget::Stub(stub) => stub.ctx,
            BranchTarget::Block(blockref) => unsafe { blockref.as_ref() }.ctx,
        }
    }

    fn get_block(&self) -> Option<BlockRef> {
        match self {
            BranchTarget::Stub(_) => None,
            BranchTarget::Block(blockref) => Some(*blockref),
        }
    }

    fn set_iseq(&self, iseq: IseqPtr) {
        match self {
            BranchTarget::Stub(stub) => stub.iseq.set(iseq),
            BranchTarget::Block(blockref) => unsafe { blockref.as_ref() }.iseq.set(iseq),
        }
    }
}

#[derive(Debug, Clone)]
struct BranchStub {
    address: Option<CodePtr>,
    iseq: Cell<IseqPtr>,
    iseq_idx: IseqIdx,
    ctx: Context,
}

/// Store info about an outgoing branch in a code segment
/// Note: care must be taken to minimize the size of branch objects
pub struct Branch {
    // Block this is attached to
    block: BlockRef,

    // Positions where the generated code starts and ends
    start_addr: CodePtr,
    end_addr: Cell<CodePtr>, // exclusive

    // Branch target blocks and their contexts
    targets: [Cell<Option<Box<BranchTarget>>>; 2],

    // Branch code generation function
    gen_fn: BranchGenFn,
}

/// A [Branch] for a [Block] that is under construction.
/// Fields correspond, but may be `None` during construction.
pub struct PendingBranch {
    /// Allocation holder for the address of the constructed branch
    /// in error paths Box deallocates it.
    uninit_branch: Box<MaybeUninit<Branch>>,

    /// Branch code generation function
    gen_fn: BranchGenFn,

    /// Positions where the generated code starts and ends
    start_addr: Cell<Option<CodePtr>>,
    end_addr: Cell<Option<CodePtr>>, // exclusive

    /// Branch target blocks and their contexts
    targets: [Cell<Option<Box<BranchTarget>>>; 2],
}

impl Branch {
    // Compute the size of the branch code
    fn code_size(&self) -> usize {
        (self.end_addr.get().as_offset() - self.start_addr.as_offset()) as usize
    }

    /// Get the address of one of the branch destination
    fn get_target_address(&self, target_idx: usize) -> Option<CodePtr> {
        unsafe {
            self.targets[target_idx]
                .ref_unchecked()
                .as_ref()
                .and_then(|target| target.get_address())
        }
    }

    fn get_stub_count(&self) -> usize {
        let mut count = 0;
        for target in self.targets.iter() {
            if unsafe {
                // SAFETY: no mutation
                matches!(
                    target.ref_unchecked().as_ref().map(Box::as_ref),
                    Some(BranchTarget::Stub(_))
                )
            } {
                count += 1;
            }
        }
        count
    }

    fn assert_layout(&self) {
        let shape = self.gen_fn.get_shape();
        assert!(
            !(shape == BranchShape::Default && 0 == self.code_size()),
            "zero-size branches are incorrect when code for neither targets are adjacent"
            // One needs to issue some instruction to steer to the branch target
            // when falling through isn't an option.
        );
    }
}

impl std::fmt::Debug for Branch {
    // Can't derive this because `targets: !Copy` due to Cell.
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let targets = unsafe {
            // SAFETY:
            // While the references are live for the result of this function,
            // no mutation happens because we are only calling derived fmt::Debug functions.
            [self.targets[0].as_ptr().as_ref().unwrap(), self.targets[1].as_ptr().as_ref().unwrap()]
        };

        formatter
            .debug_struct("Branch")
            .field("block", &self.block)
            .field("start", &self.start_addr)
            .field("end", &self.end_addr)
            .field("targets", &targets)
            .field("gen_fn", &self.gen_fn)
            .finish()
    }
}

impl PendingBranch {
    /// Set up a branch target at `target_idx`. Find an existing block to branch to
    /// or generate a stub for one.
    fn set_target(
        &self,
        target_idx: u32,
        target: BlockId,
        ctx: &Context,
        ocb: &mut OutlinedCb,
    ) -> Option<CodePtr> {
        // If the block already exists
        if let Some(blockref) = find_block_version(target, ctx) {
            let block = unsafe { blockref.as_ref() };

            // Fill out the target with this block
            self.targets[target_idx.as_usize()]
                .set(Some(Box::new(BranchTarget::Block(blockref))));
            return Some(block.start_addr);
        }

        // The branch struct is uninitialized right now but as a stable address.
        // We make sure the stub runs after the branch is initialized.
        let branch_struct_addr = self.uninit_branch.as_ptr() as usize;
        let stub_addr = gen_branch_stub(ctx, ocb, branch_struct_addr, target_idx);

        if let Some(stub_addr) = stub_addr {
            // Fill the branch target with a stub
            self.targets[target_idx.as_usize()].set(Some(Box::new(BranchTarget::Stub(Box::new(BranchStub {
                address: Some(stub_addr),
                iseq: Cell::new(target.iseq),
                iseq_idx: target.idx,
                ctx: *ctx,
            })))));
        }

        stub_addr
    }

    // Construct the branch and wire it up in the grpah
    fn into_branch(mut self, uninit_block: BlockRef) -> BranchRef {
        // Make the branch
        let branch = Branch {
            block: uninit_block,
            start_addr: self.start_addr.get().unwrap(),
            end_addr: Cell::new(self.end_addr.get().unwrap()),
            targets: self.targets,
            gen_fn: self.gen_fn,
        };
        // Move it to the designated place on
        // the heap and unwrap MaybeUninit.
        self.uninit_branch.write(branch);
        let raw_branch: *mut MaybeUninit<Branch> = Box::into_raw(self.uninit_branch);
        let branchref = NonNull::new(raw_branch as *mut Branch).expect("no null from Box");

        // SAFETY: just allocated it
        let branch = unsafe { branchref.as_ref() };
        // For block branch targets, put the new branch in the
        // appropriate incoming list.
        for target in branch.targets.iter() {
            // SAFETY: no mutation
            let out_block: Option<BlockRef> = unsafe {
                target.ref_unchecked().as_ref().and_then(|target| target.get_block())
            };

            if let Some(out_block) = out_block {
                // SAFETY: These blockrefs come from set_target() which only puts blocks from
                // ISeqs, which are all initialized. Note that uninit_block isn't in any ISeq
                // payload yet.
                unsafe { out_block.as_ref() }.incoming.push(branchref);
            }
        }

        branch.assert_layout();

        branchref
    }
}

// Store info about code used on YJIT entry
pub struct Entry {
    // Positions where the generated code starts and ends
    start_addr: CodePtr,
    end_addr: CodePtr, // exclusive
}

/// A [Branch] for a [Block] that is under construction.
pub struct PendingEntry {
    pub uninit_entry: Box<MaybeUninit<Entry>>,
    start_addr: Cell<Option<CodePtr>>,
    end_addr: Cell<Option<CodePtr>>, // exclusive
}

impl PendingEntry {
    // Construct the entry in the heap
    pub fn into_entry(mut self) -> EntryRef {
        // Make the entry
        let entry = Entry {
            start_addr: self.start_addr.get().unwrap(),
            end_addr: self.end_addr.get().unwrap(),
        };
        // Move it to the designated place on the heap and unwrap MaybeUninit.
        self.uninit_entry.write(entry);
        let raw_entry: *mut MaybeUninit<Entry> = Box::into_raw(self.uninit_entry);
        NonNull::new(raw_entry as *mut Entry).expect("no null from Box")
    }
}

// In case a block is invalidated, this helps to remove all pointers to the block.
pub type CmePtr = *const rb_callable_method_entry_t;

/// Basic block version
/// Represents a portion of an iseq compiled with a given context
/// Note: care must be taken to minimize the size of block_t objects
#[derive(Debug)]
pub struct Block {
    // The byte code instruction sequence this is a version of.
    // Can change due to moving GC.
    iseq: Cell<IseqPtr>,

    // Index range covered by this version in `ISEQ_BODY(iseq)->iseq_encoded`.
    iseq_range: Range<IseqIdx>,

    // Context at the start of the block
    // This should never be mutated
    ctx: Context,

    // Positions where the generated code starts and ends
    start_addr: CodePtr,
    end_addr: Cell<CodePtr>,

    // List of incoming branches (from predecessors)
    // These are reference counted (ownership shared between predecessor and successors)
    incoming: MutableBranchList,

    // NOTE: we might actually be able to store the branches here without refcounting
    // however, using a RefCell makes it easy to get a pointer to Branch objects
    //
    // List of outgoing branches (to successors)
    outgoing: Box<[BranchRef]>,

    // FIXME: should these be code pointers instead?
    // Offsets for GC managed objects in the mainline code block
    gc_obj_offsets: Box<[u32]>,

    // CME dependencies of this block, to help to remove all pointers to this
    // block in the system.
    cme_dependencies: Box<[Cell<CmePtr>]>,

    // Code address of an exit for `ctx` and `blockid`.
    // Used for block invalidation.
    entry_exit: Option<CodePtr>,
}

/// Pointer to a [Block].
///
/// # Safety
///
/// _Never_ derive a `&mut Block` from this and always use
/// [std::ptr::NonNull::as_ref] to get a `&Block`. `&'a mut`
/// in Rust asserts that there are no other references live
/// over the lifetime `'a`. This uniqueness assertion does
/// not hold in many situations for us, even when you ignore
/// the fact that our control flow graph can have cycles.
/// Here are just two examples where we have overlapping references:
///  - Yielding to a different OS thread within the same
///    ractor during compilation
///  - The GC calling [rb_yjit_iseq_mark] during compilation
///
/// Technically, for soundness, we also need to ensure that
/// the we have the VM lock while the result of `as_ref()`
/// is live, so that no deallocation happens while the
/// shared reference is live. The vast majority of our code run while
/// holding the VM lock, though.
pub type BlockRef = NonNull<Block>;

/// Pointer to a [Branch]. See [BlockRef] for notes about
/// proper usage.
pub type BranchRef = NonNull<Branch>;

/// Pointer to an entry that is already added to an ISEQ
pub type EntryRef = NonNull<Entry>;

/// List of block versions for a given blockid
type VersionList = Vec<BlockRef>;

/// Map from iseq indices to lists of versions for that given blockid
/// An instance of this is stored on each iseq
type VersionMap = Vec<VersionList>;

/// [Interior mutability][1] wrapper for a list of branches.
/// O(n) insertion, but space efficient. We generally expect
/// blocks to have only a few branches.
///
/// [1]: https://doc.rust-lang.org/std/cell/struct.UnsafeCell.html
#[repr(transparent)]
struct MutableBranchList(Cell<Box<[BranchRef]>>);

impl MutableBranchList {
    fn push(&self, branch: BranchRef) {
        // Temporary move the boxed slice out of self.
        // oom=abort is load bearing here...
        let mut current_list = self.0.take().into_vec();
        current_list.push(branch);
        self.0.set(current_list.into_boxed_slice());
    }
}

impl fmt::Debug for MutableBranchList {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        // SAFETY: the derived Clone for boxed slices does not mutate this Cell
        let branches = unsafe { self.0.ref_unchecked().clone() };

        formatter.debug_list().entries(branches.into_iter()).finish()
    }
}

/// This is all the data YJIT stores on an iseq
/// This will be dynamically allocated by C code
/// C code should pass an &mut IseqPayload to us
/// when calling into YJIT
#[derive(Default)]
pub struct IseqPayload {
    // Basic block versions
    pub version_map: VersionMap,

    // Indexes of code pages used by this this ISEQ
    pub pages: HashSet<usize>,

    // List of ISEQ entry codes
    pub entries: Vec<EntryRef>,

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
            let new_payload = IseqPayload::default();
            let new_payload = Box::into_raw(Box::new(new_payload));
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
        // SAFETY: points to the local below
        let callback: &mut &mut dyn FnMut(IseqPtr) -> bool = unsafe { std::mem::transmute(&mut *data) };
        callback(iseq);
    }
    let mut data: &mut dyn FnMut(IseqPtr) = &mut callback;
    unsafe { rb_yjit_for_each_iseq(Some(callback_wrapper), (&mut data) as *mut _ as *mut c_void) };
}

/// Iterate over all ISEQ payloads
pub fn for_each_iseq_payload<F: FnMut(&IseqPayload)>(mut callback: F) {
    for_each_iseq(|iseq| {
        if let Some(iseq_payload) = get_iseq_payload(iseq) {
            callback(iseq_payload);
        }
    });
}

/// Iterate over all on-stack ISEQs
pub fn for_each_on_stack_iseq<F: FnMut(IseqPtr)>(mut callback: F) {
    unsafe extern "C" fn callback_wrapper(iseq: IseqPtr, data: *mut c_void) {
        // SAFETY: points to the local below
        let callback: &mut &mut dyn FnMut(IseqPtr) -> bool = unsafe { std::mem::transmute(&mut *data) };
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
    // Get all ISEQs on the heap. Note that rb_objspace_each_objects() runs GC first,
    // which could move ISEQ pointers when GC.auto_compact = true.
    // So for_each_on_stack_iseq() must be called after this, which doesn't run GC.
    let mut iseqs: Vec<IseqPtr> = vec![];
    for_each_iseq(|iseq| iseqs.push(iseq));

    // Get all ISEQs that are on a CFP of existing ECs.
    let mut on_stack_iseqs: HashSet<IseqPtr> = HashSet::new();
    for_each_on_stack_iseq(|iseq| { on_stack_iseqs.insert(iseq); });

    // Invoke the callback for iseqs - on_stack_iseqs
    for iseq in iseqs {
        if !on_stack_iseqs.contains(&iseq) {
            if let Some(iseq_payload) = get_iseq_payload(iseq) {
                callback(iseq_payload);
            }
        }
    }
}

/// Free the per-iseq payload
#[no_mangle]
pub extern "C" fn rb_yjit_iseq_free(iseq: IseqPtr) {
    // Free invariants for the ISEQ
    iseq_free_invariants(iseq);

    let payload = {
        let payload = unsafe { rb_iseq_get_yjit_payload(iseq) };
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

    // Free all blocks in version_map. The GC doesn't free running iseqs.
    for versions in &payload.version_map {
        for block in versions {
            // SAFETY: blocks in the version_map are always well connected
            unsafe { free_block(*block, true) };
        }
    }

    // Free dead blocks
    for block in payload.dead_blocks {
        unsafe { free_block(block, false) };
    }

    // Free all entries
    for entryref in payload.entries.iter() {
        let entry = unsafe { Box::from_raw(entryref.as_ptr()) };
        mem::drop(entry);
    }

    // Increment the freed iseq count
    incr_counter!(freed_iseq_count);
}

/// GC callback for marking GC objects in the per-iseq payload.
#[no_mangle]
pub extern "C" fn rb_yjit_iseq_mark(payload: *mut c_void) {
    let payload = if payload.is_null() {
        // Nothing to mark.
        return;
    } else {
        // SAFETY: The GC takes the VM lock while marking, which
        // we assert, so we should be synchronized and data race free.
        //
        // For aliasing, having the VM lock hopefully also implies that no one
        // else has an overlapping &mut IseqPayload.
        unsafe {
            rb_yjit_assert_holding_vm_lock();
            &*(payload as *const IseqPayload)
        }
    };

    // For marking VALUEs written into the inline code block.
    // We don't write VALUEs in the outlined block.
    let cb: &CodeBlock = CodegenGlobals::get_inline_cb();

    for versions in &payload.version_map {
        for block in versions {
            // SAFETY: all blocks inside version_map are initialized.
            let block = unsafe { block.as_ref() };
            mark_block(block, cb, false);
        }
    }
    // Mark dead blocks, since there could be stubs pointing at them
    for blockref in &payload.dead_blocks {
        // SAFETY: dead blocks come from version_map, which only have initialized blocks
        let block = unsafe { blockref.as_ref() };
        mark_block(block, cb, true);
    }

    return;

    fn mark_block(block: &Block, cb: &CodeBlock, dead: bool) {
        unsafe { rb_gc_mark_movable(block.iseq.get().into()) };

        // Mark method entry dependencies
        for cme_dep in block.cme_dependencies.iter() {
            unsafe { rb_gc_mark_movable(cme_dep.get().into()) };
        }

        // Mark outgoing branch entries
        for branch in block.outgoing.iter() {
            let branch = unsafe { branch.as_ref() };
            for target in branch.targets.iter() {
                // SAFETY: no mutation inside unsafe
                let target_iseq = unsafe {
                    target.ref_unchecked().as_ref().and_then(|target| {
                        // Avoid get_blockid() on blockref. Can be dangling on dead blocks,
                        // and the iseq housing the block already naturally handles it.
                        if target.get_block().is_some() {
                            None
                        } else {
                            Some(target.get_blockid().iseq)
                        }
                    })
                };

                if let Some(target_iseq) = target_iseq {
                    unsafe { rb_gc_mark_movable(target_iseq.into()) };
                }
            }
        }

        // Mark references to objects in generated code.
        // Skip for dead blocks since they shouldn't run.
        if !dead {
            for offset in block.gc_obj_offsets.iter() {
                let value_address: *const u8 = cb.get_ptr(offset.as_usize()).raw_ptr(cb);
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

/// GC callback for updating GC objects in the per-iseq payload.
/// This is a mirror of [rb_yjit_iseq_mark].
#[no_mangle]
pub extern "C" fn rb_yjit_iseq_update_references(iseq: IseqPtr) {
    let payload = unsafe { rb_iseq_get_yjit_payload(iseq) };
    let payload = if payload.is_null() {
        // Nothing to update.
        return;
    } else {
        // SAFETY: The GC takes the VM lock while marking, which
        // we assert, so we should be synchronized and data race free.
        //
        // For aliasing, having the VM lock hopefully also implies that no one
        // else has an overlapping &mut IseqPayload.
        unsafe {
            rb_yjit_assert_holding_vm_lock();
            &*(payload as *const IseqPayload)
        }
    };

    // Evict other threads from generated code since we are about to patch them.
    // Also acts as an assert that we hold the VM lock.
    unsafe { rb_vm_barrier() };

    // For updating VALUEs written into the inline code block.
    let cb = CodegenGlobals::get_inline_cb();

    for versions in &payload.version_map {
        for version in versions {
            // SAFETY: all blocks inside version_map are initialized
            let block = unsafe { version.as_ref() };
            block_update_references(block, cb, false);
        }
    }
    // Update dead blocks, since there could be stubs pointing at them
    for blockref in &payload.dead_blocks {
        // SAFETY: dead blocks come from version_map, which only have initialized blocks
        let block = unsafe { blockref.as_ref() };
        block_update_references(block, cb, true);
    }

    // Note that we would have returned already if YJIT is off.
    cb.mark_all_executable();

    CodegenGlobals::get_outlined_cb()
        .unwrap()
        .mark_all_executable();

    return;

    fn block_update_references(block: &Block, cb: &mut CodeBlock, dead: bool) {
        block.iseq.set(unsafe { rb_gc_location(block.iseq.get().into()) }.as_iseq());

        // Update method entry dependencies
        for cme_dep in block.cme_dependencies.iter() {
            let cur_cme: VALUE = cme_dep.get().into();
            let new_cme = unsafe { rb_gc_location(cur_cme) }.as_cme();
            cme_dep.set(new_cme);
        }

        // Update outgoing branch entries
        for branch in block.outgoing.iter() {
            let branch = unsafe { branch.as_ref() };
            for target in branch.targets.iter() {
                // SAFETY: no mutation inside unsafe
                let current_iseq = unsafe {
                    target.ref_unchecked().as_ref().and_then(|target| {
                        // Avoid get_blockid() on blockref. Can be dangling on dead blocks,
                        // and the iseq housing the block already naturally handles it.
                        if target.get_block().is_some() {
                            None
                        } else {
                            Some(target.get_blockid().iseq)
                        }
                    })
                };

                if let Some(current_iseq) = current_iseq {
                    let updated_iseq = unsafe { rb_gc_location(current_iseq.into()) }
                        .as_iseq();
                    // SAFETY: the Cell::set is not on the reference given out
                    // by ref_unchecked.
                    unsafe { target.ref_unchecked().as_ref().unwrap().set_iseq(updated_iseq) };
                }
            }
        }

        // Update references to objects in generated code.
        // Skip for dead blocks since they shouldn't run and
        // so there is no potential of writing over invalidation jumps
        if !dead {
            for offset in block.gc_obj_offsets.iter() {
                let offset_to_value = offset.as_usize();
                let value_code_ptr = cb.get_ptr(offset_to_value);
                let value_ptr: *const u8 = value_code_ptr.raw_ptr(cb);
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
/// `inlined: true` counts inlined versions, and `inlined: false` counts other versions.
fn get_num_versions(blockid: BlockId, inlined: bool) -> usize {
    let insn_idx = blockid.idx.as_usize();
    match get_iseq_payload(blockid.iseq) {
        Some(payload) => {
            payload
                .version_map
                .get(insn_idx)
                .map(|versions| {
                    versions.iter().filter(|&&version|
                        unsafe { version.as_ref() }.ctx.inline() == inlined
                    ).count()
                })
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
            blocks.push(*version);
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
    for blockref in versions.iter() {
        let block = unsafe { blockref.as_ref() };

        // Note that we always prefer the first matching
        // version found because of inline-cache chains
        match ctx.diff(&block.ctx) {
            TypeDiff::Compatible(diff) if diff < best_diff => {
                best_version = Some(*blockref);
                best_diff = diff;
            }
            _ => {}
        }
    }

    return best_version;
}

/// Allow inlining a Block up to MAX_INLINE_VERSIONS times.
const MAX_INLINE_VERSIONS: usize = 1000;

/// Produce a generic context when the block version limit is hit for a blockid
pub fn limit_block_versions(blockid: BlockId, ctx: &Context) -> Context {
    // Guard chains implement limits separately, do nothing
    if ctx.get_chain_depth() > 0 {
        return *ctx;
    }

    let next_versions = get_num_versions(blockid, ctx.inline()) + 1;
    let max_versions = if ctx.inline() {
        MAX_INLINE_VERSIONS
    } else {
        get_option!(max_versions)
    };

    // If this block version we're about to add will hit the version limit
    if next_versions >= max_versions {
        // Produce a generic context that stores no type information,
        // but still respects the stack_size and sp_offset constraints.
        // This new context will then match all future requests.
        let generic_ctx = ctx.get_generic_ctx();

        if cfg!(debug_assertions) {
            let mut ctx = ctx.clone();
            if ctx.inline() {
                // Suppress TypeDiff::Incompatible from ctx.diff(). We return TypeDiff::Incompatible
                // to keep inlining blocks until we hit the limit, but it's safe to give up inlining.
                ctx.inline_block = 0;
                assert!(generic_ctx.inline_block == 0);
            }

            assert_ne!(
                TypeDiff::Incompatible,
                ctx.diff(&generic_ctx),
                "should substitute a compatible context",
            );
        }

        return generic_ctx;
    }
    incr_counter_to!(max_inline_versions, next_versions);

    return *ctx;
}

/// Install a block version into its [IseqPayload], letting the GC track its
/// lifetime, and allowing it to be considered for use for other
/// blocks we might generate. Uses `cb` for running write barriers.
///
/// # Safety
///
/// The block must be fully initialized. Its incoming and outgoing edges,
/// if there are any, must point to initialized blocks, too.
///
/// Note that the block might gain edges after this function returns,
/// as can happen during [gen_block_series]. Initialized here doesn't mean
/// ready to be consumed or that the machine code tracked by the block is
/// ready to be run.
///
/// Due to this transient state where a block is tracked by the GC by
/// being inside an [IseqPayload] but not ready to be executed, it's
/// generally unsound to call any Ruby methods during codegen. That has
/// the potential to run blocks which are not ready.
unsafe fn add_block_version(blockref: BlockRef, cb: &CodeBlock) {
    // SAFETY: caller ensures initialization
    let block = unsafe { blockref.as_ref() };

    // Function entry blocks must have stack size 0
    assert!(!(block.iseq_range.start == 0 && block.ctx.stack_size > 0));

    let version_list = get_or_create_version_list(block.get_blockid());

    // If this the first block being compiled with this block id
    if version_list.len() == 0 {
        incr_counter!(compiled_blockid_count);
    }

    version_list.push(blockref);
    version_list.shrink_to_fit();

    // By writing the new block to the iseq, the iseq now
    // contains new references to Ruby objects. Run write barriers.
    let iseq: VALUE = block.iseq.get().into();
    for dep in block.iter_cme_deps() {
        obj_written!(iseq, dep.into());
    }

    // Run write barriers for all objects in generated code.
    for offset in block.gc_obj_offsets.iter() {
        let value_address: *const u8 = cb.get_ptr(offset.as_usize()).raw_ptr(cb);
        // Creating an unaligned pointer is well defined unlike in C.
        let value_address: *const VALUE = value_address.cast();

        let object = unsafe { value_address.read_unaligned() };
        obj_written!(iseq, object);
    }

    incr_counter!(compiled_block_count);

    // Mark code pages for code GC
    let iseq_payload = get_iseq_payload(block.iseq.get()).unwrap();
    for page in cb.addrs_to_pages(block.start_addr, block.end_addr.get()) {
        iseq_payload.pages.insert(page);
    }
}

/// Remove a block version from the version map of its parent ISEQ
fn remove_block_version(blockref: &BlockRef) {
    let block = unsafe { blockref.as_ref() };
    let version_list = match get_version_list(block.get_blockid()) {
        Some(version_list) => version_list,
        None => return,
    };

    // Retain the versions that are not this one
    version_list.retain(|other| blockref != other);
}

impl JITState {
    // Finish compiling and turn a jit state into a block
    // note that the block is still not in shape.
    pub fn into_block(self, end_insn_idx: IseqIdx, start_addr: CodePtr, end_addr: CodePtr, gc_obj_offsets: Vec<u32>) -> BlockRef {
        // Allocate the block and get its pointer
        let blockref: *mut MaybeUninit<Block> = Box::into_raw(Box::new(MaybeUninit::uninit()));

        incr_counter_by!(num_gc_obj_refs, gc_obj_offsets.len());

        // Make the new block
        let block = MaybeUninit::new(Block {
            start_addr,
            iseq: Cell::new(self.get_iseq()),
            iseq_range: self.get_starting_insn_idx()..end_insn_idx,
            ctx: self.get_starting_ctx(),
            end_addr: Cell::new(end_addr),
            incoming: MutableBranchList(Cell::default()),
            gc_obj_offsets: gc_obj_offsets.into_boxed_slice(),
            entry_exit: self.get_block_entry_exit(),
            cme_dependencies: self.method_lookup_assumptions.into_iter().map(Cell::new).collect(),
            // Pending branches => actual branches
            outgoing: self.pending_outgoing.into_iter().map(|pending_out| {
                let pending_out = Rc::try_unwrap(pending_out)
                    .ok().expect("all PendingBranchRefs should be unique when ready to construct a Block");
                pending_out.into_branch(NonNull::new(blockref as *mut Block).expect("no null from Box"))
            }).collect()
        });
        // Initialize it on the heap
        // SAFETY: allocated with Box above
        unsafe { ptr::write(blockref, block) };

        // Block is initialized now. Note that MaybeUnint<T> has the same layout as T.
        let blockref = NonNull::new(blockref as *mut Block).expect("no null from Box");

        // Track all the assumptions the block makes as invariants
        if self.block_assumes_single_ractor {
            track_single_ractor_assumption(blockref);
        }
        for bop in self.bop_assumptions {
            track_bop_assumption(blockref, bop);
        }
        // SAFETY: just allocated it above
        for cme in unsafe { blockref.as_ref() }.cme_dependencies.iter() {
            track_method_lookup_stability_assumption(blockref, cme.get());
        }
        if let Some(idlist) = self.stable_constant_names_assumption {
            track_stable_constant_names_assumption(blockref, idlist);
        }
        for klass in self.no_singleton_class_assumptions {
            track_no_singleton_class_assumption(blockref, klass);
        }
        if self.no_ep_escape {
            track_no_ep_escape_assumption(blockref, self.iseq);
        }

        blockref
    }
}

impl Block {
    pub fn get_blockid(&self) -> BlockId {
        BlockId { iseq: self.iseq.get(), idx: self.iseq_range.start }
    }

    pub fn get_end_idx(&self) -> IseqIdx {
        self.iseq_range.end
    }

    pub fn get_ctx_count(&self) -> usize {
        let mut count = 1; // block.ctx
        for branch in self.outgoing.iter() {
            // SAFETY: &self implies it's initialized
            count += unsafe { branch.as_ref() }.get_stub_count();
        }
        count
    }

    #[allow(unused)]
    pub fn get_start_addr(&self) -> CodePtr {
        self.start_addr
    }

    #[allow(unused)]
    pub fn get_end_addr(&self) -> CodePtr {
        self.end_addr.get()
    }

    /// Get an immutable iterator over cme dependencies
    pub fn iter_cme_deps(&self) -> impl Iterator<Item = CmePtr> + '_ {
        self.cme_dependencies.iter().map(Cell::get)
    }

    // Push an incoming branch ref and shrink the vector
    fn push_incoming(&self, branch: BranchRef) {
        self.incoming.push(branch);
    }

    // Compute the size of the block code
    pub fn code_size(&self) -> usize {
        (self.end_addr.get().as_offset() - self.start_addr.as_offset()).try_into().unwrap()
    }
}

impl Context {
    pub fn get_stack_size(&self) -> u8 {
        self.stack_size
    }

    pub fn set_stack_size(&mut self, stack_size: u8) {
        self.stack_size = stack_size;
    }

    /// Create a new Context that is compatible with self but doesn't have type information.
    pub fn get_generic_ctx(&self) -> Context {
        let mut generic_ctx = Context::default();
        generic_ctx.stack_size = self.stack_size;
        generic_ctx.sp_offset = self.sp_offset;
        generic_ctx.reg_temps = self.reg_temps;
        if self.is_return_landing() {
            generic_ctx.set_as_return_landing();
        }
        if self.is_deferred() {
            generic_ctx.mark_as_deferred();
        }
        generic_ctx
    }

    /// Create a new Context instance with a given stack_size and sp_offset adjusted
    /// accordingly. This is useful when you want to virtually rewind a stack_size for
    /// generating a side exit while considering past sp_offset changes on gen_save_sp.
    pub fn with_stack_size(&self, stack_size: u8) -> Context {
        let mut ctx = *self;
        ctx.sp_offset -= (ctx.get_stack_size() as isize - stack_size as isize) as i8;
        ctx.stack_size = stack_size;
        ctx
    }

    pub fn get_sp_offset(&self) -> i8 {
        self.sp_offset
    }

    pub fn set_sp_offset(&mut self, offset: i8) {
        self.sp_offset = offset;
    }

    pub fn get_reg_temps(&self) -> RegTemps {
        self.reg_temps
    }

    pub fn set_reg_temps(&mut self, reg_temps: RegTemps) {
        self.reg_temps = reg_temps;
    }

    pub fn get_chain_depth(&self) -> u8 {
        self.chain_depth_and_flags & CHAIN_DEPTH_MASK
    }

    pub fn reset_chain_depth_and_defer(&mut self) {
        self.chain_depth_and_flags &= !CHAIN_DEPTH_MASK;
        self.chain_depth_and_flags &= !DEFER_BIT;
    }

    pub fn increment_chain_depth(&mut self) {
        if self.get_chain_depth() == CHAIN_DEPTH_MASK {
            panic!("max block version chain depth reached!");
        }
        self.chain_depth_and_flags += 1;
    }

    pub fn set_as_return_landing(&mut self) {
        self.chain_depth_and_flags |= RETURN_LANDING_BIT;
    }

    pub fn clear_return_landing(&mut self) {
        self.chain_depth_and_flags &= !RETURN_LANDING_BIT;
    }

    pub fn is_return_landing(&self) -> bool {
        self.chain_depth_and_flags & RETURN_LANDING_BIT != 0
    }

    pub fn mark_as_deferred(&mut self) {
        self.chain_depth_and_flags |= DEFER_BIT;
    }

    pub fn is_deferred(&self) -> bool {
        self.chain_depth_and_flags & DEFER_BIT != 0
    }

    /// Get an operand for the adjusted stack pointer address
    pub fn sp_opnd(&self, offset: i32) -> Opnd {
        let offset = (self.sp_offset as i32 + offset) * SIZEOF_VALUE_I32;
        return Opnd::mem(64, SP, offset);
    }

    /// Get an operand for the adjusted environment pointer address using SP register.
    /// This is valid only when a Binding object hasn't been created for the frame.
    pub fn ep_opnd(&self, offset: i32) -> Opnd {
        let ep_offset = self.get_stack_size() as i32 + 1;
        self.sp_opnd(-ep_offset + offset)
    }

    /// Stop using a register for a given stack temp.
    /// This allows us to reuse the register for a value that we know is dead
    /// and will no longer be used (e.g. popped stack temp).
    pub fn dealloc_temp_reg(&mut self, stack_idx: u8) {
        if stack_idx < MAX_REG_TEMPS {
            let mut reg_temps = self.get_reg_temps();
            reg_temps.set(stack_idx, false);
            self.set_reg_temps(reg_temps);
        }
    }

    /// Get the type of an instruction operand
    pub fn get_opnd_type(&self, opnd: YARVOpnd) -> Type {
        match opnd {
            SelfOpnd => self.self_type,
            StackOpnd(idx) => {
                assert!(idx < self.stack_size);
                let stack_idx: usize = (self.stack_size - 1 - idx).into();

                // If outside of tracked range, do nothing
                if stack_idx >= MAX_TEMP_TYPES {
                    return Type::Unknown;
                }

                let mapping = self.get_temp_mapping(stack_idx);

                match mapping.get_kind() {
                    MapToSelf => self.self_type,
                    MapToStack => mapping.get_type(),
                    MapToLocal => {
                        let idx = mapping.get_local_idx();
                        assert!((idx as usize) < MAX_LOCAL_TYPES);
                        return self.get_local_type(idx.into());
                    }
                }
            }
        }
    }

    /// Get the currently tracked type for a local variable
    pub fn get_local_type(&self, local_idx: usize) -> Type {
        if local_idx >= MAX_LOCAL_TYPES {
            return Type::Unknown
        } else {
            // Each type is stored in 4 bits
            let type_bits = (self.local_types >> (4 * local_idx)) & 0b1111;
            unsafe { transmute::<u8, Type>(type_bits as u8) }
        }
    }

    /// Get the current temp mapping for a given stack slot
    fn get_temp_mapping(&self, temp_idx: usize) -> TempMapping {
        assert!(temp_idx < MAX_TEMP_TYPES);

        // Extract the temp mapping kind
        let kind_bits = (self.temp_mapping_kind >> (2 * temp_idx)) & 0b11;
        let temp_kind = unsafe { transmute::<u8, TempMappingKind>(kind_bits as u8) };

        // Extract the payload bits (temp type or local idx)
        let payload_bits = (self.temp_payload >> (4 * temp_idx)) & 0b1111;

        match temp_kind {
            MapToSelf => TempMapping::map_to_self(),

            MapToStack => {
                TempMapping::map_to_stack(
                    unsafe { transmute::<u8, Type>(payload_bits as u8) }
                )
            }

            MapToLocal => {
                TempMapping::map_to_local(
                    payload_bits as u8
                )
            }
        }
    }

    /// Get the current temp mapping for a given stack slot
    fn set_temp_mapping(&mut self, temp_idx: usize, mapping: TempMapping) {
        assert!(temp_idx < MAX_TEMP_TYPES);

        // Extract the kind bits
        let mapping_kind = mapping.get_kind();
        let kind_bits = unsafe { transmute::<TempMappingKind, u8>(mapping_kind) };
        assert!(kind_bits <= 0b11);

        // Extract the payload bits
        let payload_bits = match mapping_kind {
            MapToSelf => 0,

            MapToStack => {
                let t = mapping.get_type();
                unsafe { transmute::<Type, u8>(t) }
            }

            MapToLocal => {
                mapping.get_local_idx()
            }
        };
        assert!(payload_bits <= 0b1111);

        // Update the kind bits
        {
            let mask_bits = 0b11_u16 << (2 * temp_idx);
            let shifted_bits = (kind_bits as u16) << (2 * temp_idx);
            let all_kind_bits = self.temp_mapping_kind as u16;
            self.temp_mapping_kind = (all_kind_bits & !mask_bits) | shifted_bits;
        }

        // Update the payload bits
        {
            let mask_bits = 0b1111_u32 << (4 * temp_idx);
            let shifted_bits = (payload_bits as u32) << (4 * temp_idx);
            let all_payload_bits = self.temp_payload as u32;
            self.temp_payload = (all_payload_bits & !mask_bits) | shifted_bits;
        }
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
                assert!(idx < self.stack_size);
                let stack_idx = (self.stack_size - 1 - idx) as usize;

                // If outside of tracked range, do nothing
                if stack_idx >= MAX_TEMP_TYPES {
                    return;
                }

                let mapping = self.get_temp_mapping(stack_idx);

                match mapping.get_kind() {
                    MapToSelf => self.self_type.upgrade(opnd_type),
                    MapToStack => {
                        let mut temp_type = mapping.get_type();
                        temp_type.upgrade(opnd_type);
                        self.set_temp_mapping(stack_idx, TempMapping::map_to_stack(temp_type));
                    }
                    MapToLocal => {
                        let idx = mapping.get_local_idx() as usize;
                        assert!(idx < MAX_LOCAL_TYPES);
                        let mut new_type = self.get_local_type(idx);
                        new_type.upgrade(opnd_type);
                        self.set_local_type(idx, new_type);
                        // Re-attach MapToLocal for this StackOpnd(idx). set_local_type() detaches
                        // all MapToLocal mappings, including the one we're upgrading here.
                        self.set_opnd_mapping(opnd, mapping);
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
    pub fn get_opnd_mapping(&self, opnd: YARVOpnd) -> TempMapping {
        let opnd_type = self.get_opnd_type(opnd);

        match opnd {
            SelfOpnd => TempMapping::map_to_self(),
            StackOpnd(idx) => {
                assert!(idx < self.stack_size);
                let stack_idx = (self.stack_size - 1 - idx) as usize;

                if stack_idx < MAX_TEMP_TYPES {
                    self.get_temp_mapping(stack_idx)
                } else {
                    // We can't know the source of this stack operand, so we assume it is
                    // a stack-only temporary. type will be UNKNOWN
                    assert!(opnd_type == Type::Unknown);
                    TempMapping::map_to_stack(opnd_type)
                }
            }
        }
    }

    /// Overwrite both the type and mapping of a stack operand.
    pub fn set_opnd_mapping(&mut self, opnd: YARVOpnd, mapping: TempMapping) {
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

                self.set_temp_mapping(stack_idx, mapping);
            }
        }
    }

    /// Set the type of a local variable
    pub fn set_local_type(&mut self, local_idx: usize, local_type: Type) {
        // If type propagation is disabled, store no types
        if get_option!(no_type_prop) {
            return;
        }

        if local_idx >= MAX_LOCAL_TYPES {
            return
        }

        // If any values on the stack map to this local we must detach them
        for mapping_idx in 0..MAX_TEMP_TYPES {
            let mapping = self.get_temp_mapping(mapping_idx);
            let tm = match mapping.get_kind() {
                MapToStack => mapping,
                MapToSelf => mapping,
                MapToLocal => {
                    let idx = mapping.get_local_idx();
                    if idx as usize == local_idx {
                        let local_type = self.get_local_type(local_idx);
                        TempMapping::map_to_stack(local_type)
                    } else {
                        TempMapping::map_to_local(idx)
                    }
                }
            };
            self.set_temp_mapping(mapping_idx, tm);
        }

        // Update the type bits
        let type_bits = local_type as u32;
        assert!(type_bits <= 0b1111);
        let mask_bits = 0b1111_u32 << (4 * local_idx);
        let shifted_bits = type_bits << (4 * local_idx);
        self.local_types = (self.local_types & !mask_bits) | shifted_bits;
    }

    /// Erase local variable type information
    /// eg: because of a call we can't track
    pub fn clear_local_types(&mut self) {
        // When clearing local types we must detach any stack mappings to those
        // locals. Even if local values may have changed, stack values will not.

        for mapping_idx in 0..MAX_TEMP_TYPES {
            let mapping = self.get_temp_mapping(mapping_idx);
            if mapping.get_kind() == MapToLocal {
                let local_idx = mapping.get_local_idx() as usize;
                self.set_temp_mapping(mapping_idx, TempMapping::map_to_stack(self.get_local_type(local_idx)));
            }
        }

        // Clear the local types
        self.local_types = 0;
    }

    /// Return true if the code is inlined by the caller
    pub fn inline(&self) -> bool {
        self.inline_block != 0
    }

    /// Set a block ISEQ given to the Block of this Context
    pub fn set_inline_block(&mut self, iseq: IseqPtr) {
        self.inline_block = iseq as u64
    }

    /// Compute a difference score for two context objects
    pub fn diff(&self, dst: &Context) -> TypeDiff {
        // Self is the source context (at the end of the predecessor)
        let src = self;

        // Can only lookup the first version in the chain
        if dst.get_chain_depth() != 0 {
            return TypeDiff::Incompatible;
        }

        // Blocks with depth > 0 always produce new versions
        // Sidechains cannot overlap
        if src.get_chain_depth() != 0 {
            return TypeDiff::Incompatible;
        }

        if src.is_return_landing() != dst.is_return_landing() {
            return TypeDiff::Incompatible;
        }

        if src.is_deferred() != dst.is_deferred() {
            return TypeDiff::Incompatible;
        }

        if dst.stack_size != src.stack_size {
            return TypeDiff::Incompatible;
        }

        if dst.sp_offset != src.sp_offset {
            return TypeDiff::Incompatible;
        }

        if dst.reg_temps != src.reg_temps {
            return TypeDiff::Incompatible;
        }

        // Difference sum
        let mut diff = 0;

        // Check the type of self
        diff += match src.self_type.diff(dst.self_type) {
            TypeDiff::Compatible(diff) => diff,
            TypeDiff::Incompatible => return TypeDiff::Incompatible,
        };

        // Check the block to inline
        if src.inline_block != dst.inline_block {
            // find_block_version should not find existing blocks with different
            // inline_block so that their yield will not be megamorphic.
            return TypeDiff::Incompatible;
        }

        // For each local type we track
        for i in 0.. MAX_LOCAL_TYPES {
            let t_src = src.get_local_type(i);
            let t_dst = dst.get_local_type(i);
            diff += match t_src.diff(t_dst) {
                TypeDiff::Compatible(diff) => diff,
                TypeDiff::Incompatible => return TypeDiff::Incompatible,
            };
        }

        // For each value on the temp stack
        for i in 0..src.stack_size {
            let src_mapping = src.get_opnd_mapping(StackOpnd(i));
            let dst_mapping = dst.get_opnd_mapping(StackOpnd(i));

            // If the two mappings aren't the same
            if src_mapping != dst_mapping {
                if dst_mapping.get_kind() == MapToStack {
                    // We can safely drop information about the source of the temp
                    // stack operand.
                    diff += 1;
                } else {
                    return TypeDiff::Incompatible;
                }
            }

            let src_type = src.get_opnd_type(StackOpnd(i));
            let dst_type = dst.get_opnd_type(StackOpnd(i));

            diff += match src_type.diff(dst_type) {
                TypeDiff::Compatible(diff) => diff,
                TypeDiff::Incompatible => return TypeDiff::Incompatible,
            };
        }

        return TypeDiff::Compatible(diff);
    }

    pub fn two_fixnums_on_stack(&self, jit: &mut JITState) -> Option<bool> {
        if jit.at_current_insn() {
            let comptime_recv = jit.peek_at_stack(self, 1);
            let comptime_arg = jit.peek_at_stack(self, 0);
            return Some(comptime_recv.fixnum_p() && comptime_arg.fixnum_p());
        }

        let recv_type = self.get_opnd_type(StackOpnd(1));
        let arg_type = self.get_opnd_type(StackOpnd(0));
        match (recv_type, arg_type) {
            (Type::Fixnum, Type::Fixnum) => Some(true),
            (Type::Unknown | Type::UnknownImm, Type::Unknown | Type::UnknownImm) => None,
            _ => Some(false),
        }
    }
}

impl Assembler {
    /// Push one new value on the temp stack with an explicit mapping
    /// Return a pointer to the new stack top
    pub fn stack_push_mapping(&mut self, mapping: TempMapping) -> Opnd {
        // If type propagation is disabled, store no types
        if get_option!(no_type_prop) {
            return self.stack_push_mapping(mapping.without_type());
        }

        let stack_size: usize = self.ctx.stack_size.into();

        // Keep track of the type and mapping of the value
        if stack_size < MAX_TEMP_TYPES {
            self.ctx.set_temp_mapping(stack_size, mapping);

            if mapping.get_kind() == MapToLocal {
                let idx = mapping.get_local_idx();
                assert!((idx as usize) < MAX_LOCAL_TYPES);
            }
        }

        // Allocate a register to the stack operand
        if self.ctx.stack_size < MAX_REG_TEMPS {
            self.alloc_temp_reg(self.ctx.stack_size);
        }

        self.ctx.stack_size += 1;
        self.ctx.sp_offset += 1;

        return self.stack_opnd(0);
    }

    /// Push one new value on the temp stack
    /// Return a pointer to the new stack top
    pub fn stack_push(&mut self, val_type: Type) -> Opnd {
        return self.stack_push_mapping(TempMapping::map_to_stack(val_type));
    }

    /// Push the self value on the stack
    pub fn stack_push_self(&mut self) -> Opnd {
        return self.stack_push_mapping(TempMapping::map_to_self());
    }

    /// Push a local variable on the stack
    pub fn stack_push_local(&mut self, local_idx: usize) -> Opnd {
        if local_idx >= MAX_LOCAL_TYPES {
            return self.stack_push(Type::Unknown);
        }

        return self.stack_push_mapping(TempMapping::map_to_local(local_idx as u8));
    }

    // Pop N values off the stack
    // Return a pointer to the stack top before the pop operation
    pub fn stack_pop(&mut self, n: usize) -> Opnd {
        assert!(n <= self.ctx.stack_size.into());

        let top = self.stack_opnd(0);

        // Clear the types of the popped values
        for i in 0..n {
            let idx: usize = (self.ctx.stack_size as usize) - i - 1;

            if idx < MAX_TEMP_TYPES {
                self.ctx.set_temp_mapping(idx, TempMapping::map_to_stack(Type::Unknown));
            }
        }

        self.ctx.stack_size -= n as u8;
        self.ctx.sp_offset -= n as i8;

        return top;
    }

    /// Shift stack temps to remove a Symbol for #send.
    pub fn shift_stack(&mut self, argc: usize) {
        assert!(argc < self.ctx.stack_size.into());

        let method_name_index = (self.ctx.stack_size as usize) - argc - 1;

        for i in method_name_index..(self.ctx.stack_size - 1) as usize {
            if i < MAX_TEMP_TYPES {
                let next_arg_mapping = if i + 1 < MAX_TEMP_TYPES {
                    self.ctx.get_temp_mapping(i + 1)
                } else {
                    TempMapping::map_to_stack(Type::Unknown)
                };
                self.ctx.set_temp_mapping(i, next_arg_mapping);
            }
        }
        self.stack_pop(1);
    }

    /// Get an operand pointing to a slot on the temp stack
    pub fn stack_opnd(&self, idx: i32) -> Opnd {
        Opnd::Stack {
            idx,
            num_bits: 64,
            stack_size: self.ctx.stack_size,
            sp_offset: self.ctx.sp_offset,
            reg_temps: None, // push_insn will set this
        }
    }
}

impl BlockId {
    /// Print Ruby source location for debugging
    #[cfg(debug_assertions)]
    #[allow(dead_code)]
    pub fn dump_src_loc(&self) {
        unsafe { rb_yjit_dump_iseq_loc(self.iseq, self.idx as u32) }
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
    batch.push(first_block); // Keep track of this block version

    // Add the block version to the VersionMap for this ISEQ
    unsafe { add_block_version(first_block, cb) };

    // Loop variable
    let mut last_blockref = first_block;
    loop {
        // Get the last outgoing branch from the previous block.
        let last_branchref = {
            let last_block = unsafe { last_blockref.as_ref() };
            match last_block.outgoing.last() {
                Some(branch) => *branch,
                None => {
                    break;
                } // If last block has no branches, stop.
            }
        };
        let last_branch = unsafe { last_branchref.as_ref() };

        incr_counter!(block_next_count);

        // gen_direct_jump() can request a block to be placed immediately after by
        // leaving a single target that has a `None` address.
        // SAFETY: no mutation inside the unsafe block
        let (requested_blockid, requested_ctx) = unsafe {
            match (last_branch.targets[0].ref_unchecked(), last_branch.targets[1].ref_unchecked()) {
                (Some(last_target), None) if last_target.get_address().is_none() => {
                    (last_target.get_blockid(), last_target.get_ctx())
                }
                _ => {
                    // We're done when no fallthrough block is requested
                    break;
                }
            }
        };

        // Generate new block using context from the last branch.
        let result = gen_single_block(requested_blockid, &requested_ctx, ec, cb, ocb);

        // If the block failed to compile
        if result.is_err() {
            // Remove previously compiled block
            // versions from the version map
            for blockref in batch {
                remove_block_version(&blockref);
                // SAFETY: block was well connected because it was in a version_map
                unsafe { free_block(blockref, false) };
            }

            // Stop compiling
            return None;
        }

        let new_blockref = result.unwrap();

        // Add the block version to the VersionMap for this ISEQ
        unsafe { add_block_version(new_blockref, cb) };

        // Connect the last branch and the new block
        last_branch.targets[0].set(Some(Box::new(BranchTarget::Block(new_blockref))));
        unsafe { new_blockref.as_ref().incoming.push(last_branchref) };

        // Track the block
        batch.push(new_blockref);

        // Repeat with newest block
        last_blockref = new_blockref;
    }

    #[cfg(feature = "disasm")]
    {
        // If dump_iseq_disasm is active, see if this iseq's location matches the given substring.
        // If so, we print the new blocks to the console.
        if let Some(substr) = get_option_ref!(dump_iseq_disasm).as_ref() {
            let iseq_location = iseq_get_location(blockid.iseq, blockid.idx);
            if iseq_location.contains(substr) {
                let last_block = unsafe { last_blockref.as_ref() };
                let iseq_range = &last_block.iseq_range;
                println!("Compiling {} block(s) for {}, ISEQ offsets [{}, {})", batch.len(), iseq_location, iseq_range.start, iseq_range.end);
                print!("{}", disasm_iseq_insn_range(blockid.iseq, iseq_range.start, iseq_range.end));
            }
        }
    }

    Some(first_block)
}

/// Generate a block version that is an entry point inserted into an iseq
/// NOTE: this function assumes that the VM lock has been taken
/// If jit_exception is true, compile JIT code for handling exceptions.
/// See [jit_compile_exception] for details.
pub fn gen_entry_point(iseq: IseqPtr, ec: EcPtr, jit_exception: bool) -> Option<*const u8> {
    // Compute the current instruction index based on the current PC
    let cfp = unsafe { get_ec_cfp(ec) };
    let insn_idx: u16 = unsafe {
        let ec_pc = get_cfp_pc(cfp);
        iseq_pc_to_insn_idx(iseq, ec_pc)?
    };
    let stack_size: u8 = unsafe {
        u8::try_from(get_cfp_sp(cfp).offset_from(get_cfp_bp(cfp))).ok()?
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
    let code_ptr = gen_entry_prologue(cb, ocb, iseq, insn_idx, jit_exception);

    // Try to generate code for the entry block
    let mut ctx = Context::default();
    ctx.stack_size = stack_size;
    let block = gen_block_series(blockid, &ctx, ec, cb, ocb);

    cb.mark_all_executable();
    ocb.unwrap().mark_all_executable();

    match block {
        // Compilation failed
        None => {
            // Trigger code GC. This entry point will be recompiled later.
            if get_option!(code_gc) {
                cb.code_gc(ocb);
            }
            return None;
        }

        // If the block contains no Ruby instructions
        Some(block) => {
            let block = unsafe { block.as_ref() };
            if block.iseq_range.is_empty() {
                return None;
            }
        }
    }

    // Count the number of entry points we compile
    incr_counter!(compiled_iseq_entry);

    // Compilation successful and block not empty
    code_ptr.map(|ptr| ptr.raw_ptr(cb))
}

// Change the entry's jump target from an entry stub to a next entry
pub fn regenerate_entry(cb: &mut CodeBlock, entryref: &EntryRef, next_entry: CodePtr) {
    let mut asm = Assembler::new();
    asm_comment!(asm, "regenerate_entry");

    // gen_entry_guard generates cmp + jne. We're rewriting only jne.
    asm.jne(next_entry.into());

    // Move write_pos to rewrite the entry
    let old_write_pos = cb.get_write_pos();
    let old_dropped_bytes = cb.has_dropped_bytes();
    cb.set_write_ptr(unsafe { entryref.as_ref() }.start_addr);
    cb.set_dropped_bytes(false);
    asm.compile(cb, None).expect("can rewrite existing code");

    // Rewind write_pos to the original one
    assert_eq!(cb.get_write_ptr(), unsafe { entryref.as_ref() }.end_addr);
    cb.set_pos(old_write_pos);
    cb.set_dropped_bytes(old_dropped_bytes);
}

pub type PendingEntryRef = Rc<PendingEntry>;

/// Create a new entry reference for an ISEQ
pub fn new_pending_entry() -> PendingEntryRef {
    let entry = PendingEntry {
        uninit_entry: Box::new(MaybeUninit::uninit()),
        start_addr: Cell::new(None),
        end_addr: Cell::new(None),
    };
    return Rc::new(entry);
}

c_callable! {
    /// Generated code calls this function with the SysV calling convention.
    /// See [gen_call_entry_stub_hit].
    fn entry_stub_hit(entry_ptr: *const c_void, ec: EcPtr) -> *const u8 {
        with_compile_time(|| {
            with_vm_lock(src_loc!(), || {
                let cb = CodegenGlobals::get_inline_cb();
                let ocb = CodegenGlobals::get_outlined_cb();

                let addr = entry_stub_hit_body(entry_ptr, ec, cb, ocb)
                    .unwrap_or_else(|| {
                        // Trigger code GC (e.g. no space).
                        // This entry point will be recompiled later.
                        if get_option!(code_gc) {
                            cb.code_gc(ocb);
                        }
                        CodegenGlobals::get_stub_exit_code().raw_ptr(cb)
                    });

                cb.mark_all_executable();
                ocb.unwrap().mark_all_executable();

                addr
            })
        })
    }
}

/// Called by the generated code when an entry stub is executed
fn entry_stub_hit_body(
    entry_ptr: *const c_void,
    ec: EcPtr,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb
) -> Option<*const u8> {
    // Get ISEQ and insn_idx from the current ec->cfp
    let cfp = unsafe { get_ec_cfp(ec) };
    let iseq = unsafe { get_cfp_iseq(cfp) };
    let insn_idx = iseq_pc_to_insn_idx(iseq, unsafe { get_cfp_pc(cfp) })?;
    let stack_size: u8 = unsafe {
        u8::try_from(get_cfp_sp(cfp).offset_from(get_cfp_bp(cfp))).ok()?
    };

    // Compile a new entry guard as a next entry
    let next_entry = cb.get_write_ptr();
    let mut asm = Assembler::new();
    let pending_entry = gen_entry_chain_guard(&mut asm, ocb, iseq, insn_idx)?;
    asm.compile(cb, Some(ocb))?;

    // Find or compile a block version
    let blockid = BlockId { iseq, idx: insn_idx };
    let mut ctx = Context::default();
    ctx.stack_size = stack_size;
    let blockref = match find_block_version(blockid, &ctx) {
        // If an existing block is found, generate a jump to the block.
        Some(blockref) => {
            let mut asm = Assembler::new();
            asm.jmp(unsafe { blockref.as_ref() }.start_addr.into());
            asm.compile(cb, Some(ocb))?;
            Some(blockref)
        }
        // If this block hasn't yet been compiled, generate blocks after the entry guard.
        None => gen_block_series(blockid, &ctx, ec, cb, ocb),
    };

    // Commit or retry the entry
    if blockref.is_some() {
        // Regenerate the previous entry
        let entryref = NonNull::<Entry>::new(entry_ptr as *mut Entry).expect("Entry should not be null");
        regenerate_entry(cb, &entryref, next_entry);

        // Write an entry to the heap and push it to the ISEQ
        let pending_entry = Rc::try_unwrap(pending_entry).ok().expect("PendingEntry should be unique");
        get_or_create_iseq_payload(iseq).entries.push(pending_entry.into_entry());
    }

    // Let the stub jump to the block
    blockref.map(|block| unsafe { block.as_ref() }.start_addr.raw_ptr(cb))
}

/// Generate a stub that calls entry_stub_hit
pub fn gen_entry_stub(entry_address: usize, ocb: &mut OutlinedCb) -> Option<CodePtr> {
    let ocb = ocb.unwrap();

    let mut asm = Assembler::new();
    asm_comment!(asm, "entry stub hit");

    asm.mov(C_ARG_OPNDS[0], entry_address.into());

    // Jump to trampoline to call entry_stub_hit()
    // Not really a side exit, just don't need a padded jump here.
    asm.jmp(CodegenGlobals::get_entry_stub_hit_trampoline().as_side_exit());

    asm.compile(ocb, None).map(|(code_ptr, _)| code_ptr)
}

/// A trampoline used by gen_entry_stub. entry_stub_hit may issue Code GC, so
/// it's useful for Code GC to call entry_stub_hit from a globally shared code.
pub fn gen_entry_stub_hit_trampoline(ocb: &mut OutlinedCb) -> Option<CodePtr> {
    let ocb = ocb.unwrap();
    let mut asm = Assembler::new();

    // See gen_entry_guard for how it's used.
    asm_comment!(asm, "entry_stub_hit() trampoline");
    let jump_addr = asm.ccall(entry_stub_hit as *mut u8, vec![C_ARG_OPNDS[0], EC]);

    // Jump to the address returned by the entry_stub_hit() call
    asm.jmp_opnd(jump_addr);

    asm.compile(ocb, None).map(|(code_ptr, _)| code_ptr)
}

/// Generate code for a branch, possibly rewriting and changing the size of it
fn regenerate_branch(cb: &mut CodeBlock, branch: &Branch) {
    // Remove old comments
    cb.remove_comments(branch.start_addr, branch.end_addr.get());

    // SAFETY: having a &Branch implies branch.block is initialized.
    let block = unsafe { branch.block.as_ref() };

    let branch_terminates_block = branch.end_addr.get() == block.get_end_addr();

    // Generate the branch
    let mut asm = Assembler::new();
    asm_comment!(asm, "regenerate_branch");
    branch.gen_fn.call(
        &mut asm,
        Target::CodePtr(branch.get_target_address(0).unwrap()),
        branch.get_target_address(1).map(|addr| Target::CodePtr(addr)),
    );

    // If the entire block is the branch and the block could be invalidated,
    // we need to pad to ensure there is room for invalidation patching.
    if branch.start_addr == block.start_addr && branch_terminates_block && block.entry_exit.is_some() {
        asm.pad_inval_patch();
    }

    // Rewrite the branch
    let old_write_pos = cb.get_write_pos();
    let old_dropped_bytes = cb.has_dropped_bytes();
    cb.set_write_ptr(branch.start_addr);
    cb.set_dropped_bytes(false);
    asm.compile(cb, None).expect("can rewrite existing code");
    let new_end_addr = cb.get_write_ptr();

    branch.end_addr.set(new_end_addr);

    // The block may have shrunk after the branch is rewritten
    if branch_terminates_block {
        // Adjust block size
        block.end_addr.set(new_end_addr);
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

    branch.assert_layout();
}

pub type PendingBranchRef = Rc<PendingBranch>;

/// Create a new outgoing branch entry for a block
fn new_pending_branch(jit: &mut JITState, gen_fn: BranchGenFn) -> PendingBranchRef {
    let branch = Rc::new(PendingBranch {
        uninit_branch: Box::new(MaybeUninit::uninit()),
        gen_fn,
        start_addr: Cell::new(None),
        end_addr: Cell::new(None),
        targets: [Cell::new(None), Cell::new(None)],
    });

    incr_counter!(compiled_branch_count); // TODO not true. count at finalize time

    // Add to the list of outgoing branches for the block
    jit.queue_outgoing_branch(branch.clone());

    branch
}

c_callable! {
    /// Generated code calls this function with the SysV calling convention.
    /// See [gen_branch_stub].
    fn branch_stub_hit(
        branch_ptr: *const c_void,
        target_idx: u32,
        ec: EcPtr,
    ) -> *const u8 {
        with_vm_lock(src_loc!(), || {
            with_compile_time(|| { branch_stub_hit_body(branch_ptr, target_idx, ec) })
        })
    }
}

/// Called by the generated code when a branch stub is executed
/// Triggers compilation of branches and code patching
fn branch_stub_hit_body(branch_ptr: *const c_void, target_idx: u32, ec: EcPtr) -> *const u8 {
    if get_option!(dump_insns) {
        println!("branch_stub_hit");
    }

    let branch_ref = NonNull::<Branch>::new(branch_ptr as *mut Branch)
        .expect("Branches should not be null");

    // SAFETY: We have the VM lock, and the branch is initialized by the time generated
    // code calls this function.
    let branch = unsafe { branch_ref.as_ref() };
    let branch_size_on_entry = branch.code_size();
    let housing_block = unsafe { branch.block.as_ref() };

    let target_idx: usize = target_idx.as_usize();
    let target_branch_shape = match target_idx {
        0 => BranchShape::Next0,
        1 => BranchShape::Next1,
        _ => unreachable!("target_idx < 2 must always hold"),
    };

    let cb = CodegenGlobals::get_inline_cb();
    let ocb = CodegenGlobals::get_outlined_cb();

    let (target_blockid, target_ctx): (BlockId, Context) = unsafe {
        // SAFETY: no mutation of the target's Cell. Just reading out data.
        let target = branch.targets[target_idx].ref_unchecked().as_ref().unwrap();

        // If this branch has already been patched, return the dst address
        // Note: recursion can cause the same stub to be hit multiple times
        if let BranchTarget::Block(_) = target.as_ref() {
            return target.get_address().unwrap().raw_ptr(cb);
        }

        (target.get_blockid(), target.get_ctx())
    };

    let (cfp, original_interp_sp) = unsafe {
        let cfp = get_ec_cfp(ec);
        let original_interp_sp = get_cfp_sp(cfp);

        let running_iseq = get_cfp_iseq(cfp);
        assert_eq!(running_iseq, target_blockid.iseq as _, "each stub expects a particular iseq");

        let reconned_pc = rb_iseq_pc_at_idx(running_iseq, target_blockid.idx.into());
        let reconned_sp = original_interp_sp.offset(target_ctx.sp_offset.into());
        // Unlike in the interpreter, our `leave` doesn't write to the caller's
        // SP -- we do it in the returned-to code. Account for this difference.
        let reconned_sp = reconned_sp.add(target_ctx.is_return_landing().into());

        // Update the PC in the current CFP, because it may be out of sync in JITted code
        rb_set_cfp_pc(cfp, reconned_pc);

        // :stub-sp-flush:
        // Generated code do stack operations without modifying cfp->sp, while the
        // cfp->sp tells the GC what values on the stack to root. Generated code
        // generally takes care of updating cfp->sp when it calls runtime routines that
        // could trigger GC, but it's inconvenient to do it before calling this function.
        // So we do it here instead.
        rb_set_cfp_sp(cfp, reconned_sp);

        // Bail if code GC is disabled and we've already run out of spaces.
        if !get_option!(code_gc) && (cb.has_dropped_bytes() || ocb.unwrap().has_dropped_bytes()) {
            return CodegenGlobals::get_stub_exit_code().raw_ptr(cb);
        }

        // Bail if we're about to run out of native stack space.
        // We've just reconstructed interpreter state.
        if rb_ec_stack_check(ec as _) != 0 {
            return CodegenGlobals::get_stub_exit_code().raw_ptr(cb);
        }

        (cfp, original_interp_sp)
    };

    // Try to find an existing compiled version of this block
    let mut block = find_block_version(target_blockid, &target_ctx);
    let mut branch_modified = false;
    // If this block hasn't yet been compiled
    if block.is_none() {
        let branch_old_shape = branch.gen_fn.get_shape();

        // If the new block can be generated right after the branch (at cb->write_pos)
        if cb.get_write_ptr() == branch.end_addr.get() {
            // This branch should be terminating its block
            assert!(branch.end_addr == housing_block.end_addr);

            // Change the branch shape to indicate the target block will be placed next
            branch.gen_fn.set_shape(target_branch_shape);

            // Rewrite the branch with the new, potentially more compact shape
            regenerate_branch(cb, branch);
            branch_modified = true;

            // Ensure that the branch terminates the codeblock just like
            // before entering this if block. This drops bytes off the end
            // in case we shrank the branch when regenerating.
            cb.set_write_ptr(branch.end_addr.get());
        }

        // Compile the new block version
        block = gen_block_series(target_blockid, &target_ctx, ec, cb, ocb);

        if block.is_none() && branch_modified {
            // We couldn't generate a new block for the branch, but we modified the branch.
            // Restore the branch by regenerating it.
            branch.gen_fn.set_shape(branch_old_shape);
            regenerate_branch(cb, branch);
        }
    }

    // Finish building the new block
    let dst_addr = match block {
        Some(new_block) => {
            let new_block = unsafe { new_block.as_ref() };

            // Branch shape should reflect layout
            assert!(!(branch.gen_fn.get_shape() == target_branch_shape && new_block.start_addr != branch.end_addr.get()));

            // Add this branch to the list of incoming branches for the target
            new_block.push_incoming(branch_ref);

            // Update the branch target address
            branch.targets[target_idx].set(Some(Box::new(BranchTarget::Block(new_block.into()))));

            // Rewrite the branch with the new jump target address
            regenerate_branch(cb, branch);

            // Restore interpreter sp, since the code hitting the stub expects the original.
            unsafe { rb_set_cfp_sp(cfp, original_interp_sp) };

            new_block.start_addr
        }
        None => {
            // Trigger code GC. The whole ISEQ will be recompiled later.
            // We shouldn't trigger it in the middle of compilation in branch_stub_hit
            // because incomplete code could be used when cb.dropped_bytes is flipped
            // by code GC. So this place, after all compilation, is the safest place
            // to hook code GC on branch_stub_hit.
            if get_option!(code_gc) {
                cb.code_gc(ocb);
            }

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
        branch.start_addr.raw_ptr(cb), branch_size_on_entry, new_branch_size,
    );

    // Return a pointer to the compiled block version
    dst_addr.raw_ptr(cb)
}

/// Generate a "stub", a piece of code that calls the compiler back when run.
/// A piece of code that redeems for more code; a thunk for code.
fn gen_branch_stub(
    ctx: &Context,
    ocb: &mut OutlinedCb,
    branch_struct_address: usize,
    target_idx: u32,
) -> Option<CodePtr> {
    let ocb = ocb.unwrap();

    let mut asm = Assembler::new();
    asm.ctx = *ctx;
    asm.set_reg_temps(ctx.reg_temps);
    asm_comment!(asm, "branch stub hit");

    if asm.ctx.is_return_landing() {
        asm.mov(SP, Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP));
        let top = asm.stack_push(Type::Unknown);
        asm.mov(top, C_RET_OPND);
    }

    // Save caller-saved registers before C_ARG_OPNDS get clobbered.
    // Spill all registers for consistency with the trampoline.
    for &reg in caller_saved_temp_regs() {
        asm.cpush(Opnd::Reg(reg));
    }

    // Spill temps to the VM stack as well for jit.peek_at_stack()
    asm.spill_temps();

    // Set up the arguments unique to this stub for:
    //
    //    branch_stub_hit(branch_ptr, target_idx, ec)
    //
    // Bake pointer to Branch into output code.
    // We make sure the block housing the branch is still alive when branch_stub_hit() is running.
    asm.mov(C_ARG_OPNDS[0], branch_struct_address.into());
    asm.mov(C_ARG_OPNDS[1], target_idx.into());

    // Jump to trampoline to call branch_stub_hit()
    // Not really a side exit, just don't need a padded jump here.
    asm.jmp(CodegenGlobals::get_branch_stub_hit_trampoline().as_side_exit());

    asm.compile(ocb, None).map(|(code_ptr, _)| code_ptr)
}

pub fn gen_branch_stub_hit_trampoline(ocb: &mut OutlinedCb) -> Option<CodePtr> {
    let ocb = ocb.unwrap();
    let mut asm = Assembler::new();

    // For `branch_stub_hit(branch_ptr, target_idx, ec)`,
    // `branch_ptr` and `target_idx` is different for each stub,
    // but the call and what's after is the same. This trampoline
    // is the unchanging part.
    // Since this trampoline is static, it allows code GC inside
    // branch_stub_hit() to free stubs without problems.
    asm_comment!(asm, "branch_stub_hit() trampoline");
    let stub_hit_ret = asm.ccall(
        branch_stub_hit as *mut u8,
        vec![
            C_ARG_OPNDS[0],
            C_ARG_OPNDS[1],
            EC,
        ]
    );
    let jump_addr = asm.load(stub_hit_ret);

    // Restore caller-saved registers for stack temps
    for &reg in caller_saved_temp_regs().rev() {
        asm.cpop_into(Opnd::Reg(reg));
    }

    // Jump to the address returned by the branch_stub_hit() call
    asm.jmp_opnd(jump_addr);

    // HACK: popping into C_RET_REG clobbers the return value of branch_stub_hit() we need to jump
    // to, so we need a scratch register to preserve it. This extends the live range of the C
    // return register so we get something else for the return value.
    let _ = asm.live_reg_opnd(stub_hit_ret);

    asm.compile(ocb, None).map(|(code_ptr, _)| code_ptr)
}

/// Return registers to be pushed and popped on branch_stub_hit.
pub fn caller_saved_temp_regs() -> impl Iterator<Item = &'static Reg> + DoubleEndedIterator {
    let temp_regs = Assembler::get_temp_regs().iter();
    let len = temp_regs.len();
    // The return value gen_leave() leaves in C_RET_REG
    // needs to survive the branch_stub_hit() call.
    let regs = temp_regs.chain(std::iter::once(&C_RET_REG));

    // On x86_64, maintain 16-byte stack alignment
    if cfg!(target_arch = "x86_64") && len % 2 == 0 {
        static ONE_MORE: [Reg; 1] = [C_RET_REG];
        regs.chain(ONE_MORE.iter())
    } else {
        regs.chain(&[])
    }
}

impl Assembler
{
    /// Mark the start position of a patchable entry point in the machine code
    pub fn mark_entry_start(&mut self, entryref: &PendingEntryRef) {
        // We need to create our own entry rc object
        // so that we can move the closure below
        let entryref = entryref.clone();

        self.pos_marker(move |code_ptr, _| {
            entryref.start_addr.set(Some(code_ptr));
        });
    }

    /// Mark the end position of a patchable entry point in the machine code
    pub fn mark_entry_end(&mut self, entryref: &PendingEntryRef) {
        // We need to create our own entry rc object
        // so that we can move the closure below
        let entryref = entryref.clone();

        self.pos_marker(move |code_ptr, _| {
            entryref.end_addr.set(Some(code_ptr));
        });
    }

    // Mark the start position of a patchable branch in the machine code
    fn mark_branch_start(&mut self, branchref: &PendingBranchRef)
    {
        // We need to create our own branch rc object
        // so that we can move the closure below
        let branchref = branchref.clone();

        self.pos_marker(move |code_ptr, _| {
            branchref.start_addr.set(Some(code_ptr));
        });
    }

    // Mark the end position of a patchable branch in the machine code
    fn mark_branch_end(&mut self, branchref: &PendingBranchRef)
    {
        // We need to create our own branch rc object
        // so that we can move the closure below
        let branchref = branchref.clone();

        self.pos_marker(move |code_ptr, _| {
            branchref.end_addr.set(Some(code_ptr));
        });
    }
}

pub fn gen_branch(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    target0: BlockId,
    ctx0: &Context,
    target1: Option<BlockId>,
    ctx1: Option<&Context>,
    gen_fn: BranchGenFn,
) {
    let branch = new_pending_branch(jit, gen_fn);

    // Get the branch targets or stubs
    let target0_addr = branch.set_target(0, target0, ctx0, ocb);
    let target1_addr = if let Some(ctx) = ctx1 {
        let addr = branch.set_target(1, target1.unwrap(), ctx, ocb);
        if addr.is_none() {
            // target1 requested but we're out of memory.
            // Avoid unwrap() in gen_fn()
            return;
        }

        addr
    } else { None };

    // Call the branch generation function
    asm.mark_branch_start(&branch);
    if let Some(dst_addr) = target0_addr {
        branch.gen_fn.call(asm, Target::CodePtr(dst_addr), target1_addr.map(|addr| Target::CodePtr(addr)));
    }
    asm.mark_branch_end(&branch);
}

pub fn gen_direct_jump(jit: &mut JITState, ctx: &Context, target0: BlockId, asm: &mut Assembler) {
    let branch = new_pending_branch(jit, BranchGenFn::JumpToTarget0(Cell::new(BranchShape::Default)));
    let maybe_block = find_block_version(target0, ctx);

    // If the block already exists
    let new_target = if let Some(blockref) = maybe_block {
        let block = unsafe { blockref.as_ref() };
        let block_addr = block.start_addr;

        // Call the branch generation function
        asm_comment!(asm, "gen_direct_jmp: existing block");
        asm.mark_branch_start(&branch);
        branch.gen_fn.call(asm, Target::CodePtr(block_addr), None);
        asm.mark_branch_end(&branch);

        BranchTarget::Block(blockref)
    } else {
        // The branch is effectively empty (a noop)
        asm_comment!(asm, "gen_direct_jmp: fallthrough");
        asm.mark_branch_start(&branch);
        asm.mark_branch_end(&branch);
        branch.gen_fn.set_shape(BranchShape::Next0);

        // `None` in new_target.address signals gen_block_series() to
        // compile the target block right after this one (fallthrough).
        BranchTarget::Stub(Box::new(BranchStub {
            address: None,
            ctx: *ctx,
            iseq: Cell::new(target0.iseq),
            iseq_idx: target0.idx,
        }))
    };

    branch.targets[0].set(Some(Box::new(new_target)));
}

/// Create a stub to force the code up to this point to be executed
pub fn defer_compilation(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) {
    if asm.ctx.is_deferred() {
        panic!("Double defer!");
    }

    let mut next_ctx = asm.ctx;

    next_ctx.mark_as_deferred();

    let branch = new_pending_branch(jit, BranchGenFn::JumpToTarget0(Cell::new(BranchShape::Default)));

    let blockid = BlockId {
        iseq: jit.get_iseq(),
        idx: jit.get_insn_idx(),
    };

    // Likely a stub due to the increased chain depth
    let target0_address = branch.set_target(0, blockid, &next_ctx, ocb);

    // Pad the block if it has the potential to be invalidated. This must be
    // done before gen_fn() in case the jump is overwritten by a fallthrough.
    if jit.block_entry_exit.is_some() {
        asm.pad_inval_patch();
    }

    // Call the branch generation function
    asm_comment!(asm, "defer_compilation");
    asm.mark_branch_start(&branch);
    if let Some(dst_addr) = target0_address {
        branch.gen_fn.call(asm, Target::CodePtr(dst_addr), None);
    }
    asm.mark_branch_end(&branch);

    // If the block we're deferring from is empty
    if jit.get_starting_insn_idx() == jit.get_insn_idx() {
        incr_counter!(defer_empty_count);
    }

    incr_counter!(defer_count);
}

/// Remove a block from the live control flow graph.
/// Block must be initialized and incoming/outgoing edges
/// must also point to initialized blocks.
unsafe fn remove_from_graph(blockref: BlockRef) {
    let block = unsafe { blockref.as_ref() };

    // Remove this block from the predecessor's targets
    for pred_branchref in block.incoming.0.take().iter() {
        // Branch from the predecessor to us
        let pred_branch = unsafe { pred_branchref.as_ref() };

        // If this is us, nullify the target block
        for target_idx in 0..pred_branch.targets.len() {
            // SAFETY: no mutation inside unsafe
            let target_is_us = unsafe {
                pred_branch.targets[target_idx]
                    .ref_unchecked()
                    .as_ref()
                    .and_then(|target| target.get_block())
                    .and_then(|target_block| (target_block == blockref).then(|| ()))
                    .is_some()
            };

            if target_is_us {
                pred_branch.targets[target_idx].set(None);
            }
        }
    }

    // For each outgoing branch
    for out_branchref in block.outgoing.iter() {
        let out_branch = unsafe { out_branchref.as_ref() };
        // For each successor block
        for out_target in out_branch.targets.iter() {
            // SAFETY: copying out an Option<BlockRef>. No mutation.
            let succ_block: Option<BlockRef> = unsafe {
                out_target.ref_unchecked().as_ref().and_then(|target| target.get_block())
            };

            if let Some(succ_block) = succ_block {
                // Remove outgoing branch from the successor's incoming list
                // SAFETY: caller promises the block has valid outgoing edges.
                let succ_block = unsafe { succ_block.as_ref() };
                // Temporarily move out of succ_block.incoming.
                let succ_incoming = succ_block.incoming.0.take();
                let mut succ_incoming = succ_incoming.into_vec();
                succ_incoming.retain(|branch| branch != out_branchref);
                succ_block.incoming.0.set(succ_incoming.into_boxed_slice()); // allocs. Rely on oom=abort
            }
        }
    }
}

/// Tear down a block and deallocate it.
/// Caller has to ensure that the code tracked by the block is not
/// running, as running code may hit [branch_stub_hit] who exepcts
/// [Branch] to be live.
///
/// We currently ensure this through the `jit_cont` system in cont.c
/// and sometimes through the GC calling [rb_yjit_iseq_free]. The GC
/// has proven that an ISeq is not running if it calls us to free it.
///
/// For delayed deallocation, since dead blocks don't keep
/// blocks they refer alive, by the time we get here their outgoing
/// edges may be dangling. Pass `graph_intact=false` such these cases.
pub unsafe fn free_block(blockref: BlockRef, graph_intact: bool) {
    // Careful with order here.
    // First, remove all pointers to the referent block
    unsafe {
        block_assumptions_free(blockref);

        if graph_intact {
            remove_from_graph(blockref);
        }
    }

    // SAFETY: we should now have a unique pointer to the block
    unsafe { dealloc_block(blockref) }
}

/// Deallocate a block and its outgoing branches. Blocks own their outgoing branches.
/// Caller must ensure that we have unique ownership for the referent block
unsafe fn dealloc_block(blockref: BlockRef) {
    unsafe {
        for outgoing in blockref.as_ref().outgoing.iter() {
            // this Box::from_raw matches the Box::into_raw from PendingBranch::into_branch
            mem::drop(Box::from_raw(outgoing.as_ptr()));
        }
    }

    // Deallocate the referent Block
    unsafe {
        // this Box::from_raw matches the Box::into_raw from JITState::into_block
        mem::drop(Box::from_raw(blockref.as_ptr()));
    }
}

// Some runtime checks for integrity of a program location
pub fn verify_blockid(blockid: BlockId) {
    unsafe {
        assert!(rb_IMEMO_TYPE_P(blockid.iseq.into(), imemo_iseq) != 0);
        assert!(u32::from(blockid.idx) < get_iseq_encoded_size(blockid.iseq));
    }
}

// Invalidate one specific block version
pub fn invalidate_block_version(blockref: &BlockRef) {
    //ASSERT_vm_locking();

    // TODO: want to assert that all other ractors are stopped here. Can't patch
    // machine code that some other thread is running.

    let block = unsafe { (*blockref).as_ref() };
    let id_being_invalidated = block.get_blockid();
    let mut cb = CodegenGlobals::get_inline_cb();
    let ocb = CodegenGlobals::get_outlined_cb();

    verify_blockid(id_being_invalidated);

    #[cfg(feature = "disasm")]
    {
        // If dump_iseq_disasm is specified, print to console that blocks for matching ISEQ names were invalidated.
        if let Some(substr) = get_option_ref!(dump_iseq_disasm).as_ref() {
            let iseq_range = &block.iseq_range;
            let iseq_location = iseq_get_location(block.iseq.get(), iseq_range.start);
            if iseq_location.contains(substr) {
                println!("Invalidating block from {}, ISEQ offsets [{}, {})", iseq_location, iseq_range.start, iseq_range.end);
            }
        }
    }

    // Remove this block from the version array
    remove_block_version(blockref);

    // Get a pointer to the generated code for this block
    let block_start = block.start_addr;

    // Make the start of the block do an exit. This handles OOM situations
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
        let block_end = block.get_end_addr();

        if block_start == block_entry_exit {
            // Some blocks exit on entry. Patching a jump to the entry at the
            // entry makes an infinite loop.
        } else {
            // Patch in a jump to block.entry_exit.

            let cur_pos = cb.get_write_ptr();
            let cur_dropped_bytes = cb.has_dropped_bytes();
            cb.set_write_ptr(block_start);

            let mut asm = Assembler::new();
            asm.jmp(block_entry_exit.as_side_exit());
            cb.set_dropped_bytes(false);
            asm.compile(&mut cb, Some(ocb)).expect("can rewrite existing code");

            assert!(
                cb.get_write_ptr() <= block_end,
                "invalidation wrote past end of block (code_size: {:?}, new_size: {}, start_addr: {:?})",
                block.code_size(),
                cb.get_write_ptr().as_offset() - block_start.as_offset(),
                block.start_addr.raw_ptr(cb),
            );
            cb.set_write_ptr(cur_pos);
            cb.set_dropped_bytes(cur_dropped_bytes);
        }
    }

    // For each incoming branch
    for branchref in block.incoming.0.take().iter() {
        let branch = unsafe { branchref.as_ref() };
        let target_idx = if branch.get_target_address(0) == Some(block_start) {
            0
        } else {
            1
        };

        // Assert that the incoming branch indeed points to the block being invalidated
        // SAFETY: no mutation.
        unsafe {
            let incoming_target = branch.targets[target_idx].ref_unchecked().as_ref().unwrap();
            assert_eq!(Some(block_start), incoming_target.get_address());
            if let Some(incoming_block) = &incoming_target.get_block() {
                assert_eq!(blockref, incoming_block);
            }
        }

        // Create a stub for this branch target
        let stub_addr = gen_branch_stub(&block.ctx, ocb, branchref.as_ptr() as usize, target_idx as u32);

        // In case we were unable to generate a stub (e.g. OOM). Use the block's
        // exit instead of a stub for the block. It's important that we
        // still patch the branch in this situation so stubs are unique
        // to branches. Think about what could go wrong if we run out of
        // memory in the middle of this loop.
        let stub_addr = stub_addr.unwrap_or(block_entry_exit);

        // Fill the branch target with a stub
        branch.targets[target_idx].set(Some(Box::new(BranchTarget::Stub(Box::new(BranchStub {
            address: Some(stub_addr),
            iseq: block.iseq.clone(),
            iseq_idx: block.iseq_range.start,
            ctx: block.ctx,
        })))));

        // Check if the invalidated block immediately follows
        let target_next = block.start_addr == branch.end_addr.get();

        if target_next {
            // The new block will no longer be adjacent.
            // Note that we could be enlarging the branch and writing into the
            // start of the block being invalidated.
            branch.gen_fn.set_shape(BranchShape::Default);
        }

        // Rewrite the branch with the new jump target address
        let old_branch_size = branch.code_size();
        regenerate_branch(cb, branch);

        if target_next && branch.end_addr > block.end_addr {
            panic!("yjit invalidate rewrote branch past end of invalidated block: {:?} (code_size: {})", branch, block.code_size());
        }
        if !target_next && branch.code_size() > old_branch_size {
            panic!(
                "invalidated branch grew in size (start_addr: {:?}, old_size: {}, new_size: {})",
                branch.start_addr.raw_ptr(cb), old_branch_size, branch.code_size()
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
    if block.iseq_range.start == 0 {
        // TODO:
        // We could reset the exec counter to zero in rb_iseq_reset_jit_func()
        // so that we eventually compile a new entry point when useful
        unsafe { rb_iseq_reset_jit_func(block.iseq.get()) };
    }

    // FIXME:
    // Call continuation addresses on the stack can also be atomically replaced by jumps going to the stub.

    // SAFETY: This block was in a version_map earlier
    // in this function before we removed it, so it's well connected.
    unsafe { remove_from_graph(*blockref) };

    delayed_deallocation(*blockref);

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
//       # 1.times.each to create a cfunc frame to preserve the JIT frame
//       # which will return to a stub housed in an invalidated block
//       return 1.times.each { Object.define_method(:foo) {} }
//     end
//
//     foo(n + 1)
//   end
//   p foo(1)
pub fn delayed_deallocation(blockref: BlockRef) {
    block_assumptions_free(blockref);

    let payload = get_iseq_payload(unsafe { blockref.as_ref() }.iseq.get()).unwrap();
    payload.dead_blocks.push(blockref);
}

trait RefUnchecked {
    type Contained;
    unsafe fn ref_unchecked(&self) -> &Self::Contained;
}

impl<T> RefUnchecked for Cell<T> {
    type Contained = T;

    /// Gives a reference to the contents of a [Cell].
    /// Dangerous; please include a SAFETY note.
    ///
    /// An easy way to use this without triggering Undefined Behavior is to
    ///   1. ensure there is transitively no Cell/UnsafeCell mutation in the `unsafe` block
    ///   2. ensure the `unsafe` block does not return any references, so our
    ///      analysis is lexically confined. This is trivially true if the block
    ///      returns a `bool`, for example. Aggregates that store references have
    ///      explicit lifetime parameters that look like `<'a>`.
    ///
    /// There are other subtler situations that don't follow these rules yet
    /// are still sound.
    /// See `test_miri_ref_unchecked()` for examples. You can play with it
    /// with `cargo +nightly miri test miri`.
    unsafe fn ref_unchecked(&self) -> &Self::Contained {
        // SAFETY: pointer is dereferenceable because it's from a &Cell.
        // It's up to the caller to follow aliasing rules with the output
        // reference.
        unsafe { self.as_ptr().as_ref().unwrap() }
    }
}

#[cfg(test)]
mod tests {
    use crate::core::*;

    #[test]
    fn type_size() {
        // Check that we can store types in 4 bits,
        // and all local types in 32 bits
        assert_eq!(mem::size_of::<Type>(), 1);
        assert!(Type::BlockParamProxy as usize <= 0b1111);
        assert!(MAX_LOCAL_TYPES * 4 <= 32);
    }

    #[test]
    fn tempmapping_size() {
        assert_eq!(mem::size_of::<TempMapping>(), 1);
    }

    #[test]
    fn local_types() {
        let mut ctx = Context::default();

        for i in 0..MAX_LOCAL_TYPES {
            ctx.set_local_type(i, Type::Fixnum);
            assert_eq!(ctx.get_local_type(i), Type::Fixnum);
            ctx.set_local_type(i, Type::BlockParamProxy);
            assert_eq!(ctx.get_local_type(i), Type::BlockParamProxy);
        }

        ctx.set_local_type(0, Type::Fixnum);
        ctx.clear_local_types();
        assert!(ctx.get_local_type(0) == Type::Unknown);

        // Make sure we don't accidentally set bits incorrectly
        let mut ctx = Context::default();
        ctx.set_local_type(0, Type::Fixnum);
        assert_eq!(ctx.get_local_type(0), Type::Fixnum);
        ctx.set_local_type(2, Type::Fixnum);
        ctx.set_local_type(1, Type::BlockParamProxy);
        assert_eq!(ctx.get_local_type(0), Type::Fixnum);
        assert_eq!(ctx.get_local_type(2), Type::Fixnum);
    }

    #[test]
    fn tempmapping() {
        let t = TempMapping::map_to_stack(Type::Unknown);
        assert_eq!(t.get_kind(), MapToStack);
        assert_eq!(t.get_type(), Type::Unknown);

        let t = TempMapping::map_to_stack(Type::TString);
        assert_eq!(t.get_kind(), MapToStack);
        assert_eq!(t.get_type(), Type::TString);

        let t = TempMapping::map_to_local(7);
        assert_eq!(t.get_kind(), MapToLocal);
        assert_eq!(t.get_local_idx(), 7);
    }

    #[test]
    fn context_size() {
        assert_eq!(mem::size_of::<Context>(), 23);
    }

    #[test]
    fn types() {
        // Valid src => dst
        assert_eq!(Type::Unknown.diff(Type::Unknown), TypeDiff::Compatible(0));
        assert_eq!(Type::UnknownImm.diff(Type::UnknownImm), TypeDiff::Compatible(0));
        assert_ne!(Type::UnknownImm.diff(Type::Unknown), TypeDiff::Incompatible);
        assert_ne!(Type::Fixnum.diff(Type::Unknown), TypeDiff::Incompatible);
        assert_ne!(Type::Fixnum.diff(Type::UnknownImm), TypeDiff::Incompatible);

        // Invalid src => dst
        assert_eq!(Type::Unknown.diff(Type::UnknownImm), TypeDiff::Incompatible);
        assert_eq!(Type::Unknown.diff(Type::Fixnum), TypeDiff::Incompatible);
        assert_eq!(Type::Fixnum.diff(Type::UnknownHeap), TypeDiff::Incompatible);
    }

    #[test]
    fn reg_temps() {
        let mut reg_temps = RegTemps(0);

        // 0 means every slot is not spilled
        for stack_idx in 0..MAX_REG_TEMPS {
            assert_eq!(reg_temps.get(stack_idx), false);
        }

        // Set 0, 2, 7 (RegTemps: 10100001)
        reg_temps.set(0, true);
        reg_temps.set(2, true);
        reg_temps.set(3, true);
        reg_temps.set(3, false);
        reg_temps.set(7, true);

        // Get 0..8
        assert_eq!(reg_temps.get(0), true);
        assert_eq!(reg_temps.get(1), false);
        assert_eq!(reg_temps.get(2), true);
        assert_eq!(reg_temps.get(3), false);
        assert_eq!(reg_temps.get(4), false);
        assert_eq!(reg_temps.get(5), false);
        assert_eq!(reg_temps.get(6), false);
        assert_eq!(reg_temps.get(7), true);

        // Test conflicts
        assert_eq!(5, get_option!(num_temp_regs));
        assert_eq!(reg_temps.conflicts_with(0), false); // already set, but no conflict
        assert_eq!(reg_temps.conflicts_with(1), false);
        assert_eq!(reg_temps.conflicts_with(2), true); // already set, and conflicts with 7
        assert_eq!(reg_temps.conflicts_with(3), false);
        assert_eq!(reg_temps.conflicts_with(4), false);
        assert_eq!(reg_temps.conflicts_with(5), true); // not set, and will conflict with 0
        assert_eq!(reg_temps.conflicts_with(6), false);
        assert_eq!(reg_temps.conflicts_with(7), true); // already set, and conflicts with 2
    }

    #[test]
    fn context() {
        // Valid src => dst
        assert_eq!(Context::default().diff(&Context::default()), TypeDiff::Compatible(0));

        // Try pushing an operand and getting its type
        let mut asm = Assembler::new();
        asm.stack_push(Type::Fixnum);
        let top_type = asm.ctx.get_opnd_type(StackOpnd(0));
        assert!(top_type == Type::Fixnum);

        // TODO: write more tests for Context type diff
    }

    #[test]
    fn context_upgrade_local() {
        let mut asm = Assembler::new();
        asm.stack_push_local(0);
        asm.ctx.upgrade_opnd_type(StackOpnd(0), Type::Nil);
        assert_eq!(Type::Nil, asm.ctx.get_opnd_type(StackOpnd(0)));
    }

    #[test]
    fn context_chain_depth() {
        let mut ctx = Context::default();
        assert_eq!(ctx.get_chain_depth(), 0);
        assert_eq!(ctx.is_return_landing(), false);
        assert_eq!(ctx.is_deferred(), false);

        for _ in 0..5 {
            ctx.increment_chain_depth();
        }
        assert_eq!(ctx.get_chain_depth(), 5);

        ctx.set_as_return_landing();
        assert_eq!(ctx.is_return_landing(), true);

        ctx.clear_return_landing();
        assert_eq!(ctx.is_return_landing(), false);

        ctx.mark_as_deferred();
        assert_eq!(ctx.is_deferred(), true);

        ctx.reset_chain_depth_and_defer();
        assert_eq!(ctx.get_chain_depth(), 0);
        assert_eq!(ctx.is_deferred(), false);
    }

    #[test]
    fn shift_stack_for_send() {
        let mut asm = Assembler::new();

        // Push values to simulate send(:name, arg) with 6 items already on-stack
        for _ in 0..6 {
            asm.stack_push(Type::Fixnum);
        }
        asm.stack_push(Type::Unknown);
        asm.stack_push(Type::ImmSymbol);
        asm.stack_push(Type::Unknown);

        // This method takes argc of the sendee, not argc of send
        asm.shift_stack(1);

        // The symbol should be gone
        assert_eq!(Type::Unknown, asm.ctx.get_opnd_type(StackOpnd(0)));
        assert_eq!(Type::Unknown, asm.ctx.get_opnd_type(StackOpnd(1)));
    }

    #[test]
    fn test_miri_ref_unchecked() {
        let blockid = BlockId {
            iseq: ptr::null(),
            idx: 0,
        };
        let cb = CodeBlock::new_dummy(1024);
        let dumm_addr = cb.get_write_ptr();
        let block = JITState::new(blockid, Context::default(), dumm_addr, ptr::null())
            .into_block(0, dumm_addr, dumm_addr, vec![]);
        let _dropper = BlockDropper(block);

        // Outside of brief moments during construction,
        // we're always working with &Branch (a shared reference to a Branch).
        let branch: &Branch = &Branch {
            gen_fn: BranchGenFn::JZToTarget0,
            block,
            start_addr: dumm_addr,
            end_addr: Cell::new(dumm_addr),
            targets: [Cell::new(None), Cell::new(Some(Box::new(BranchTarget::Stub(Box::new(BranchStub {
                iseq: Cell::new(ptr::null()),
                iseq_idx: 0,
                address: None,
                ctx: Context::default(),
            })))))]
        };
        // For easier soundness reasoning, make sure the reference returned does not out live the
        // `unsafe` block! It's tempting to do, but it leads to non-local issues.
        // Here is an example where it goes wrong:
        if false {
            for target in branch.targets.iter().as_ref() {
                if let Some(btarget) = unsafe { target.ref_unchecked() } {
                    // btarget is derived from the usnafe block!
                    target.set(None); // This drops the contents of the cell...
                    assert!(btarget.get_address().is_none()); // but `btarget` is still live! UB.
                }
            }
        }

        // Do something like this instead. It's not pretty, but it's easier to vet for UB this way.
        for target in branch.targets.iter().as_ref() {
            // SAFETY: no mutation within unsafe
            if unsafe { target.ref_unchecked().is_none() } {
                continue;
            }
            // SAFETY: no mutation within unsafe
            assert!(unsafe { target.ref_unchecked().as_ref().unwrap().get_address().is_none() });
            target.set(None);
        }

        // A more subtle situation where we do Cell/UnsafeCell mutation over the
        // lifetime of the reference released by ref_unchecked().
        branch.targets[0].set(Some(Box::new(BranchTarget::Stub(Box::new(BranchStub {
            iseq: Cell::new(ptr::null()),
            iseq_idx: 0,
            address: None,
            ctx: Context::default(),
        })))));
        // Invalid ISeq; we never dereference it.
        let secret_iseq = NonNull::<rb_iseq_t>::dangling().as_ptr();
        unsafe {
            if let Some(branch_target) = branch.targets[0].ref_unchecked().as_ref() {
                if let BranchTarget::Stub(stub) = branch_target.as_ref() {
                    // SAFETY:
                    // This is a Cell mutation, but it mutates the contents
                    // of a a Cell<IseqPtr>, which is a different type
                    // from the type of Cell found in `Branch::targets`, so
                    // there is no chance of mutating the Cell that we called
                    // ref_unchecked() on above.
                    Cell::set(&stub.iseq, secret_iseq);
                }
            }
        };
        // Check that we indeed changed the iseq of the stub
        // Cell::take moves out of the cell.
        assert_eq!(
            secret_iseq as usize,
            branch.targets[0].take().unwrap().get_blockid().iseq as usize
        );

        struct BlockDropper(BlockRef);
        impl Drop for BlockDropper {
            fn drop(&mut self) {
                // SAFETY: we have ownership because the test doesn't stash
                // the block away in any global structure.
                // Note that the test being self-contained is also why we
                // use dealloc_block() over free_block(), as free_block() touches
                // the global invariants tables unavailable in tests.
                unsafe { dealloc_block(self.0) };
            }
        }
    }
}
