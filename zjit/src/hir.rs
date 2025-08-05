//! High-level intermediary representation (IR) in static single-assignment (SSA) form.

// We use the YARV bytecode constants which have a CRuby-style name
#![allow(non_upper_case_globals)]

use crate::{
    cast::IntoUsize, cruby::*, gc::{get_or_create_iseq_payload, IseqPayload}, options::{get_option, DumpHIR}, state::ZJITState, stats::Counter
};
use std::{
    cell::RefCell, collections::{HashMap, HashSet, VecDeque}, ffi::{c_int, c_void, CStr}, fmt::Display, mem::{align_of, size_of}, ptr, slice::Iter
};
use crate::hir_type::{Type, types};
use crate::bitset::BitSet;
use crate::profile::{TypeDistributionSummary, ProfiledType};

/// An index of an [`Insn`] in a [`Function`]. This is a popular
/// type since this effectively acts as a pointer to an [`Insn`].
/// See also: [`Function::find`].
#[derive(Copy, Clone, Ord, PartialOrd, Eq, PartialEq, Hash, Debug)]
pub struct InsnId(pub usize);

impl Into<usize> for InsnId {
    fn into(self) -> usize {
        self.0
    }
}

impl std::fmt::Display for InsnId {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "v{}", self.0)
    }
}

/// The index of a [`Block`], which effectively acts like a pointer.
#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub struct BlockId(pub usize);

impl Into<usize> for BlockId {
    fn into(self) -> usize {
        self.0
    }
}

impl std::fmt::Display for BlockId {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "bb{}", self.0)
    }
}

type InsnSet = BitSet<InsnId>;
type BlockSet = BitSet<BlockId>;

fn write_vec<T: std::fmt::Display>(f: &mut std::fmt::Formatter, objs: &Vec<T>) -> std::fmt::Result {
    write!(f, "[")?;
    let mut prefix = "";
    for obj in objs {
        write!(f, "{prefix}{obj}")?;
        prefix = ", ";
    }
    write!(f, "]")
}

impl std::fmt::Display for VALUE {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        self.print(&PtrPrintMap::identity()).fmt(f)
    }
}

impl VALUE {
    pub fn print(self, ptr_map: &PtrPrintMap) -> VALUEPrinter {
        VALUEPrinter { inner: self, ptr_map }
    }
}

/// Print adaptor for [`VALUE`]. See [`PtrPrintMap`].
pub struct VALUEPrinter<'a> {
    inner: VALUE,
    ptr_map: &'a PtrPrintMap,
}

impl<'a> std::fmt::Display for VALUEPrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self.inner {
            val if val.fixnum_p() => write!(f, "{}", val.as_fixnum()),
            Qnil => write!(f, "nil"),
            Qtrue => write!(f, "true"),
            Qfalse => write!(f, "false"),
            val => write!(f, "VALUE({:p})", self.ptr_map.map_ptr(val.as_ptr::<VALUE>())),
        }
    }
}

#[derive(Debug, PartialEq, Clone)]
pub struct BranchEdge {
    pub target: BlockId,
    pub args: Vec<InsnId>,
}

impl std::fmt::Display for BranchEdge {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}(", self.target)?;
        let mut prefix = "";
        for arg in &self.args {
            write!(f, "{prefix}{arg}")?;
            prefix = ", ";
        }
        write!(f, ")")
    }
}

/// Invalidation reasons
#[derive(Debug, Clone, Copy)]
pub enum Invariant {
    /// Basic operation is redefined
    BOPRedefined {
        /// {klass}_REDEFINED_OP_FLAG
        klass: RedefinitionFlag,
        /// BOP_{bop}
        bop: ruby_basic_operators,
    },
    MethodRedefined {
        /// The class object whose method we want to assume unchanged
        klass: VALUE,
        /// The method ID of the method we want to assume unchanged
        method: ID,
        /// The callable method entry that we want to track
        cme: *const rb_callable_method_entry_t,
    },
    /// A list of constant expression path segments that must have not been written to for the
    /// following code to be valid.
    StableConstantNames {
        idlist: *const ID,
    },
    /// There is one ractor running. If a non-root ractor gets spawned, this is invalidated.
    SingleRactorMode,
}

impl Invariant {
    pub fn print(self, ptr_map: &PtrPrintMap) -> InvariantPrinter {
        InvariantPrinter { inner: self, ptr_map }
    }
}

impl Display for Invariant {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.print(&PtrPrintMap::identity()).fmt(f)
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SpecialObjectType {
    VMCore = 1,
    CBase = 2,
    ConstBase = 3,
}

impl From<u32> for SpecialObjectType {
    fn from(value: u32) -> Self {
        match value {
            VM_SPECIAL_OBJECT_VMCORE => SpecialObjectType::VMCore,
            VM_SPECIAL_OBJECT_CBASE => SpecialObjectType::CBase,
            VM_SPECIAL_OBJECT_CONST_BASE => SpecialObjectType::ConstBase,
            _ => panic!("Invalid special object type: {}", value),
        }
    }
}

impl From<SpecialObjectType> for u64 {
    fn from(special_type: SpecialObjectType) -> Self {
        special_type as u64
    }
}

impl std::fmt::Display for SpecialObjectType {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            SpecialObjectType::VMCore => write!(f, "VMCore"),
            SpecialObjectType::CBase => write!(f, "CBase"),
            SpecialObjectType::ConstBase => write!(f, "ConstBase"),
        }
    }
}

/// Print adaptor for [`Invariant`]. See [`PtrPrintMap`].
pub struct InvariantPrinter<'a> {
    inner: Invariant,
    ptr_map: &'a PtrPrintMap,
}

impl<'a> std::fmt::Display for InvariantPrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self.inner {
            Invariant::BOPRedefined { klass, bop } => {
                write!(f, "BOPRedefined(")?;
                match klass {
                    INTEGER_REDEFINED_OP_FLAG => write!(f, "INTEGER_REDEFINED_OP_FLAG")?,
                    STRING_REDEFINED_OP_FLAG => write!(f, "STRING_REDEFINED_OP_FLAG")?,
                    ARRAY_REDEFINED_OP_FLAG => write!(f, "ARRAY_REDEFINED_OP_FLAG")?,
                    HASH_REDEFINED_OP_FLAG => write!(f, "HASH_REDEFINED_OP_FLAG")?,
                    _ => write!(f, "{klass}")?,
                }
                write!(f, ", ")?;
                match bop {
                    BOP_PLUS  => write!(f, "BOP_PLUS")?,
                    BOP_MINUS => write!(f, "BOP_MINUS")?,
                    BOP_MULT  => write!(f, "BOP_MULT")?,
                    BOP_DIV   => write!(f, "BOP_DIV")?,
                    BOP_MOD   => write!(f, "BOP_MOD")?,
                    BOP_EQ    => write!(f, "BOP_EQ")?,
                    BOP_NEQ   => write!(f, "BOP_NEQ")?,
                    BOP_LT    => write!(f, "BOP_LT")?,
                    BOP_LE    => write!(f, "BOP_LE")?,
                    BOP_GT    => write!(f, "BOP_GT")?,
                    BOP_GE    => write!(f, "BOP_GE")?,
                    BOP_FREEZE => write!(f, "BOP_FREEZE")?,
                    BOP_UMINUS => write!(f, "BOP_UMINUS")?,
                    BOP_MAX    => write!(f, "BOP_MAX")?,
                    BOP_AREF   => write!(f, "BOP_AREF")?,
                    _ => write!(f, "{bop}")?,
                }
                write!(f, ")")
            }
            Invariant::MethodRedefined { klass, method, cme } => {
                let class_name = get_class_name(klass);
                write!(f, "MethodRedefined({class_name}@{:p}, {}@{:p}, cme:{:p})",
                    self.ptr_map.map_ptr(klass.as_ptr::<VALUE>()),
                    method.contents_lossy(),
                    self.ptr_map.map_id(method.0),
                    self.ptr_map.map_ptr(cme)
                )
            }
            Invariant::StableConstantNames { idlist } => {
                write!(f, "StableConstantNames({:p}, ", self.ptr_map.map_ptr(idlist))?;
                let mut idx = 0;
                let mut sep = "";
                loop {
                    let id = unsafe { *idlist.wrapping_add(idx) };
                    if id.0 == 0 {
                        break;
                    }
                    write!(f, "{sep}{}", id.contents_lossy())?;
                    sep = "::";
                    idx += 1;
                }
                write!(f, ")")
            }
            Invariant::SingleRactorMode => write!(f, "SingleRactorMode"),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Const {
    Value(VALUE),
    CBool(bool),
    CInt8(i8),
    CInt16(i16),
    CInt32(i32),
    CInt64(i64),
    CUInt8(u8),
    CUInt16(u16),
    CUInt32(u32),
    CUInt64(u64),
    CPtr(*mut u8),
    CDouble(f64),
}

impl std::fmt::Display for Const {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        self.print(&PtrPrintMap::identity()).fmt(f)
    }
}

impl Const {
    fn print<'a>(&'a self, ptr_map: &'a PtrPrintMap) -> ConstPrinter<'a> {
        ConstPrinter { inner: self, ptr_map }
    }
}

pub enum RangeType {
    Inclusive = 0, // include the end value
    Exclusive = 1, // exclude the end value
}

impl std::fmt::Display for RangeType {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}", match self {
            RangeType::Inclusive => "NewRangeInclusive",
            RangeType::Exclusive => "NewRangeExclusive",
        })
    }
}

impl std::fmt::Debug for RangeType {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}", self)
    }
}

impl Clone for RangeType {
    fn clone(&self) -> Self {
        *self
    }
}

impl Copy for RangeType {}

impl From<u32> for RangeType {
    fn from(flag: u32) -> Self {
        match flag {
            0 => RangeType::Inclusive,
            1 => RangeType::Exclusive,
            _ => panic!("Invalid range flag: {}", flag),
        }
    }
}

impl From<RangeType> for u32 {
    fn from(range_type: RangeType) -> Self {
        range_type as u32
    }
}

/// Print adaptor for [`Const`]. See [`PtrPrintMap`].
struct ConstPrinter<'a> {
    inner: &'a Const,
    ptr_map: &'a PtrPrintMap,
}

impl<'a> std::fmt::Display for ConstPrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self.inner {
            Const::Value(val) => write!(f, "Value({})", val.print(self.ptr_map)),
            Const::CPtr(val) => write!(f, "CPtr({:p})", self.ptr_map.map_ptr(val)),
            _ => write!(f, "{:?}", self.inner),
        }
    }
}

/// For output stability in tests, we assign each pointer with a stable
/// address the first time we see it. This mapping is off by default;
/// set [`PtrPrintMap::map_ptrs`] to switch it on.
///
/// Because this is extra state external to any pointer being printed, a
/// printing adapter struct that wraps the pointer along with this map is
/// required to make use of this effectly. The [`std::fmt::Display`]
/// implementation on the adapter struct can then be reused to implement
/// `Display` on the inner type with a default [`PtrPrintMap`], which
/// does not perform any mapping.
pub struct PtrPrintMap {
    inner: RefCell<PtrPrintMapInner>,
    map_ptrs: bool,
}

struct PtrPrintMapInner {
    map: HashMap<*const c_void, *const c_void>,
    next_ptr: *const c_void,
}

impl PtrPrintMap {
    /// Return a mapper that maps the pointer to itself.
    pub fn identity() -> Self {
        Self {
            map_ptrs: false,
            inner: RefCell::new(PtrPrintMapInner {
                map: HashMap::default(), next_ptr:
                ptr::without_provenance(0x1000) // Simulate 4 KiB zero page
            })
        }
    }
}

impl PtrPrintMap {
    /// Map a pointer for printing
    fn map_ptr<T>(&self, ptr: *const T) -> *const T {
        // When testing, address stability is not a concern so print real address to enable code
        // reuse
        if !self.map_ptrs {
            return ptr;
        }

        use std::collections::hash_map::Entry::*;
        let ptr = ptr.cast();
        let inner = &mut *self.inner.borrow_mut();
        match inner.map.entry(ptr) {
            Occupied(entry) => entry.get().cast(),
            Vacant(entry) => {
                // Pick a fake address that is suitably aligns for T and remember it in the map
                let mapped = inner.next_ptr.wrapping_add(inner.next_ptr.align_offset(align_of::<T>()));
                entry.insert(mapped);

                // Bump for the next pointer
                inner.next_ptr = mapped.wrapping_add(size_of::<T>());
                mapped.cast()
            }
        }
    }

    /// Map a Ruby ID (index into intern table) for printing
    fn map_id(&self, id: u64) -> *const c_void {
        self.map_ptr(id as *const c_void)
    }
}

#[derive(Debug, Clone, Copy)]
pub enum SideExitReason {
    UnknownNewarraySend(vm_opt_newarray_send_type),
    UnknownCallType,
    UnknownOpcode(u32),
    FixnumAddOverflow,
    FixnumSubOverflow,
    FixnumMultOverflow,
    GuardType(Type),
    GuardBitEquals(VALUE),
    PatchPoint(Invariant),
    CalleeSideExit,
}

impl std::fmt::Display for SideExitReason {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            SideExitReason::UnknownOpcode(opcode) => write!(f, "UnknownOpcode({})", insn_name(*opcode as usize)),
            SideExitReason::UnknownNewarraySend(VM_OPT_NEWARRAY_SEND_MAX) => write!(f, "UnknownNewarraySend(MAX)"),
            SideExitReason::UnknownNewarraySend(VM_OPT_NEWARRAY_SEND_MIN) => write!(f, "UnknownNewarraySend(MIN)"),
            SideExitReason::UnknownNewarraySend(VM_OPT_NEWARRAY_SEND_HASH) => write!(f, "UnknownNewarraySend(HASH)"),
            SideExitReason::UnknownNewarraySend(VM_OPT_NEWARRAY_SEND_PACK) => write!(f, "UnknownNewarraySend(PACK)"),
            SideExitReason::UnknownNewarraySend(VM_OPT_NEWARRAY_SEND_PACK_BUFFER) => write!(f, "UnknownNewarraySend(PACK_BUFFER)"),
            SideExitReason::UnknownNewarraySend(VM_OPT_NEWARRAY_SEND_INCLUDE_P) => write!(f, "UnknownNewarraySend(INCLUDE_P)"),
            SideExitReason::GuardType(guard_type) => write!(f, "GuardType({guard_type})"),
            SideExitReason::GuardBitEquals(value) => write!(f, "GuardBitEquals({})", value.print(&PtrPrintMap::identity())),
            SideExitReason::PatchPoint(invariant) => write!(f, "PatchPoint({invariant})"),
            _ => write!(f, "{self:?}"),
        }
    }
}

/// An instruction in the SSA IR. The output of an instruction is referred to by the index of
/// the instruction ([`InsnId`]). SSA form enables this, and [`UnionFind`] ([`Function::find`])
/// helps with editing.
#[derive(Debug, Clone)]
pub enum Insn {
    Const { val: Const },
    /// SSA block parameter. Also used for function parameters in the function's entry block.
    Param { idx: usize },

    StringCopy { val: InsnId, chilled: bool },
    StringIntern { val: InsnId },

    /// Put special object (VMCORE, CBASE, etc.) based on value_type
    PutSpecialObject { value_type: SpecialObjectType },

    /// Call `to_a` on `val` if the method is defined, or make a new array `[val]` otherwise.
    ToArray { val: InsnId, state: InsnId },
    /// Call `to_a` on `val` if the method is defined, or make a new array `[val]` otherwise. If we
    /// called `to_a`, duplicate the returned array.
    ToNewArray { val: InsnId, state: InsnId },
    NewArray { elements: Vec<InsnId>, state: InsnId },
    /// NewHash contains a vec of (key, value) pairs
    NewHash { elements: Vec<(InsnId,InsnId)>, state: InsnId },
    NewRange { low: InsnId, high: InsnId, flag: RangeType, state: InsnId },
    ArrayDup { val: InsnId, state: InsnId },
    ArrayMax { elements: Vec<InsnId>, state: InsnId },
    /// Extend `left` with the elements from `right`. `left` and `right` must both be `Array`.
    ArrayExtend { left: InsnId, right: InsnId, state: InsnId },
    /// Push `val` onto `array`, where `array` is already `Array`.
    ArrayPush { array: InsnId, val: InsnId, state: InsnId },

    HashDup { val: InsnId, state: InsnId },

    /// Check if the value is truthy and "return" a C boolean. In reality, we will likely fuse this
    /// with IfTrue/IfFalse in the backend to generate jcc.
    Test { val: InsnId },
    /// Return C `true` if `val` is `Qnil`, else `false`.
    IsNil { val: InsnId },
    Defined { op_type: usize, obj: VALUE, pushval: VALUE, v: InsnId },
    GetConstantPath { ic: *const iseq_inline_constant_cache, state: InsnId },

    /// Get a global variable named `id`
    GetGlobal { id: ID, state: InsnId },
    /// Set a global variable named `id` to `val`
    SetGlobal { id: ID, val: InsnId, state: InsnId },

    //NewObject?
    /// Get an instance variable `id` from `self_val`
    GetIvar { self_val: InsnId, id: ID, state: InsnId },
    /// Set `self_val`'s instance variable `id` to `val`
    SetIvar { self_val: InsnId, id: ID, val: InsnId, state: InsnId },
    /// Check whether an instance variable exists on `self_val`
    DefinedIvar { self_val: InsnId, id: ID, pushval: VALUE, state: InsnId },

    /// Get a local variable from a higher scope or the heap
    GetLocal { level: u32, ep_offset: u32 },
    /// Set a local variable in a higher scope or the heap
    SetLocal { level: u32, ep_offset: u32, val: InsnId },

    /// Own a FrameState so that instructions can look up their dominating FrameState when
    /// generating deopt side-exits and frame reconstruction metadata. Does not directly generate
    /// any code.
    Snapshot { state: FrameState },

    /// Unconditional jump
    Jump(BranchEdge),

    /// Conditional branch instructions
    IfTrue { val: InsnId, target: BranchEdge },
    IfFalse { val: InsnId, target: BranchEdge },

    /// Call a C function
    /// `name` is for printing purposes only
    CCall { cfun: *const u8, args: Vec<InsnId>, name: ID, return_type: Type, elidable: bool },

    /// Send without block with dynamic dispatch
    /// Ignoring keyword arguments etc for now
    SendWithoutBlock { self_val: InsnId, cd: *const rb_call_data, args: Vec<InsnId>, state: InsnId },
    Send { self_val: InsnId, cd: *const rb_call_data, blockiseq: IseqPtr, args: Vec<InsnId>, state: InsnId },
    SendWithoutBlockDirect {
        self_val: InsnId,
        cd: *const rb_call_data,
        cme: *const rb_callable_method_entry_t,
        iseq: IseqPtr,
        args: Vec<InsnId>,
        state: InsnId,
    },

    // Invoke a builtin function
    InvokeBuiltin {
        bf: rb_builtin_function,
        args: Vec<InsnId>,
        state: InsnId,
        return_type: Option<Type>,  // None for unannotated builtins
    },

    /// Control flow instructions
    Return { val: InsnId },
    /// Non-local control flow. See the throw YARV instruction
    Throw { throw_state: u32, val: InsnId },

    /// Fixnum +, -, *, /, %, ==, !=, <, <=, >, >=, &, |
    FixnumAdd  { left: InsnId, right: InsnId, state: InsnId },
    FixnumSub  { left: InsnId, right: InsnId, state: InsnId },
    FixnumMult { left: InsnId, right: InsnId, state: InsnId },
    FixnumDiv  { left: InsnId, right: InsnId, state: InsnId },
    FixnumMod  { left: InsnId, right: InsnId, state: InsnId },
    FixnumEq   { left: InsnId, right: InsnId },
    FixnumNeq  { left: InsnId, right: InsnId },
    FixnumLt   { left: InsnId, right: InsnId },
    FixnumLe   { left: InsnId, right: InsnId },
    FixnumGt   { left: InsnId, right: InsnId },
    FixnumGe   { left: InsnId, right: InsnId },
    FixnumAnd  { left: InsnId, right: InsnId },
    FixnumOr   { left: InsnId, right: InsnId },

    // Distinct from `SendWithoutBlock` with `mid:to_s` because does not have a patch point for String to_s being redefined
    ObjToString { val: InsnId, cd: *const rb_call_data, state: InsnId },
    AnyToString { val: InsnId, str: InsnId, state: InsnId },

    /// Side-exit if val doesn't have the expected type.
    GuardType { val: InsnId, guard_type: Type, state: InsnId },
    /// Side-exit if val is not the expected VALUE.
    GuardBitEquals { val: InsnId, expected: VALUE, state: InsnId },

    /// Generate no code (or padding if necessary) and insert a patch point
    /// that can be rewritten to a side exit when the Invariant is broken.
    PatchPoint { invariant: Invariant, state: InsnId },

    /// Side-exit into the interpreter.
    SideExit { state: InsnId, reason: SideExitReason },

    /// Increment a counter in ZJIT stats
    IncrCounter(Counter),
}

impl Insn {
    /// Not every instruction returns a value. Return true if the instruction does and false otherwise.
    pub fn has_output(&self) -> bool {
        match self {
            Insn::Jump(_)
            | Insn::IfTrue { .. } | Insn::IfFalse { .. } | Insn::Return { .. }
            | Insn::PatchPoint { .. } | Insn::SetIvar { .. } | Insn::ArrayExtend { .. }
            | Insn::ArrayPush { .. } | Insn::SideExit { .. } | Insn::SetGlobal { .. }
            | Insn::SetLocal { .. } | Insn::Throw { .. } | Insn::IncrCounter(_) => false,
            _ => true,
        }
    }

    /// Return true if the instruction ends a basic block and false otherwise.
    pub fn is_terminator(&self) -> bool {
        match self {
            Insn::Jump(_) | Insn::Return { .. } | Insn::SideExit { .. } | Insn::Throw { .. } => true,
            _ => false,
        }
    }

    pub fn print<'a>(&self, ptr_map: &'a PtrPrintMap) -> InsnPrinter<'a> {
        InsnPrinter { inner: self.clone(), ptr_map }
    }

    /// Return true if the instruction needs to be kept around. For example, if the instruction
    /// might have a side effect, or if the instruction may raise an exception.
    fn has_effects(&self) -> bool {
        match self {
            Insn::Const { .. } => false,
            Insn::Param { .. } => false,
            Insn::StringCopy { .. } => false,
            Insn::NewArray { .. } => false,
            Insn::NewHash { .. } => false,
            Insn::NewRange { .. } => false,
            Insn::ArrayDup { .. } => false,
            Insn::HashDup { .. } => false,
            Insn::Test { .. } => false,
            Insn::Snapshot { .. } => false,
            Insn::FixnumAdd  { .. } => false,
            Insn::FixnumSub  { .. } => false,
            Insn::FixnumMult { .. } => false,
            // TODO(max): Consider adding a Guard that the rhs is non-zero before Div and Mod
            // Div *is* critical unless we can prove the right hand side != 0
            // Mod *is* critical unless we can prove the right hand side != 0
            Insn::FixnumEq   { .. } => false,
            Insn::FixnumNeq  { .. } => false,
            Insn::FixnumLt   { .. } => false,
            Insn::FixnumLe   { .. } => false,
            Insn::FixnumGt   { .. } => false,
            Insn::FixnumGe   { .. } => false,
            Insn::FixnumAnd  { .. } => false,
            Insn::FixnumOr   { .. } => false,
            Insn::GetLocal   { .. } => false,
            Insn::IsNil      { .. } => false,
            Insn::CCall { elidable, .. } => !elidable,
            _ => true,
        }
    }
}

/// Print adaptor for [`Insn`]. See [`PtrPrintMap`].
pub struct InsnPrinter<'a> {
    inner: Insn,
    ptr_map: &'a PtrPrintMap,
}

impl<'a> std::fmt::Display for InsnPrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match &self.inner {
            Insn::Const { val } => { write!(f, "Const {}", val.print(self.ptr_map)) }
            Insn::Param { idx } => { write!(f, "Param {idx}") }
            Insn::NewArray { elements, .. } => {
                write!(f, "NewArray")?;
                let mut prefix = " ";
                for element in elements {
                    write!(f, "{prefix}{element}")?;
                    prefix = ", ";
                }
                Ok(())
            }
            Insn::NewHash { elements, .. } => {
                write!(f, "NewHash")?;
                let mut prefix = " ";
                for (key, value) in elements {
                    write!(f, "{prefix}{key}: {value}")?;
                    prefix = ", ";
                }
                Ok(())
            }
            Insn::NewRange { low, high, flag, .. } => {
                write!(f, "NewRange {low} {flag} {high}")
            }
            Insn::ArrayMax { elements, .. } => {
                write!(f, "ArrayMax")?;
                let mut prefix = " ";
                for element in elements {
                    write!(f, "{prefix}{element}")?;
                    prefix = ", ";
                }
                Ok(())
            }
            Insn::ArrayDup { val, .. } => { write!(f, "ArrayDup {val}") }
            Insn::HashDup { val, .. } => { write!(f, "HashDup {val}") }
            Insn::StringCopy { val, .. } => { write!(f, "StringCopy {val}") }
            Insn::Test { val } => { write!(f, "Test {val}") }
            Insn::IsNil { val } => { write!(f, "IsNil {val}") }
            Insn::Jump(target) => { write!(f, "Jump {target}") }
            Insn::IfTrue { val, target } => { write!(f, "IfTrue {val}, {target}") }
            Insn::IfFalse { val, target } => { write!(f, "IfFalse {val}, {target}") }
            Insn::SendWithoutBlock { self_val, cd, args, .. } => {
                write!(f, "SendWithoutBlock {self_val}, :{}", ruby_call_method_name(*cd))?;
                for arg in args {
                    write!(f, ", {arg}")?;
                }
                Ok(())
            }
            Insn::SendWithoutBlockDirect { self_val, cd, iseq, args, .. } => {
                write!(f, "SendWithoutBlockDirect {self_val}, :{} ({:?})", ruby_call_method_name(*cd), self.ptr_map.map_ptr(iseq))?;
                for arg in args {
                    write!(f, ", {arg}")?;
                }
                Ok(())
            }
            Insn::Send { self_val, cd, args, blockiseq, .. } => {
                // For tests, we want to check HIR snippets textually. Addresses change
                // between runs, making tests fail. Instead, pick an arbitrary hex value to
                // use as a "pointer" so we can check the rest of the HIR.
                write!(f, "Send {self_val}, {:p}, :{}", self.ptr_map.map_ptr(blockiseq), ruby_call_method_name(*cd))?;
                for arg in args {
                    write!(f, ", {arg}")?;
                }
                Ok(())
            }
            Insn::InvokeBuiltin { bf, args, .. } => {
                write!(f, "InvokeBuiltin {}", unsafe { CStr::from_ptr(bf.name) }.to_str().unwrap())?;
                for arg in args {
                    write!(f, ", {arg}")?;
                }
                Ok(())
            }
            Insn::Return { val } => { write!(f, "Return {val}") }
            Insn::FixnumAdd  { left, right, .. } => { write!(f, "FixnumAdd {left}, {right}") },
            Insn::FixnumSub  { left, right, .. } => { write!(f, "FixnumSub {left}, {right}") },
            Insn::FixnumMult { left, right, .. } => { write!(f, "FixnumMult {left}, {right}") },
            Insn::FixnumDiv  { left, right, .. } => { write!(f, "FixnumDiv {left}, {right}") },
            Insn::FixnumMod  { left, right, .. } => { write!(f, "FixnumMod {left}, {right}") },
            Insn::FixnumEq   { left, right, .. } => { write!(f, "FixnumEq {left}, {right}") },
            Insn::FixnumNeq  { left, right, .. } => { write!(f, "FixnumNeq {left}, {right}") },
            Insn::FixnumLt   { left, right, .. } => { write!(f, "FixnumLt {left}, {right}") },
            Insn::FixnumLe   { left, right, .. } => { write!(f, "FixnumLe {left}, {right}") },
            Insn::FixnumGt   { left, right, .. } => { write!(f, "FixnumGt {left}, {right}") },
            Insn::FixnumGe   { left, right, .. } => { write!(f, "FixnumGe {left}, {right}") },
            Insn::FixnumAnd  { left, right, .. } => { write!(f, "FixnumAnd {left}, {right}") },
            Insn::FixnumOr   { left, right, .. } => { write!(f, "FixnumOr {left}, {right}") },
            Insn::GuardType { val, guard_type, .. } => { write!(f, "GuardType {val}, {}", guard_type.print(self.ptr_map)) },
            Insn::GuardBitEquals { val, expected, .. } => { write!(f, "GuardBitEquals {val}, {}", expected.print(self.ptr_map)) },
            Insn::PatchPoint { invariant, .. } => { write!(f, "PatchPoint {}", invariant.print(self.ptr_map)) },
            Insn::GetConstantPath { ic, .. } => { write!(f, "GetConstantPath {:p}", self.ptr_map.map_ptr(ic)) },
            Insn::CCall { cfun, args, name, return_type: _, elidable: _ } => {
                write!(f, "CCall {}@{:p}", name.contents_lossy(), self.ptr_map.map_ptr(cfun))?;
                for arg in args {
                    write!(f, ", {arg}")?;
                }
                Ok(())
            },
            Insn::Snapshot { state } => write!(f, "Snapshot {}", state),
            Insn::Defined { op_type, v, .. } => {
                // op_type (enum defined_type) printing logic from iseq.c.
                // Not sure why rb_iseq_defined_string() isn't exhaustive.
                write!(f, "Defined ")?;
                let op_type = *op_type as u32;
                if op_type == DEFINED_FUNC {
                    write!(f, "func")?;
                } else if op_type == DEFINED_REF {
                    write!(f, "ref")?;
                } else if op_type == DEFINED_CONST_FROM {
                    write!(f, "constant-from")?;
                } else {
                    write!(f, "{}", String::from_utf8_lossy(unsafe { rb_iseq_defined_string(op_type).as_rstring_byte_slice().unwrap() }))?;
                };
                write!(f, ", {v}")
            }
            Insn::DefinedIvar { self_val, id, .. } => write!(f, "DefinedIvar {self_val}, :{}", id.contents_lossy()),
            Insn::GetIvar { self_val, id, .. } => write!(f, "GetIvar {self_val}, :{}", id.contents_lossy()),
            Insn::SetIvar { self_val, id, val, .. } => write!(f, "SetIvar {self_val}, :{}, {val}", id.contents_lossy()),
            Insn::GetGlobal { id, .. } => write!(f, "GetGlobal :{}", id.contents_lossy()),
            Insn::SetGlobal { id, val, .. } => write!(f, "SetGlobal :{}, {val}", id.contents_lossy()),
            Insn::GetLocal { level, ep_offset } => write!(f, "GetLocal l{level}, EP@{ep_offset}"),
            Insn::SetLocal { val, level, ep_offset } => write!(f, "SetLocal l{level}, EP@{ep_offset}, {val}"),
            Insn::ToArray { val, .. } => write!(f, "ToArray {val}"),
            Insn::ToNewArray { val, .. } => write!(f, "ToNewArray {val}"),
            Insn::ArrayExtend { left, right, .. } => write!(f, "ArrayExtend {left}, {right}"),
            Insn::ArrayPush { array, val, .. } => write!(f, "ArrayPush {array}, {val}"),
            Insn::ObjToString { val, .. } => { write!(f, "ObjToString {val}") },
            Insn::AnyToString { val, str, .. } => { write!(f, "AnyToString {val}, str: {str}") },
            Insn::SideExit { reason, .. } => write!(f, "SideExit {reason}"),
            Insn::PutSpecialObject { value_type } => write!(f, "PutSpecialObject {value_type}"),
            Insn::Throw { throw_state, val } => {
                write!(f, "Throw ")?;
                match throw_state & VM_THROW_STATE_MASK {
                    RUBY_TAG_NONE   => write!(f, "TAG_NONE"),
                    RUBY_TAG_RETURN => write!(f, "TAG_RETURN"),
                    RUBY_TAG_BREAK  => write!(f, "TAG_BREAK"),
                    RUBY_TAG_NEXT   => write!(f, "TAG_NEXT"),
                    RUBY_TAG_RETRY  => write!(f, "TAG_RETRY"),
                    RUBY_TAG_REDO   => write!(f, "TAG_REDO"),
                    RUBY_TAG_RAISE  => write!(f, "TAG_RAISE"),
                    RUBY_TAG_THROW  => write!(f, "TAG_THROW"),
                    RUBY_TAG_FATAL  => write!(f, "TAG_FATAL"),
                    tag => write!(f, "{tag}")
                }?;
                if throw_state & VM_THROW_NO_ESCAPE_FLAG != 0 {
                    write!(f, "|NO_ESCAPE")?;
                }
                write!(f, ", {val}")
            }
            Insn::IncrCounter(counter) => write!(f, "IncrCounter {counter:?}"),
            insn => { write!(f, "{insn:?}") }
        }
    }
}

impl std::fmt::Display for Insn {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        self.print(&PtrPrintMap::identity()).fmt(f)
    }
}

/// An extended basic block in a [`Function`].
#[derive(Default, Debug)]
pub struct Block {
    /// The index of the first YARV instruction for the Block in the ISEQ
    pub insn_idx: u32,
    params: Vec<InsnId>,
    insns: Vec<InsnId>,
}

impl Block {
    /// Return an iterator over params
    pub fn params(&self) -> Iter<InsnId> {
        self.params.iter()
    }

    /// Return an iterator over insns
    pub fn insns(&self) -> Iter<InsnId> {
        self.insns.iter()
    }
}

/// Pretty printer for [`Function`].
pub struct FunctionPrinter<'a> {
    fun: &'a Function,
    display_snapshot: bool,
    ptr_map: PtrPrintMap,
}

impl<'a> FunctionPrinter<'a> {
    pub fn without_snapshot(fun: &'a Function) -> Self {
        let mut ptr_map = PtrPrintMap::identity();
        if cfg!(test) {
            ptr_map.map_ptrs = true;
        }
        Self { fun, display_snapshot: false, ptr_map }
    }

    pub fn with_snapshot(fun: &'a Function) -> FunctionPrinter<'a> {
        let mut printer = Self::without_snapshot(fun);
        printer.display_snapshot = true;
        printer
    }
}

/// Union-Find (Disjoint-Set) is a data structure for managing disjoint sets that has an interface
/// of two operations:
///
/// * find (what set is this item part of?)
/// * union (join these two sets)
///
/// Union-Find identifies sets by their *representative*, which is some chosen element of the set.
/// This is implemented by structuring each set as its own graph component with the representative
/// pointing at nothing. For example:
///
/// * A -> B -> C
/// * D -> E
///
/// This represents two sets `C` and `E`, with three and two members, respectively. In this
/// example, `find(A)=C`, `find(C)=C`, `find(D)=E`, and so on.
///
/// To union sets, call `make_equal_to` on any set element. That is, `make_equal_to(A, D)` and
/// `make_equal_to(B, E)` have the same result: the two sets are joined into the same graph
/// component. After this operation, calling `find` on any element will return `E`.
///
/// This is a useful data structure in compilers because it allows in-place rewriting without
/// linking/unlinking instructions and without replacing all uses. When calling `make_equal_to` on
/// any instruction, all of its uses now implicitly point to the replacement.
///
/// This does mean that pattern matching and analysis of the instruction graph must be careful to
/// call `find` whenever it is inspecting an instruction (or its operands). If not, this may result
/// in missing optimizations.
#[derive(Debug)]
struct UnionFind<T: Copy + Into<usize>> {
    forwarded: Vec<Option<T>>,
}

impl<T: Copy + Into<usize> + PartialEq> UnionFind<T> {
    fn new() -> UnionFind<T> {
        UnionFind { forwarded: vec![] }
    }

    /// Private. Return the internal representation of the forwarding pointer for a given element.
    fn at(&self, idx: T) -> Option<T> {
        self.forwarded.get(idx.into()).map(|x| *x).flatten()
    }

    /// Private. Set the internal representation of the forwarding pointer for the given element
    /// `idx`. Extend the internal vector if necessary.
    fn set(&mut self, idx: T, value: T) {
        if idx.into() >= self.forwarded.len() {
            self.forwarded.resize(idx.into()+1, None);
        }
        self.forwarded[idx.into()] = Some(value);
    }

    /// Find the set representative for `insn`. Perform path compression at the same time to speed
    /// up further find operations. For example, before:
    ///
    /// `A -> B -> C`
    ///
    /// and after `find(A)`:
    ///
    /// ```
    /// A -> C
    /// B ---^
    /// ```
    pub fn find(&mut self, insn: T) -> T {
        let result = self.find_const(insn);
        if result != insn {
            // Path compression
            self.set(insn, result);
        }
        result
    }

    /// Find the set representative for `insn` without doing path compression.
    fn find_const(&self, insn: T) -> T {
        let mut result = insn;
        loop {
            match self.at(result) {
                None => return result,
                Some(insn) => result = insn,
            }
        }
    }

    /// Union the two sets containing `insn` and `target` such that every element in `insn`s set is
    /// now part of `target`'s. Neither argument must be the representative in its set.
    pub fn make_equal_to(&mut self, insn: T, target: T) {
        let found = self.find(insn);
        self.set(found, target);
    }
}

#[derive(Debug, PartialEq)]
pub enum ValidationError {
    BlockHasNoTerminator(BlockId),
    // The terminator and its actual position
    TerminatorNotAtEnd(BlockId, InsnId, usize),
    /// Expected length, actual length
    MismatchedBlockArity(BlockId, usize, usize),
    JumpTargetNotInRPO(BlockId),
    // The offending instruction, and the operand
    OperandNotDefined(BlockId, InsnId, InsnId),
    /// The offending block and instruction
    DuplicateInstruction(BlockId, InsnId),
}

fn can_direct_send(iseq: *const rb_iseq_t) -> bool {
    if unsafe { rb_get_iseq_flags_has_rest(iseq) } { false }
    else if unsafe { rb_get_iseq_flags_has_opt(iseq) } { false }
    else if unsafe { rb_get_iseq_flags_has_kw(iseq) } { false }
    else if unsafe { rb_get_iseq_flags_has_kwrest(iseq) } { false }
    else if unsafe { rb_get_iseq_flags_has_block(iseq) } { false }
    else { true }
}

/// A [`Function`], which is analogous to a Ruby ISeq, is a control-flow graph of [`Block`]s
/// containing instructions.
#[derive(Debug)]
pub struct Function {
    // ISEQ this function refers to
    iseq: *const rb_iseq_t,
    // The types for the parameters of this function
    param_types: Vec<Type>,

    // TODO: get method name and source location from the ISEQ

    insns: Vec<Insn>,
    union_find: std::cell::RefCell<UnionFind<InsnId>>,
    insn_types: Vec<Type>,
    blocks: Vec<Block>,
    entry_block: BlockId,
    profiles: Option<ProfileOracle>,
}

impl Function {
    fn new(iseq: *const rb_iseq_t) -> Function {
        Function {
            iseq,
            insns: vec![],
            insn_types: vec![],
            union_find: UnionFind::new().into(),
            blocks: vec![Block::default()],
            entry_block: BlockId(0),
            param_types: vec![],
            profiles: None,
        }
    }

    // Add an instruction to the function without adding it to any block
    fn new_insn(&mut self, insn: Insn) -> InsnId {
        let id = InsnId(self.insns.len());
        if insn.has_output() {
            self.insn_types.push(types::Any);
        } else {
            self.insn_types.push(types::Empty);
        }
        self.insns.push(insn);
        id
    }

    // Add an instruction to an SSA block
    fn push_insn(&mut self, block: BlockId, insn: Insn) -> InsnId {
        let is_param = matches!(insn, Insn::Param { .. });
        let id = self.new_insn(insn);
        if is_param {
            self.blocks[block.0].params.push(id);
        } else {
            self.blocks[block.0].insns.push(id);
        }
        id
    }

    // Add an instruction to an SSA block
    fn push_insn_id(&mut self, block: BlockId, insn_id: InsnId) -> InsnId {
        self.blocks[block.0].insns.push(insn_id);
        insn_id
    }

    /// Return the number of instructions
    pub fn num_insns(&self) -> usize {
        self.insns.len()
    }

    /// Return a FrameState at the given instruction index.
    pub fn frame_state(&self, insn_id: InsnId) -> FrameState {
        match self.find(insn_id) {
            Insn::Snapshot { state } => state,
            insn => panic!("Unexpected non-Snapshot {insn} when looking up FrameState"),
        }
    }

    fn new_block(&mut self, insn_idx: u32) -> BlockId {
        let id = BlockId(self.blocks.len());
        let mut block = Block::default();
        block.insn_idx = insn_idx;
        self.blocks.push(block);
        id
    }

    /// Return a reference to the Block at the given index.
    pub fn block(&self, block_id: BlockId) -> &Block {
        &self.blocks[block_id.0]
    }

    /// Return the number of blocks
    pub fn num_blocks(&self) -> usize {
        self.blocks.len()
    }

    /// Return a copy of the instruction where the instruction and its operands have been read from
    /// the union-find table (to find the current most-optimized version of this instruction). See
    /// [`UnionFind`] for more.
    ///
    /// This is _the_ function for reading [`Insn`]. Use frequently. Example:
    ///
    /// ```rust
    /// match func.find(insn_id) {
    ///   IfTrue { val, target } if func.is_truthy(val) => {
    ///     let jump = self.new_insn(Insn::Jump(target));
    ///     func.make_equal_to(insn_id, jump);
    ///   }
    ///   _ => {}
    /// }
    /// ```
    pub fn find(&self, insn_id: InsnId) -> Insn {
        macro_rules! find {
            ( $x:expr ) => {
                {
                    // TODO(max): Figure out why borrow_mut().find() causes `already borrowed:
                    // BorrowMutError`
                    self.union_find.borrow().find_const($x)
                }
            };
        }
        macro_rules! find_vec {
            ( $x:expr ) => {
                {
                    $x.iter().map(|arg| find!(*arg)).collect()
                }
            };
        }
        macro_rules! find_branch_edge {
            ( $edge:ident ) => {
                {
                    BranchEdge {
                        target: $edge.target,
                        args: find_vec!($edge.args),
                    }
                }
            };
        }
        let insn_id = find!(insn_id);
        use Insn::*;
        match &self.insns[insn_id.0] {
            result@(Const {..}
                    | Param {..}
                    | GetConstantPath {..}
                    | PatchPoint {..}
                    | PutSpecialObject {..}
                    | GetGlobal {..}
                    | GetLocal {..}
                    | SideExit {..}
                    | IncrCounter(_)) => result.clone(),
            &Snapshot { state: FrameState { iseq, insn_idx, pc, ref stack, ref locals } } =>
                Snapshot {
                    state: FrameState {
                        iseq,
                        insn_idx,
                        pc,
                        stack: find_vec!(stack),
                        locals: find_vec!(locals),
                    }
                },
            &Return { val } => Return { val: find!(val) },
            &Throw { throw_state, val } => Throw { throw_state, val: find!(val) },
            &StringCopy { val, chilled } => StringCopy { val: find!(val), chilled },
            &StringIntern { val } => StringIntern { val: find!(val) },
            &Test { val } => Test { val: find!(val) },
            &IsNil { val } => IsNil { val: find!(val) },
            &Jump(ref target) => Jump(find_branch_edge!(target)),
            &IfTrue { val, ref target } => IfTrue { val: find!(val), target: find_branch_edge!(target) },
            &IfFalse { val, ref target } => IfFalse { val: find!(val), target: find_branch_edge!(target) },
            &GuardType { val, guard_type, state } => GuardType { val: find!(val), guard_type: guard_type, state },
            &GuardBitEquals { val, expected, state } => GuardBitEquals { val: find!(val), expected: expected, state },
            &FixnumAdd { left, right, state } => FixnumAdd { left: find!(left), right: find!(right), state },
            &FixnumSub { left, right, state } => FixnumSub { left: find!(left), right: find!(right), state },
            &FixnumMult { left, right, state } => FixnumMult { left: find!(left), right: find!(right), state },
            &FixnumDiv { left, right, state } => FixnumDiv { left: find!(left), right: find!(right), state },
            &FixnumMod { left, right, state } => FixnumMod { left: find!(left), right: find!(right), state },
            &FixnumNeq { left, right } => FixnumNeq { left: find!(left), right: find!(right) },
            &FixnumEq { left, right } => FixnumEq { left: find!(left), right: find!(right) },
            &FixnumGt { left, right } => FixnumGt { left: find!(left), right: find!(right) },
            &FixnumGe { left, right } => FixnumGe { left: find!(left), right: find!(right) },
            &FixnumLt { left, right } => FixnumLt { left: find!(left), right: find!(right) },
            &FixnumLe { left, right } => FixnumLe { left: find!(left), right: find!(right) },
            &FixnumAnd { left, right } => FixnumAnd { left: find!(left), right: find!(right) },
            &FixnumOr { left, right } => FixnumOr { left: find!(left), right: find!(right) },
            &ObjToString { val, cd, state } => ObjToString {
                val: find!(val),
                cd: cd,
                state,
            },
            &AnyToString { val, str, state } => AnyToString {
                val: find!(val),
                str: find!(str),
                state,
            },
            &SendWithoutBlock { self_val, cd, ref args, state } => SendWithoutBlock {
                self_val: find!(self_val),
                cd: cd,
                args: find_vec!(args),
                state,
            },
            &SendWithoutBlockDirect { self_val, cd, cme, iseq, ref args, state } => SendWithoutBlockDirect {
                self_val: find!(self_val),
                cd: cd,
                cme: cme,
                iseq: iseq,
                args: find_vec!(args),
                state,
            },
            &Send { self_val, cd, blockiseq, ref args, state } => Send {
                self_val: find!(self_val),
                cd: cd,
                blockiseq: blockiseq,
                args: find_vec!(args),
                state,
            },
            &InvokeBuiltin { bf, ref args, state, return_type } => InvokeBuiltin { bf, args: find_vec!(args), state, return_type },
            &ArrayDup { val, state } => ArrayDup { val: find!(val), state },
            &HashDup { val, state } => HashDup { val: find!(val), state },
            &CCall { cfun, ref args, name, return_type, elidable } => CCall { cfun, args: find_vec!(args), name, return_type, elidable },
            &Defined { op_type, obj, pushval, v } => Defined { op_type, obj, pushval, v: find!(v) },
            &DefinedIvar { self_val, pushval, id, state } => DefinedIvar { self_val: find!(self_val), pushval, id, state },
            &NewArray { ref elements, state } => NewArray { elements: find_vec!(elements), state: find!(state) },
            &NewHash { ref elements, state } => {
                let mut found_elements = vec![];
                for &(key, value) in elements {
                    found_elements.push((find!(key), find!(value)));
                }
                NewHash { elements: found_elements, state: find!(state) }
            }
            &NewRange { low, high, flag, state } => NewRange { low: find!(low), high: find!(high), flag, state: find!(state) },
            &ArrayMax { ref elements, state } => ArrayMax { elements: find_vec!(elements), state: find!(state) },
            &SetGlobal { id, val, state } => SetGlobal { id, val: find!(val), state },
            &GetIvar { self_val, id, state } => GetIvar { self_val: find!(self_val), id, state },
            &SetIvar { self_val, id, val, state } => SetIvar { self_val: find!(self_val), id, val: find!(val), state },
            &SetLocal { val, ep_offset, level } => SetLocal { val: find!(val), ep_offset, level },
            &ToArray { val, state } => ToArray { val: find!(val), state },
            &ToNewArray { val, state } => ToNewArray { val: find!(val), state },
            &ArrayExtend { left, right, state } => ArrayExtend { left: find!(left), right: find!(right), state },
            &ArrayPush { array, val, state } => ArrayPush { array: find!(array), val: find!(val), state },
        }
    }

    /// Replace `insn` with the new instruction `replacement`, which will get appended to `insns`.
    fn make_equal_to(&mut self, insn: InsnId, replacement: InsnId) {
        // Don't push it to the block
        self.union_find.borrow_mut().make_equal_to(insn, replacement);
    }

    fn type_of(&self, insn: InsnId) -> Type {
        assert!(self.insns[insn.0].has_output());
        self.insn_types[self.union_find.borrow_mut().find(insn).0]
    }

    /// Check if the type of `insn` is a subtype of `ty`.
    fn is_a(&self, insn: InsnId, ty: Type) -> bool {
        self.type_of(insn).is_subtype(ty)
    }

    fn infer_type(&self, insn: InsnId) -> Type {
        assert!(self.insns[insn.0].has_output());
        match &self.insns[insn.0] {
            Insn::Param { .. } => unimplemented!("params should not be present in block.insns"),
            Insn::SetGlobal { .. } | Insn::Jump(_)
            | Insn::IfTrue { .. } | Insn::IfFalse { .. } | Insn::Return { .. } | Insn::Throw { .. }
            | Insn::PatchPoint { .. } | Insn::SetIvar { .. } | Insn::ArrayExtend { .. }
            | Insn::ArrayPush { .. } | Insn::SideExit { .. } | Insn::SetLocal { .. } | Insn::IncrCounter(_) =>
                panic!("Cannot infer type of instruction with no output: {}", self.insns[insn.0]),
            Insn::Const { val: Const::Value(val) } => Type::from_value(*val),
            Insn::Const { val: Const::CBool(val) } => Type::from_cbool(*val),
            Insn::Const { val: Const::CInt8(val) } => Type::from_cint(types::CInt8, *val as i64),
            Insn::Const { val: Const::CInt16(val) } => Type::from_cint(types::CInt16, *val as i64),
            Insn::Const { val: Const::CInt32(val) } => Type::from_cint(types::CInt32, *val as i64),
            Insn::Const { val: Const::CInt64(val) } => Type::from_cint(types::CInt64, *val),
            Insn::Const { val: Const::CUInt8(val) } => Type::from_cint(types::CUInt8, *val as i64),
            Insn::Const { val: Const::CUInt16(val) } => Type::from_cint(types::CUInt16, *val as i64),
            Insn::Const { val: Const::CUInt32(val) } => Type::from_cint(types::CUInt32, *val as i64),
            Insn::Const { val: Const::CUInt64(val) } => Type::from_cint(types::CUInt64, *val as i64),
            Insn::Const { val: Const::CPtr(val) } => Type::from_cint(types::CPtr, *val as i64),
            Insn::Const { val: Const::CDouble(val) } => Type::from_double(*val),
            Insn::Test { val } if self.type_of(*val).is_known_falsy() => Type::from_cbool(false),
            Insn::Test { val } if self.type_of(*val).is_known_truthy() => Type::from_cbool(true),
            Insn::Test { .. } => types::CBool,
            Insn::IsNil { val } if self.is_a(*val, types::NilClass) => Type::from_cbool(true),
            Insn::IsNil { val } if !self.type_of(*val).could_be(types::NilClass) => Type::from_cbool(false),
            Insn::IsNil { .. } => types::CBool,
            Insn::StringCopy { .. } => types::StringExact,
            Insn::StringIntern { .. } => types::StringExact,
            Insn::NewArray { .. } => types::ArrayExact,
            Insn::ArrayDup { .. } => types::ArrayExact,
            Insn::NewHash { .. } => types::HashExact,
            Insn::HashDup { .. } => types::HashExact,
            Insn::NewRange { .. } => types::RangeExact,
            Insn::CCall { return_type, .. } => *return_type,
            Insn::GuardType { val, guard_type, .. } => self.type_of(*val).intersection(*guard_type),
            Insn::GuardBitEquals { val, expected, .. } => self.type_of(*val).intersection(Type::from_value(*expected)),
            Insn::FixnumAdd  { .. } => types::Fixnum,
            Insn::FixnumSub  { .. } => types::Fixnum,
            Insn::FixnumMult { .. } => types::Fixnum,
            Insn::FixnumDiv  { .. } => types::Fixnum,
            Insn::FixnumMod  { .. } => types::Fixnum,
            Insn::FixnumEq   { .. } => types::BoolExact,
            Insn::FixnumNeq  { .. } => types::BoolExact,
            Insn::FixnumLt   { .. } => types::BoolExact,
            Insn::FixnumLe   { .. } => types::BoolExact,
            Insn::FixnumGt   { .. } => types::BoolExact,
            Insn::FixnumGe   { .. } => types::BoolExact,
            Insn::FixnumAnd  { .. } => types::Fixnum,
            Insn::FixnumOr   { .. } => types::Fixnum,
            Insn::PutSpecialObject { .. } => types::BasicObject,
            Insn::SendWithoutBlock { .. } => types::BasicObject,
            Insn::SendWithoutBlockDirect { .. } => types::BasicObject,
            Insn::Send { .. } => types::BasicObject,
            Insn::InvokeBuiltin { return_type, .. } => return_type.unwrap_or(types::BasicObject),
            Insn::Defined { .. } => types::BasicObject,
            Insn::DefinedIvar { .. } => types::BasicObject,
            Insn::GetConstantPath { .. } => types::BasicObject,
            Insn::ArrayMax { .. } => types::BasicObject,
            Insn::GetGlobal { .. } => types::BasicObject,
            Insn::GetIvar { .. } => types::BasicObject,
            Insn::ToNewArray { .. } => types::ArrayExact,
            Insn::ToArray { .. } => types::ArrayExact,
            Insn::ObjToString { .. } => types::BasicObject,
            Insn::AnyToString { .. } => types::String,
            Insn::GetLocal { .. } => types::BasicObject,
            // The type of Snapshot doesn't really matter; it's never materialized. It's used only
            // as a reference for FrameState, which we use to generate side-exit code.
            Insn::Snapshot { .. } => types::Any,
        }
    }

    fn infer_types(&mut self) {
        // Reset all types
        self.insn_types.fill(types::Empty);

        // Fill parameter types
        let entry_params = self.blocks[self.entry_block.0].params.iter();
        let param_types = self.param_types.iter();
        assert_eq!(
            entry_params.len(),
            entry_params.len(),
            "param types should be initialized before type inference"
        );
        for (param, param_type) in std::iter::zip(entry_params, param_types) {
            // We know that function parameters are BasicObject or some subclass
            self.insn_types[param.0] = *param_type;
        }
        let rpo = self.rpo();
        // Walk the graph, computing types until fixpoint
        let mut reachable = BlockSet::with_capacity(self.blocks.len());
        reachable.insert(self.entry_block);
        loop {
            let mut changed = false;
            for &block in &rpo {
                if !reachable.get(block) { continue; }
                for insn_id in &self.blocks[block.0].insns {
                    let insn_type = match self.find(*insn_id) {
                        Insn::IfTrue { val, target: BranchEdge { target, args } } => {
                            assert!(!self.type_of(val).bit_equal(types::Empty));
                            if self.type_of(val).could_be(Type::from_cbool(true)) {
                                reachable.insert(target);
                                for (idx, arg) in args.iter().enumerate() {
                                    let param = self.blocks[target.0].params[idx];
                                    self.insn_types[param.0] = self.type_of(param).union(self.type_of(*arg));
                                }
                            }
                            continue;
                        }
                        Insn::IfFalse { val, target: BranchEdge { target, args } } => {
                            assert!(!self.type_of(val).bit_equal(types::Empty));
                            if self.type_of(val).could_be(Type::from_cbool(false)) {
                                reachable.insert(target);
                                for (idx, arg) in args.iter().enumerate() {
                                    let param = self.blocks[target.0].params[idx];
                                    self.insn_types[param.0] = self.type_of(param).union(self.type_of(*arg));
                                }
                            }
                            continue;
                        }
                        Insn::Jump(BranchEdge { target, args }) => {
                            reachable.insert(target);
                            for (idx, arg) in args.iter().enumerate() {
                                let param = self.blocks[target.0].params[idx];
                                self.insn_types[param.0] = self.type_of(param).union(self.type_of(*arg));
                            }
                            continue;
                        }
                        insn if insn.has_output() => self.infer_type(*insn_id),
                        _ => continue,
                    };
                    if !self.type_of(*insn_id).bit_equal(insn_type) {
                        self.insn_types[insn_id.0] = insn_type;
                        changed = true;
                    }
                }
            }
            if !changed {
                break;
            }
        }
    }

    /// Return the interpreter-profiled type of the HIR instruction at the given ISEQ instruction
    /// index, if it is known. This historical type record is not a guarantee and must be checked
    /// with a GuardType or similar.
    fn profiled_type_of_at(&self, insn: InsnId, iseq_insn_idx: usize) -> Option<ProfiledType> {
        let Some(ref profiles) = self.profiles else { return None };
        let Some(entries) = profiles.types.get(&iseq_insn_idx) else { return None };
        for (entry_insn, entry_type_summary) in entries {
            if self.union_find.borrow().find_const(*entry_insn) == self.union_find.borrow().find_const(insn) {
                if entry_type_summary.is_monomorphic() || entry_type_summary.is_skewed_polymorphic() {
                    return Some(entry_type_summary.bucket(0));
                } else {
                    return None;
                }
            }
        }
        None
    }

    fn likely_is_fixnum(&self, val: InsnId, profiled_type: ProfiledType) -> bool {
        return self.is_a(val, types::Fixnum) || profiled_type.is_fixnum();
    }

    fn coerce_to_fixnum(&mut self, block: BlockId, val: InsnId, state: InsnId) -> InsnId {
        if self.is_a(val, types::Fixnum) { return val; }
        return self.push_insn(block, Insn::GuardType { val, guard_type: types::Fixnum, state });
    }

    fn arguments_likely_fixnums(&mut self, left: InsnId, right: InsnId, state: InsnId) -> bool {
        let frame_state = self.frame_state(state);
        let iseq_insn_idx = frame_state.insn_idx as usize;
        let left_profiled_type = self.profiled_type_of_at(left, iseq_insn_idx).unwrap_or(ProfiledType::empty());
        let right_profiled_type = self.profiled_type_of_at(right, iseq_insn_idx).unwrap_or(ProfiledType::empty());
        self.likely_is_fixnum(left, left_profiled_type) && self.likely_is_fixnum(right, right_profiled_type)
    }

    fn try_rewrite_fixnum_op(&mut self, block: BlockId, orig_insn_id: InsnId, f: &dyn Fn(InsnId, InsnId) -> Insn, bop: u32, left: InsnId, right: InsnId, state: InsnId) {
        if !unsafe { rb_BASIC_OP_UNREDEFINED_P(bop, INTEGER_REDEFINED_OP_FLAG) } {
            // If the basic operation is already redefined, we cannot optimize it.
            self.push_insn_id(block, orig_insn_id);
            return;
        }
        if self.arguments_likely_fixnums(left, right, state) {
            if bop == BOP_NEQ {
                // For opt_neq, the interpreter checks that both neq and eq are unchanged.
                self.push_insn(block, Insn::PatchPoint { invariant: Invariant::BOPRedefined { klass: INTEGER_REDEFINED_OP_FLAG, bop: BOP_EQ }, state });
            }
            self.push_insn(block, Insn::PatchPoint { invariant: Invariant::BOPRedefined { klass: INTEGER_REDEFINED_OP_FLAG, bop }, state });
            let left = self.coerce_to_fixnum(block, left, state);
            let right = self.coerce_to_fixnum(block, right, state);
            let result = self.push_insn(block, f(left, right));
            self.make_equal_to(orig_insn_id, result);
            self.insn_types[result.0] = self.infer_type(result);
        } else {
            self.push_insn_id(block, orig_insn_id);
        }
    }

    fn rewrite_if_frozen(&mut self, block: BlockId, orig_insn_id: InsnId, self_val: InsnId, klass: u32, bop: u32, state: InsnId) {
        if !unsafe { rb_BASIC_OP_UNREDEFINED_P(bop, klass) } {
            // If the basic operation is already redefined, we cannot optimize it.
            self.push_insn_id(block, orig_insn_id);
            return;
        }
        let self_type = self.type_of(self_val);
        if let Some(obj) = self_type.ruby_object() {
            if obj.is_frozen() {
                self.push_insn(block, Insn::PatchPoint { invariant: Invariant::BOPRedefined { klass, bop }, state });
                self.make_equal_to(orig_insn_id, self_val);
                return;
            }
        }
        self.push_insn_id(block, orig_insn_id);
    }

    fn try_rewrite_freeze(&mut self, block: BlockId, orig_insn_id: InsnId, self_val: InsnId, state: InsnId) {
        if self.is_a(self_val, types::StringExact) {
            self.rewrite_if_frozen(block, orig_insn_id, self_val, STRING_REDEFINED_OP_FLAG, BOP_FREEZE, state);
        } else if self.is_a(self_val, types::ArrayExact) {
            self.rewrite_if_frozen(block, orig_insn_id, self_val, ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE, state);
        } else if self.is_a(self_val, types::HashExact) {
            self.rewrite_if_frozen(block, orig_insn_id, self_val, HASH_REDEFINED_OP_FLAG, BOP_FREEZE, state);
        } else {
            self.push_insn_id(block, orig_insn_id);
        }
    }

    fn try_rewrite_uminus(&mut self, block: BlockId, orig_insn_id: InsnId, self_val: InsnId, state: InsnId) {
        if self.is_a(self_val, types::StringExact) {
            self.rewrite_if_frozen(block, orig_insn_id, self_val, STRING_REDEFINED_OP_FLAG, BOP_UMINUS, state);
        } else {
            self.push_insn_id(block, orig_insn_id);
        }
    }

    fn try_rewrite_aref(&mut self, block: BlockId, orig_insn_id: InsnId, self_val: InsnId, idx_val: InsnId, state: InsnId) {
        if !unsafe { rb_BASIC_OP_UNREDEFINED_P(BOP_AREF, ARRAY_REDEFINED_OP_FLAG) } {
            // If the basic operation is already redefined, we cannot optimize it.
            self.push_insn_id(block, orig_insn_id);
            return;
        }
        let self_type = self.type_of(self_val);
        let idx_type = self.type_of(idx_val);
        if self_type.is_subtype(types::ArrayExact) {
            if let Some(array_obj) = self_type.ruby_object() {
                if array_obj.is_frozen() {
                    if let Some(idx) = idx_type.fixnum_value() {
                        self.push_insn(block, Insn::PatchPoint { invariant: Invariant::BOPRedefined { klass: ARRAY_REDEFINED_OP_FLAG, bop: BOP_AREF }, state });
                        let val = unsafe { rb_yarv_ary_entry_internal(array_obj, idx) };
                        let const_insn = self.push_insn(block, Insn::Const { val: Const::Value(val) });
                        self.make_equal_to(orig_insn_id, const_insn);
                        return;
                    }
                }
            }
        }
        self.push_insn_id(block, orig_insn_id);
    }

    /// Rewrite SendWithoutBlock opcodes into SendWithoutBlockDirect opcodes if we know the target
    /// ISEQ statically. This removes run-time method lookups and opens the door for inlining.
    fn optimize_direct_sends(&mut self) {
        for block in self.rpo() {
            let old_insns = std::mem::take(&mut self.blocks[block.0].insns);
            assert!(self.blocks[block.0].insns.is_empty());
            for insn_id in old_insns {
                match self.find(insn_id) {
                    Insn::SendWithoutBlock { self_val, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(plus) && args.len() == 1 =>
                        self.try_rewrite_fixnum_op(block, insn_id, &|left, right| Insn::FixnumAdd { left, right, state }, BOP_PLUS, self_val, args[0], state),
                    Insn::SendWithoutBlock { self_val, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(minus) && args.len() == 1 =>
                        self.try_rewrite_fixnum_op(block, insn_id, &|left, right| Insn::FixnumSub { left, right, state }, BOP_MINUS, self_val, args[0], state),
                    Insn::SendWithoutBlock { self_val, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(mult) && args.len() == 1 =>
                        self.try_rewrite_fixnum_op(block, insn_id, &|left, right| Insn::FixnumMult { left, right, state }, BOP_MULT, self_val, args[0], state),
                    Insn::SendWithoutBlock { self_val, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(div) && args.len() == 1 =>
                        self.try_rewrite_fixnum_op(block, insn_id, &|left, right| Insn::FixnumDiv { left, right, state }, BOP_DIV, self_val, args[0], state),
                    Insn::SendWithoutBlock { self_val, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(modulo) && args.len() == 1 =>
                        self.try_rewrite_fixnum_op(block, insn_id, &|left, right| Insn::FixnumMod { left, right, state }, BOP_MOD, self_val, args[0], state),
                    Insn::SendWithoutBlock { self_val, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(eq) && args.len() == 1 =>
                        self.try_rewrite_fixnum_op(block, insn_id, &|left, right| Insn::FixnumEq { left, right }, BOP_EQ, self_val, args[0], state),
                    Insn::SendWithoutBlock { self_val, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(neq) && args.len() == 1 =>
                        self.try_rewrite_fixnum_op(block, insn_id, &|left, right| Insn::FixnumNeq { left, right }, BOP_NEQ, self_val, args[0], state),
                    Insn::SendWithoutBlock { self_val, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(lt) && args.len() == 1 =>
                        self.try_rewrite_fixnum_op(block, insn_id, &|left, right| Insn::FixnumLt { left, right }, BOP_LT, self_val, args[0], state),
                    Insn::SendWithoutBlock { self_val, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(le) && args.len() == 1 =>
                        self.try_rewrite_fixnum_op(block, insn_id, &|left, right| Insn::FixnumLe { left, right }, BOP_LE, self_val, args[0], state),
                    Insn::SendWithoutBlock { self_val, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(gt) && args.len() == 1 =>
                        self.try_rewrite_fixnum_op(block, insn_id, &|left, right| Insn::FixnumGt { left, right }, BOP_GT, self_val, args[0], state),
                    Insn::SendWithoutBlock { self_val, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(ge) && args.len() == 1 =>
                        self.try_rewrite_fixnum_op(block, insn_id, &|left, right| Insn::FixnumGe { left, right }, BOP_GE, self_val, args[0], state),
                    Insn::SendWithoutBlock { self_val, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(and) && args.len() == 1 =>
                        self.try_rewrite_fixnum_op(block, insn_id, &|left, right| Insn::FixnumAnd { left, right }, BOP_AND, self_val, args[0], state),
                    Insn::SendWithoutBlock { self_val, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(or) && args.len() == 1 =>
                        self.try_rewrite_fixnum_op(block, insn_id, &|left, right| Insn::FixnumOr { left, right }, BOP_OR, self_val, args[0], state),
                    Insn::SendWithoutBlock { self_val, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(freeze) && args.len() == 0 =>
                        self.try_rewrite_freeze(block, insn_id, self_val, state),
                    Insn::SendWithoutBlock { self_val, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(minusat) && args.len() == 0 =>
                        self.try_rewrite_uminus(block, insn_id, self_val, state),
                    Insn::SendWithoutBlock { self_val, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(aref) && args.len() == 1 =>
                        self.try_rewrite_aref(block, insn_id, self_val, args[0], state),
                    Insn::SendWithoutBlock { mut self_val, cd, args, state } => {
                        let frame_state = self.frame_state(state);
                        let (klass, profiled_type) = if let Some(klass) = self.type_of(self_val).runtime_exact_ruby_class() {
                            // If we know the class statically, use it to fold the lookup at compile-time.
                            (klass, None)
                        } else {
                            // If we know that self is reasonably monomorphic from profile information, guard and use it to fold the lookup at compile-time.
                            // TODO(max): Figure out how to handle top self?
                            let Some(recv_type) = self.profiled_type_of_at(self_val, frame_state.insn_idx) else {
                                self.push_insn_id(block, insn_id); continue;
                            };
                            (recv_type.class(), Some(recv_type))
                        };
                        let ci = unsafe { get_call_data_ci(cd) }; // info about the call site
                        let mid = unsafe { vm_ci_mid(ci) };
                        // Do method lookup
                        let mut cme = unsafe { rb_callable_method_entry(klass, mid) };
                        if cme.is_null() {
                            self.push_insn_id(block, insn_id); continue;
                        }
                        // Load an overloaded cme if applicable. See vm_search_cc().
                        // It allows you to use a faster ISEQ if possible.
                        cme = unsafe { rb_check_overloaded_cme(cme, ci) };
                        let def_type = unsafe { get_cme_def_type(cme) };
                        if def_type != VM_METHOD_TYPE_ISEQ {
                            // TODO(max): Allow non-iseq; cache cme
                            self.push_insn_id(block, insn_id); continue;
                        }
                        // Only specialize positional-positional calls
                        // TODO(max): Handle other kinds of parameter passing
                        let iseq = unsafe { get_def_iseq_ptr((*cme).def) };
                        if !can_direct_send(iseq) {
                            self.push_insn_id(block, insn_id); continue;
                        }
                        self.push_insn(block, Insn::PatchPoint { invariant: Invariant::MethodRedefined { klass, method: mid, cme }, state });
                        if let Some(profiled_type) = profiled_type {
                            self_val = self.push_insn(block, Insn::GuardType { val: self_val, guard_type: Type::from_profiled_type(profiled_type), state });
                        }
                        let send_direct = self.push_insn(block, Insn::SendWithoutBlockDirect { self_val, cd, cme, iseq, args, state });
                        self.make_equal_to(insn_id, send_direct);
                    }
                    Insn::GetConstantPath { ic, state, .. } => {
                        let idlist: *const ID = unsafe { (*ic).segments };
                        let ice = unsafe { (*ic).entry };
                        if ice.is_null() {
                            self.push_insn_id(block, insn_id); continue;
                        }
                        let cref_sensitive = !unsafe { (*ice).ic_cref }.is_null();
                        let multi_ractor_mode = unsafe { rb_zjit_multi_ractor_p() };
                        if cref_sensitive || multi_ractor_mode {
                            self.push_insn_id(block, insn_id); continue;
                        }
                        // Assume single-ractor mode.
                        self.push_insn(block, Insn::PatchPoint { invariant: Invariant::SingleRactorMode, state });
                        // Invalidate output code on any constant writes associated with constants
                        // referenced after the PatchPoint.
                        self.push_insn(block, Insn::PatchPoint { invariant: Invariant::StableConstantNames { idlist }, state });
                        let replacement = self.push_insn(block, Insn::Const { val: Const::Value(unsafe { (*ice).value }) });
                        self.insn_types[replacement.0] = self.infer_type(replacement);
                        self.make_equal_to(insn_id, replacement);
                    }
                    Insn::ObjToString { val, cd, state, .. } => {
                        if self.is_a(val, types::String) {
                            // behaves differently from `SendWithoutBlock` with `mid:to_s` because ObjToString should not have a patch point for String to_s being redefined
                            self.make_equal_to(insn_id, val);
                        } else {
                            let replacement = self.push_insn(block, Insn::SendWithoutBlock { self_val: val, cd, args: vec![], state });
                            self.make_equal_to(insn_id, replacement)
                        }
                    }
                    Insn::AnyToString { str, .. } => {
                        if self.is_a(str, types::String) {
                            self.make_equal_to(insn_id, str);
                        } else {
                            self.push_insn_id(block, insn_id);
                        }
                    }
                    _ => { self.push_insn_id(block, insn_id); }
                }
            }
        }
        self.infer_types();
    }

    /// Optimize SendWithoutBlock that land in a C method to a direct CCall without
    /// runtime lookup.
    fn optimize_c_calls(&mut self) {
        // Try to reduce one SendWithoutBlock to a CCall
        fn reduce_to_ccall(
            fun: &mut Function,
            block: BlockId,
            self_type: Type,
            send: Insn,
            send_insn_id: InsnId,
        ) -> Result<(), ()> {
            let Insn::SendWithoutBlock { mut self_val, cd, mut args, state, .. } = send else {
                return Err(());
            };

            let call_info = unsafe { (*cd).ci };
            let argc = unsafe { vm_ci_argc(call_info) };
            let method_id = unsafe { rb_vm_ci_mid(call_info) };

            // If we have info about the class of the receiver
            let (recv_class, profiled_type) = if let Some(class) = self_type.runtime_exact_ruby_class() {
                (class, None)
            } else {
                let iseq_insn_idx = fun.frame_state(state).insn_idx;
                let Some(recv_type) = fun.profiled_type_of_at(self_val, iseq_insn_idx) else { return Err(()) };
                (recv_type.class(), Some(recv_type))
            };

            // Do method lookup
            let method = unsafe { rb_callable_method_entry(recv_class, method_id) };
            if method.is_null() {
                return Err(());
            }

            // Filter for C methods
            let def_type = unsafe { get_cme_def_type(method) };
            if def_type != VM_METHOD_TYPE_CFUNC {
                return Err(());
            }

            // Find the `argc` (arity) of the C method, which describes the parameters it expects
            let cfunc = unsafe { get_cme_def_body_cfunc(method) };
            let cfunc_argc = unsafe { get_mct_argc(cfunc) };
            match cfunc_argc {
                0.. => {
                    // (self, arg0, arg1, ..., argc) form
                    //
                    // Bail on argc mismatch
                    if argc != cfunc_argc as u32 {
                        return Err(());
                    }

                    // Filter for a leaf and GC free function
                    use crate::cruby_methods::FnProperties;
                    let Some(FnProperties { leaf: true, no_gc: true, return_type, elidable }) =
                        ZJITState::get_method_annotations().get_cfunc_properties(method)
                    else {
                        return Err(());
                    };

                    let ci_flags = unsafe { vm_ci_flag(call_info) };
                    // Filter for simple call sites (i.e. no splats etc.)
                    if ci_flags & VM_CALL_ARGS_SIMPLE != 0 {
                        // Commit to the replacement. Put PatchPoint.
                        fun.push_insn(block, Insn::PatchPoint { invariant: Invariant::MethodRedefined { klass: recv_class, method: method_id, cme: method }, state });
                        if let Some(profiled_type) = profiled_type {
                            // Guard receiver class
                            self_val = fun.push_insn(block, Insn::GuardType { val: self_val, guard_type: Type::from_profiled_type(profiled_type), state });
                        }
                        let cfun = unsafe { get_mct_func(cfunc) }.cast();
                        let mut cfunc_args = vec![self_val];
                        cfunc_args.append(&mut args);
                        let ccall = fun.push_insn(block, Insn::CCall { cfun, args: cfunc_args, name: method_id, return_type, elidable });
                        fun.make_equal_to(send_insn_id, ccall);
                        return Ok(());
                    }
                }
                -1 => {
                    // (argc, argv, self) parameter form
                    // Falling through for now
                }
                -2 => {
                    // (self, args_ruby_array) parameter form
                    // Falling through for now
                }
                _ => unreachable!("unknown cfunc kind: argc={argc}")
            }

            Err(())
        }

        for block in self.rpo() {
            let old_insns = std::mem::take(&mut self.blocks[block.0].insns);
            assert!(self.blocks[block.0].insns.is_empty());
            for insn_id in old_insns {
                if let send @ Insn::SendWithoutBlock { self_val, .. } = self.find(insn_id) {
                    let self_type = self.type_of(self_val);
                    if reduce_to_ccall(self, block, self_type, send, insn_id).is_ok() {
                        continue;
                    }
                }
                self.push_insn_id(block, insn_id);
            }
        }
        self.infer_types();
    }

    /// Fold a binary operator on fixnums.
    fn fold_fixnum_bop(&mut self, insn_id: InsnId, left: InsnId, right: InsnId, f: impl FnOnce(Option<i64>, Option<i64>) -> Option<i64>) -> InsnId {
        f(self.type_of(left).fixnum_value(), self.type_of(right).fixnum_value())
            .filter(|&n| n >= (RUBY_FIXNUM_MIN as i64) && n <= RUBY_FIXNUM_MAX as i64)
            .map(|n| self.new_insn(Insn::Const { val: Const::Value(VALUE::fixnum_from_isize(n as isize)) }))
            .unwrap_or(insn_id)
    }

    /// Fold a binary predicate on fixnums.
    fn fold_fixnum_pred(&mut self, insn_id: InsnId, left: InsnId, right: InsnId, f: impl FnOnce(Option<i64>, Option<i64>) -> Option<bool>) -> InsnId {
        f(self.type_of(left).fixnum_value(), self.type_of(right).fixnum_value())
            .map(|b| if b { Qtrue } else { Qfalse })
            .map(|b| self.new_insn(Insn::Const { val: Const::Value(b) }))
            .unwrap_or(insn_id)
    }

    /// Use type information left by `infer_types` to fold away operations that can be evaluated at compile-time.
    ///
    /// It can fold fixnum math, truthiness tests, and branches with constant conditionals.
    fn fold_constants(&mut self) {
        // TODO(max): Determine if it's worth it for us to reflow types after each branch
        // simplification. This means that we can have nice cascading optimizations if what used to
        // be a union of two different basic block arguments now has a single value.
        //
        // This would require 1) fixpointing, 2) worklist, or 3) (slightly less powerful) calling a
        // function-level infer_types after each pruned branch.
        for block in self.rpo() {
            let old_insns = std::mem::take(&mut self.blocks[block.0].insns);
            let mut new_insns = vec![];
            for insn_id in old_insns {
                let replacement_id = match self.find(insn_id) {
                    Insn::GuardType { val, guard_type, .. } if self.is_a(val, guard_type) => {
                        self.make_equal_to(insn_id, val);
                        // Don't bother re-inferring the type of val; we already know it.
                        continue;
                    }
                    Insn::FixnumAdd { left, right, .. } => {
                        self.fold_fixnum_bop(insn_id, left, right, |l, r| match (l, r) {
                            (Some(l), Some(r)) => l.checked_add(r),
                            _ => None,
                        })
                    }
                    Insn::FixnumSub { left, right, .. } => {
                        self.fold_fixnum_bop(insn_id, left, right, |l, r| match (l, r) {
                            (Some(l), Some(r)) => l.checked_sub(r),
                            _ => None,
                        })
                    }
                    Insn::FixnumMult { left, right, .. } => {
                        self.fold_fixnum_bop(insn_id, left, right, |l, r| match (l, r) {
                            (Some(l), Some(r)) => l.checked_mul(r),
                            (Some(0), _) | (_, Some(0)) => Some(0),
                            _ => None,
                        })
                    }
                    Insn::FixnumEq { left, right, .. } => {
                        self.fold_fixnum_pred(insn_id, left, right, |l, r| match (l, r) {
                            (Some(l), Some(r)) => Some(l == r),
                            _ => None,
                        })
                    }
                    Insn::FixnumNeq { left, right, .. } => {
                        self.fold_fixnum_pred(insn_id, left, right, |l, r| match (l, r) {
                            (Some(l), Some(r)) => Some(l != r),
                            _ => None,
                        })
                    }
                    Insn::FixnumLt { left, right, .. } => {
                        self.fold_fixnum_pred(insn_id, left, right, |l, r| match (l, r) {
                            (Some(l), Some(r)) => Some(l < r),
                            _ => None,
                        })
                    }
                    Insn::FixnumLe { left, right, .. } => {
                        self.fold_fixnum_pred(insn_id, left, right, |l, r| match (l, r) {
                            (Some(l), Some(r)) => Some(l <= r),
                            _ => None,
                        })
                    }
                    Insn::FixnumGt { left, right, .. } => {
                        self.fold_fixnum_pred(insn_id, left, right, |l, r| match (l, r) {
                            (Some(l), Some(r)) => Some(l > r),
                            _ => None,
                        })
                    }
                    Insn::FixnumGe { left, right, .. } => {
                        self.fold_fixnum_pred(insn_id, left, right, |l, r| match (l, r) {
                            (Some(l), Some(r)) => Some(l >= r),
                            _ => None,
                        })
                    }
                    Insn::Test { val } if self.type_of(val).is_known_falsy() => {
                        self.new_insn(Insn::Const { val: Const::CBool(false) })
                    }
                    Insn::Test { val } if self.type_of(val).is_known_truthy() => {
                        self.new_insn(Insn::Const { val: Const::CBool(true) })
                    }
                    Insn::IfTrue { val, target } if self.is_a(val, Type::from_cbool(true)) => {
                        self.new_insn(Insn::Jump(target))
                    }
                    Insn::IfFalse { val, target } if self.is_a(val, Type::from_cbool(false)) => {
                        self.new_insn(Insn::Jump(target))
                    }
                    // If we know that the branch condition is never going to cause a branch,
                    // completely drop the branch from the block.
                    Insn::IfTrue { val, .. } if self.is_a(val, Type::from_cbool(false)) => continue,
                    Insn::IfFalse { val, .. } if self.is_a(val, Type::from_cbool(true)) => continue,
                    _ => insn_id,
                };
                // If we're adding a new instruction, mark the two equivalent in the union-find and
                // do an incremental flow typing of the new instruction.
                if insn_id != replacement_id {
                    self.make_equal_to(insn_id, replacement_id);
                    if self.insns[replacement_id.0].has_output() {
                        self.insn_types[replacement_id.0] = self.infer_type(replacement_id);
                    }
                }
                new_insns.push(replacement_id);
                // If we've just folded an IfTrue into a Jump, for example, don't bother copying
                // over unreachable instructions afterward.
                if self.insns[replacement_id.0].is_terminator() {
                    break;
                }
            }
            self.blocks[block.0].insns = new_insns;
        }
    }

    fn worklist_traverse_single_insn(&self, insn: &Insn, worklist: &mut VecDeque<InsnId>) {
        match insn {
            &Insn::Const { .. }
            | &Insn::Param { .. }
            | &Insn::GetLocal { .. }
            | &Insn::PutSpecialObject { .. }
            | &Insn::IncrCounter(_) =>
                {}
            &Insn::PatchPoint { state, .. }
            | &Insn::GetConstantPath { ic: _, state } => {
                worklist.push_back(state);
            }
            &Insn::ArrayMax { ref elements, state }
            | &Insn::NewArray { ref elements, state } => {
                worklist.extend(elements);
                worklist.push_back(state);
            }
            &Insn::NewHash { ref elements, state } => {
                for &(key, value) in elements {
                    worklist.push_back(key);
                    worklist.push_back(value);
                }
                worklist.push_back(state);
            }
            &Insn::NewRange { low, high, state, .. } => {
                worklist.push_back(low);
                worklist.push_back(high);
                worklist.push_back(state);
            }
            &Insn::StringCopy { val, .. }
            | &Insn::StringIntern { val }
            | &Insn::Return { val }
            | &Insn::Throw { val, .. }
            | &Insn::Defined { v: val, .. }
            | &Insn::Test { val }
            | &Insn::SetLocal { val, .. }
            | &Insn::IsNil { val } =>
                worklist.push_back(val),
            &Insn::SetGlobal { val, state, .. }
            | &Insn::GuardType { val, state, .. }
            | &Insn::GuardBitEquals { val, state, .. }
            | &Insn::ToArray { val, state }
            | &Insn::ToNewArray { val, state } => {
                worklist.push_back(val);
                worklist.push_back(state);
            }
            &Insn::Snapshot { ref state } => {
                worklist.extend(&state.stack);
                worklist.extend(&state.locals);
            }
            &Insn::FixnumAdd { left, right, state }
            | &Insn::FixnumSub { left, right, state }
            | &Insn::FixnumMult { left, right, state }
            | &Insn::FixnumDiv { left, right, state }
            | &Insn::FixnumMod { left, right, state }
            | &Insn::ArrayExtend { left, right, state }
            => {
                worklist.push_back(left);
                worklist.push_back(right);
                worklist.push_back(state);
            }
            &Insn::FixnumLt { left, right }
            | &Insn::FixnumLe { left, right }
            | &Insn::FixnumGt { left, right }
            | &Insn::FixnumGe { left, right }
            | &Insn::FixnumEq { left, right }
            | &Insn::FixnumNeq { left, right }
            | &Insn::FixnumAnd { left, right }
            | &Insn::FixnumOr { left, right }
            => {
                worklist.push_back(left);
                worklist.push_back(right);
            }
            &Insn::Jump(BranchEdge { ref args, .. }) => worklist.extend(args),
            &Insn::IfTrue { val, target: BranchEdge { ref args, .. } } | &Insn::IfFalse { val, target: BranchEdge { ref args, .. } } => {
                worklist.push_back(val);
                worklist.extend(args);
            }
            &Insn::ArrayDup { val, state } | &Insn::HashDup { val, state } => {
                worklist.push_back(val);
                worklist.push_back(state);
            }
            &Insn::Send { self_val, ref args, state, .. }
            | &Insn::SendWithoutBlock { self_val, ref args, state, .. }
            | &Insn::SendWithoutBlockDirect { self_val, ref args, state, .. } => {
                worklist.push_back(self_val);
                worklist.extend(args);
                worklist.push_back(state);
            }
            &Insn::InvokeBuiltin { ref args, state, .. } => {
                worklist.extend(args);
                worklist.push_back(state)
            }
            &Insn::CCall { ref args, .. } => worklist.extend(args),
            &Insn::GetIvar { self_val, state, .. } | &Insn::DefinedIvar { self_val, state, .. } => {
                worklist.push_back(self_val);
                worklist.push_back(state);
            }
            &Insn::SetIvar { self_val, val, state, .. } => {
                worklist.push_back(self_val);
                worklist.push_back(val);
                worklist.push_back(state);
            }
            &Insn::ArrayPush { array, val, state } => {
                worklist.push_back(array);
                worklist.push_back(val);
                worklist.push_back(state);
            }
            &Insn::ObjToString { val, state, .. } => {
                worklist.push_back(val);
                worklist.push_back(state);
            }
            &Insn::AnyToString { val, str, state, .. } => {
                worklist.push_back(val);
                worklist.push_back(str);
                worklist.push_back(state);
            }
            &Insn::GetGlobal { state, .. } |
            &Insn::SideExit { state, .. } => worklist.push_back(state),
        }
    }

    /// Remove instructions that do not have side effects and are not referenced by any other
    /// instruction.
    fn eliminate_dead_code(&mut self) {
        let rpo = self.rpo();
        let mut worklist = VecDeque::new();
        // Find all of the instructions that have side effects, are control instructions, or are
        // otherwise necessary to keep around
        for block_id in &rpo {
            for insn_id in &self.blocks[block_id.0].insns {
                let insn = &self.insns[insn_id.0];
                if insn.has_effects() {
                    worklist.push_back(*insn_id);
                }
            }
        }
        let mut necessary = InsnSet::with_capacity(self.insns.len());
        // Now recursively traverse their data dependencies and mark those as necessary
        while let Some(insn_id) = worklist.pop_front() {
            if necessary.get(insn_id) { continue; }
            necessary.insert(insn_id);
            self.worklist_traverse_single_insn(&self.find(insn_id), &mut worklist);
        }
        // Now remove all unnecessary instructions
        for block_id in &rpo {
            self.blocks[block_id.0].insns.retain(|&insn_id| necessary.get(insn_id));
        }
    }

    fn absorb_dst_block(&mut self, num_in_edges: &Vec<u32>, block: BlockId) -> bool {
        let Some(terminator_id) = self.blocks[block.0].insns.last()
            else { return false };
        let Insn::Jump(BranchEdge { target, args }) = self.find(*terminator_id)
            else { return false };
        if target == block {
            // Can't absorb self
            return false;
        }
        if num_in_edges[target.0] != 1 {
            // Can't absorb block if it's the target of more than one branch
            return false;
        }
        // Link up params with block args
        let params = std::mem::take(&mut self.blocks[target.0].params);
        assert_eq!(args.len(), params.len());
        for (arg, param) in args.iter().zip(params) {
            self.make_equal_to(param, *arg);
        }
        // Remove branch instruction
        self.blocks[block.0].insns.pop();
        // Move target instructions into block
        let target_insns = std::mem::take(&mut self.blocks[target.0].insns);
        self.blocks[block.0].insns.extend(target_insns);
        true
    }

    /// Clean up linked lists of blocks A -> B -> C into A (with B's and C's instructions).
    fn clean_cfg(&mut self) {
        // num_in_edges is invariant throughout cleaning the CFG:
        // * we don't allocate new blocks
        // * blocks that get absorbed are not in RPO anymore
        // * blocks pointed to by blocks that get absorbed retain the same number of in-edges
        let mut num_in_edges = vec![0; self.blocks.len()];
        for block in self.rpo() {
            for &insn in &self.blocks[block.0].insns {
                if let Insn::IfTrue { target, .. } | Insn::IfFalse { target, .. } | Insn::Jump(target) = self.find(insn) {
                    num_in_edges[target.target.0] += 1;
                }
            }
        }
        let mut changed = false;
        loop {
            let mut iter_changed = false;
            for block in self.rpo() {
                // Ignore transient empty blocks
                if self.blocks[block.0].insns.is_empty() { continue; }
                loop {
                    let absorbed = self.absorb_dst_block(&num_in_edges, block);
                    if !absorbed { break; }
                    iter_changed = true;
                }
            }
            if !iter_changed { break; }
            changed = true;
        }
        if changed {
            self.infer_types();
        }
    }

    /// Return a traversal of the `Function`'s `BlockId`s in reverse post-order.
    pub fn rpo(&self) -> Vec<BlockId> {
        let mut result = self.po_from(self.entry_block);
        result.reverse();
        result
    }

    fn po_from(&self, start: BlockId) -> Vec<BlockId> {
        #[derive(PartialEq)]
        enum Action {
            VisitEdges,
            VisitSelf,
        }
        let mut result = vec![];
        let mut seen = BlockSet::with_capacity(self.blocks.len());
        let mut stack = vec![(start, Action::VisitEdges)];
        while let Some((block, action)) = stack.pop() {
            if action == Action::VisitSelf {
                result.push(block);
                continue;
            }
            if !seen.insert(block) { continue; }
            stack.push((block, Action::VisitSelf));
            for insn_id in &self.blocks[block.0].insns {
                let insn = self.find(*insn_id);
                if let Insn::IfTrue { target, .. } | Insn::IfFalse { target, .. } | Insn::Jump(target) = insn {
                    stack.push((target.target, Action::VisitEdges));
                }
            }
        }
        result
    }

    fn assert_validates(&self) {
        if let Err(err) = self.validate() {
            eprintln!("Function failed validation.");
            eprintln!("Err: {err:?}");
            eprintln!("{}", FunctionPrinter::with_snapshot(self));
            panic!("Aborting...");
        }
    }

    /// Run all the optimization passes we have.
    pub fn optimize(&mut self) {
        // Function is assumed to have types inferred already
        self.optimize_direct_sends();
        #[cfg(debug_assertions)] self.assert_validates();
        self.optimize_c_calls();
        #[cfg(debug_assertions)] self.assert_validates();
        self.fold_constants();
        #[cfg(debug_assertions)] self.assert_validates();
        self.clean_cfg();
        #[cfg(debug_assertions)] self.assert_validates();
        self.eliminate_dead_code();
        #[cfg(debug_assertions)] self.assert_validates();

        // Dump HIR after optimization
        match get_option!(dump_hir_opt) {
            Some(DumpHIR::WithoutSnapshot) => println!("Optimized HIR:\n{}", FunctionPrinter::without_snapshot(&self)),
            Some(DumpHIR::All) => println!("Optimized HIR:\n{}", FunctionPrinter::with_snapshot(&self)),
            Some(DumpHIR::Debug) => println!("Optimized HIR:\n{:#?}", &self),
            None => {},
        }
    }


    /// Validates the following:
    /// 1. Basic block jump args match parameter arity.
    /// 2. Every terminator must be in the last position.
    /// 3. Every block must have a terminator.
    fn validate_block_terminators_and_jumps(&self) -> Result<(), ValidationError> {
        for block_id in self.rpo() {
            let mut block_has_terminator = false;
            let insns = &self.blocks[block_id.0].insns;
            for (idx, insn_id) in insns.iter().enumerate() {
                let insn = self.find(*insn_id);
                match &insn {
                    Insn::Jump(BranchEdge{target, args})
                    | Insn::IfTrue { val: _, target: BranchEdge{target, args} }
                    | Insn::IfFalse { val: _, target: BranchEdge{target, args}} => {
                        let target_block = &self.blocks[target.0];
                        let target_len = target_block.params.len();
                        let args_len = args.len();
                        if target_len != args_len {
                            return Err(ValidationError::MismatchedBlockArity(block_id, target_len, args_len))
                        }
                    }
                    _ => {}
                }
                if !insn.is_terminator() {
                    continue;
                }
                block_has_terminator = true;
                if idx != insns.len() - 1 {
                    return Err(ValidationError::TerminatorNotAtEnd(block_id, *insn_id, idx));
                }
            }
            if !block_has_terminator {
                return Err(ValidationError::BlockHasNoTerminator(block_id));
            }
        }
        Ok(())
    }

    // This performs a dataflow def-analysis over the entire CFG to detect any
    // possibly undefined instruction operands.
    fn validate_definite_assignment(&self) -> Result<(), ValidationError> {
        // Map of block ID -> InsnSet
        // Initialize with all missing values at first, to catch if a jump target points to a
        // missing location.
        let mut assigned_in = vec![None; self.num_blocks()];
        let rpo = self.rpo();
        // Begin with every block having every variable defined, except for the entry block, which
        // starts with nothing defined.
        assigned_in[self.entry_block.0] = Some(InsnSet::with_capacity(self.insns.len()));
        for &block in &rpo {
            if block != self.entry_block {
                let mut all_ones = InsnSet::with_capacity(self.insns.len());
                all_ones.insert_all();
                assigned_in[block.0] = Some(all_ones);
            }
        }
        let mut worklist = VecDeque::with_capacity(self.num_blocks());
        worklist.push_back(self.entry_block);
        while let Some(block) = worklist.pop_front() {
            let mut assigned = assigned_in[block.0].clone().unwrap();
            for &param in &self.blocks[block.0].params {
                assigned.insert(param);
            }
            for &insn_id in &self.blocks[block.0].insns {
                let insn_id = self.union_find.borrow().find_const(insn_id);
                match self.find(insn_id) {
                    Insn::Jump(target) | Insn::IfTrue { target, .. } | Insn::IfFalse { target, .. } => {
                        let Some(block_in) = assigned_in[target.target.0].as_mut() else {
                            return Err(ValidationError::JumpTargetNotInRPO(target.target));
                        };
                        // jump target's block_in was modified, we need to queue the block for processing.
                        if block_in.intersect_with(&assigned) {
                            worklist.push_back(target.target);
                        }
                    }
                    insn if insn.has_output() => {
                        assigned.insert(insn_id);
                    }
                    _ => {}
                }
            }
        }
        // Check that each instruction's operands are assigned
        for &block in &rpo {
            let mut assigned = assigned_in[block.0].clone().unwrap();
            for &param in &self.blocks[block.0].params {
                assigned.insert(param);
            }
            for &insn_id in &self.blocks[block.0].insns {
                let insn_id = self.union_find.borrow().find_const(insn_id);
                let mut operands = VecDeque::new();
                let insn = self.find(insn_id);
                self.worklist_traverse_single_insn(&insn, &mut operands);
                for operand in operands {
                    if !assigned.get(operand) {
                        return Err(ValidationError::OperandNotDefined(block, insn_id, operand));
                    }
                }
                if insn.has_output() {
                    assigned.insert(insn_id);
                }
            }
        }
        Ok(())
    }

    /// Checks that each instruction('s representative) appears only once in the CFG.
    fn validate_insn_uniqueness(&self) -> Result<(), ValidationError> {
        let mut seen = InsnSet::with_capacity(self.insns.len());
        for block_id in self.rpo() {
            for &insn_id in &self.blocks[block_id.0].insns {
                let insn_id = self.union_find.borrow().find_const(insn_id);
                if !seen.insert(insn_id) {
                    return Err(ValidationError::DuplicateInstruction(block_id, insn_id));
                }
            }
        }
        Ok(())
    }

    /// Run all validation passes we have.
    pub fn validate(&self) -> Result<(), ValidationError> {
        self.validate_block_terminators_and_jumps()?;
        self.validate_definite_assignment()?;
        self.validate_insn_uniqueness()?;
        Ok(())
    }
}

impl<'a> std::fmt::Display for FunctionPrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let fun = &self.fun;
        let iseq_name = iseq_get_location(fun.iseq, 0);
        // In tests, strip the line number for builtin ISEQs to make tests stable across line changes
        let iseq_name = if cfg!(test) && iseq_name.contains("@<internal:") {
            iseq_name[..iseq_name.rfind(':').unwrap()].to_string()
        } else {
            iseq_name
        };
        writeln!(f, "fn {iseq_name}:")?;
        for block_id in fun.rpo() {
            write!(f, "{block_id}(")?;
            if !fun.blocks[block_id.0].params.is_empty() {
                let mut sep = "";
                for param in &fun.blocks[block_id.0].params {
                    write!(f, "{sep}{param}")?;
                    let insn_type = fun.type_of(*param);
                    if !insn_type.is_subtype(types::Empty) {
                        write!(f, ":{}", insn_type.print(&self.ptr_map))?;
                    }
                    sep = ", ";
                }
            }
            writeln!(f, "):")?;
            for insn_id in &fun.blocks[block_id.0].insns {
                let insn = fun.find(*insn_id);
                if !self.display_snapshot && matches!(insn, Insn::Snapshot {..}) {
                    continue;
                }
                write!(f, "  ")?;
                if insn.has_output() {
                    let insn_type = fun.type_of(*insn_id);
                    if insn_type.is_subtype(types::Empty) {
                        write!(f, "{insn_id} = ")?;
                    } else {
                        write!(f, "{insn_id}:{} = ", insn_type.print(&self.ptr_map))?;
                    }
                }
                writeln!(f, "{}", insn.print(&self.ptr_map))?;
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct FrameState {
    iseq: IseqPtr,
    insn_idx: usize,
    // Ruby bytecode instruction pointer
    pub pc: *const VALUE,

    stack: Vec<InsnId>,
    locals: Vec<InsnId>,
}

impl FrameState {
    /// Get the opcode for the current instruction
    pub fn get_opcode(&self) -> i32 {
        unsafe { rb_iseq_opcode_at_pc(self.iseq, self.pc) }
    }
}

/// Compute the index of a local variable from its slot index
fn ep_offset_to_local_idx(iseq: IseqPtr, ep_offset: u32) -> usize {
    // Layout illustration
    // This is an array of VALUE
    //                                           | VM_ENV_DATA_SIZE |
    //                                           v                  v
    // low addr <+-------+-------+-------+-------+------------------+
    //           |local 0|local 1|  ...  |local n|       ....       |
    //           +-------+-------+-------+-------+------------------+
    //           ^       ^                       ^                  ^
    //           +-------+---local_table_size----+         cfp->ep--+
    //                   |                                          |
    //                   +------------------ep_offset---------------+
    //
    // See usages of local_var_name() from iseq.c for similar calculation.

    // Equivalent of iseq->body->local_table_size
    let local_table_size: i32 = unsafe { get_iseq_body_local_table_size(iseq) }
        .try_into()
        .unwrap();
    let op = (ep_offset - VM_ENV_DATA_SIZE) as i32;
    let local_idx = local_table_size - op - 1;
    assert!(local_idx >= 0 && local_idx < local_table_size);
    local_idx.try_into().unwrap()
}

impl FrameState {
    fn new(iseq: IseqPtr) -> FrameState {
        FrameState { iseq, pc: std::ptr::null::<VALUE>(), insn_idx: 0, stack: vec![], locals: vec![] }
    }

    /// Get the number of stack operands
    pub fn stack_size(&self) -> usize {
        self.stack.len()
    }

    /// Iterate over all stack slots
    pub fn stack(&self) -> Iter<InsnId> {
        self.stack.iter()
    }

    /// Iterate over all local variables
    pub fn locals(&self) -> Iter<InsnId> {
        self.locals.iter()
    }

    /// Push a stack operand
    fn stack_push(&mut self, opnd: InsnId) {
        self.stack.push(opnd);
    }

    /// Pop a stack operand
    fn stack_pop(&mut self) -> Result<InsnId, ParseError> {
        self.stack.pop().ok_or_else(|| ParseError::StackUnderflow(self.clone()))
    }

    /// Get a stack-top operand
    fn stack_top(&self) -> Result<InsnId, ParseError> {
        self.stack.last().ok_or_else(|| ParseError::StackUnderflow(self.clone())).copied()
    }

    /// Set a stack operand at idx
    fn stack_setn(&mut self, idx: usize, opnd: InsnId) {
        let idx = self.stack.len() - idx - 1;
        self.stack[idx] = opnd;
    }

    /// Get a stack operand at idx
    fn stack_topn(&self, idx: usize) -> Result<InsnId, ParseError> {
        let idx = self.stack.len() - idx - 1;
        self.stack.get(idx).ok_or_else(|| ParseError::StackUnderflow(self.clone())).copied()
    }

    fn setlocal(&mut self, ep_offset: u32, opnd: InsnId) {
        let idx = ep_offset_to_local_idx(self.iseq, ep_offset);
        self.locals[idx] = opnd;
    }

    fn getlocal(&mut self, ep_offset: u32) -> InsnId {
        let idx = ep_offset_to_local_idx(self.iseq, ep_offset);
        self.locals[idx]
    }

    fn as_args(&self, self_param: InsnId) -> Vec<InsnId> {
        // We're currently passing around the self parameter as a basic block
        // argument because the register allocator uses a fixed register based
        // on the basic block argument index, which would cause a conflict if
        // we reuse an argument from another basic block.
        // TODO: Modify the register allocator to allow reusing an argument
        // of another basic block.
        let mut args = vec![self_param];
        args.extend(self.locals.iter().chain(self.stack.iter()).map(|op| *op));
        args
    }
}

impl std::fmt::Display for FrameState {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "FrameState {{ pc: {:?}, stack: ", self.pc)?;
        write_vec(f, &self.stack)?;
        write!(f, ", locals: ")?;
        write_vec(f, &self.locals)?;
        write!(f, " }}")
    }
}

/// Get YARV instruction argument
fn get_arg(pc: *const VALUE, arg_idx: isize) -> VALUE {
    unsafe { *(pc.offset(arg_idx + 1)) }
}

/// Compute YARV instruction index at relative offset
fn insn_idx_at_offset(idx: u32, offset: i64) -> u32 {
    ((idx as isize) + (offset as isize)) as u32
}

fn compute_jump_targets(iseq: *const rb_iseq_t) -> Vec<u32> {
    let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
    let mut insn_idx = 0;
    let mut jump_targets = HashSet::new();
    while insn_idx < iseq_size {
        // Get the current pc and opcode
        let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx) };

        // try_into() call below is unfortunate. Maybe pick i32 instead of usize for opcodes.
        let opcode: u32 = unsafe { rb_iseq_opcode_at_pc(iseq, pc) }
            .try_into()
            .unwrap();
        insn_idx += insn_len(opcode as usize);
        match opcode {
            YARVINSN_branchunless | YARVINSN_jump | YARVINSN_branchif | YARVINSN_branchnil => {
                let offset = get_arg(pc, 0).as_i64();
                jump_targets.insert(insn_idx_at_offset(insn_idx, offset));
            }
            YARVINSN_opt_new => {
                let offset = get_arg(pc, 1).as_i64();
                jump_targets.insert(insn_idx_at_offset(insn_idx, offset));
            }
            YARVINSN_leave | YARVINSN_opt_invokebuiltin_delegate_leave => {
                if insn_idx < iseq_size {
                    jump_targets.insert(insn_idx);
                }
            }
            _ => {}
        }
    }
    let mut result = jump_targets.into_iter().collect::<Vec<_>>();
    result.sort();
    result
}

#[derive(Debug, PartialEq)]
pub enum CallType {
    Splat,
    BlockArg,
    Kwarg,
    KwSplat,
    Tailcall,
    Super,
    Zsuper,
    OptSend,
    KwSplatMut,
    SplatMut,
    Forwarding,
}

#[derive(Debug, PartialEq)]
pub enum ParameterType {
    Optional,
}

#[derive(Debug, PartialEq)]
pub enum ParseError {
    StackUnderflow(FrameState),
    UnknownParameterType(ParameterType),
    MalformedIseq(u32), // insn_idx into iseq_encoded
    Validation(ValidationError),
    NotAllowed,
}

/// Return the number of locals in the current ISEQ (includes parameters)
fn num_locals(iseq: *const rb_iseq_t) -> usize {
    (unsafe { get_iseq_body_local_table_size(iseq) }).as_usize()
}

/// If we can't handle the type of send (yet), bail out.
fn unknown_call_type(flag: u32) -> bool {
    if (flag & VM_CALL_KW_SPLAT_MUT) != 0 { return true; }
    if (flag & VM_CALL_ARGS_SPLAT_MUT) != 0 { return true; }
    if (flag & VM_CALL_ARGS_SPLAT) != 0 { return true; }
    if (flag & VM_CALL_KW_SPLAT) != 0 { return true; }
    if (flag & VM_CALL_ARGS_BLOCKARG) != 0 { return true; }
    if (flag & VM_CALL_KWARG) != 0 { return true; }
    if (flag & VM_CALL_TAILCALL) != 0 { return true; }
    if (flag & VM_CALL_SUPER) != 0 { return true; }
    if (flag & VM_CALL_ZSUPER) != 0 { return true; }
    if (flag & VM_CALL_OPT_SEND) != 0 { return true; }
    if (flag & VM_CALL_FORWARDING) != 0 { return true; }
    false
}

/// We have IseqPayload, which keeps track of HIR Types in the interpreter, but this is not useful
/// or correct to query from inside the optimizer. Instead, ProfileOracle provides an API to look
/// up profiled type information by HIR InsnId at a given ISEQ instruction.
#[derive(Debug)]
struct ProfileOracle {
    payload: &'static IseqPayload,
    /// types is a map from ISEQ instruction indices -> profiled type information at that ISEQ
    /// instruction index. At a given ISEQ instruction, the interpreter has profiled the stack
    /// operands to a given ISEQ instruction, and this list of pairs of (InsnId, Type) map that
    /// profiling information into HIR instructions.
    types: HashMap<usize, Vec<(InsnId, TypeDistributionSummary)>>,
}

impl ProfileOracle {
    fn new(payload: &'static IseqPayload) -> Self {
        Self { payload, types: Default::default() }
    }

    /// Map the interpreter-recorded types of the stack onto the HIR operands on our compile-time virtual stack
    fn profile_stack(&mut self, state: &FrameState) {
        let iseq_insn_idx = state.insn_idx;
        let Some(operand_types) = self.payload.profile.get_operand_types(iseq_insn_idx) else { return };
        let entry = self.types.entry(iseq_insn_idx).or_insert_with(|| vec![]);
        // operand_types is always going to be <= stack size (otherwise it would have an underflow
        // at run-time) so use that to drive iteration.
        for (idx, insn_type_distribution) in operand_types.iter().rev().enumerate() {
            let insn = state.stack_topn(idx).expect("Unexpected stack underflow in profiling");
            entry.push((insn, TypeDistributionSummary::new(insn_type_distribution)))
        }
    }
}

/// The index of the self parameter in the HIR function
pub const SELF_PARAM_IDX: usize = 0;

fn filter_unknown_parameter_type(iseq: *const rb_iseq_t) -> Result<(), ParseError> {
    if unsafe { rb_get_iseq_body_param_opt_num(iseq) } != 0 { return Err(ParseError::UnknownParameterType(ParameterType::Optional)); }
    Ok(())
}

/// Compile ISEQ into High-level IR
pub fn iseq_to_hir(iseq: *const rb_iseq_t) -> Result<Function, ParseError> {
    if !ZJITState::can_compile_iseq(iseq) {
        return Err(ParseError::NotAllowed);
    }
    filter_unknown_parameter_type(iseq)?;
    let payload = get_or_create_iseq_payload(iseq);
    let mut profiles = ProfileOracle::new(payload);
    let mut fun = Function::new(iseq);
    // Compute a map of PC->Block by finding jump targets
    let jump_targets = compute_jump_targets(iseq);
    let mut insn_idx_to_block = HashMap::new();
    for insn_idx in jump_targets {
        if insn_idx == 0 {
            todo!("Separate entry block for param/self/...");
        }
        insn_idx_to_block.insert(insn_idx, fun.new_block(insn_idx));
    }

    // Iteratively fill out basic blocks using a queue
    // TODO(max): Basic block arguments at edges
    let mut queue = std::collections::VecDeque::new();
    // Index of the rest parameter for comparison below
    let rest_param_idx = if !iseq.is_null() && unsafe { get_iseq_flags_has_rest(iseq) } {
        let opt_num = unsafe { get_iseq_body_param_opt_num(iseq) };
        let lead_num = unsafe { get_iseq_body_param_lead_num(iseq) };
        opt_num + lead_num
    } else {
        -1
    };
    // The HIR function will have the same number of parameter as the iseq so
    // we properly handle calls from the interpreter. Roughly speaking, each
    // item between commas in the source increase the parameter count by one,
    // regardless of parameter kind.
    let mut entry_state = FrameState::new(iseq);
    fun.push_insn(fun.entry_block, Insn::Param { idx: SELF_PARAM_IDX });
    fun.param_types.push(types::BasicObject); // self
    for local_idx in 0..num_locals(iseq) {
        if local_idx < unsafe { get_iseq_body_param_size(iseq) }.as_usize() {
            entry_state.locals.push(fun.push_insn(fun.entry_block, Insn::Param { idx: local_idx + 1 })); // +1 for self
        } else {
            entry_state.locals.push(fun.push_insn(fun.entry_block, Insn::Const { val: Const::Value(Qnil) }));
        }

        let mut param_type = types::BasicObject;
        // Rest parameters are always ArrayExact
        if let Ok(true) = c_int::try_from(local_idx).map(|idx| idx == rest_param_idx) {
            param_type = types::ArrayExact;
        }
        fun.param_types.push(param_type);
    }
    queue.push_back((entry_state, fun.entry_block, /*insn_idx=*/0_u32));

    let mut visited = HashSet::new();

    let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
    let iseq_type = unsafe { get_iseq_body_type(iseq) };
    while let Some((incoming_state, block, mut insn_idx)) = queue.pop_front() {
        if visited.contains(&block) { continue; }
        visited.insert(block);
        let (self_param, mut state) = if insn_idx == 0 {
            (fun.blocks[fun.entry_block.0].params[SELF_PARAM_IDX], incoming_state.clone())
        } else {
            let self_param = fun.push_insn(block, Insn::Param { idx: SELF_PARAM_IDX });
            let mut result = FrameState::new(iseq);
            let mut idx = 1;
            for _ in 0..incoming_state.locals.len() {
                result.locals.push(fun.push_insn(block, Insn::Param { idx }));
                idx += 1;
            }
            for _ in incoming_state.stack {
                result.stack.push(fun.push_insn(block, Insn::Param { idx }));
                idx += 1;
            }
            (self_param, result)
        };
        // Start the block off with a Snapshot so that if we need to insert a new Guard later on
        // and we don't have a Snapshot handy, we can just iterate backward (at the earliest, to
        // the beginning of the block).
        fun.push_insn(block, Insn::Snapshot { state: state.clone() });
        while insn_idx < iseq_size {
            state.insn_idx = insn_idx as usize;
            // Get the current pc and opcode
            let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx) };
            state.pc = pc;
            let exit_state = state.clone();
            profiles.profile_stack(&exit_state);

            // Increment zjit_insns_count for each YARV instruction if --zjit-stats is enabled.
            if get_option!(stats) {
                fun.push_insn(block, Insn::IncrCounter(Counter::zjit_insns_count));
            }

            // try_into() call below is unfortunate. Maybe pick i32 instead of usize for opcodes.
            let opcode: u32 = unsafe { rb_iseq_opcode_at_pc(iseq, pc) }
                .try_into()
                .unwrap();
            // Move to the next instruction to compile
            insn_idx += insn_len(opcode as usize);

            match opcode {
                YARVINSN_nop => {},
                YARVINSN_putnil => { state.stack_push(fun.push_insn(block, Insn::Const { val: Const::Value(Qnil) })); },
                YARVINSN_putobject => { state.stack_push(fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) })); },
                YARVINSN_putspecialobject => {
                    let value_type = SpecialObjectType::from(get_arg(pc, 0).as_u32());
                    let insn = if value_type == SpecialObjectType::VMCore {
                        Insn::Const { val: Const::Value(unsafe { rb_mRubyVMFrozenCore }) }
                    } else {
                        Insn::PutSpecialObject { value_type }
                    };
                    state.stack_push(fun.push_insn(block, insn));
                }
                YARVINSN_putstring => {
                    let val = fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) });
                    let insn_id = fun.push_insn(block, Insn::StringCopy { val, chilled: false });
                    state.stack_push(insn_id);
                }
                YARVINSN_putchilledstring => {
                    let val = fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) });
                    let insn_id = fun.push_insn(block, Insn::StringCopy { val, chilled: true });
                    state.stack_push(insn_id);
                }
                YARVINSN_putself => { state.stack_push(self_param); }
                YARVINSN_intern => {
                    let val = state.stack_pop()?;
                    let insn_id = fun.push_insn(block, Insn::StringIntern { val });
                    state.stack_push(insn_id);
                }
                YARVINSN_newarray => {
                    let count = get_arg(pc, 0).as_usize();
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let mut elements = vec![];
                    for _ in 0..count {
                        elements.push(state.stack_pop()?);
                    }
                    elements.reverse();
                    state.stack_push(fun.push_insn(block, Insn::NewArray { elements, state: exit_id }));
                }
                YARVINSN_opt_newarray_send => {
                    let count = get_arg(pc, 0).as_usize();
                    let method = get_arg(pc, 1).as_u32();
                    let mut elements = vec![];
                    for _ in 0..count {
                        elements.push(state.stack_pop()?);
                    }
                    elements.reverse();
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let (bop, insn) = match method {
                        VM_OPT_NEWARRAY_SEND_MAX => (BOP_MAX, Insn::ArrayMax { elements, state: exit_id }),
                        _ => {
                            // Unknown opcode; side-exit into the interpreter
                            fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnknownNewarraySend(method) });
                            break;  // End the block
                        },
                    };
                    if !unsafe { rb_BASIC_OP_UNREDEFINED_P(bop, ARRAY_REDEFINED_OP_FLAG) } {
                        // If the basic operation is already redefined, we cannot optimize it.
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::PatchPoint(Invariant::BOPRedefined { klass: ARRAY_REDEFINED_OP_FLAG, bop }) });
                        break;  // End the block
                    }
                    fun.push_insn(block, Insn::PatchPoint { invariant: Invariant::BOPRedefined { klass: ARRAY_REDEFINED_OP_FLAG, bop }, state: exit_id });
                    state.stack_push(fun.push_insn(block, insn));
                }
                YARVINSN_duparray => {
                    let val = fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) });
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let insn_id = fun.push_insn(block, Insn::ArrayDup { val, state: exit_id });
                    state.stack_push(insn_id);
                }
                YARVINSN_newhash => {
                    let count = get_arg(pc, 0).as_usize();
                    assert!(count % 2 == 0, "newhash count should be even");
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let mut elements = vec![];
                    for _ in 0..(count/2) {
                        let value = state.stack_pop()?;
                        let key = state.stack_pop()?;
                        elements.push((key, value));
                    }
                    elements.reverse();
                    state.stack_push(fun.push_insn(block, Insn::NewHash { elements, state: exit_id }));
                }
                YARVINSN_duphash => {
                    let val = fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) });
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let insn_id = fun.push_insn(block, Insn::HashDup { val, state: exit_id });
                    state.stack_push(insn_id);
                }
                YARVINSN_splatarray => {
                    let flag = get_arg(pc, 0);
                    let result_must_be_mutable = flag.test();
                    let val = state.stack_pop()?;
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let obj = if result_must_be_mutable {
                        fun.push_insn(block, Insn::ToNewArray { val, state: exit_id })
                    } else {
                        fun.push_insn(block, Insn::ToArray { val, state: exit_id })
                    };
                    state.stack_push(obj);
                }
                YARVINSN_concattoarray => {
                    let right = state.stack_pop()?;
                    let left = state.stack_pop()?;
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let right_array = fun.push_insn(block, Insn::ToArray { val: right, state: exit_id });
                    fun.push_insn(block, Insn::ArrayExtend { left, right: right_array, state: exit_id });
                    state.stack_push(left);
                }
                YARVINSN_pushtoarray => {
                    let count = get_arg(pc, 0).as_usize();
                    let mut vals = vec![];
                    for _ in 0..count {
                        vals.push(state.stack_pop()?);
                    }
                    let array = state.stack_pop()?;
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    for val in vals.into_iter().rev() {
                        fun.push_insn(block, Insn::ArrayPush { array, val, state: exit_id });
                    }
                    state.stack_push(array);
                }
                YARVINSN_putobject_INT2FIX_0_ => {
                    state.stack_push(fun.push_insn(block, Insn::Const { val: Const::Value(VALUE::fixnum_from_usize(0)) }));
                }
                YARVINSN_putobject_INT2FIX_1_ => {
                    state.stack_push(fun.push_insn(block, Insn::Const { val: Const::Value(VALUE::fixnum_from_usize(1)) }));
                }
                YARVINSN_defined => {
                    // (rb_num_t op_type, VALUE obj, VALUE pushval)
                    let op_type = get_arg(pc, 0).as_usize();
                    let obj = get_arg(pc, 1);
                    let pushval = get_arg(pc, 2);
                    let v = state.stack_pop()?;
                    state.stack_push(fun.push_insn(block, Insn::Defined { op_type, obj, pushval, v }));
                }
                YARVINSN_definedivar => {
                    // (ID id, IVC ic, VALUE pushval)
                    let id = ID(get_arg(pc, 0).as_u64());
                    let pushval = get_arg(pc, 2);
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    state.stack_push(fun.push_insn(block, Insn::DefinedIvar { self_val: self_param, id, pushval, state: exit_id }));
                }
                YARVINSN_opt_getconstant_path => {
                    let ic = get_arg(pc, 0).as_ptr();
                    let snapshot = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    state.stack_push(fun.push_insn(block, Insn::GetConstantPath { ic, state: snapshot }));
                }
                YARVINSN_branchunless => {
                    let offset = get_arg(pc, 0).as_i64();
                    let val = state.stack_pop()?;
                    let test_id = fun.push_insn(block, Insn::Test { val });
                    // TODO(max): Check interrupts
                    let target_idx = insn_idx_at_offset(insn_idx, offset);
                    let target = insn_idx_to_block[&target_idx];
                    let _branch_id = fun.push_insn(block, Insn::IfFalse {
                        val: test_id,
                        target: BranchEdge { target, args: state.as_args(self_param) }
                    });
                    queue.push_back((state.clone(), target, target_idx));
                }
                YARVINSN_branchif => {
                    let offset = get_arg(pc, 0).as_i64();
                    let val = state.stack_pop()?;
                    let test_id = fun.push_insn(block, Insn::Test { val });
                    // TODO(max): Check interrupts
                    let target_idx = insn_idx_at_offset(insn_idx, offset);
                    let target = insn_idx_to_block[&target_idx];
                    let _branch_id = fun.push_insn(block, Insn::IfTrue {
                        val: test_id,
                        target: BranchEdge { target, args: state.as_args(self_param) }
                    });
                    queue.push_back((state.clone(), target, target_idx));
                }
                YARVINSN_branchnil => {
                    let offset = get_arg(pc, 0).as_i64();
                    let val = state.stack_pop()?;
                    let test_id = fun.push_insn(block, Insn::IsNil { val });
                    // TODO(max): Check interrupts
                    let target_idx = insn_idx_at_offset(insn_idx, offset);
                    let target = insn_idx_to_block[&target_idx];
                    let _branch_id = fun.push_insn(block, Insn::IfTrue {
                        val: test_id,
                        target: BranchEdge { target, args: state.as_args(self_param) }
                    });
                    queue.push_back((state.clone(), target, target_idx));
                }
                YARVINSN_opt_new => {
                    let offset = get_arg(pc, 1).as_i64();
                    // TODO(max): Check interrupts
                    let target_idx = insn_idx_at_offset(insn_idx, offset);
                    let target = insn_idx_to_block[&target_idx];
                    // Skip the fast-path and go straight to the fallback code. We will let the
                    // optimizer take care of the converting Class#new->alloc+initialize instead.
                    fun.push_insn(block, Insn::Jump(BranchEdge { target, args: state.as_args(self_param) }));
                    queue.push_back((state.clone(), target, target_idx));
                    break;  // Don't enqueue the next block as a successor
                }
                YARVINSN_jump => {
                    let offset = get_arg(pc, 0).as_i64();
                    // TODO(max): Check interrupts
                    let target_idx = insn_idx_at_offset(insn_idx, offset);
                    let target = insn_idx_to_block[&target_idx];
                    let _branch_id = fun.push_insn(block, Insn::Jump(
                        BranchEdge { target, args: state.as_args(self_param) }
                    ));
                    queue.push_back((state.clone(), target, target_idx));
                    break;  // Don't enqueue the next block as a successor
                }
                YARVINSN_getlocal_WC_0 => {
                    let ep_offset = get_arg(pc, 0).as_u32();
                    if iseq_type == ISEQ_TYPE_EVAL {
                        // On eval, the locals are always on the heap, so read the local using EP.
                        state.stack_push(fun.push_insn(block, Insn::GetLocal { ep_offset, level: 0 }));
                    } else {
                        // TODO(alan): This implementation doesn't read from EP, so will miss writes
                        // from nested ISeqs. This will need to be amended when we add codegen for
                        // Send.
                        let val = state.getlocal(ep_offset);
                        state.stack_push(val);
                    }
                }
                YARVINSN_setlocal_WC_0 => {
                    // TODO(alan): This implementation doesn't write to EP, where nested scopes
                    // read, so they'll miss these writes. This will need to be amended when we
                    // add codegen for Send.
                    let ep_offset = get_arg(pc, 0).as_u32();
                    let val = state.stack_pop()?;
                    state.setlocal(ep_offset, val);
                    if iseq_type == ISEQ_TYPE_EVAL {
                        // On eval, the locals are always on the heap, so write the local using EP.
                        fun.push_insn(block, Insn::SetLocal { val, ep_offset, level: 0 });
                    }
                }
                YARVINSN_getlocal_WC_1 => {
                    let ep_offset = get_arg(pc, 0).as_u32();
                    state.stack_push(fun.push_insn(block, Insn::GetLocal { ep_offset, level: 1 }));
                }
                YARVINSN_setlocal_WC_1 => {
                    let ep_offset = get_arg(pc, 0).as_u32();
                    fun.push_insn(block, Insn::SetLocal { val: state.stack_pop()?, ep_offset, level: 1 });
                }
                YARVINSN_getlocal => {
                    let ep_offset = get_arg(pc, 0).as_u32();
                    let level = get_arg(pc, 1).as_u32();
                    state.stack_push(fun.push_insn(block, Insn::GetLocal { ep_offset, level }));
                }
                YARVINSN_setlocal => {
                    let ep_offset = get_arg(pc, 0).as_u32();
                    let level = get_arg(pc, 1).as_u32();
                    fun.push_insn(block, Insn::SetLocal { val: state.stack_pop()?, ep_offset, level });
                }
                YARVINSN_pop => { state.stack_pop()?; }
                YARVINSN_dup => { state.stack_push(state.stack_top()?); }
                YARVINSN_dupn => {
                    // Duplicate the top N element of the stack. As we push, n-1 naturally
                    // points higher in the original stack.
                    let n = get_arg(pc, 0).as_usize();
                    for _ in 0..n {
                        state.stack_push(state.stack_topn(n-1)?);
                    }
                }
                YARVINSN_swap => {
                    let right = state.stack_pop()?;
                    let left = state.stack_pop()?;
                    state.stack_push(right);
                    state.stack_push(left);
                }
                YARVINSN_setn => {
                    let n = get_arg(pc, 0).as_usize();
                    let top = state.stack_top()?;
                    state.stack_setn(n, top);
                }
                YARVINSN_topn => {
                    let n = get_arg(pc, 0).as_usize();
                    let top = state.stack_topn(n)?;
                    state.stack_push(top);
                }
                YARVINSN_adjuststack => {
                    let mut n = get_arg(pc, 0).as_usize();
                    while n > 0 {
                        state.stack_pop()?;
                        n -= 1;
                    }
                }
                YARVINSN_opt_aref_with => {
                    // NB: opt_aref_with has an instruction argument for the call at get_arg(0)
                    let cd: *const rb_call_data = get_arg(pc, 1).as_ptr();
                    let call_info = unsafe { rb_get_call_data_ci(cd) };
                    if unknown_call_type(unsafe { rb_vm_ci_flag(call_info) }) {
                        // Unknown call type; side-exit into the interpreter
                        let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnknownCallType });
                        break;  // End the block
                    }
                    let argc = unsafe { vm_ci_argc((*cd).ci) };

                    assert_eq!(1, argc, "opt_aref_with should only be emitted for argc=1");
                    let aref_arg = fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) });
                    let args = vec![aref_arg];

                    let recv = state.stack_pop()?;
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let send = fun.push_insn(block, Insn::SendWithoutBlock { self_val: recv, cd, args, state: exit_id });
                    state.stack_push(send);
                }
                YARVINSN_opt_neq => {
                    // NB: opt_neq has two cd; get_arg(0) is for eq and get_arg(1) is for neq
                    let cd: *const rb_call_data = get_arg(pc, 1).as_ptr();
                    let call_info = unsafe { rb_get_call_data_ci(cd) };
                    if unknown_call_type(unsafe { rb_vm_ci_flag(call_info) }) {
                        // Unknown call type; side-exit into the interpreter
                        let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnknownCallType });
                        break;  // End the block
                    }
                    let argc = unsafe { vm_ci_argc((*cd).ci) };

                    let mut args = vec![];
                    for _ in 0..argc {
                        args.push(state.stack_pop()?);
                    }
                    args.reverse();

                    let recv = state.stack_pop()?;
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let send = fun.push_insn(block, Insn::SendWithoutBlock { self_val: recv, cd, args, state: exit_id });
                    state.stack_push(send);
                }
                YARVINSN_opt_hash_freeze |
                YARVINSN_opt_ary_freeze |
                YARVINSN_opt_str_freeze |
                YARVINSN_opt_str_uminus => {
                    // NB: these instructions have the recv for the call at get_arg(0)
                    let cd: *const rb_call_data = get_arg(pc, 1).as_ptr();
                    let call_info = unsafe { rb_get_call_data_ci(cd) };
                    if unknown_call_type(unsafe { rb_vm_ci_flag(call_info) }) {
                        // Unknown call type; side-exit into the interpreter
                        let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnknownCallType });
                        break;  // End the block
                    }
                    let argc = unsafe { vm_ci_argc((*cd).ci) };
                    let name = insn_name(opcode as usize);
                    assert_eq!(0, argc, "{name} should not have args");
                    let args = vec![];

                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let recv = fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) });
                    let send = fun.push_insn(block, Insn::SendWithoutBlock { self_val: recv, cd, args, state: exit_id });
                    state.stack_push(send);
                }

                YARVINSN_leave => {
                    fun.push_insn(block, Insn::Return { val: state.stack_pop()? });
                    break;  // Don't enqueue the next block as a successor
                }
                YARVINSN_throw => {
                    fun.push_insn(block, Insn::Throw { throw_state: get_arg(pc, 0).as_u32(), val: state.stack_pop()? });
                    break;  // Don't enqueue the next block as a successor
                }

                // These are opt_send_without_block and all the opt_* instructions
                // specialized to a certain method that could also be serviced
                // using the general send implementation. The optimizer start from
                // a general send for all of these later in the pipeline.
                YARVINSN_opt_nil_p |
                YARVINSN_opt_plus |
                YARVINSN_opt_minus |
                YARVINSN_opt_mult |
                YARVINSN_opt_div |
                YARVINSN_opt_mod |
                YARVINSN_opt_eq |
                YARVINSN_opt_lt |
                YARVINSN_opt_le |
                YARVINSN_opt_gt |
                YARVINSN_opt_ge |
                YARVINSN_opt_ltlt |
                YARVINSN_opt_aset |
                YARVINSN_opt_length |
                YARVINSN_opt_size |
                YARVINSN_opt_aref |
                YARVINSN_opt_empty_p |
                YARVINSN_opt_succ |
                YARVINSN_opt_and |
                YARVINSN_opt_or |
                YARVINSN_opt_not |
                YARVINSN_opt_regexpmatch2 |
                YARVINSN_opt_send_without_block => {
                    let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                    let call_info = unsafe { rb_get_call_data_ci(cd) };
                    if unknown_call_type(unsafe { rb_vm_ci_flag(call_info) }) {
                        // Unknown call type; side-exit into the interpreter
                        let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnknownCallType });
                        break;  // End the block
                    }
                    let argc = unsafe { vm_ci_argc((*cd).ci) };

                    let mut args = vec![];
                    for _ in 0..argc {
                        args.push(state.stack_pop()?);
                    }
                    args.reverse();

                    let recv = state.stack_pop()?;
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let send = fun.push_insn(block, Insn::SendWithoutBlock { self_val: recv, cd, args, state: exit_id });
                    state.stack_push(send);
                }
                YARVINSN_send => {
                    let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                    let blockiseq: IseqPtr = get_arg(pc, 1).as_iseq();
                    let call_info = unsafe { rb_get_call_data_ci(cd) };
                    if unknown_call_type(unsafe { rb_vm_ci_flag(call_info) }) {
                        // Unknown call type; side-exit into the interpreter
                        let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnknownCallType });
                        break;  // End the block
                    }
                    let argc = unsafe { vm_ci_argc((*cd).ci) };

                    let mut args = vec![];
                    for _ in 0..argc {
                        args.push(state.stack_pop()?);
                    }
                    args.reverse();

                    let recv = state.stack_pop()?;
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let send = fun.push_insn(block, Insn::Send { self_val: recv, cd, blockiseq, args, state: exit_id });
                    state.stack_push(send);
                }
                YARVINSN_getglobal => {
                    let id = ID(get_arg(pc, 0).as_u64());
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let result = fun.push_insn(block, Insn::GetGlobal { id, state: exit_id });
                    state.stack_push(result);
                }
                YARVINSN_setglobal => {
                    let id = ID(get_arg(pc, 0).as_u64());
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let val = state.stack_pop()?;
                    fun.push_insn(block, Insn::SetGlobal { id, val, state: exit_id });
                }
                YARVINSN_getinstancevariable => {
                    let id = ID(get_arg(pc, 0).as_u64());
                    // ic is in arg 1
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let result = fun.push_insn(block, Insn::GetIvar { self_val: self_param, id, state: exit_id });
                    state.stack_push(result);
                }
                YARVINSN_setinstancevariable => {
                    let id = ID(get_arg(pc, 0).as_u64());
                    // ic is in arg 1
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let val = state.stack_pop()?;
                    fun.push_insn(block, Insn::SetIvar { self_val: self_param, id, val, state: exit_id });
                }
                YARVINSN_opt_reverse => {
                    // Reverse the order of the top N stack items.
                    let n = get_arg(pc, 0).as_usize();
                    for i in 0..n/2 {
                        let bottom = state.stack_topn(n - 1 - i)?;
                        let top = state.stack_topn(i)?;
                        state.stack_setn(i, bottom);
                        state.stack_setn(n - 1 - i, top);
                    }
                }
                YARVINSN_newrange => {
                    let flag = RangeType::from(get_arg(pc, 0).as_u32());
                    let high = state.stack_pop()?;
                    let low = state.stack_pop()?;
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let insn_id = fun.push_insn(block, Insn::NewRange { low, high, flag, state: exit_id });
                    state.stack_push(insn_id);
                }
                YARVINSN_invokebuiltin => {
                    let bf: rb_builtin_function = unsafe { *get_arg(pc, 0).as_ptr() };

                    let mut args = vec![];
                    for _ in 0..bf.argc {
                        args.push(state.stack_pop()?);
                    }
                    args.push(self_param);
                    args.reverse();

                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });

                    // Check if this builtin is annotated
                    let return_type = ZJITState::get_method_annotations()
                        .get_builtin_properties(&bf)
                        .map(|props| props.return_type);

                    let insn_id = fun.push_insn(block, Insn::InvokeBuiltin {
                        bf,
                        args,
                        state: exit_id,
                        return_type,
                    });
                    state.stack_push(insn_id);
                }
                YARVINSN_opt_invokebuiltin_delegate |
                YARVINSN_opt_invokebuiltin_delegate_leave => {
                    let bf: rb_builtin_function = unsafe { *get_arg(pc, 0).as_ptr() };
                    let index = get_arg(pc, 1).as_usize();
                    let argc = bf.argc as usize;

                    let mut args = vec![self_param];
                    for &local in state.locals().skip(index).take(argc) {
                        args.push(local);
                    }

                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });

                    // Check if this builtin is annotated
                    let return_type = ZJITState::get_method_annotations()
                        .get_builtin_properties(&bf)
                        .map(|props| props.return_type);

                    let insn_id = fun.push_insn(block, Insn::InvokeBuiltin {
                        bf,
                        args,
                        state: exit_id,
                        return_type,
                    });
                    state.stack_push(insn_id);
                }
                YARVINSN_objtostring => {
                    let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                    let call_info = unsafe { rb_get_call_data_ci(cd) };

                    if unknown_call_type(unsafe { rb_vm_ci_flag(call_info) }) {
                        assert!(false, "objtostring should not have unknown call type");
                    }
                    let argc = unsafe { vm_ci_argc((*cd).ci) };
                    assert_eq!(0, argc, "objtostring should not have args");

                    let recv = state.stack_pop()?;
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let objtostring = fun.push_insn(block, Insn::ObjToString { val: recv, cd, state: exit_id });
                    state.stack_push(objtostring)
                }
                YARVINSN_anytostring => {
                    let str = state.stack_pop()?;
                    let val = state.stack_pop()?;

                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    let anytostring = fun.push_insn(block, Insn::AnyToString { val, str, state: exit_id });
                    state.stack_push(anytostring);
                }
                _ => {
                    // Unknown opcode; side-exit into the interpreter
                    let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnknownOpcode(opcode) });
                    break;  // End the block
                }
            }

            if insn_idx_to_block.contains_key(&insn_idx) {
                let target = insn_idx_to_block[&insn_idx];
                fun.push_insn(block, Insn::Jump(BranchEdge { target, args: state.as_args(self_param) }));
                queue.push_back((state, target, insn_idx));
                break;  // End the block
            }
        }
    }

    fun.infer_types();

    match get_option!(dump_hir_init) {
        Some(DumpHIR::WithoutSnapshot) => println!("Initial HIR:\n{}", FunctionPrinter::without_snapshot(&fun)),
        Some(DumpHIR::All) => println!("Initial HIR:\n{}", FunctionPrinter::with_snapshot(&fun)),
        Some(DumpHIR::Debug) => println!("Initial HIR:\n{:#?}", &fun),
        None => {},
    }

    fun.profiles = Some(profiles);
    if let Err(e) = fun.validate() {
        return Err(ParseError::Validation(e));
    }
    Ok(fun)
}

#[cfg(test)]
mod union_find_tests {
    use super::UnionFind;

    #[test]
    fn test_find_returns_self() {
        let mut uf = UnionFind::new();
        assert_eq!(uf.find(3usize), 3);
    }

    #[test]
    fn test_find_returns_target() {
        let mut uf = UnionFind::new();
        uf.make_equal_to(3, 4);
        assert_eq!(uf.find(3usize), 4);
    }

    #[test]
    fn test_find_returns_transitive_target() {
        let mut uf = UnionFind::new();
        uf.make_equal_to(3, 4);
        uf.make_equal_to(4, 5);
        assert_eq!(uf.find(3usize), 5);
        assert_eq!(uf.find(4usize), 5);
    }

    #[test]
    fn test_find_compresses_path() {
        let mut uf = UnionFind::new();
        uf.make_equal_to(3, 4);
        uf.make_equal_to(4, 5);
        assert_eq!(uf.at(3usize), Some(4));
        assert_eq!(uf.find(3usize), 5);
        assert_eq!(uf.at(3usize), Some(5));
    }
}

#[cfg(test)]
mod rpo_tests {
    use super::*;

    #[test]
    fn one_block() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let val = function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        function.push_insn(entry, Insn::Return { val });
        assert_eq!(function.rpo(), vec![entry]);
    }

    #[test]
    fn jump() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let exit = function.new_block(0);
        function.push_insn(entry, Insn::Jump(BranchEdge { target: exit, args: vec![] }));
        let val = function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        function.push_insn(entry, Insn::Return { val });
        assert_eq!(function.rpo(), vec![entry, exit]);
    }

    #[test]
    fn diamond_iftrue() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let side = function.new_block(0);
        let exit = function.new_block(0);
        function.push_insn(side, Insn::Jump(BranchEdge { target: exit, args: vec![] }));
        let val = function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        function.push_insn(entry, Insn::IfTrue { val, target: BranchEdge { target: side, args: vec![] } });
        function.push_insn(entry, Insn::Jump(BranchEdge { target: exit, args: vec![] }));
        let val = function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        function.push_insn(entry, Insn::Return { val });
        assert_eq!(function.rpo(), vec![entry, side, exit]);
    }

    #[test]
    fn diamond_iffalse() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let side = function.new_block(0);
        let exit = function.new_block(0);
        function.push_insn(side, Insn::Jump(BranchEdge { target: exit, args: vec![] }));
        let val = function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        function.push_insn(entry, Insn::IfFalse { val, target: BranchEdge { target: side, args: vec![] } });
        function.push_insn(entry, Insn::Jump(BranchEdge { target: exit, args: vec![] }));
        let val = function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        function.push_insn(entry, Insn::Return { val });
        assert_eq!(function.rpo(), vec![entry, side, exit]);
    }

    #[test]
    fn a_loop() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        function.push_insn(entry, Insn::Jump(BranchEdge { target: entry, args: vec![] }));
        assert_eq!(function.rpo(), vec![entry]);
    }
}

#[cfg(test)]
mod validation_tests {
    use super::*;

    #[track_caller]
    fn assert_matches_err(res: Result<(), ValidationError>, expected: ValidationError) {
        match res {
            Err(validation_err) => {
                assert_eq!(validation_err, expected);
            }
            Ok(_) => assert!(false, "Expected validation error"),
        }
    }

    #[test]
    fn one_block_no_terminator() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        assert_matches_err(function.validate(), ValidationError::BlockHasNoTerminator(entry));
    }

    #[test]
    fn one_block_terminator_not_at_end() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let val = function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        let insn_id = function.push_insn(entry, Insn::Return { val });
        function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        assert_matches_err(function.validate(), ValidationError::TerminatorNotAtEnd(entry, insn_id, 1));
    }

    #[test]
    fn iftrue_mismatch_args() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let side = function.new_block(0);
        let val = function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        function.push_insn(entry, Insn::IfTrue { val, target: BranchEdge { target: side, args: vec![val, val, val] } });
        assert_matches_err(function.validate(), ValidationError::MismatchedBlockArity(entry, 0, 3));
    }

    #[test]
    fn iffalse_mismatch_args() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let side = function.new_block(0);
        let val = function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        function.push_insn(entry, Insn::IfFalse { val, target: BranchEdge { target: side, args: vec![val, val, val] } });
        assert_matches_err(function.validate(), ValidationError::MismatchedBlockArity(entry, 0, 3));
    }

    #[test]
    fn jump_mismatch_args() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let side = function.new_block(0);
        let val = function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        function.push_insn(entry, Insn::Jump ( BranchEdge { target: side, args: vec![val, val, val] } ));
        assert_matches_err(function.validate(), ValidationError::MismatchedBlockArity(entry, 0, 3));
    }

    #[test]
    fn not_defined_within_bb() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        // Create an instruction without making it belong to anything.
        let dangling = function.new_insn(Insn::Const{val: Const::CBool(true)});
        let val = function.push_insn(function.entry_block, Insn::ArrayDup { val: dangling, state: InsnId(0usize) });
        assert_matches_err(function.validate_definite_assignment(), ValidationError::OperandNotDefined(entry, val, dangling));
    }

    #[test]
    fn using_non_output_insn() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let const_ = function.push_insn(function.entry_block, Insn::Const{val: Const::CBool(true)});
        // Ret is a non-output instruction.
        let ret = function.push_insn(function.entry_block, Insn::Return { val: const_ });
        let val = function.push_insn(function.entry_block, Insn::ArrayDup { val: ret, state: InsnId(0usize) });
        assert_matches_err(function.validate_definite_assignment(), ValidationError::OperandNotDefined(entry, val, ret));
    }

    #[test]
    fn not_dominated_by_diamond() {
        // This tests that one branch is missing a definition which fails.
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let side = function.new_block(0);
        let exit = function.new_block(0);
        let v0 = function.push_insn(side, Insn::Const { val: Const::Value(VALUE::fixnum_from_usize(3)) });
        function.push_insn(side, Insn::Jump(BranchEdge { target: exit, args: vec![] }));
        let val1 = function.push_insn(entry, Insn::Const { val: Const::CBool(false) });
        function.push_insn(entry, Insn::IfFalse { val: val1, target: BranchEdge { target: side, args: vec![] } });
        function.push_insn(entry, Insn::Jump(BranchEdge { target: exit, args: vec![] }));
        let val2 = function.push_insn(exit, Insn::ArrayDup { val: v0, state: v0 });
        crate::cruby::with_rubyvm(|| {
            function.infer_types();
            assert_matches_err(function.validate_definite_assignment(), ValidationError::OperandNotDefined(exit, val2, v0));
        });
    }

    #[test]
    fn dominated_by_diamond() {
        // This tests that both branches with a definition succeeds.
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let side = function.new_block(0);
        let exit = function.new_block(0);
        let v0 = function.push_insn(entry, Insn::Const { val: Const::Value(VALUE::fixnum_from_usize(3)) });
        function.push_insn(side, Insn::Jump(BranchEdge { target: exit, args: vec![] }));
        let val = function.push_insn(entry, Insn::Const { val: Const::CBool(false) });
        function.push_insn(entry, Insn::IfFalse { val, target: BranchEdge { target: side, args: vec![] } });
        function.push_insn(entry, Insn::Jump(BranchEdge { target: exit, args: vec![] }));
        let _val = function.push_insn(exit, Insn::ArrayDup { val: v0, state: v0 });
        crate::cruby::with_rubyvm(|| {
            function.infer_types();
            // Just checking that we don't panic.
            assert!(function.validate_definite_assignment().is_ok());
        });
    }

    #[test]
    fn instruction_appears_twice_in_same_block() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let val = function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        function.push_insn_id(entry, val);
        function.push_insn(entry, Insn::Return { val });
        assert_matches_err(function.validate(), ValidationError::DuplicateInstruction(entry, val));
    }

    #[test]
    fn instruction_appears_twice_with_different_ids() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let val0 = function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        let val1 = function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        function.make_equal_to(val1, val0);
        function.push_insn(entry, Insn::Return { val: val0 });
        assert_matches_err(function.validate(), ValidationError::DuplicateInstruction(entry, val0));
    }

    #[test]
    fn instruction_appears_twice_in_different_blocks() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let val = function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        let exit = function.new_block(0);
        function.push_insn(entry, Insn::Jump(BranchEdge { target: exit, args: vec![] }));
        function.push_insn_id(exit, val);
        function.push_insn(exit, Insn::Return { val });
        assert_matches_err(function.validate(), ValidationError::DuplicateInstruction(exit, val));
    }
}

#[cfg(test)]
mod infer_tests {
    use super::*;

    #[track_caller]
    fn assert_subtype(left: Type, right: Type) {
        assert!(left.is_subtype(right), "{left} is not a subtype of {right}");
    }

    #[track_caller]
    fn assert_bit_equal(left: Type, right: Type) {
        assert!(left.bit_equal(right), "{left} != {right}");
    }

    #[test]
    fn test_const() {
        let mut function = Function::new(std::ptr::null());
        let val = function.push_insn(function.entry_block, Insn::Const { val: Const::Value(Qnil) });
        assert_bit_equal(function.infer_type(val), types::NilClass);
    }

    #[test]
    fn test_nil() {
        crate::cruby::with_rubyvm(|| {
            let mut function = Function::new(std::ptr::null());
            let nil = function.push_insn(function.entry_block, Insn::Const { val: Const::Value(Qnil) });
            let val = function.push_insn(function.entry_block, Insn::Test { val: nil });
            function.infer_types();
            assert_bit_equal(function.type_of(val), Type::from_cbool(false));
        });
    }

    #[test]
    fn test_false() {
        crate::cruby::with_rubyvm(|| {
            let mut function = Function::new(std::ptr::null());
            let false_ = function.push_insn(function.entry_block, Insn::Const { val: Const::Value(Qfalse) });
            let val = function.push_insn(function.entry_block, Insn::Test { val: false_ });
            function.infer_types();
            assert_bit_equal(function.type_of(val), Type::from_cbool(false));
        });
    }

    #[test]
    fn test_truthy() {
        crate::cruby::with_rubyvm(|| {
            let mut function = Function::new(std::ptr::null());
            let true_ = function.push_insn(function.entry_block, Insn::Const { val: Const::Value(Qtrue) });
            let val = function.push_insn(function.entry_block, Insn::Test { val: true_ });
            function.infer_types();
            assert_bit_equal(function.type_of(val), Type::from_cbool(true));
        });
    }

    #[test]
    fn test_unknown() {
        crate::cruby::with_rubyvm(|| {
            let mut function = Function::new(std::ptr::null());
            let param = function.push_insn(function.entry_block, Insn::Param { idx: SELF_PARAM_IDX });
            function.param_types.push(types::BasicObject); // self
            let val = function.push_insn(function.entry_block, Insn::Test { val: param });
            function.infer_types();
            assert_bit_equal(function.type_of(val), types::CBool);
        });
    }

    #[test]
    fn newarray() {
        let mut function = Function::new(std::ptr::null());
        // Fake FrameState index of 0usize
        let val = function.push_insn(function.entry_block, Insn::NewArray { elements: vec![], state: InsnId(0usize) });
        assert_bit_equal(function.infer_type(val), types::ArrayExact);
    }

    #[test]
    fn arraydup() {
        let mut function = Function::new(std::ptr::null());
        // Fake FrameState index of 0usize
        let arr = function.push_insn(function.entry_block, Insn::NewArray { elements: vec![], state: InsnId(0usize) });
        let val = function.push_insn(function.entry_block, Insn::ArrayDup { val: arr, state: InsnId(0usize) });
        assert_bit_equal(function.infer_type(val), types::ArrayExact);
    }

    #[test]
    fn diamond_iffalse_merge_fixnum() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let side = function.new_block(0);
        let exit = function.new_block(0);
        let v0 = function.push_insn(side, Insn::Const { val: Const::Value(VALUE::fixnum_from_usize(3)) });
        function.push_insn(side, Insn::Jump(BranchEdge { target: exit, args: vec![v0] }));
        let val = function.push_insn(entry, Insn::Const { val: Const::CBool(false) });
        function.push_insn(entry, Insn::IfFalse { val, target: BranchEdge { target: side, args: vec![] } });
        let v1 = function.push_insn(entry, Insn::Const { val: Const::Value(VALUE::fixnum_from_usize(4)) });
        function.push_insn(entry, Insn::Jump(BranchEdge { target: exit, args: vec![v1] }));
        let param = function.push_insn(exit, Insn::Param { idx: 0 });
        crate::cruby::with_rubyvm(|| {
            function.infer_types();
        });
        assert_bit_equal(function.type_of(param), types::Fixnum);
    }

    #[test]
    fn diamond_iffalse_merge_bool() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let side = function.new_block(0);
        let exit = function.new_block(0);
        let v0 = function.push_insn(side, Insn::Const { val: Const::Value(Qtrue) });
        function.push_insn(side, Insn::Jump(BranchEdge { target: exit, args: vec![v0] }));
        let val = function.push_insn(entry, Insn::Const { val: Const::CBool(false) });
        function.push_insn(entry, Insn::IfFalse { val, target: BranchEdge { target: side, args: vec![] } });
        let v1 = function.push_insn(entry, Insn::Const { val: Const::Value(Qfalse) });
        function.push_insn(entry, Insn::Jump(BranchEdge { target: exit, args: vec![v1] }));
        let param = function.push_insn(exit, Insn::Param { idx: 0 });
        crate::cruby::with_rubyvm(|| {
            function.infer_types();
            assert_bit_equal(function.type_of(param), types::TrueClass.union(types::FalseClass));
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use expect_test::{expect, Expect};

    #[macro_export]
    macro_rules! assert_matches {
        ( $x:expr, $pat:pat ) => {
            {
                let val = $x;
                if (!matches!(val, $pat)) {
                    eprintln!("{} ({:?}) does not match pattern {}", stringify!($x), val, stringify!($pat));
                    assert!(false);
                }
            }
        };
    }


    #[track_caller]
    fn assert_matches_value(insn: Option<&Insn>, val: VALUE) {
        match insn {
            Some(Insn::Const { val: Const::Value(spec) }) => {
                assert_eq!(*spec, val);
            }
            _ => assert!(false, "Expected Const {val}, found {insn:?}"),
        }
    }

    #[track_caller]
    fn assert_matches_const(insn: Option<&Insn>, expected: Const) {
        match insn {
            Some(Insn::Const { val }) => {
                assert_eq!(*val, expected, "{val:?} does not match {expected:?}");
            }
            _ => assert!(false, "Expected Const {expected:?}, found {insn:?}"),
        }
    }

    #[track_caller]
    fn assert_method_hir(method: &str, hir: Expect) {
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("self", method));
        unsafe { crate::cruby::rb_zjit_profile_disable(iseq) };
        let function = iseq_to_hir(iseq).unwrap();
        assert_function_hir(function, hir);
    }

    fn iseq_contains_opcode(iseq: IseqPtr, expected_opcode: u32) -> bool {
        let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
        let mut insn_idx = 0;
        while insn_idx < iseq_size {
            // Get the current pc and opcode
            let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx) };

            // try_into() call below is unfortunate. Maybe pick i32 instead of usize for opcodes.
            let opcode: u32 = unsafe { rb_iseq_opcode_at_pc(iseq, pc) }
                .try_into()
                .unwrap();
            if opcode == expected_opcode {
                return true;
            }
            insn_idx += insn_len(opcode as usize);
        }
        false
    }

    #[track_caller]
    fn assert_method_hir_with_opcodes(method: &str, opcodes: &[u32], hir: Expect) {
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("self", method));
        unsafe { crate::cruby::rb_zjit_profile_disable(iseq) };
        for &opcode in opcodes {
            assert!(iseq_contains_opcode(iseq, opcode), "iseq {method} does not contain {}", insn_name(opcode as usize));
        }
        let function = iseq_to_hir(iseq).unwrap();
        assert_function_hir(function, hir);
    }

    #[track_caller]
    fn assert_method_hir_with_opcode(method: &str, opcode: u32, hir: Expect) {
        assert_method_hir_with_opcodes(method, &[opcode], hir)
    }

    #[track_caller]
    pub fn assert_function_hir(function: Function, expected_hir: Expect) {
        let actual_hir = format!("{}", FunctionPrinter::without_snapshot(&function));
        expected_hir.assert_eq(&actual_hir);
    }

    #[track_caller]
    fn assert_compile_fails(method: &str, reason: ParseError) {
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("self", method));
        unsafe { crate::cruby::rb_zjit_profile_disable(iseq) };
        let result = iseq_to_hir(iseq);
        assert!(result.is_err(), "Expected an error but successfully compiled to HIR: {}", FunctionPrinter::without_snapshot(&result.unwrap()));
        assert_eq!(result.unwrap_err(), reason);
    }

    #[test]
    fn test_cant_compile_optional() {
        eval("def test(x=1) = 123");
        assert_compile_fails("test", ParseError::UnknownParameterType(ParameterType::Optional));
    }

    #[test]
    fn test_putobject() {
        eval("def test = 123");
        assert_method_hir_with_opcode("test", YARVINSN_putobject, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject):
              v2:Fixnum[123] = Const Value(123)
              Return v2
        "#]]);
    }

    #[test]
    fn test_new_array() {
        eval("def test = []");
        assert_method_hir_with_opcode("test", YARVINSN_newarray, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject):
              v3:ArrayExact = NewArray
              Return v3
        "#]]);
    }

    #[test]
    fn test_new_array_with_element() {
        eval("def test(a) = [a]");
        assert_method_hir_with_opcode("test", YARVINSN_newarray, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject, v1:BasicObject):
              v4:ArrayExact = NewArray v1
              Return v4
        "#]]);
    }

    #[test]
    fn test_new_array_with_elements() {
        eval("def test(a, b) = [a, b]");
        assert_method_hir_with_opcode("test", YARVINSN_newarray, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:ArrayExact = NewArray v1, v2
              Return v5
        "#]]);
    }

    #[test]
    fn test_new_range_inclusive_with_one_element() {
        eval("def test(a) = (a..10)");
        assert_method_hir_with_opcode("test", YARVINSN_newrange, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:Fixnum[10] = Const Value(10)
              v5:RangeExact = NewRange v1 NewRangeInclusive v3
              Return v5
        "#]]);
    }

    #[test]
    fn test_new_range_inclusive_with_two_elements() {
        eval("def test(a, b) = (a..b)");
        assert_method_hir_with_opcode("test", YARVINSN_newrange, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:RangeExact = NewRange v1 NewRangeInclusive v2
              Return v5
        "#]]);
    }

    #[test]
    fn test_new_range_exclusive_with_one_element() {
        eval("def test(a) = (a...10)");
        assert_method_hir_with_opcode("test", YARVINSN_newrange, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:Fixnum[10] = Const Value(10)
              v5:RangeExact = NewRange v1 NewRangeExclusive v3
              Return v5
        "#]]);
    }

    #[test]
    fn test_new_range_exclusive_with_two_elements() {
        eval("def test(a, b) = (a...b)");
        assert_method_hir_with_opcode("test", YARVINSN_newrange, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:RangeExact = NewRange v1 NewRangeExclusive v2
              Return v5
        "#]]);
    }

    #[test]
    fn test_array_dup() {
        eval("def test = [1, 2, 3]");
        assert_method_hir_with_opcode("test", YARVINSN_duparray, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject):
              v2:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v4:ArrayExact = ArrayDup v2
              Return v4
        "#]]);
    }

    #[test]
    fn test_hash_dup() {
        eval("def test = {a: 1, b: 2}");
        assert_method_hir_with_opcode("test", YARVINSN_duphash, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject):
              v2:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v4:HashExact = HashDup v2
              Return v4
        "#]]);
    }

    #[test]
    fn test_new_hash_empty() {
        eval("def test = {}");
        assert_method_hir_with_opcode("test", YARVINSN_newhash, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject):
              v3:HashExact = NewHash
              Return v3
        "#]]);
    }

    #[test]
    fn test_new_hash_with_elements() {
        eval("def test(aval, bval) = {a: aval, b: bval}");
        assert_method_hir_with_opcode("test", YARVINSN_newhash, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v4:StaticSymbol[:a] = Const Value(VALUE(0x1000))
              v5:StaticSymbol[:b] = Const Value(VALUE(0x1008))
              v7:HashExact = NewHash v4: v1, v5: v2
              Return v7
        "#]]);
    }

    #[test]
    fn test_string_copy() {
        eval("def test = \"hello\"");
        assert_method_hir_with_opcode("test", YARVINSN_putchilledstring, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject):
              v2:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v3:StringExact = StringCopy v2
              Return v3
        "#]]);
    }

    #[test]
    fn test_bignum() {
        eval("def test = 999999999999999999999999999999999999");
        assert_method_hir_with_opcode("test", YARVINSN_putobject, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject):
              v2:Bignum[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              Return v2
        "#]]);
    }

    #[test]
    fn test_flonum() {
        eval("def test = 1.5");
        assert_method_hir_with_opcode("test", YARVINSN_putobject, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject):
              v2:Flonum[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              Return v2
        "#]]);
    }

    #[test]
    fn test_heap_float() {
        eval("def test = 1.7976931348623157e+308");
        assert_method_hir_with_opcode("test", YARVINSN_putobject, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject):
              v2:HeapFloat[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              Return v2
        "#]]);
    }

    #[test]
    fn test_static_sym() {
        eval("def test = :foo");
        assert_method_hir_with_opcode("test", YARVINSN_putobject, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject):
              v2:StaticSymbol[:foo] = Const Value(VALUE(0x1000))
              Return v2
        "#]]);
    }

    #[test]
    fn test_opt_plus() {
        eval("def test = 1+2");
        assert_method_hir_with_opcode("test", YARVINSN_opt_plus, expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              v3:Fixnum[2] = Const Value(2)
              v5:BasicObject = SendWithoutBlock v2, :+, v3
              Return v5
        "#]]);
    }

    #[test]
    fn test_opt_hash_freeze() {
        eval("
            def test = {}.freeze
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_hash_freeze, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v4:BasicObject = SendWithoutBlock v3, :freeze
              Return v4
        "#]]);
    }

    #[test]
    fn test_opt_ary_freeze() {
        eval("
            def test = [].freeze
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_ary_freeze, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v4:BasicObject = SendWithoutBlock v3, :freeze
              Return v4
        "#]]);
    }

    #[test]
    fn test_opt_str_freeze() {
        eval("
            def test = ''.freeze
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_str_freeze, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v4:BasicObject = SendWithoutBlock v3, :freeze
              Return v4
        "#]]);
    }

    #[test]
    fn test_opt_str_uminus() {
        eval("
            def test = -''
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_str_uminus, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v4:BasicObject = SendWithoutBlock v3, :-@
              Return v4
        "#]]);
    }

    #[test]
    fn test_setlocal_getlocal() {
        eval("
            def test
              a = 1
              a
            end
        ");
        assert_method_hir_with_opcodes("test", &[YARVINSN_getlocal_WC_0, YARVINSN_setlocal_WC_0], expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v1:NilClass = Const Value(nil)
              v3:Fixnum[1] = Const Value(1)
              Return v3
        "#]]);
    }

    #[test]
    fn test_nested_setlocal_getlocal() {
        eval("
          l3 = 3
          _unused = _unused1 = nil
          1.times do |l2|
            _ = nil
            l2 = 2
            1.times do |l1|
              l1 = 1
              define_method(:test) do
                l1 = l2
                l2 = l1 + l2
                l3 = l2 + l3
              end
            end
          end
        ");
        assert_method_hir_with_opcodes(
            "test",
            &[YARVINSN_getlocal_WC_1, YARVINSN_setlocal_WC_1,
              YARVINSN_getlocal, YARVINSN_setlocal],
            expect![[r#"
                fn block (3 levels) in <compiled>@<compiled>:10:
                bb0(v0:BasicObject):
                  v2:BasicObject = GetLocal l2, EP@4
                  SetLocal l1, EP@3, v2
                  v4:BasicObject = GetLocal l1, EP@3
                  v5:BasicObject = GetLocal l2, EP@4
                  v7:BasicObject = SendWithoutBlock v4, :+, v5
                  SetLocal l2, EP@4, v7
                  v9:BasicObject = GetLocal l2, EP@4
                  v10:BasicObject = GetLocal l3, EP@5
                  v12:BasicObject = SendWithoutBlock v9, :+, v10
                  SetLocal l3, EP@5, v12
                  Return v12
            "#]]
        );
    }

    #[test]
    fn defined_ivar() {
        eval("
            def test = defined?(@foo)
        ");
        assert_method_hir_with_opcode("test", YARVINSN_definedivar, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:BasicObject = DefinedIvar v0, :@foo
              Return v3
        "#]]);
    }

    #[test]
    fn defined() {
        eval("
            def test = return defined?(SeaChange), defined?(favourite), defined?($ruby)
        ");
        assert_method_hir_with_opcode("test", YARVINSN_defined, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v2:NilClass = Const Value(nil)
              v3:BasicObject = Defined constant, v2
              v4:BasicObject = Defined func, v0
              v5:NilClass = Const Value(nil)
              v6:BasicObject = Defined global-variable, v5
              v8:ArrayExact = NewArray v3, v4, v6
              Return v8
        "#]]);
    }

    #[test]
    fn test_return_const() {
        eval("
            def test(cond)
              if cond
                3
              else
                4
              end
            end
        ");
        assert_method_hir_with_opcode("test", YARVINSN_leave, expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:CBool = Test v1
              IfFalse v3, bb1(v0, v1)
              v5:Fixnum[3] = Const Value(3)
              Return v5
            bb1(v7:BasicObject, v8:BasicObject):
              v10:Fixnum[4] = Const Value(4)
              Return v10
        "#]]);
    }

    #[test]
    fn test_merge_const() {
        eval("
            def test(cond)
              if cond
                result = 3
              else
                result = 4
              end
              result
            end
        ");
        assert_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject):
              v2:NilClass = Const Value(nil)
              v4:CBool = Test v1
              IfFalse v4, bb1(v0, v1, v2)
              v6:Fixnum[3] = Const Value(3)
              Jump bb2(v0, v1, v6)
            bb1(v8:BasicObject, v9:BasicObject, v10:NilClass):
              v12:Fixnum[4] = Const Value(4)
              Jump bb2(v8, v9, v12)
            bb2(v14:BasicObject, v15:BasicObject, v16:Fixnum):
              Return v16
        "#]]);
    }

    #[test]
    fn test_opt_plus_fixnum() {
        eval("
            def test(a, b) = a + b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:BasicObject = SendWithoutBlock v1, :+, v2
              Return v5
        "#]]);
    }

    #[test]
    fn test_opt_minus_fixnum() {
        eval("
            def test(a, b) = a - b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_minus, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:BasicObject = SendWithoutBlock v1, :-, v2
              Return v5
        "#]]);
    }

    #[test]
    fn test_opt_mult_fixnum() {
        eval("
            def test(a, b) = a * b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_mult, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:BasicObject = SendWithoutBlock v1, :*, v2
              Return v5
        "#]]);
    }

    #[test]
    fn test_opt_div_fixnum() {
        eval("
            def test(a, b) = a / b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_div, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:BasicObject = SendWithoutBlock v1, :/, v2
              Return v5
        "#]]);
    }

    #[test]
    fn test_opt_mod_fixnum() {
        eval("
            def test(a, b) = a % b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_mod, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:BasicObject = SendWithoutBlock v1, :%, v2
              Return v5
        "#]]);
    }

    #[test]
    fn test_opt_eq_fixnum() {
        eval("
            def test(a, b) = a == b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_eq, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:BasicObject = SendWithoutBlock v1, :==, v2
              Return v5
        "#]]);
    }

    #[test]
    fn test_opt_neq_fixnum() {
        eval("
            def test(a, b) = a != b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_neq, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:BasicObject = SendWithoutBlock v1, :!=, v2
              Return v5
        "#]]);
    }

    #[test]
    fn test_opt_lt_fixnum() {
        eval("
            def test(a, b) = a < b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_lt, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:BasicObject = SendWithoutBlock v1, :<, v2
              Return v5
        "#]]);
    }

    #[test]
    fn test_opt_le_fixnum() {
        eval("
            def test(a, b) = a <= b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_le, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:BasicObject = SendWithoutBlock v1, :<=, v2
              Return v5
        "#]]);
    }

    #[test]
    fn test_opt_gt_fixnum() {
        eval("
            def test(a, b) = a > b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_gt, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:BasicObject = SendWithoutBlock v1, :>, v2
              Return v5
        "#]]);
    }

    #[test]
    fn test_loop() {
        eval("
            def test
              result = 0
              times = 10
              while times > 0
                result = result + 1
                times = times - 1
              end
              result
            end
            test
        ");
        assert_method_hir("test",  expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v1:NilClass = Const Value(nil)
              v2:NilClass = Const Value(nil)
              v4:Fixnum[0] = Const Value(0)
              v5:Fixnum[10] = Const Value(10)
              Jump bb2(v0, v4, v5)
            bb2(v7:BasicObject, v8:BasicObject, v9:BasicObject):
              v11:Fixnum[0] = Const Value(0)
              v13:BasicObject = SendWithoutBlock v9, :>, v11
              v14:CBool = Test v13
              IfTrue v14, bb1(v7, v8, v9)
              v16:NilClass = Const Value(nil)
              Return v8
            bb1(v18:BasicObject, v19:BasicObject, v20:BasicObject):
              v22:Fixnum[1] = Const Value(1)
              v24:BasicObject = SendWithoutBlock v19, :+, v22
              v25:Fixnum[1] = Const Value(1)
              v27:BasicObject = SendWithoutBlock v20, :-, v25
              Jump bb2(v18, v24, v27)
        "#]]);
    }

    #[test]
    fn test_opt_ge_fixnum() {
        eval("
            def test(a, b) = a >= b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_ge, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:BasicObject = SendWithoutBlock v1, :>=, v2
              Return v5
        "#]]);
    }

    #[test]
    fn test_display_types() {
        eval("
            def test
              cond = true
              if cond
                3
              else
                4
              end
            end
        ");
        assert_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v1:NilClass = Const Value(nil)
              v3:TrueClass = Const Value(true)
              v4:CBool[true] = Test v3
              IfFalse v4, bb1(v0, v3)
              v6:Fixnum[3] = Const Value(3)
              Return v6
            bb1(v8, v9):
              v11 = Const Value(4)
              Return v11
        "#]]);
    }

    #[test]
    fn test_send_without_block() {
        eval("
            def bar(a, b)
              a+b
            end
            def test
              bar(2, 3)
            end
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_send_without_block, expect![[r#"
            fn test@<compiled>:6:
            bb0(v0:BasicObject):
              v2:Fixnum[2] = Const Value(2)
              v3:Fixnum[3] = Const Value(3)
              v5:BasicObject = SendWithoutBlock v0, :bar, v2, v3
              Return v5
        "#]]);
    }

    #[test]
    fn test_send_with_block() {
        eval("
            def test(a)
              a.each {|item|
                item
              }
            end
            test([1,2,3])
        ");
        assert_method_hir_with_opcode("test", YARVINSN_send, expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject):
              v4:BasicObject = Send v1, 0x1000, :each
              Return v4
        "#]]);
    }

    #[test]
    fn different_objects_get_addresses() {
        eval("def test = unknown_method([0], [1], '2', '2')");

        // The 2 string literals have the same address because they're deduped.
        assert_method_hir("test",  expect![[r#"
            fn test@<compiled>:1:
            bb0(v0:BasicObject):
              v2:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v4:ArrayExact = ArrayDup v2
              v5:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
              v7:ArrayExact = ArrayDup v5
              v8:StringExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
              v9:StringExact = StringCopy v8
              v10:StringExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
              v11:StringExact = StringCopy v10
              v13:BasicObject = SendWithoutBlock v0, :unknown_method, v4, v7, v9, v11
              Return v13
        "#]]);
    }

    #[test]
    fn test_cant_compile_splat() {
        eval("
            def test(a) = foo(*a)
        ");
        assert_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v4:ArrayExact = ToArray v1
              SideExit UnknownCallType
        "#]]);
    }

    #[test]
    fn test_cant_compile_block_arg() {
        eval("
            def test(a) = foo(&a)
        ");
        assert_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              SideExit UnknownCallType
        "#]]);
    }

    #[test]
    fn test_cant_compile_kwarg() {
        eval("
            def test(a) = foo(a: 1)
        ");
        assert_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:Fixnum[1] = Const Value(1)
              SideExit UnknownCallType
        "#]]);
    }

    #[test]
    fn test_cant_compile_kw_splat() {
        eval("
            def test(a) = foo(**a)
        ");
        assert_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              SideExit UnknownCallType
        "#]]);
    }

    // TODO(max): Figure out how to generate a call with TAILCALL flag

    #[test]
    fn test_cant_compile_super() {
        eval("
            def test = super()
        ");
        assert_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              SideExit UnknownOpcode(invokesuper)
        "#]]);
    }

    #[test]
    fn test_cant_compile_zsuper() {
        eval("
            def test = super
        ");
        assert_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              SideExit UnknownOpcode(invokesuper)
        "#]]);
    }

    #[test]
    fn test_cant_compile_super_forward() {
        eval("
            def test(...) = super(...)
        ");
        assert_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              SideExit UnknownOpcode(invokesuperforward)
        "#]]);
    }

    // TODO(max): Figure out how to generate a call with OPT_SEND flag

    #[test]
    fn test_cant_compile_kw_splat_mut() {
        eval("
            def test(a) = foo **a, b: 1
        ");
        assert_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:Class[VMFrozenCore] = Const Value(VALUE(0x1000))
              v5:HashExact = NewHash
              v7:BasicObject = SendWithoutBlock v3, :core#hash_merge_kwd, v5, v1
              v8:Class[VMFrozenCore] = Const Value(VALUE(0x1000))
              v9:StaticSymbol[:b] = Const Value(VALUE(0x1008))
              v10:Fixnum[1] = Const Value(1)
              v12:BasicObject = SendWithoutBlock v8, :core#hash_merge_ptr, v7, v9, v10
              SideExit UnknownCallType
        "#]]);
    }

    #[test]
    fn test_cant_compile_splat_mut() {
        eval("
            def test(*) = foo *, 1
        ");
        assert_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:ArrayExact):
              v4:ArrayExact = ToNewArray v1
              v5:Fixnum[1] = Const Value(1)
              ArrayPush v4, v5
              SideExit UnknownCallType
        "#]]);
    }

    #[test]
    fn test_cant_compile_forwarding() {
        eval("
            def test(...) = foo(...)
        ");
        assert_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              SideExit UnknownOpcode(sendforward)
        "#]]);
    }

    #[test]
    fn test_opt_new() {
        eval("
            class C; end
            def test = C.new
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_new, expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v3:BasicObject = GetConstantPath 0x1000
              v4:NilClass = Const Value(nil)
              Jump bb1(v0, v4, v3)
            bb1(v6:BasicObject, v7:NilClass, v8:BasicObject):
              v11:BasicObject = SendWithoutBlock v8, :new
              Jump bb2(v6, v11, v7)
            bb2(v13:BasicObject, v14:BasicObject, v15:NilClass):
              Return v14
        "#]]);
    }

    #[test]
    fn test_opt_newarray_send_max_no_elements() {
        eval("
            def test = [].max
        ");
        // TODO(max): Rewrite to nil
        assert_method_hir_with_opcode("test", YARVINSN_opt_newarray_send, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_MAX)
              v4:BasicObject = ArrayMax
              Return v4
        "#]]);
    }

    #[test]
    fn test_opt_newarray_send_max() {
        eval("
            def test(a,b) = [a,b].max
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_newarray_send, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_MAX)
              v6:BasicObject = ArrayMax v1, v2
              Return v6
        "#]]);
    }

    #[test]
    fn test_opt_newarray_send_min() {
        eval("
            def test(a,b)
              sum = a+b
              result = [a,b].min
              puts [1,2,3]
              result
            end
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_newarray_send, expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v3:NilClass = Const Value(nil)
              v4:NilClass = Const Value(nil)
              v7:BasicObject = SendWithoutBlock v1, :+, v2
              SideExit UnknownNewarraySend(MIN)
        "#]]);
    }

    #[test]
    fn test_opt_newarray_send_hash() {
        eval("
            def test(a,b)
              sum = a+b
              result = [a,b].hash
              puts [1,2,3]
              result
            end
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_newarray_send, expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v3:NilClass = Const Value(nil)
              v4:NilClass = Const Value(nil)
              v7:BasicObject = SendWithoutBlock v1, :+, v2
              SideExit UnknownNewarraySend(HASH)
        "#]]);
    }

    #[test]
    fn test_opt_newarray_send_pack() {
        eval("
            def test(a,b)
              sum = a+b
              result = [a,b].pack 'C'
              puts [1,2,3]
              result
            end
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_newarray_send, expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v3:NilClass = Const Value(nil)
              v4:NilClass = Const Value(nil)
              v7:BasicObject = SendWithoutBlock v1, :+, v2
              v8:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v9:StringExact = StringCopy v8
              SideExit UnknownNewarraySend(PACK)
        "#]]);
    }

    // TODO(max): Add a test for VM_OPT_NEWARRAY_SEND_PACK_BUFFER

    #[test]
    fn test_opt_newarray_send_include_p() {
        eval("
            def test(a,b)
              sum = a+b
              result = [a,b].include? b
              puts [1,2,3]
              result
            end
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_newarray_send, expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v3:NilClass = Const Value(nil)
              v4:NilClass = Const Value(nil)
              v7:BasicObject = SendWithoutBlock v1, :+, v2
              SideExit UnknownNewarraySend(INCLUDE_P)
        "#]]);
    }

    #[test]
    fn test_opt_length() {
        eval("
            def test(a,b) = [a,b].length
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_length, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:ArrayExact = NewArray v1, v2
              v7:BasicObject = SendWithoutBlock v5, :length
              Return v7
        "#]]);
    }

    #[test]
    fn test_opt_size() {
        eval("
            def test(a,b) = [a,b].size
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_size, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:ArrayExact = NewArray v1, v2
              v7:BasicObject = SendWithoutBlock v5, :size
              Return v7
        "#]]);
    }

    #[test]
    fn test_getinstancevariable() {
        eval("
            def test = @foo
            test
        ");
        assert_method_hir_with_opcode("test", YARVINSN_getinstancevariable, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:BasicObject = GetIvar v0, :@foo
              Return v3
        "#]]);
    }

    #[test]
    fn test_setinstancevariable() {
        eval("
            def test = @foo = 1
            test
        ");
        assert_method_hir_with_opcode("test", YARVINSN_setinstancevariable, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              SetIvar v0, :@foo, v2
              Return v2
        "#]]);
    }

    #[test]
    fn test_setglobal() {
        eval("
            def test = $foo = 1
            test
        ");
        assert_method_hir_with_opcode("test", YARVINSN_setglobal, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              SetGlobal :$foo, v2
              Return v2
        "#]]);
    }

    #[test]
    fn test_getglobal() {
        eval("
            def test = $foo
            test
        ");
        assert_method_hir_with_opcode("test", YARVINSN_getglobal, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:BasicObject = GetGlobal :$foo
              Return v3
        "#]]);
    }

    #[test]
    fn test_splatarray_mut() {
        eval("
            def test(a) = [*a]
        ");
        assert_method_hir_with_opcode("test", YARVINSN_splatarray, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v4:ArrayExact = ToNewArray v1
              Return v4
        "#]]);
    }

    #[test]
    fn test_concattoarray() {
        eval("
            def test(a) = [1, *a]
        ");
        assert_method_hir_with_opcode("test", YARVINSN_concattoarray, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:Fixnum[1] = Const Value(1)
              v5:ArrayExact = NewArray v3
              v7:ArrayExact = ToArray v1
              ArrayExtend v5, v7
              Return v5
        "#]]);
    }

    #[test]
    fn test_pushtoarray_one_element() {
        eval("
            def test(a) = [*a, 1]
        ");
        assert_method_hir_with_opcode("test", YARVINSN_pushtoarray, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v4:ArrayExact = ToNewArray v1
              v5:Fixnum[1] = Const Value(1)
              ArrayPush v4, v5
              Return v4
        "#]]);
    }

    #[test]
    fn test_pushtoarray_multiple_elements() {
        eval("
            def test(a) = [*a, 1, 2, 3]
        ");
        assert_method_hir_with_opcode("test", YARVINSN_pushtoarray, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v4:ArrayExact = ToNewArray v1
              v5:Fixnum[1] = Const Value(1)
              v6:Fixnum[2] = Const Value(2)
              v7:Fixnum[3] = Const Value(3)
              ArrayPush v4, v5
              ArrayPush v4, v6
              ArrayPush v4, v7
              Return v4
        "#]]);
    }

    #[test]
    fn test_aset() {
        eval("
            def test(a, b) = a[b] = 1
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_aset, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v4:NilClass = Const Value(nil)
              v5:Fixnum[1] = Const Value(1)
              v7:BasicObject = SendWithoutBlock v1, :[]=, v2, v5
              Return v5
        "#]]);
    }

    #[test]
    fn test_aref() {
        eval("
            def test(a, b) = a[b]
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_aref, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:BasicObject = SendWithoutBlock v1, :[], v2
              Return v5
        "#]]);
    }

    #[test]
    fn test_aref_with() {
        eval("
            def test(a) = a['string lit triggers aref_with']
        ");
        assert_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v5:BasicObject = SendWithoutBlock v1, :[], v3
              Return v5
        "#]]);
    }

    #[test]
    fn opt_empty_p() {
        eval("
            def test(x) = x.empty?
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_empty_p, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v4:BasicObject = SendWithoutBlock v1, :empty?
              Return v4
        "#]]);
    }

    #[test]
    fn opt_succ() {
        eval("
            def test(x) = x.succ
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_succ, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v4:BasicObject = SendWithoutBlock v1, :succ
              Return v4
        "#]]);
    }

    #[test]
    fn opt_and() {
        eval("
            def test(x, y) = x & y
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_and, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:BasicObject = SendWithoutBlock v1, :&, v2
              Return v5
        "#]]);
    }

    #[test]
    fn opt_or() {
        eval("
            def test(x, y) = x | y
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_or, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:BasicObject = SendWithoutBlock v1, :|, v2
              Return v5
        "#]]);
    }

    #[test]
    fn opt_not() {
        eval("
            def test(x) = !x
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_not, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v4:BasicObject = SendWithoutBlock v1, :!
              Return v4
        "#]]);
    }

    #[test]
    fn opt_regexpmatch2() {
        eval("
            def test(regexp, matchee) = regexp =~ matchee
        ");
        assert_method_hir_with_opcode("test", YARVINSN_opt_regexpmatch2, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:BasicObject = SendWithoutBlock v1, :=~, v2
              Return v5
        "#]]);
    }

    #[test]
    // Tests for ConstBase requires either constant or class definition, both
    // of which can't be performed inside a method.
    fn test_putspecialobject_vm_core_and_cbase() {
        eval("
            def test
              alias aliased __callee__
            end
        ");
        assert_method_hir_with_opcode("test", YARVINSN_putspecialobject, expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Class[VMFrozenCore] = Const Value(VALUE(0x1000))
              v3:BasicObject = PutSpecialObject CBase
              v4:StaticSymbol[:aliased] = Const Value(VALUE(0x1008))
              v5:StaticSymbol[:__callee__] = Const Value(VALUE(0x1010))
              v7:BasicObject = SendWithoutBlock v2, :core#set_method_alias, v3, v4, v5
              Return v7
        "#]]);
    }

    #[test]
    fn opt_reverse() {
        eval("
            def reverse_odd
              a, b, c = @a, @b, @c
              [a, b, c]
            end

            def reverse_even
              a, b, c, d = @a, @b, @c, @d
              [a, b, c, d]
            end
        ");
        assert_method_hir_with_opcode("reverse_odd", YARVINSN_opt_reverse, expect![[r#"
            fn reverse_odd@<compiled>:3:
            bb0(v0:BasicObject):
              v1:NilClass = Const Value(nil)
              v2:NilClass = Const Value(nil)
              v3:NilClass = Const Value(nil)
              v6:BasicObject = GetIvar v0, :@a
              v8:BasicObject = GetIvar v0, :@b
              v10:BasicObject = GetIvar v0, :@c
              v12:ArrayExact = NewArray v6, v8, v10
              Return v12
        "#]]);
        assert_method_hir_with_opcode("reverse_even", YARVINSN_opt_reverse, expect![[r#"
            fn reverse_even@<compiled>:8:
            bb0(v0:BasicObject):
              v1:NilClass = Const Value(nil)
              v2:NilClass = Const Value(nil)
              v3:NilClass = Const Value(nil)
              v4:NilClass = Const Value(nil)
              v7:BasicObject = GetIvar v0, :@a
              v9:BasicObject = GetIvar v0, :@b
              v11:BasicObject = GetIvar v0, :@c
              v13:BasicObject = GetIvar v0, :@d
              v15:ArrayExact = NewArray v7, v9, v11, v13
              Return v15
        "#]]);
    }

    #[test]
    fn test_branchnil() {
        eval("
        def test(x) = x&.itself
        ");
        assert_method_hir_with_opcode("test", YARVINSN_branchnil, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:CBool = IsNil v1
              IfTrue v3, bb1(v0, v1, v1)
              v6:BasicObject = SendWithoutBlock v1, :itself
              Jump bb1(v0, v1, v6)
            bb1(v8:BasicObject, v9:BasicObject, v10:BasicObject):
              Return v10
        "#]]);
    }

    #[test]
    fn test_invokebuiltin_delegate_annotated() {
        assert_method_hir_with_opcode("Float", YARVINSN_opt_invokebuiltin_delegate_leave, expect![[r#"
            fn Float@<internal:kernel>:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject, v3:BasicObject):
              v6:Flonum = InvokeBuiltin rb_f_float, v0, v1, v2
              Jump bb1(v0, v1, v2, v3, v6)
            bb1(v8:BasicObject, v9:BasicObject, v10:BasicObject, v11:BasicObject, v12:Flonum):
              Return v12
        "#]]);
    }

    #[test]
    fn test_invokebuiltin_cexpr_annotated() {
        assert_method_hir_with_opcode("class", YARVINSN_opt_invokebuiltin_delegate_leave, expect![[r#"
            fn class@<internal:kernel>:
            bb0(v0:BasicObject):
              v3:Class = InvokeBuiltin _bi20, v0
              Jump bb1(v0, v3)
            bb1(v5:BasicObject, v6:Class):
              Return v6
        "#]]);
    }

    #[test]
    fn test_invokebuiltin_delegate_with_args() {
        // Using an unannotated builtin to test InvokeBuiltin generation
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("Dir", "open"));
        assert!(iseq_contains_opcode(iseq, YARVINSN_opt_invokebuiltin_delegate), "iseq Dir.open does not contain invokebuiltin");
        let function = iseq_to_hir(iseq).unwrap();
        assert_function_hir(function, expect![[r#"
            fn open@<internal:dir>:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject, v3:BasicObject, v4:BasicObject):
              v5:NilClass = Const Value(nil)
              v8:BasicObject = InvokeBuiltin dir_s_open, v0, v1, v2
              SideExit UnknownOpcode(getblockparamproxy)
        "#]]);
    }

    #[test]
    fn test_invokebuiltin_delegate_without_args() {
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("GC", "enable"));
        assert!(iseq_contains_opcode(iseq, YARVINSN_opt_invokebuiltin_delegate_leave), "iseq GC.enable does not contain invokebuiltin");
        let function = iseq_to_hir(iseq).unwrap();
        assert_function_hir(function, expect![[r#"
            fn enable@<internal:gc>:
            bb0(v0:BasicObject):
              v3:BasicObject = InvokeBuiltin gc_enable, v0
              Jump bb1(v0, v3)
            bb1(v5:BasicObject, v6:BasicObject):
              Return v6
        "#]]);
    }

    #[test]
    fn test_invokebuiltin_with_args() {
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("GC", "start"));
        assert!(iseq_contains_opcode(iseq, YARVINSN_invokebuiltin), "iseq GC.start does not contain invokebuiltin");
        let function = iseq_to_hir(iseq).unwrap();
        assert_function_hir(function, expect![[r#"
            fn start@<internal:gc>:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject, v3:BasicObject, v4:BasicObject):
              v6:FalseClass = Const Value(false)
              v8:BasicObject = InvokeBuiltin gc_start_internal, v0, v1, v2, v3, v6
              Return v8
        "#]]);
    }

    #[test]
    fn dupn() {
        eval("
            def test(x) = (x[0, 1] ||= 2)
        ");
        assert_method_hir_with_opcode("test", YARVINSN_dupn, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:NilClass = Const Value(nil)
              v4:Fixnum[0] = Const Value(0)
              v5:Fixnum[1] = Const Value(1)
              v7:BasicObject = SendWithoutBlock v1, :[], v4, v5
              v8:CBool = Test v7
              IfTrue v8, bb1(v0, v1, v3, v1, v4, v5, v7)
              v10:Fixnum[2] = Const Value(2)
              v12:BasicObject = SendWithoutBlock v1, :[]=, v4, v5, v10
              Return v10
            bb1(v14:BasicObject, v15:BasicObject, v16:NilClass, v17:BasicObject, v18:Fixnum[0], v19:Fixnum[1], v20:BasicObject):
              Return v20
        "#]]);
    }

    #[test]
    fn test_objtostring_anytostring() {
        eval("
            def test = \"#{1}\"
        ");
        assert_method_hir_with_opcode("test", YARVINSN_objtostring, expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v2:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v3:Fixnum[1] = Const Value(1)
              v5:BasicObject = ObjToString v3
              v7:String = AnyToString v3, str: v5
              SideExit UnknownOpcode(concatstrings)
        "#]]);
    }

    #[test]
    fn throw() {
        eval("
            define_method(:throw_return) { return 1 }
            define_method(:throw_break) { break 2 }
        ");
        assert_method_hir_with_opcode("throw_return", YARVINSN_throw, expect![[r#"
            fn block in <compiled>@<compiled>:2:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              Throw TAG_RETURN, v2
        "#]]);
        assert_method_hir_with_opcode("throw_break", YARVINSN_throw, expect![[r#"
            fn block in <compiled>@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[2] = Const Value(2)
              Throw TAG_BREAK, v2
        "#]]);
    }
}

#[cfg(test)]
mod opt_tests {
    use super::*;
    use super::tests::assert_function_hir;
    use expect_test::{expect, Expect};

    #[track_caller]
    fn assert_optimized_method_hir(method: &str, hir: Expect) {
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("self", method));
        unsafe { crate::cruby::rb_zjit_profile_disable(iseq) };
        let mut function = iseq_to_hir(iseq).unwrap();
        function.optimize();
        function.validate().unwrap();
        assert_function_hir(function, hir);
    }

    #[test]
    fn test_fold_iftrue_away() {
        eval("
            def test
              cond = true
              if cond
                3
              else
                4
              end
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v6:Fixnum[3] = Const Value(3)
              Return v6
        "#]]);
    }

    #[test]
    fn test_fold_iftrue_into_jump() {
        eval("
            def test
              cond = false
              if cond
                3
              else
                4
              end
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v11:Fixnum[4] = Const Value(4)
              Return v11
        "#]]);
    }

    #[test]
    fn test_fold_fixnum_add() {
        eval("
            def test
              1 + 2 + 3
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              v3:Fixnum[2] = Const Value(2)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
              v14:Fixnum[3] = Const Value(3)
              v6:Fixnum[3] = Const Value(3)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
              v15:Fixnum[6] = Const Value(6)
              Return v15
        "#]]);
    }

    #[test]
    fn test_fold_fixnum_sub() {
        eval("
            def test
              5 - 3 - 1
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[5] = Const Value(5)
              v3:Fixnum[3] = Const Value(3)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MINUS)
              v14:Fixnum[2] = Const Value(2)
              v6:Fixnum[1] = Const Value(1)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MINUS)
              v15:Fixnum[1] = Const Value(1)
              Return v15
        "#]]);
    }

    #[test]
    fn test_fold_fixnum_sub_large_negative_result() {
        eval("
            def test
              0 - 1073741825
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[0] = Const Value(0)
              v3:Fixnum[1073741825] = Const Value(1073741825)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MINUS)
              v9:Fixnum[-1073741825] = Const Value(-1073741825)
              Return v9
        "#]]);
    }

    #[test]
    fn test_fold_fixnum_mult() {
        eval("
            def test
              6 * 7
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[6] = Const Value(6)
              v3:Fixnum[7] = Const Value(7)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MULT)
              v9:Fixnum[42] = Const Value(42)
              Return v9
        "#]]);
    }

    #[test]
    fn test_fold_fixnum_mult_zero() {
        eval("
            def test(n)
              0 * n + n * 0
            end
            test 1; test 2
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:Fixnum[0] = Const Value(0)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MULT)
              v13:Fixnum = GuardType v1, Fixnum
              v20:Fixnum[0] = Const Value(0)
              v6:Fixnum[0] = Const Value(0)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MULT)
              v16:Fixnum = GuardType v1, Fixnum
              v21:Fixnum[0] = Const Value(0)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
              v22:Fixnum[0] = Const Value(0)
              Return v22
        "#]]);
    }

    #[test]
    fn test_fold_fixnum_less() {
        eval("
            def test
              if 1 < 2
                3
              else
                4
              end
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              v3:Fixnum[2] = Const Value(2)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LT)
              v8:Fixnum[3] = Const Value(3)
              Return v8
        "#]]);
    }

    #[test]
    fn test_fold_fixnum_less_equal() {
        eval("
            def test
              if 1 <= 2 && 2 <= 2
                3
              else
                4
              end
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              v3:Fixnum[2] = Const Value(2)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LE)
              v8:Fixnum[2] = Const Value(2)
              v9:Fixnum[2] = Const Value(2)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LE)
              v14:Fixnum[3] = Const Value(3)
              Return v14
        "#]]);
    }

    #[test]
    fn test_fold_fixnum_greater() {
        eval("
            def test
              if 2 > 1
                3
              else
                4
              end
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[2] = Const Value(2)
              v3:Fixnum[1] = Const Value(1)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_GT)
              v8:Fixnum[3] = Const Value(3)
              Return v8
        "#]]);
    }

    #[test]
    fn test_fold_fixnum_greater_equal() {
        eval("
            def test
              if 2 >= 1 && 2 >= 2
                3
              else
                4
              end
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[2] = Const Value(2)
              v3:Fixnum[1] = Const Value(1)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_GE)
              v8:Fixnum[2] = Const Value(2)
              v9:Fixnum[2] = Const Value(2)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_GE)
              v14:Fixnum[3] = Const Value(3)
              Return v14
        "#]]);
    }

    #[test]
    fn test_fold_fixnum_eq_false() {
        eval("
            def test
              if 1 == 2
                3
              else
                4
              end
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              v3:Fixnum[2] = Const Value(2)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
              v12:Fixnum[4] = Const Value(4)
              Return v12
        "#]]);
    }

    #[test]
    fn test_fold_fixnum_eq_true() {
        eval("
            def test
              if 2 == 2
                3
              else
                4
              end
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[2] = Const Value(2)
              v3:Fixnum[2] = Const Value(2)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
              v8:Fixnum[3] = Const Value(3)
              Return v8
        "#]]);
    }

    #[test]
    fn test_fold_fixnum_neq_true() {
        eval("
            def test
              if 1 != 2
                3
              else
                4
              end
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              v3:Fixnum[2] = Const Value(2)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_NEQ)
              v8:Fixnum[3] = Const Value(3)
              Return v8
        "#]]);
    }

    #[test]
    fn test_fold_fixnum_neq_false() {
        eval("
            def test
              if 2 != 2
                3
              else
                4
              end
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[2] = Const Value(2)
              v3:Fixnum[2] = Const Value(2)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_NEQ)
              v12:Fixnum[4] = Const Value(4)
              Return v12
        "#]]);
    }

    #[test]
    fn test_replace_guard_if_known_fixnum() {
        eval("
            def test(a)
              a + 1
            end
            test(2); test(3)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:Fixnum[1] = Const Value(1)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
              v8:Fixnum = GuardType v1, Fixnum
              v9:Fixnum = FixnumAdd v8, v3
              Return v9
        "#]]);
    }

    #[test]
    fn test_param_forms_get_bb_param() {
        eval("
            def rest(*array) = array
            def kw(k:) = k
            def kw_rest(**k) = k
            def post(*rest, post) = post
            def block(&b) = nil
            def forwardable(...) = nil
        ");

        assert_optimized_method_hir("rest", expect![[r#"
            fn rest@<compiled>:2:
            bb0(v0:BasicObject, v1:ArrayExact):
              Return v1
        "#]]);
        // extra hidden param for the set of specified keywords
        assert_optimized_method_hir("kw", expect![[r#"
            fn kw@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              Return v1
        "#]]);
        assert_optimized_method_hir("kw_rest", expect![[r#"
            fn kw_rest@<compiled>:4:
            bb0(v0:BasicObject, v1:BasicObject):
              Return v1
        "#]]);
        assert_optimized_method_hir("block", expect![[r#"
            fn block@<compiled>:6:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:NilClass = Const Value(nil)
              Return v3
        "#]]);
        assert_optimized_method_hir("post", expect![[r#"
            fn post@<compiled>:5:
            bb0(v0:BasicObject, v1:ArrayExact, v2:BasicObject):
              Return v2
        "#]]);
        assert_optimized_method_hir("forwardable", expect![[r#"
            fn forwardable@<compiled>:7:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:NilClass = Const Value(nil)
              Return v3
        "#]]);
    }

    #[test]
    fn test_optimize_top_level_call_into_send_direct() {
        eval("
            def foo
            end
            def test
              foo
            end
            test; test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:5:
            bb0(v0:BasicObject):
              PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
              v6:BasicObject[class_exact*:Object@VALUE(0x1000)] = GuardType v0, BasicObject[class_exact*:Object@VALUE(0x1000)]
              v7:BasicObject = SendWithoutBlockDirect v6, :foo (0x1038)
              Return v7
        "#]]);
    }

    #[test]
    fn test_optimize_nonexistent_top_level_call() {
        eval("
            def foo
            end
            def test
              foo
            end
            test; test
            undef :foo
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:5:
            bb0(v0:BasicObject):
              v3:BasicObject = SendWithoutBlock v0, :foo
              Return v3
        "#]]);
    }

    #[test]
    fn test_optimize_private_top_level_call() {
        eval("
            def foo
            end
            private :foo
            def test
              foo
            end
            test; test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:6:
            bb0(v0:BasicObject):
              PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
              v6:BasicObject[class_exact*:Object@VALUE(0x1000)] = GuardType v0, BasicObject[class_exact*:Object@VALUE(0x1000)]
              v7:BasicObject = SendWithoutBlockDirect v6, :foo (0x1038)
              Return v7
        "#]]);
    }

    #[test]
    fn test_optimize_top_level_call_with_overloaded_cme() {
        eval("
            def test
              Integer(3)
            end
            test; test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[3] = Const Value(3)
              PatchPoint MethodRedefined(Object@0x1000, Integer@0x1008, cme:0x1010)
              v7:BasicObject[class_exact*:Object@VALUE(0x1000)] = GuardType v0, BasicObject[class_exact*:Object@VALUE(0x1000)]
              v8:BasicObject = SendWithoutBlockDirect v7, :Integer (0x1038), v2
              Return v8
        "#]]);
    }

    #[test]
    fn test_optimize_top_level_call_with_args_into_send_direct() {
        eval("
            def foo a, b
            end
            def test
              foo 1, 2
            end
            test; test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:5:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              v3:Fixnum[2] = Const Value(2)
              PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
              v8:BasicObject[class_exact*:Object@VALUE(0x1000)] = GuardType v0, BasicObject[class_exact*:Object@VALUE(0x1000)]
              v9:BasicObject = SendWithoutBlockDirect v8, :foo (0x1038), v2, v3
              Return v9
        "#]]);
    }

    #[test]
    fn test_optimize_top_level_sends_into_send_direct() {
        eval("
            def foo
            end
            def bar
            end
            def test
              foo
              bar
            end
            test; test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:7:
            bb0(v0:BasicObject):
              PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
              v8:BasicObject[class_exact*:Object@VALUE(0x1000)] = GuardType v0, BasicObject[class_exact*:Object@VALUE(0x1000)]
              v9:BasicObject = SendWithoutBlockDirect v8, :foo (0x1038)
              PatchPoint MethodRedefined(Object@0x1000, bar@0x1040, cme:0x1048)
              v11:BasicObject[class_exact*:Object@VALUE(0x1000)] = GuardType v0, BasicObject[class_exact*:Object@VALUE(0x1000)]
              v12:BasicObject = SendWithoutBlockDirect v11, :bar (0x1038)
              Return v12
        "#]]);
    }

    #[test]
    fn test_dont_optimize_fixnum_add_if_redefined() {
        eval("
            class Integer
              def +(other)
                100
              end
            end
            def test(a, b) = a + b
            test(1,2); test(3,4)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:7:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:BasicObject = SendWithoutBlock v1, :+, v2
              Return v5
        "#]]);
    }

    #[test]
    fn test_optimize_send_into_fixnum_add_both_profiled() {
        eval("
            def test(a, b) = a + b
            test(1,2); test(3,4)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
              v8:Fixnum = GuardType v1, Fixnum
              v9:Fixnum = GuardType v2, Fixnum
              v10:Fixnum = FixnumAdd v8, v9
              Return v10
        "#]]);
    }

    #[test]
    fn test_optimize_send_into_fixnum_add_left_profiled() {
        eval("
            def test(a) = a + 1
            test(1); test(3)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:Fixnum[1] = Const Value(1)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
              v8:Fixnum = GuardType v1, Fixnum
              v9:Fixnum = FixnumAdd v8, v3
              Return v9
        "#]]);
    }

    #[test]
    fn test_optimize_send_into_fixnum_add_right_profiled() {
        eval("
            def test(a) = 1 + a
            test(1); test(3)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:Fixnum[1] = Const Value(1)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
              v8:Fixnum = GuardType v1, Fixnum
              v9:Fixnum = FixnumAdd v3, v8
              Return v9
        "#]]);
    }

    #[test]
    fn test_optimize_send_into_fixnum_lt_both_profiled() {
        eval("
            def test(a, b) = a < b
            test(1,2); test(3,4)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LT)
              v8:Fixnum = GuardType v1, Fixnum
              v9:Fixnum = GuardType v2, Fixnum
              v10:BoolExact = FixnumLt v8, v9
              Return v10
        "#]]);
    }

    #[test]
    fn test_optimize_send_into_fixnum_lt_left_profiled() {
        eval("
            def test(a) = a < 1
            test(1); test(3)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:Fixnum[1] = Const Value(1)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LT)
              v8:Fixnum = GuardType v1, Fixnum
              v9:BoolExact = FixnumLt v8, v3
              Return v9
        "#]]);
    }

    #[test]
    fn test_optimize_send_into_fixnum_lt_right_profiled() {
        eval("
            def test(a) = 1 < a
            test(1); test(3)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:Fixnum[1] = Const Value(1)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LT)
              v8:Fixnum = GuardType v1, Fixnum
              v9:BoolExact = FixnumLt v3, v8
              Return v9
        "#]]);
    }

    #[test]
    fn test_eliminate_new_array() {
        eval("
            def test()
              c = []
              5
            end
            test; test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v5:Fixnum[5] = Const Value(5)
              Return v5
        "#]]);
    }

    #[test]
    fn test_eliminate_new_range() {
        eval("
            def test()
              c = (1..2)
              5
            end
            test; test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v4:Fixnum[5] = Const Value(5)
              Return v4
        "#]]);
    }

    #[test]
    fn test_eliminate_new_array_with_elements() {
        eval("
            def test(a)
              c = [a]
              5
            end
            test(1); test(2)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject):
              v6:Fixnum[5] = Const Value(5)
              Return v6
        "#]]);
    }

    #[test]
    fn test_eliminate_new_hash() {
        eval("
            def test()
              c = {}
              5
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v5:Fixnum[5] = Const Value(5)
              Return v5
        "#]]);
    }

    #[test]
    fn test_eliminate_new_hash_with_elements() {
        eval("
            def test(aval, bval)
              c = {a: aval, b: bval}
              5
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v9:Fixnum[5] = Const Value(5)
              Return v9
        "#]]);
    }

    #[test]
    fn test_eliminate_array_dup() {
        eval("
            def test
              c = [1, 2]
              5
            end
            test; test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v6:Fixnum[5] = Const Value(5)
              Return v6
        "#]]);
    }

    #[test]
    fn test_eliminate_hash_dup() {
        eval("
            def test
              c = {a: 1, b: 2}
              5
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v6:Fixnum[5] = Const Value(5)
              Return v6
        "#]]);
    }

    #[test]
    fn test_eliminate_putself() {
        eval("
            def test()
              c = self
              5
            end
            test; test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v3:Fixnum[5] = Const Value(5)
              Return v3
        "#]]);
    }

    #[test]
    fn test_eliminate_string_copy() {
        eval(r#"
            def test()
              c = "abc"
              5
            end
            test; test
        "#);
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v5:Fixnum[5] = Const Value(5)
              Return v5
        "#]]);
    }

    #[test]
    fn test_eliminate_fixnum_add() {
        eval("
            def test(a, b)
              a + b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
              v9:Fixnum = GuardType v1, Fixnum
              v10:Fixnum = GuardType v2, Fixnum
              v6:Fixnum[5] = Const Value(5)
              Return v6
        "#]]);
    }

    #[test]
    fn test_eliminate_fixnum_sub() {
        eval("
            def test(a, b)
              a - b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MINUS)
              v9:Fixnum = GuardType v1, Fixnum
              v10:Fixnum = GuardType v2, Fixnum
              v6:Fixnum[5] = Const Value(5)
              Return v6
        "#]]);
    }

    #[test]
    fn test_eliminate_fixnum_mul() {
        eval("
            def test(a, b)
              a * b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MULT)
              v9:Fixnum = GuardType v1, Fixnum
              v10:Fixnum = GuardType v2, Fixnum
              v6:Fixnum[5] = Const Value(5)
              Return v6
        "#]]);
    }

    #[test]
    fn test_do_not_eliminate_fixnum_div() {
        eval("
            def test(a, b)
              a / b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_DIV)
              v9:Fixnum = GuardType v1, Fixnum
              v10:Fixnum = GuardType v2, Fixnum
              v11:Fixnum = FixnumDiv v9, v10
              v6:Fixnum[5] = Const Value(5)
              Return v6
        "#]]);
    }

    #[test]
    fn test_do_not_eliminate_fixnum_mod() {
        eval("
            def test(a, b)
              a % b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MOD)
              v9:Fixnum = GuardType v1, Fixnum
              v10:Fixnum = GuardType v2, Fixnum
              v11:Fixnum = FixnumMod v9, v10
              v6:Fixnum[5] = Const Value(5)
              Return v6
        "#]]);
    }

    #[test]
    fn test_eliminate_fixnum_lt() {
        eval("
            def test(a, b)
              a < b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LT)
              v9:Fixnum = GuardType v1, Fixnum
              v10:Fixnum = GuardType v2, Fixnum
              v6:Fixnum[5] = Const Value(5)
              Return v6
        "#]]);
    }

    #[test]
    fn test_eliminate_fixnum_le() {
        eval("
            def test(a, b)
              a <= b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LE)
              v9:Fixnum = GuardType v1, Fixnum
              v10:Fixnum = GuardType v2, Fixnum
              v6:Fixnum[5] = Const Value(5)
              Return v6
        "#]]);
    }

    #[test]
    fn test_eliminate_fixnum_gt() {
        eval("
            def test(a, b)
              a > b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_GT)
              v9:Fixnum = GuardType v1, Fixnum
              v10:Fixnum = GuardType v2, Fixnum
              v6:Fixnum[5] = Const Value(5)
              Return v6
        "#]]);
    }

    #[test]
    fn test_eliminate_fixnum_ge() {
        eval("
            def test(a, b)
              a >= b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_GE)
              v9:Fixnum = GuardType v1, Fixnum
              v10:Fixnum = GuardType v2, Fixnum
              v6:Fixnum[5] = Const Value(5)
              Return v6
        "#]]);
    }

    #[test]
    fn test_eliminate_fixnum_eq() {
        eval("
            def test(a, b)
              a == b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
              v9:Fixnum = GuardType v1, Fixnum
              v10:Fixnum = GuardType v2, Fixnum
              v6:Fixnum[5] = Const Value(5)
              Return v6
        "#]]);
    }

    #[test]
    fn test_eliminate_fixnum_neq() {
        eval("
            def test(a, b)
              a != b
              5
            end
            test(1, 2); test(3, 4)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_NEQ)
              v10:Fixnum = GuardType v1, Fixnum
              v11:Fixnum = GuardType v2, Fixnum
              v6:Fixnum[5] = Const Value(5)
              Return v6
        "#]]);
    }

    #[test]
    fn test_do_not_eliminate_get_constant_path() {
        eval("
            def test()
              C
              5
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v3:BasicObject = GetConstantPath 0x1000
              v4:Fixnum[5] = Const Value(5)
              Return v4
        "#]]);
    }

    #[test]
    fn kernel_itself_const() {
        eval("
            def test(x) = x.itself
            test(0) # profile
            test(1)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint MethodRedefined(Integer@0x1000, itself@0x1008, cme:0x1010)
              v7:Fixnum = GuardType v1, Fixnum
              v8:BasicObject = CCall itself@0x1038, v7
              Return v8
        "#]]);
    }

    #[test]
    fn kernel_itself_known_type() {
        eval("
            def test = [].itself
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:ArrayExact = NewArray
              PatchPoint MethodRedefined(Array@0x1000, itself@0x1008, cme:0x1010)
              v8:BasicObject = CCall itself@0x1038, v3
              Return v8
        "#]]);
    }

    #[test]
    fn eliminate_kernel_itself() {
        eval("
            def test
              x = [].itself
              1
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v1:NilClass = Const Value(nil)
              v4:ArrayExact = NewArray
              PatchPoint MethodRedefined(Array@0x1000, itself@0x1008, cme:0x1010)
              v7:Fixnum[1] = Const Value(1)
              Return v7
        "#]]);
    }

    #[test]
    fn eliminate_module_name() {
        eval("
            module M; end
            def test
              x = M.name
              1
            end
            test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:4:
            bb0(v0:BasicObject):
              v1:NilClass = Const Value(nil)
              PatchPoint SingleRactorMode
              PatchPoint StableConstantNames(0x1000, M)
              v11:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
              PatchPoint MethodRedefined(Module@0x1010, name@0x1018, cme:0x1020)
              v7:Fixnum[1] = Const Value(1)
              Return v7
        "#]]);
    }

    #[test]
    fn eliminate_array_length() {
        eval("
            def test
              x = [].length
              5
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v1:NilClass = Const Value(nil)
              v4:ArrayExact = NewArray
              PatchPoint MethodRedefined(Array@0x1000, length@0x1008, cme:0x1010)
              v7:Fixnum[5] = Const Value(5)
              Return v7
        "#]]);
    }

    #[test]
    fn normal_class_type_inference() {
        eval("
            class C; end
            def test = C
            test # Warm the constant cache
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              PatchPoint SingleRactorMode
              PatchPoint StableConstantNames(0x1000, C)
              v7:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
              Return v7
        "#]]);
    }

    #[test]
    fn core_classes_type_inference() {
        eval("
            def test = [String, Class, Module, BasicObject]
            test # Warm the constant cache
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              PatchPoint SingleRactorMode
              PatchPoint StableConstantNames(0x1000, String)
              v15:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
              PatchPoint SingleRactorMode
              PatchPoint StableConstantNames(0x1010, Class)
              v18:Class[VALUE(0x1018)] = Const Value(VALUE(0x1018))
              PatchPoint SingleRactorMode
              PatchPoint StableConstantNames(0x1020, Module)
              v21:Class[VALUE(0x1028)] = Const Value(VALUE(0x1028))
              PatchPoint SingleRactorMode
              PatchPoint StableConstantNames(0x1030, BasicObject)
              v24:Class[VALUE(0x1038)] = Const Value(VALUE(0x1038))
              v11:ArrayExact = NewArray v15, v18, v21, v24
              Return v11
        "#]]);
    }

    #[test]
    fn module_instances_are_module_exact() {
        eval("
            def test = [Enumerable, Kernel]
            test # Warm the constant cache
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              PatchPoint SingleRactorMode
              PatchPoint StableConstantNames(0x1000, Enumerable)
              v11:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
              PatchPoint SingleRactorMode
              PatchPoint StableConstantNames(0x1010, Kernel)
              v14:ModuleExact[VALUE(0x1018)] = Const Value(VALUE(0x1018))
              v7:ArrayExact = NewArray v11, v14
              Return v7
        "#]]);
    }

    #[test]
    fn module_subclasses_are_not_module_exact() {
        eval("
            class ModuleSubclass < Module; end
            MY_MODULE = ModuleSubclass.new
            def test = MY_MODULE
            test # Warm the constant cache
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:4:
            bb0(v0:BasicObject):
              PatchPoint SingleRactorMode
              PatchPoint StableConstantNames(0x1000, MY_MODULE)
              v7:BasicObject[VALUE(0x1008)] = Const Value(VALUE(0x1008))
              Return v7
        "#]]);
    }

    #[test]
    fn eliminate_array_size() {
        eval("
            def test
              x = [].size
              5
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v1:NilClass = Const Value(nil)
              v4:ArrayExact = NewArray
              PatchPoint MethodRedefined(Array@0x1000, size@0x1008, cme:0x1010)
              v7:Fixnum[5] = Const Value(5)
              Return v7
        "#]]);
    }

    #[test]
    fn kernel_itself_argc_mismatch() {
        eval("
            def test = 1.itself(0)
            test rescue 0
            test rescue 0
        ");
        // Not specialized
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              v3:Fixnum[0] = Const Value(0)
              v5:BasicObject = SendWithoutBlock v2, :itself, v3
              Return v5
        "#]]);
    }

    #[test]
    fn const_send_direct_integer() {
        eval("
            def test(x) = 1.zero?
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              v3:Fixnum[1] = Const Value(1)
              PatchPoint MethodRedefined(Integer@0x1000, zero?@0x1008, cme:0x1010)
              v8:BasicObject = SendWithoutBlockDirect v3, :zero? (0x1038)
              Return v8
        "#]]);
    }

    #[test]
    fn class_known_send_direct_array() {
        eval("
            def test(x)
              a = [1,2,3]
              a.first
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject, v1:BasicObject):
              v2:NilClass = Const Value(nil)
              v4:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v6:ArrayExact = ArrayDup v4
              PatchPoint MethodRedefined(Array@0x1008, first@0x1010, cme:0x1018)
              v11:BasicObject = SendWithoutBlockDirect v6, :first (0x1040)
              Return v11
        "#]]);
    }

    #[test]
    fn send_direct_to_module() {
        eval("
            module M; end
            def test = M.class
            test
            test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              PatchPoint SingleRactorMode
              PatchPoint StableConstantNames(0x1000, M)
              v9:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
              PatchPoint MethodRedefined(Module@0x1010, class@0x1018, cme:0x1020)
              v11:BasicObject = SendWithoutBlockDirect v9, :class (0x1048)
              Return v11
        "#]]);
    }

    #[test]
    fn test_send_direct_to_instance_method() {
        eval("
            class C
              def foo
                3
              end
            end

            def test(c) = c.foo
            c = C.new
            test c
            test c
        ");

        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:8:
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint MethodRedefined(C@0x1000, foo@0x1008, cme:0x1010)
              v7:BasicObject[class_exact:C] = GuardType v1, BasicObject[class_exact:C]
              v8:BasicObject = SendWithoutBlockDirect v7, :foo (0x1038)
              Return v8
        "#]]);
    }

    #[test]
    fn dont_specialize_call_to_iseq_with_opt() {
        eval("
            def foo(arg=1) = 1
            def test = foo 1
            test
            test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              v4:BasicObject = SendWithoutBlock v0, :foo, v2
              Return v4
        "#]]);
    }

    #[test]
    fn dont_specialize_call_to_iseq_with_block() {
        eval("
            def foo(&block) = 1
            def test = foo {|| }
            test
            test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v3:BasicObject = Send v0, 0x1000, :foo
              Return v3
        "#]]);
    }

    #[test]
    fn dont_specialize_call_to_iseq_with_rest() {
        eval("
            def foo(*args) = 1
            def test = foo 1
            test
            test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              v4:BasicObject = SendWithoutBlock v0, :foo, v2
              Return v4
        "#]]);
    }

    #[test]
    fn dont_specialize_call_to_iseq_with_kw() {
        eval("
            def foo(a:) = 1
            def test = foo(a: 1)
            test
            test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              SideExit UnknownCallType
        "#]]);
    }

    #[test]
    fn dont_specialize_call_to_iseq_with_kwrest() {
        eval("
            def foo(**args) = 1
            def test = foo(a: 1)
            test
            test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              SideExit UnknownCallType
        "#]]);
    }

    #[test]
    fn string_bytesize_simple() {
        eval("
            def test = 'abc'.bytesize
            test
            test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v2:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v3:StringExact = StringCopy v2
              PatchPoint MethodRedefined(String@0x1008, bytesize@0x1010, cme:0x1018)
              v8:Fixnum = CCall bytesize@0x1040, v3
              Return v8
        "#]]);
    }

    #[test]
    fn dont_replace_get_constant_path_with_empty_ic() {
        eval("
            def test = Kernel
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:BasicObject = GetConstantPath 0x1000
              Return v3
        "#]]);
    }

    #[test]
    fn dont_replace_get_constant_path_with_invalidated_ic() {
        eval("
            def test = Kernel
            test
            Kernel = 5
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:BasicObject = GetConstantPath 0x1000
              Return v3
        "#]]);
    }

    #[test]
    fn replace_get_constant_path_with_const() {
        eval("
            def test = Kernel
            test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              PatchPoint SingleRactorMode
              PatchPoint StableConstantNames(0x1000, Kernel)
              v7:ModuleExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
              Return v7
        "#]]);
    }

    #[test]
    fn replace_nested_get_constant_path_with_const() {
        eval("
            module Foo
              module Bar
                class C
                end
              end
            end
            def test = Foo::Bar::C
            test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:8:
            bb0(v0:BasicObject):
              PatchPoint SingleRactorMode
              PatchPoint StableConstantNames(0x1000, Foo::Bar::C)
              v7:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
              Return v7
        "#]]);
    }

    #[test]
    fn test_opt_new_no_initialize() {
        eval("
            class C; end
            def test = C.new
            test
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              PatchPoint SingleRactorMode
              PatchPoint StableConstantNames(0x1000, C)
              v20:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
              v4:NilClass = Const Value(nil)
              v11:BasicObject = SendWithoutBlock v20, :new
              Return v11
        "#]]);
    }

    #[test]
    fn test_opt_new_initialize() {
        eval("
            class C
              def initialize x
                @x = x
              end
            end
            def test = C.new 1
            test
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:7:
            bb0(v0:BasicObject):
              PatchPoint SingleRactorMode
              PatchPoint StableConstantNames(0x1000, C)
              v22:Class[VALUE(0x1008)] = Const Value(VALUE(0x1008))
              v4:NilClass = Const Value(nil)
              v5:Fixnum[1] = Const Value(1)
              v13:BasicObject = SendWithoutBlock v22, :new, v5
              Return v13
        "#]]);
    }

    #[test]
    fn test_opt_length() {
        eval("
            def test(a,b) = [a,b].length
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:ArrayExact = NewArray v1, v2
              PatchPoint MethodRedefined(Array@0x1000, length@0x1008, cme:0x1010)
              v10:Fixnum = CCall length@0x1038, v5
              Return v10
        "#]]);
    }

    #[test]
    fn test_opt_size() {
        eval("
            def test(a,b) = [a,b].size
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              v5:ArrayExact = NewArray v1, v2
              PatchPoint MethodRedefined(Array@0x1000, size@0x1008, cme:0x1010)
              v10:Fixnum = CCall size@0x1038, v5
              Return v10
        "#]]);
    }

    #[test]
    fn test_getinstancevariable() {
        eval("
            def test = @foo
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:BasicObject = GetIvar v0, :@foo
              Return v3
        "#]]);
    }

    #[test]
    fn test_setinstancevariable() {
        eval("
            def test = @foo = 1
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              SetIvar v0, :@foo, v2
              Return v2
        "#]]);
    }

    #[test]
    fn test_elide_freeze_with_frozen_hash() {
        eval("
            def test = {}.freeze
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              PatchPoint BOPRedefined(HASH_REDEFINED_OP_FLAG, BOP_FREEZE)
              Return v3
        "#]]);
    }

    #[test]
    fn test_dont_optimize_hash_freeze_if_redefined() {
        eval("
            class Hash
              def freeze; end
            end
            def test = {}.freeze
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:5:
            bb0(v0:BasicObject):
              v3:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v4:BasicObject = SendWithoutBlock v3, :freeze
              Return v4
        "#]]);
    }

    #[test]
    fn test_elide_freeze_with_refrozen_hash() {
        eval("
            def test = {}.freeze.freeze
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:HashExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              PatchPoint BOPRedefined(HASH_REDEFINED_OP_FLAG, BOP_FREEZE)
              PatchPoint BOPRedefined(HASH_REDEFINED_OP_FLAG, BOP_FREEZE)
              Return v3
        "#]]);
    }

    #[test]
    fn test_no_elide_freeze_with_unfrozen_hash() {
        eval("
            def test = {}.dup.freeze
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:HashExact = NewHash
              v5:BasicObject = SendWithoutBlock v3, :dup
              v7:BasicObject = SendWithoutBlock v5, :freeze
              Return v7
        "#]]);
    }

    #[test]
    fn test_no_elide_freeze_hash_with_args() {
        eval("
            def test = {}.freeze(nil)
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:HashExact = NewHash
              v4:NilClass = Const Value(nil)
              v6:BasicObject = SendWithoutBlock v3, :freeze, v4
              Return v6
        "#]]);
    }

    #[test]
    fn test_elide_freeze_with_frozen_ary() {
        eval("
            def test = [].freeze
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
              Return v3
        "#]]);
    }

    #[test]
    fn test_elide_freeze_with_refrozen_ary() {
        eval("
            def test = [].freeze.freeze
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
              PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
              Return v3
        "#]]);
    }

    #[test]
    fn test_no_elide_freeze_with_unfrozen_ary() {
        eval("
            def test = [].dup.freeze
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:ArrayExact = NewArray
              v5:BasicObject = SendWithoutBlock v3, :dup
              v7:BasicObject = SendWithoutBlock v5, :freeze
              Return v7
        "#]]);
    }

    #[test]
    fn test_no_elide_freeze_ary_with_args() {
        eval("
            def test = [].freeze(nil)
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:ArrayExact = NewArray
              v4:NilClass = Const Value(nil)
              v6:BasicObject = SendWithoutBlock v3, :freeze, v4
              Return v6
        "#]]);
    }

    #[test]
    fn test_elide_freeze_with_frozen_str() {
        eval("
            def test = ''.freeze
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE)
              Return v3
        "#]]);
    }

    #[test]
    fn test_elide_freeze_with_refrozen_str() {
        eval("
            def test = ''.freeze.freeze
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE)
              PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE)
              Return v3
        "#]]);
    }

    #[test]
    fn test_no_elide_freeze_with_unfrozen_str() {
        eval("
            def test = ''.dup.freeze
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v2:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v3:StringExact = StringCopy v2
              v5:BasicObject = SendWithoutBlock v3, :dup
              v7:BasicObject = SendWithoutBlock v5, :freeze
              Return v7
        "#]]);
    }

    #[test]
    fn test_no_elide_freeze_str_with_args() {
        eval("
            def test = ''.freeze(nil)
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v2:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v3:StringExact = StringCopy v2
              v4:NilClass = Const Value(nil)
              v6:BasicObject = SendWithoutBlock v3, :freeze, v4
              Return v6
        "#]]);
    }

    #[test]
    fn test_elide_uminus_with_frozen_str() {
        eval("
            def test = -''
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_UMINUS)
              Return v3
        "#]]);
    }

    #[test]
    fn test_elide_uminus_with_refrozen_str() {
        eval("
            def test = -''.freeze
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_FREEZE)
              PatchPoint BOPRedefined(STRING_REDEFINED_OP_FLAG, BOP_UMINUS)
              Return v3
        "#]]);
    }

    #[test]
    fn test_no_elide_uminus_with_unfrozen_str() {
        eval("
            def test = -''.dup
        ");
        assert_optimized_method_hir("test",  expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v2:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v3:StringExact = StringCopy v2
              v5:BasicObject = SendWithoutBlock v3, :dup
              v7:BasicObject = SendWithoutBlock v5, :-@
              Return v7
        "#]]);
    }

    #[test]
    fn test_objtostring_anytostring_string() {
        eval(r##"
            def test = "#{('foo')}"
        "##);
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v2:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v3:StringExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
              v4:StringExact = StringCopy v3
              SideExit UnknownOpcode(concatstrings)
        "#]]);
    }

    #[test]
    fn test_objtostring_anytostring_with_non_string() {
        eval(r##"
            def test = "#{1}"
        "##);
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v2:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v3:Fixnum[1] = Const Value(1)
              v10:BasicObject = SendWithoutBlock v3, :to_s
              v7:String = AnyToString v3, str: v10
              SideExit UnknownOpcode(concatstrings)
        "#]]);
    }

    #[test]
    fn test_branchnil_nil() {
        eval("
            def test
              x = nil
              x&.itself
            end
        ");

        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v3:NilClass = Const Value(nil)
              Return v3
        "#]]);
    }

    #[test]
    fn test_branchnil_truthy() {
        eval("
            def test
              x = 1
              x&.itself
            end
        ");

        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v3:Fixnum[1] = Const Value(1)
              PatchPoint MethodRedefined(Integer@0x1000, itself@0x1008, cme:0x1010)
              v15:BasicObject = CCall itself@0x1038, v3
              Return v15
        "#]]);
    }

    #[test]
    fn test_eliminate_load_from_frozen_array_in_bounds() {
        eval(r##"
            def test = [4,5,6].freeze[1]
        "##);
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
              v5:Fixnum[1] = Const Value(1)
              PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_AREF)
              v11:Fixnum[5] = Const Value(5)
              Return v11
        "#]]);
    }

    #[test]
    fn test_eliminate_load_from_frozen_array_negative() {
        eval(r##"
            def test = [4,5,6].freeze[-3]
        "##);
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
              v5:Fixnum[-3] = Const Value(-3)
              PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_AREF)
              v11:Fixnum[4] = Const Value(4)
              Return v11
        "#]]);
    }

    #[test]
    fn test_eliminate_load_from_frozen_array_negative_out_of_bounds() {
        eval(r##"
            def test = [4,5,6].freeze[-10]
        "##);
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
              v5:Fixnum[-10] = Const Value(-10)
              PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_AREF)
              v11:NilClass = Const Value(nil)
              Return v11
        "#]]);
    }

    #[test]
    fn test_eliminate_load_from_frozen_array_out_of_bounds() {
        eval(r##"
            def test = [4,5,6].freeze[10]
        "##);
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v3:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
              v5:Fixnum[10] = Const Value(10)
              PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_AREF)
              v11:NilClass = Const Value(nil)
              Return v11
        "#]]);
    }

    #[test]
    fn test_dont_optimize_array_aref_if_redefined() {
        eval(r##"
            class Array
              def [](index); end
            end
            def test = [4,5,6].freeze[10]
        "##);
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:5:
            bb0(v0:BasicObject):
              v3:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              PatchPoint BOPRedefined(ARRAY_REDEFINED_OP_FLAG, BOP_FREEZE)
              v5:Fixnum[10] = Const Value(10)
              v7:BasicObject = SendWithoutBlock v3, :[], v5
              Return v7
        "#]]);
    }

    #[test]
    fn test_dont_optimize_array_max_if_redefined() {
        eval(r##"
            class Array
              def max = 10
            end
            def test = [4,5,6].max
        "##);
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:5:
            bb0(v0:BasicObject):
              v2:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v4:ArrayExact = ArrayDup v2
              PatchPoint MethodRedefined(Array@0x1008, max@0x1010, cme:0x1018)
              v9:BasicObject = SendWithoutBlockDirect v4, :max (0x1040)
              Return v9
        "#]]);
    }

    #[test]
    fn test_set_type_from_constant() {
        eval("
            MY_SET = Set.new

            def test = MY_SET

            test
            test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:4:
            bb0(v0:BasicObject):
              PatchPoint SingleRactorMode
              PatchPoint StableConstantNames(0x1000, MY_SET)
              v7:SetExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
              Return v7
        "#]]);
    }

    #[test]
    fn test_regexp_type() {
        eval("
            def test = /a/
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v2:RegexpExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              Return v2
        "#]]);
    }

    #[test]
    fn test_nil_nil_specialized_to_ccall() {
        eval("
            def test = nil.nil?
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v2:NilClass = Const Value(nil)
              PatchPoint MethodRedefined(NilClass@0x1000, nil?@0x1008, cme:0x1010)
              v7:TrueClass = CCall nil?@0x1038, v2
              Return v7
        "#]]);
    }

    #[test]
    fn test_eliminate_nil_nil_specialized_to_ccall() {
        eval("
            def test
              nil.nil?
              1
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:NilClass = Const Value(nil)
              PatchPoint MethodRedefined(NilClass@0x1000, nil?@0x1008, cme:0x1010)
              v5:Fixnum[1] = Const Value(1)
              Return v5
        "#]]);
    }

    #[test]
    fn test_non_nil_nil_specialized_to_ccall() {
        eval("
            def test = 1.nil?
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              PatchPoint MethodRedefined(Integer@0x1000, nil?@0x1008, cme:0x1010)
              v7:FalseClass = CCall nil?@0x1038, v2
              Return v7
        "#]]);
    }

    #[test]
    fn test_eliminate_non_nil_nil_specialized_to_ccall() {
        eval("
            def test
              1.nil?
              2
            end
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              v2:Fixnum[1] = Const Value(1)
              PatchPoint MethodRedefined(Integer@0x1000, nil?@0x1008, cme:0x1010)
              v5:Fixnum[2] = Const Value(2)
              Return v5
        "#]]);
    }

    #[test]
    fn test_guard_nil_for_nil_opt() {
        eval("
            def test(val) = val.nil?

            test(nil)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint MethodRedefined(NilClass@0x1000, nil?@0x1008, cme:0x1010)
              v7:NilClass = GuardType v1, NilClass
              v8:TrueClass = CCall nil?@0x1038, v7
              Return v8
        "#]]);
    }

    #[test]
    fn test_guard_false_for_nil_opt() {
        eval("
            def test(val) = val.nil?

            test(false)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint MethodRedefined(FalseClass@0x1000, nil?@0x1008, cme:0x1010)
              v7:FalseClass = GuardType v1, FalseClass
              v8:FalseClass = CCall nil?@0x1038, v7
              Return v8
        "#]]);
    }

    #[test]
    fn test_guard_true_for_nil_opt() {
        eval("
            def test(val) = val.nil?

            test(true)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint MethodRedefined(TrueClass@0x1000, nil?@0x1008, cme:0x1010)
              v7:TrueClass = GuardType v1, TrueClass
              v8:FalseClass = CCall nil?@0x1038, v7
              Return v8
        "#]]);
    }

    #[test]
    fn test_guard_symbol_for_nil_opt() {
        eval("
            def test(val) = val.nil?

            test(:foo)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint MethodRedefined(Symbol@0x1000, nil?@0x1008, cme:0x1010)
              v7:StaticSymbol = GuardType v1, StaticSymbol
              v8:FalseClass = CCall nil?@0x1038, v7
              Return v8
        "#]]);
    }

    #[test]
    fn test_guard_fixnum_for_nil_opt() {
        eval("
            def test(val) = val.nil?

            test(1)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint MethodRedefined(Integer@0x1000, nil?@0x1008, cme:0x1010)
              v7:Fixnum = GuardType v1, Fixnum
              v8:FalseClass = CCall nil?@0x1038, v7
              Return v8
        "#]]);
    }

    #[test]
    fn test_guard_float_for_nil_opt() {
        eval("
            def test(val) = val.nil?

            test(1.0)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint MethodRedefined(Float@0x1000, nil?@0x1008, cme:0x1010)
              v7:Flonum = GuardType v1, Flonum
              v8:FalseClass = CCall nil?@0x1038, v7
              Return v8
        "#]]);
    }

    #[test]
    fn test_guard_string_for_nil_opt() {
        eval("
            def test(val) = val.nil?

            test('foo')
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint MethodRedefined(String@0x1000, nil?@0x1008, cme:0x1010)
              v7:StringExact = GuardType v1, StringExact
              v8:FalseClass = CCall nil?@0x1038, v7
              Return v8
        "#]]);
    }

    #[test]
    fn test_guard_fixnum_and_fixnum() {
        eval("
            def test(x, y) = x & y

            test(1, 2)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, 28)
              v8:Fixnum = GuardType v1, Fixnum
              v9:Fixnum = GuardType v2, Fixnum
              v10:Fixnum = FixnumAnd v8, v9
              Return v10
        "#]]);
    }

    #[test]
    fn test_guard_fixnum_or_fixnum() {
        eval("
            def test(x, y) = x | y

            test(1, 2)
        ");
        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:2:
            bb0(v0:BasicObject, v1:BasicObject, v2:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, 29)
              v8:Fixnum = GuardType v1, Fixnum
              v9:Fixnum = GuardType v2, Fixnum
              v10:Fixnum = FixnumOr v8, v9
              Return v10
        "#]]);
    }

    #[test]
    fn test_method_redefinition_patch_point_on_top_level_method() {
        eval("
            def foo; end
            def test = foo

            test; test
        ");

        assert_optimized_method_hir("test", expect![[r#"
            fn test@<compiled>:3:
            bb0(v0:BasicObject):
              PatchPoint MethodRedefined(Object@0x1000, foo@0x1008, cme:0x1010)
              v6:BasicObject[class_exact*:Object@VALUE(0x1000)] = GuardType v0, BasicObject[class_exact*:Object@VALUE(0x1000)]
              v7:BasicObject = SendWithoutBlockDirect v6, :foo (0x1038)
              Return v7
        "#]]);
    }
}
