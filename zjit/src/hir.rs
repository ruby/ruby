//! High-level intermediary representation (IR) in static single-assignment (SSA) form.

// We use the YARV bytecode constants which have a CRuby-style name
#![allow(non_upper_case_globals)]

#![allow(clippy::if_same_then_else)]
#![allow(clippy::match_like_matches_macro)]
use crate::{
    cast::IntoUsize, codegen::local_idx_to_ep_offset, cruby::*, payload::{get_or_create_iseq_payload, IseqPayload}, options::{debug, get_option, DumpHIR}, state::ZJITState, json::Json
};
use std::{
    cell::RefCell, collections::{BTreeSet, HashMap, HashSet, VecDeque}, ffi::{c_void, c_uint, c_int, CStr}, fmt::Display, mem::{align_of, size_of}, ptr, slice::Iter
};
use crate::hir_type::{Type, types};
use crate::bitset::BitSet;
use crate::profile::{TypeDistributionSummary, ProfiledType};
use crate::stats::Counter;
use SendFallbackReason::*;

mod tests;
mod opt_tests;

/// An index of an [`Insn`] in a [`Function`]. This is a popular
/// type since this effectively acts as a pointer to an [`Insn`].
/// See also: [`Function::find`].
#[derive(Copy, Clone, Ord, PartialOrd, Eq, PartialEq, Hash, Debug)]
pub struct InsnId(pub usize);

impl From<InsnId> for usize {
    fn from(val: InsnId) -> Self {
        val.0
    }
}

impl std::fmt::Display for InsnId {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "v{}", self.0)
    }
}

/// The index of a [`Block`], which effectively acts like a pointer.
#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug, PartialOrd, Ord)]
pub struct BlockId(pub usize);

impl From<BlockId> for usize {
    fn from(val: BlockId) -> Self {
        val.0
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
    pub fn print(self, ptr_map: &PtrPrintMap) -> VALUEPrinter<'_> {
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
    /// TracePoint is not enabled. If TracePoint is enabled, this is invalidated.
    NoTracePoint,
    /// cfp->ep is not escaped to the heap on the ISEQ
    NoEPEscape(IseqPtr),
    /// There is one ractor running. If a non-root ractor gets spawned, this is invalidated.
    SingleRactorMode,
    /// Objects of this class have no singleton class.
    /// When a singleton class is created for an object of this class, this is invalidated.
    NoSingletonClass {
        klass: VALUE,
    },
}

impl Invariant {
    pub fn print(self, ptr_map: &PtrPrintMap) -> InvariantPrinter<'_> {
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
            _ => panic!("Invalid special object type: {value}"),
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
                    BOP_PLUS     => write!(f, "BOP_PLUS")?,
                    BOP_MINUS    => write!(f, "BOP_MINUS")?,
                    BOP_MULT     => write!(f, "BOP_MULT")?,
                    BOP_DIV      => write!(f, "BOP_DIV")?,
                    BOP_MOD      => write!(f, "BOP_MOD")?,
                    BOP_EQ       => write!(f, "BOP_EQ")?,
                    BOP_EQQ      => write!(f, "BOP_EQQ")?,
                    BOP_LT       => write!(f, "BOP_LT")?,
                    BOP_LE       => write!(f, "BOP_LE")?,
                    BOP_LTLT     => write!(f, "BOP_LTLT")?,
                    BOP_AREF     => write!(f, "BOP_AREF")?,
                    BOP_ASET     => write!(f, "BOP_ASET")?,
                    BOP_LENGTH   => write!(f, "BOP_LENGTH")?,
                    BOP_SIZE     => write!(f, "BOP_SIZE")?,
                    BOP_EMPTY_P  => write!(f, "BOP_EMPTY_P")?,
                    BOP_NIL_P    => write!(f, "BOP_NIL_P")?,
                    BOP_SUCC     => write!(f, "BOP_SUCC")?,
                    BOP_GT       => write!(f, "BOP_GT")?,
                    BOP_GE       => write!(f, "BOP_GE")?,
                    BOP_NOT      => write!(f, "BOP_NOT")?,
                    BOP_NEQ      => write!(f, "BOP_NEQ")?,
                    BOP_MATCH    => write!(f, "BOP_MATCH")?,
                    BOP_FREEZE   => write!(f, "BOP_FREEZE")?,
                    BOP_UMINUS   => write!(f, "BOP_UMINUS")?,
                    BOP_MAX      => write!(f, "BOP_MAX")?,
                    BOP_MIN      => write!(f, "BOP_MIN")?,
                    BOP_HASH     => write!(f, "BOP_HASH")?,
                    BOP_CALL     => write!(f, "BOP_CALL")?,
                    BOP_AND      => write!(f, "BOP_AND")?,
                    BOP_OR       => write!(f, "BOP_OR")?,
                    BOP_CMP      => write!(f, "BOP_CMP")?,
                    BOP_DEFAULT  => write!(f, "BOP_DEFAULT")?,
                    BOP_PACK     => write!(f, "BOP_PACK")?,
                    BOP_INCLUDE_P => write!(f, "BOP_INCLUDE_P")?,
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
            Invariant::NoTracePoint => write!(f, "NoTracePoint"),
            Invariant::NoEPEscape(iseq) => write!(f, "NoEPEscape({})", &iseq_name(iseq)),
            Invariant::SingleRactorMode => write!(f, "SingleRactorMode"),
            Invariant::NoSingletonClass { klass } => {
                let class_name = get_class_name(klass);
                write!(f, "NoSingletonClass({}@{:p})",
                    class_name,
                    self.ptr_map.map_ptr(klass.as_ptr::<VALUE>()))
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq, Copy)]
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
    CShape(ShapeId),
    CUInt64(u64),
    CPtr(*const u8),
    CDouble(f64),
}

impl std::fmt::Display for Const {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        self.print(&PtrPrintMap::identity()).fmt(f)
    }
}

impl Const {
    pub fn print<'a>(&'a self, ptr_map: &'a PtrPrintMap) -> ConstPrinter<'a> {
        ConstPrinter { inner: self, ptr_map }
    }
}

#[derive(Clone, Copy)]
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
        write!(f, "{self}")
    }
}

impl From<u32> for RangeType {
    fn from(flag: u32) -> Self {
        match flag {
            0 => RangeType::Inclusive,
            1 => RangeType::Exclusive,
            _ => panic!("Invalid range flag: {flag}"),
        }
    }
}

/// Special regex backref symbol types
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SpecialBackrefSymbol {
    LastMatch,     // $&
    PreMatch,      // $`
    PostMatch,     // $'
    LastGroup,     // $+
}

impl TryFrom<u8> for SpecialBackrefSymbol {
    type Error = String;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value as char {
            '&' => Ok(SpecialBackrefSymbol::LastMatch),
            '`' => Ok(SpecialBackrefSymbol::PreMatch),
            '\'' => Ok(SpecialBackrefSymbol::PostMatch),
            '+' => Ok(SpecialBackrefSymbol::LastGroup),
            c => Err(format!("invalid backref symbol: '{c}'")),
        }
    }
}

/// Print adaptor for [`Const`]. See [`PtrPrintMap`].
pub struct ConstPrinter<'a> {
    inner: &'a Const,
    ptr_map: &'a PtrPrintMap,
}

impl<'a> std::fmt::Display for ConstPrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self.inner {
            Const::Value(val) => write!(f, "Value({})", val.print(self.ptr_map)),
            // TODO: Break out CPtr as a special case. For some reason,
            // when we do that now, {:p} prints a completely different
            // number than {:?} does and we don't know why.
            // We'll have to resolve that first.
            Const::CPtr(val) => write!(f, "CPtr({:?})", self.ptr_map.map_ptr(val)),
            &Const::CShape(shape_id) => write!(f, "CShape({:p})", self.ptr_map.map_shape(shape_id)),
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
/// required to make use of this effectively. The [`std::fmt::Display`]
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
    pub fn map_ptr<T>(&self, ptr: *const T) -> *const T {
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

    /// Map an index into a Ruby object (e.g. for an ivar) for printing
    fn map_index(&self, id: u64) -> *const c_void {
        self.map_ptr(id as *const c_void)
    }

    fn map_offset(&self, id: i32) -> *const c_void {
        self.map_ptr(id as *const c_void)
    }

    /// Map shape ID into a pointer for printing
    pub fn map_shape(&self, id: ShapeId) -> *const c_void {
        self.map_ptr(id.0 as *const c_void)
    }
}

#[derive(Debug, Clone, Copy)]
pub enum SideExitReason {
    UnhandledNewarraySend(vm_opt_newarray_send_type),
    UnhandledDuparraySend(u64),
    UnknownSpecialVariable(u64),
    UnhandledHIRInsn(InsnId),
    UnhandledYARVInsn(u32),
    UnhandledCallType(CallType),
    TooManyKeywordParameters,
    FixnumAddOverflow,
    FixnumSubOverflow,
    FixnumMultOverflow,
    FixnumLShiftOverflow,
    GuardType(Type),
    GuardTypeNot(Type),
    GuardShape(ShapeId),
    GuardBitEquals(Const),
    GuardNotFrozen,
    GuardLess,
    GuardGreaterEq,
    PatchPoint(Invariant),
    CalleeSideExit,
    ObjToStringFallback,
    Interrupt,
    BlockParamProxyModified,
    BlockParamProxyNotIseqOrIfunc,
    StackOverflow,
    FixnumModByZero,
    FixnumDivByZero,
    BoxFixnumOverflow,
}

#[derive(Debug, Clone, Copy)]
pub enum MethodType {
    Iseq,
    Cfunc,
    Attrset,
    Ivar,
    Bmethod,
    Zsuper,
    Alias,
    Undefined,
    NotImplemented,
    Optimized,
    Missing,
    Refined,
    Null,
}

impl From<u32> for MethodType {
    fn from(value: u32) -> Self {
        match value {
            VM_METHOD_TYPE_ISEQ => MethodType::Iseq,
            VM_METHOD_TYPE_CFUNC => MethodType::Cfunc,
            VM_METHOD_TYPE_ATTRSET => MethodType::Attrset,
            VM_METHOD_TYPE_IVAR => MethodType::Ivar,
            VM_METHOD_TYPE_BMETHOD => MethodType::Bmethod,
            VM_METHOD_TYPE_ZSUPER => MethodType::Zsuper,
            VM_METHOD_TYPE_ALIAS => MethodType::Alias,
            VM_METHOD_TYPE_UNDEF => MethodType::Undefined,
            VM_METHOD_TYPE_NOTIMPLEMENTED => MethodType::NotImplemented,
            VM_METHOD_TYPE_OPTIMIZED => MethodType::Optimized,
            VM_METHOD_TYPE_MISSING => MethodType::Missing,
            VM_METHOD_TYPE_REFINED => MethodType::Refined,
            _ => unreachable!("unknown send_without_block def_type: {}", value),
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub enum OptimizedMethodType {
    Send,
    Call,
    BlockCall,
    StructAref,
    StructAset,
}

impl From<u32> for OptimizedMethodType {
    fn from(value: u32) -> Self {
        match value {
            OPTIMIZED_METHOD_TYPE_SEND => OptimizedMethodType::Send,
            OPTIMIZED_METHOD_TYPE_CALL => OptimizedMethodType::Call,
            OPTIMIZED_METHOD_TYPE_BLOCK_CALL => OptimizedMethodType::BlockCall,
            OPTIMIZED_METHOD_TYPE_STRUCT_AREF => OptimizedMethodType::StructAref,
            OPTIMIZED_METHOD_TYPE_STRUCT_ASET => OptimizedMethodType::StructAset,
            _ => unreachable!("unknown send_without_block optimized method type: {}", value),
        }
    }
}

impl std::fmt::Display for SideExitReason {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            SideExitReason::UnhandledYARVInsn(opcode) => write!(f, "UnhandledYARVInsn({})", insn_name(*opcode as usize)),
            SideExitReason::UnhandledNewarraySend(VM_OPT_NEWARRAY_SEND_MAX) => write!(f, "UnhandledNewarraySend(MAX)"),
            SideExitReason::UnhandledNewarraySend(VM_OPT_NEWARRAY_SEND_MIN) => write!(f, "UnhandledNewarraySend(MIN)"),
            SideExitReason::UnhandledNewarraySend(VM_OPT_NEWARRAY_SEND_HASH) => write!(f, "UnhandledNewarraySend(HASH)"),
            SideExitReason::UnhandledNewarraySend(VM_OPT_NEWARRAY_SEND_PACK) => write!(f, "UnhandledNewarraySend(PACK)"),
            SideExitReason::UnhandledNewarraySend(VM_OPT_NEWARRAY_SEND_PACK_BUFFER) => write!(f, "UnhandledNewarraySend(PACK_BUFFER)"),
            SideExitReason::UnhandledNewarraySend(VM_OPT_NEWARRAY_SEND_INCLUDE_P) => write!(f, "UnhandledNewarraySend(INCLUDE_P)"),
            SideExitReason::UnhandledDuparraySend(method_id) => write!(f, "UnhandledDuparraySend({method_id})"),
            SideExitReason::GuardType(guard_type) => write!(f, "GuardType({guard_type})"),
            SideExitReason::GuardTypeNot(guard_type) => write!(f, "GuardTypeNot({guard_type})"),
            SideExitReason::GuardBitEquals(value) => write!(f, "GuardBitEquals({})", value.print(&PtrPrintMap::identity())),
            SideExitReason::PatchPoint(invariant) => write!(f, "PatchPoint({invariant})"),
            _ => write!(f, "{self:?}"),
        }
    }
}

/// Result of resolving the receiver type for method dispatch optimization.
/// Represents whether we know the receiver's class statically at compile-time,
/// have profiled type information, or know nothing about it.
pub enum ReceiverTypeResolution {
    /// No profile information available for the receiver
    NoProfile,
    /// The receiver has a monomorphic profile (single type observed, guard needed)
    Monomorphic { profiled_type: ProfiledType },
    /// The receiver is polymorphic (multiple types, none dominant)
    Polymorphic,
    /// The receiver has a skewed polymorphic profile (dominant type with some other types, guard needed)
    SkewedPolymorphic { profiled_type: ProfiledType },
    /// More than N types seen with no clear winner
    Megamorphic,
    /// Megamorphic, but with a significant skew towards one type
    SkewedMegamorphic { profiled_type: ProfiledType },
    /// The receiver's class is statically known at JIT compile-time (no guard needed)
    StaticallyKnown { class: VALUE },
}

/// Reason why a send-ish instruction cannot be optimized from a fallback instruction
#[derive(Debug, Clone, Copy)]
pub enum SendFallbackReason {
    SendWithoutBlockPolymorphic,
    SendWithoutBlockMegamorphic,
    SendWithoutBlockNoProfiles,
    SendWithoutBlockCfuncNotVariadic,
    SendWithoutBlockCfuncArrayVariadic,
    SendWithoutBlockNotOptimizedMethodType(MethodType),
    SendWithoutBlockNotOptimizedMethodTypeOptimized(OptimizedMethodType),
    SendWithoutBlockNotOptimizedNeedPermission,
    SendWithoutBlockBopRedefined,
    SendWithoutBlockOperandsNotFixnum,
    SendWithoutBlockDirectKeywordMismatch,
    SendWithoutBlockDirectOptionalKeywords,
    SendWithoutBlockDirectKeywordCountMismatch,
    SendWithoutBlockDirectMissingKeyword,
    SendPolymorphic,
    SendMegamorphic,
    SendNoProfiles,
    SendCfuncVariadic,
    SendCfuncArrayVariadic,
    SendNotOptimizedMethodType(MethodType),
    SendNotOptimizedNeedPermission,
    CCallWithFrameTooManyArgs,
    ObjToStringNotString,
    TooManyArgsForLir,
    /// The Proc object for a BMETHOD is not defined by an ISEQ. (See `enum rb_block_type`.)
    BmethodNonIseqProc,
    /// Caller supplies too few or too many arguments than what the callee's parameters expects.
    ArgcParamMismatch,
    /// The call has at least one feature on the caller or callee side that the optimizer does not
    /// support.
    ComplexArgPass,
    /// Caller has keyword arguments but callee doesn't expect them; need to convert to hash.
    UnexpectedKeywordArgs,
    /// Initial fallback reason for every instruction, which should be mutated to
    /// a more actionable reason when an attempt to specialize the instruction fails.
    Uncategorized(ruby_vminsn_type),
}

impl Display for SendFallbackReason {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            SendWithoutBlockPolymorphic => write!(f, "SendWithoutBlock: polymorphic call site"),
            SendWithoutBlockMegamorphic => write!(f, "SendWithoutBlock: megamorphic call site"),
            SendWithoutBlockNoProfiles => write!(f, "SendWithoutBlock: no profile data available"),
            SendWithoutBlockCfuncNotVariadic => write!(f, "SendWithoutBlock: C function is not variadic"),
            SendWithoutBlockCfuncArrayVariadic => write!(f, "SendWithoutBlock: C function expects array variadic"),
            SendWithoutBlockNotOptimizedMethodType(method_type) => write!(f, "SendWithoutBlock: unsupported method type {:?}", method_type),
            SendWithoutBlockNotOptimizedMethodTypeOptimized(opt_type) => write!(f, "SendWithoutBlock: unsupported optimized method type {:?}", opt_type),
            SendWithoutBlockNotOptimizedNeedPermission => write!(f, "SendWithoutBlock: method private or protected and no FCALL"),
            SendNotOptimizedNeedPermission => write!(f, "Send: method private or protected and no FCALL"),
            SendWithoutBlockBopRedefined => write!(f, "SendWithoutBlock: basic operation was redefined"),
            SendWithoutBlockOperandsNotFixnum => write!(f, "SendWithoutBlock: operands are not fixnums"),
            SendWithoutBlockDirectKeywordMismatch => write!(f, "SendWithoutBlockDirect: keyword mismatch"),
            SendWithoutBlockDirectOptionalKeywords => write!(f, "SendWithoutBlockDirect: optional keywords"),
            SendWithoutBlockDirectKeywordCountMismatch => write!(f, "SendWithoutBlockDirect: keyword count mismatch"),
            SendWithoutBlockDirectMissingKeyword => write!(f, "SendWithoutBlockDirect: missing keyword"),
            SendPolymorphic => write!(f, "Send: polymorphic call site"),
            SendMegamorphic => write!(f, "Send: megamorphic call site"),
            SendNoProfiles => write!(f, "Send: no profile data available"),
            SendCfuncVariadic => write!(f, "Send: C function is variadic"),
            SendCfuncArrayVariadic => write!(f, "Send: C function expects array variadic"),
            SendNotOptimizedMethodType(method_type) => write!(f, "Send: unsupported method type {:?}", method_type),
            CCallWithFrameTooManyArgs => write!(f, "CCallWithFrame: too many arguments"),
            ObjToStringNotString => write!(f, "ObjToString: result is not a string"),
            TooManyArgsForLir => write!(f, "Too many arguments for LIR"),
            BmethodNonIseqProc => write!(f, "Bmethod: Proc object is not defined by an ISEQ"),
            ArgcParamMismatch => write!(f, "Argument count does not match parameter count"),
            ComplexArgPass => write!(f, "Complex argument passing"),
            UnexpectedKeywordArgs => write!(f, "Unexpected Keyword Args"),
            Uncategorized(insn) => write!(f, "Uncategorized({})", insn_name(*insn as usize)),
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
    Param,

    StringCopy { val: InsnId, chilled: bool, state: InsnId },
    StringIntern { val: InsnId, state: InsnId },
    StringConcat { strings: Vec<InsnId>, state: InsnId },
    /// Call rb_str_getbyte with known-Fixnum index
    StringGetbyte { string: InsnId, index: InsnId },
    StringSetbyteFixnum { string: InsnId, index: InsnId, value: InsnId },
    StringAppend { recv: InsnId, other: InsnId, state: InsnId },
    StringAppendCodepoint { recv: InsnId, other: InsnId, state: InsnId },

    /// Combine count stack values into a regexp
    ToRegexp { opt: usize, values: Vec<InsnId>, state: InsnId },

    /// Put special object (VMCORE, CBASE, etc.) based on value_type
    PutSpecialObject { value_type: SpecialObjectType },

    /// Call `to_a` on `val` if the method is defined, or make a new array `[val]` otherwise.
    ToArray { val: InsnId, state: InsnId },
    /// Call `to_a` on `val` if the method is defined, or make a new array `[val]` otherwise. If we
    /// called `to_a`, duplicate the returned array.
    ToNewArray { val: InsnId, state: InsnId },
    NewArray { elements: Vec<InsnId>, state: InsnId },
    /// NewHash contains a vec of (key, value) pairs
    NewHash { elements: Vec<InsnId>, state: InsnId },
    NewRange { low: InsnId, high: InsnId, flag: RangeType, state: InsnId },
    NewRangeFixnum { low: InsnId, high: InsnId, flag: RangeType, state: InsnId },
    ArrayDup { val: InsnId, state: InsnId },
    ArrayHash { elements: Vec<InsnId>, state: InsnId },
    ArrayMax { elements: Vec<InsnId>, state: InsnId },
    ArrayInclude { elements: Vec<InsnId>, target: InsnId, state: InsnId },
    ArrayPackBuffer { elements: Vec<InsnId>, fmt: InsnId, buffer: InsnId, state: InsnId },
    DupArrayInclude { ary: VALUE, target: InsnId, state: InsnId },
    /// Extend `left` with the elements from `right`. `left` and `right` must both be `Array`.
    ArrayExtend { left: InsnId, right: InsnId, state: InsnId },
    /// Push `val` onto `array`, where `array` is already `Array`.
    ArrayPush { array: InsnId, val: InsnId, state: InsnId },
    ArrayArefFixnum { array: InsnId, index: InsnId },
    ArrayPop { array: InsnId, state: InsnId },
    /// Return the length of the array as a C `long` ([`types::CInt64`])
    ArrayLength { array: InsnId },

    HashAref { hash: InsnId, key: InsnId, state: InsnId },
    HashAset { hash: InsnId, key: InsnId, val: InsnId, state: InsnId },
    HashDup { val: InsnId, state: InsnId },

    /// Allocate an instance of the `val` object without calling `#initialize` on it.
    /// This can:
    /// * raise an exception if `val` is not a class
    /// * run arbitrary code if `val` is a class with a custom allocator
    ObjectAlloc { val: InsnId, state: InsnId },
    /// Allocate an instance of the `val` class without calling `#initialize` on it.
    /// This requires that `class` has the default allocator (for example via `IsMethodCfunc`).
    /// This won't raise or run arbitrary code because `class` has the default allocator.
    ObjectAllocClass { class: VALUE, state: InsnId },

    /// Check if the value is truthy and "return" a C boolean. In reality, we will likely fuse this
    /// with IfTrue/IfFalse in the backend to generate jcc.
    Test { val: InsnId },
    /// Return C `true` if `val` is `Qnil`, else `false`.
    IsNil { val: InsnId },
    /// Return C `true` if `val`'s method on cd resolves to the cfunc.
    IsMethodCfunc { val: InsnId, cd: *const rb_call_data, cfunc: *const u8, state: InsnId },
    /// Return C `true` if left == right
    IsBitEqual { left: InsnId, right: InsnId },
    /// Return C `true` if left != right
    IsBitNotEqual { left: InsnId, right: InsnId },
    /// Convert a C `bool` to a Ruby `Qtrue`/`Qfalse`. Same as `RBOOL` macro.
    BoxBool { val: InsnId },
    /// Convert a C `long` to a Ruby `Fixnum`. Side exit on overflow.
    BoxFixnum { val: InsnId, state: InsnId },
    UnboxFixnum { val: InsnId },
    // TODO(max): In iseq body types that are not ISEQ_TYPE_METHOD, rewrite to Constant false.
    Defined { op_type: usize, obj: VALUE, pushval: VALUE, v: InsnId, state: InsnId },
    GetConstantPath { ic: *const iseq_inline_constant_cache, state: InsnId },
    /// Kernel#block_given? but without pushing a frame. Similar to [`Insn::Defined`] with
    /// `DEFINED_YIELD`
    IsBlockGiven,
    /// Test the bit at index of val, a Fixnum.
    /// Return Qtrue if the bit is set, else Qfalse.
    FixnumBitCheck { val: InsnId, index: u8 },
    /// Return Qtrue if `val` is an instance of `class`, else Qfalse.
    /// Equivalent to `class_search_ancestor(CLASS_OF(val), class)`.
    IsA { val: InsnId, class: InsnId },

    /// Get a global variable named `id`
    GetGlobal { id: ID, state: InsnId },
    /// Set a global variable named `id` to `val`
    SetGlobal { id: ID, val: InsnId, state: InsnId },

    //NewObject?
    /// Get an instance variable `id` from `self_val`, using the inline cache `ic` if present
    GetIvar { self_val: InsnId, id: ID, ic: *const iseq_inline_iv_cache_entry, state: InsnId },
    /// Set `self_val`'s instance variable `id` to `val`, using the inline cache `ic` if present
    SetIvar { self_val: InsnId, id: ID, val: InsnId, ic: *const iseq_inline_iv_cache_entry, state: InsnId },
    /// Check whether an instance variable exists on `self_val`
    DefinedIvar { self_val: InsnId, id: ID, pushval: VALUE, state: InsnId },

    /// Load cfp->pc
    LoadPC,
    /// Load EC
    LoadEC,
    /// Load cfp->self
    LoadSelf,
    LoadField { recv: InsnId, id: ID, offset: i32, return_type: Type },
    /// Write `val` at an offset of `recv`.
    /// When writing a Ruby object to a Ruby object, one must use GuardNotFrozen (or equivalent) before and WriteBarrier after.
    StoreField { recv: InsnId, id: ID, offset: i32, val: InsnId },
    WriteBarrier { recv: InsnId, val: InsnId },

    /// Get a local variable from a higher scope or the heap.
    /// If `use_sp` is true, it uses the SP register to optimize the read.
    /// `rest_param` is used by infer_types to infer the ArrayExact type.
    GetLocal { level: u32, ep_offset: u32, use_sp: bool, rest_param: bool },
    /// Set a local variable in a higher scope or the heap
    SetLocal { level: u32, ep_offset: u32, val: InsnId },
    GetSpecialSymbol { symbol_type: SpecialBackrefSymbol, state: InsnId },
    GetSpecialNumber { nth: u64, state: InsnId },

    /// Get a class variable `id`
    GetClassVar { id: ID, ic: *const iseq_inline_cvar_cache_entry, state: InsnId },
    /// Set a class variable `id` to `val`
    SetClassVar { id: ID, val: InsnId, ic: *const iseq_inline_cvar_cache_entry, state: InsnId },

    /// Own a FrameState so that instructions can look up their dominating FrameState when
    /// generating deopt side-exits and frame reconstruction metadata. Does not directly generate
    /// any code.
    Snapshot { state: FrameState },

    /// Unconditional jump
    Jump(BranchEdge),

    /// Conditional branch instructions
    IfTrue { val: InsnId, target: BranchEdge },
    IfFalse { val: InsnId, target: BranchEdge },

    /// Call a C function without pushing a frame
    /// `name` is for printing purposes only
    CCall { cfunc: *const u8, recv: InsnId, args: Vec<InsnId>, name: ID, return_type: Type, elidable: bool },

    /// Call a C function that pushes a frame
    CCallWithFrame {
        cd: *const rb_call_data, // cd for falling back to SendWithoutBlock
        cfunc: *const u8,
        recv: InsnId,
        args: Vec<InsnId>,
        cme: *const rb_callable_method_entry_t,
        name: ID,
        state: InsnId,
        return_type: Type,
        elidable: bool,
        blockiseq: Option<IseqPtr>,
    },

    /// Call a variadic C function with signature: func(int argc, VALUE *argv, VALUE recv)
    /// This handles frame setup, argv creation, and frame teardown all in one
    CCallVariadic {
        cfunc: *const u8,
        recv: InsnId,
        args: Vec<InsnId>,
        cme: *const rb_callable_method_entry_t,
        name: ID,
        state: InsnId,
        return_type: Type,
        elidable: bool,
        blockiseq: Option<IseqPtr>,
    },

    /// Un-optimized fallback implementation (dynamic dispatch) for send-ish instructions
    /// Ignoring keyword arguments etc for now
    SendWithoutBlock {
        recv: InsnId,
        cd: *const rb_call_data,
        args: Vec<InsnId>,
        state: InsnId,
        reason: SendFallbackReason,
    },
    Send {
        recv: InsnId,
        cd: *const rb_call_data,
        blockiseq: IseqPtr,
        args: Vec<InsnId>,
        state: InsnId,
        reason: SendFallbackReason,
    },
    SendForward {
        recv: InsnId,
        cd: *const rb_call_data,
        blockiseq: IseqPtr,
        args: Vec<InsnId>,
        state: InsnId,
        reason: SendFallbackReason,
    },
    InvokeSuper {
        recv: InsnId,
        cd: *const rb_call_data,
        blockiseq: IseqPtr,
        args: Vec<InsnId>,
        state: InsnId,
        reason: SendFallbackReason,
    },
    InvokeBlock {
        cd: *const rb_call_data,
        args: Vec<InsnId>,
        state: InsnId,
        reason: SendFallbackReason,
    },

    /// Optimized ISEQ call
    SendWithoutBlockDirect {
        recv: InsnId,
        cd: *const rb_call_data,
        cme: *const rb_callable_method_entry_t,
        iseq: IseqPtr,
        args: Vec<InsnId>,
        state: InsnId,
    },

    // Invoke a builtin function
    InvokeBuiltin {
        bf: rb_builtin_function,
        recv: InsnId,
        args: Vec<InsnId>,
        state: InsnId,
        leaf: bool,
        return_type: Option<Type>,  // None for unannotated builtins
    },

    /// Set up frame. Remember the address as the JIT entry for the insn_idx in `jit_entry_insns()[jit_entry_idx]`.
    EntryPoint { jit_entry_idx: Option<usize> },
    /// Control flow instructions
    Return { val: InsnId },
    /// Non-local control flow. See the throw YARV instruction
    Throw { throw_state: u32, val: InsnId, state: InsnId },

    /// Fixnum +, -, *, /, %, ==, !=, <, <=, >, >=, &, |, ^, <<
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
    FixnumXor  { left: InsnId, right: InsnId },
    FixnumLShift { left: InsnId, right: InsnId, state: InsnId },
    FixnumRShift { left: InsnId, right: InsnId },

    // Distinct from `SendWithoutBlock` with `mid:to_s` because does not have a patch point for String to_s being redefined
    ObjToString { val: InsnId, cd: *const rb_call_data, state: InsnId },
    AnyToString { val: InsnId, str: InsnId, state: InsnId },

    /// Side-exit if val doesn't have the expected type.
    GuardType { val: InsnId, guard_type: Type, state: InsnId },
    GuardTypeNot { val: InsnId, guard_type: Type, state: InsnId },
    /// Side-exit if val is not the expected Const.
    GuardBitEquals { val: InsnId, expected: Const, state: InsnId },
    /// Side-exit if val doesn't have the expected shape.
    GuardShape { val: InsnId, shape: ShapeId, state: InsnId },
    /// Side-exit if the block param has been modified or the block handler for the frame
    /// is neither ISEQ nor ifunc, which makes it incompatible with rb_block_param_proxy.
    GuardBlockParamProxy { level: u32, state: InsnId },
    /// Side-exit if val is frozen. Does *not* check if the val is an immediate; assumes that it is
    /// a heap object.
    GuardNotFrozen { recv: InsnId, state: InsnId },
    /// Side-exit if left is not greater than or equal to right (both operands are C long).
    GuardGreaterEq { left: InsnId, right: InsnId, state: InsnId },
    /// Side-exit if left is not less than right (both operands are C long).
    GuardLess { left: InsnId, right: InsnId, state: InsnId },

    /// Generate no code (or padding if necessary) and insert a patch point
    /// that can be rewritten to a side exit when the Invariant is broken.
    PatchPoint { invariant: Invariant, state: InsnId },

    /// Side-exit into the interpreter.
    SideExit { state: InsnId, reason: SideExitReason },

    /// Increment a counter in ZJIT stats
    IncrCounter(Counter),

    /// Increment a counter in ZJIT stats for the given counter pointer
    IncrCounterPtr { counter_ptr: *mut u64 },

    /// Equivalent of RUBY_VM_CHECK_INTS. Automatically inserted by the compiler before jumps and
    /// return instructions.
    CheckInterrupts { state: InsnId },
}

impl Insn {
    /// Not every instruction returns a value. Return true if the instruction does and false otherwise.
    pub fn has_output(&self) -> bool {
        match self {
            Insn::Jump(_)
            | Insn::IfTrue { .. } | Insn::IfFalse { .. } | Insn::EntryPoint { .. } | Insn::Return { .. }
            | Insn::PatchPoint { .. } | Insn::SetIvar { .. } | Insn::SetClassVar { .. } | Insn::ArrayExtend { .. }
            | Insn::ArrayPush { .. } | Insn::SideExit { .. } | Insn::SetGlobal { .. }
            | Insn::SetLocal { .. } | Insn::Throw { .. } | Insn::IncrCounter(_) | Insn::IncrCounterPtr { .. }
            | Insn::CheckInterrupts { .. } | Insn::GuardBlockParamProxy { .. } | Insn::StoreField { .. } | Insn::WriteBarrier { .. }
            | Insn::HashAset { .. } => false,
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

    pub fn print<'a>(&self, ptr_map: &'a PtrPrintMap, iseq: Option<IseqPtr>) -> InsnPrinter<'a> {
        InsnPrinter { inner: self.clone(), ptr_map, iseq }
    }

    /// Return true if the instruction needs to be kept around. For example, if the instruction
    /// might have a side effect, or if the instruction may raise an exception.
    fn has_effects(&self) -> bool {
        match self {
            Insn::Const { .. } => false,
            Insn::Param => false,
            Insn::StringCopy { .. } => false,
            Insn::NewArray { .. } => false,
            // NewHash's operands may be hashed and compared for equality, which could have
            // side-effects.
            Insn::NewHash { elements, .. } => !elements.is_empty(),
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
            Insn::FixnumXor  { .. } => false,
            Insn::FixnumLShift { .. } => false,
            Insn::FixnumRShift { .. } => false,
            Insn::GetLocal   { .. } => false,
            Insn::IsNil      { .. } => false,
            Insn::LoadPC => false,
            Insn::LoadEC => false,
            Insn::LoadSelf => false,
            Insn::LoadField { .. } => false,
            Insn::CCall { elidable, .. } => !elidable,
            Insn::CCallWithFrame { elidable, .. } => !elidable,
            Insn::ObjectAllocClass { .. } => false,
            // TODO: NewRange is effects free if we can prove the two ends to be Fixnum,
            // but we don't have type information here in `impl Insn`. See rb_range_new().
            Insn::NewRange { .. } => true,
            Insn::NewRangeFixnum { .. } => false,
            Insn::StringGetbyte { .. } => false,
            Insn::IsBlockGiven => false,
            Insn::BoxFixnum { .. } => false,
            Insn::BoxBool { .. } => false,
            Insn::IsBitEqual { .. } => false,
            Insn::IsA { .. } => false,
            _ => true,
        }
    }
}

/// Print adaptor for [`Insn`]. See [`PtrPrintMap`].
pub struct InsnPrinter<'a> {
    inner: Insn,
    ptr_map: &'a PtrPrintMap,
    iseq: Option<IseqPtr>,
}

/// Get the name of a local variable given iseq, level, and ep_offset.
/// Returns
/// - `":name"` if iseq is available and name is a real identifier,
/// - `"<empty>"` for anonymous locals.
/// - `None` if iseq is not available.
///   (When `Insn` is printed in a panic/debug message the `Display::fmt` method is called, which can't access an iseq.)
///
/// This mimics local_var_name() from iseq.c.
fn get_local_var_name_for_printer(iseq: Option<IseqPtr>, level: u32, ep_offset: u32) -> Option<String> {
    let mut current_iseq = iseq?;
    for _ in 0..level {
        current_iseq = unsafe { rb_get_iseq_body_parent_iseq(current_iseq) };
    }
    let local_idx = ep_offset_to_local_idx(current_iseq, ep_offset);
    let id: ID = unsafe { rb_zjit_local_id(current_iseq, local_idx.try_into().unwrap()) };

    if id.0 == 0 || unsafe { rb_id2str(id) } == Qfalse {
        return Some(String::from("<empty>"));
    }

    Some(format!(":{}", id.contents_lossy()))
}

static REGEXP_FLAGS: &[(u32, &str)] = &[
    (ONIG_OPTION_MULTILINE, "MULTILINE"),
    (ONIG_OPTION_IGNORECASE, "IGNORECASE"),
    (ONIG_OPTION_EXTEND, "EXTENDED"),
    (ARG_ENCODING_FIXED, "FIXEDENCODING"),
    (ARG_ENCODING_NONE, "NOENCODING"),
];

impl<'a> std::fmt::Display for InsnPrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match &self.inner {
            Insn::Const { val } => { write!(f, "Const {}", val.print(self.ptr_map)) }
            Insn::Param => { write!(f, "Param") }
            Insn::NewArray { elements, .. } => {
                write!(f, "NewArray")?;
                let mut prefix = " ";
                for element in elements {
                    write!(f, "{prefix}{element}")?;
                    prefix = ", ";
                }
                Ok(())
            }
            Insn::ArrayArefFixnum { array, index, .. } => {
                write!(f, "ArrayArefFixnum {array}, {index}")
            }
            Insn::ArrayPop { array, .. } => {
                write!(f, "ArrayPop {array}")
            }
            Insn::ArrayLength { array } => {
                write!(f, "ArrayLength {array}")
            }
            Insn::NewHash { elements, .. } => {
                write!(f, "NewHash")?;
                let mut prefix = " ";
                for chunk in elements.chunks(2) {
                    if let [key, value] = chunk {
                        write!(f, "{prefix}{key}: {value}")?;
                        prefix = ", ";
                    }
                }
                Ok(())
            }
            Insn::NewRange { low, high, flag, .. } => {
                write!(f, "NewRange {low} {flag} {high}")
            }
            Insn::NewRangeFixnum { low, high, flag, .. } => {
                write!(f, "NewRangeFixnum {low} {flag} {high}")
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
            Insn::ArrayHash { elements, .. } => {
                write!(f, "ArrayHash")?;
                let mut prefix = " ";
                for element in elements {
                    write!(f, "{prefix}{element}")?;
                    prefix = ", ";
                }
                Ok(())
            }
            Insn::ArrayInclude { elements, target, .. } => {
                write!(f, "ArrayInclude")?;
                let mut prefix = " ";
                for element in elements {
                    write!(f, "{prefix}{element}")?;
                    prefix = ", ";
                }
                write!(f, " | {target}")
            }
            Insn::ArrayPackBuffer { elements, fmt, buffer, .. } => {
                write!(f, "ArrayPackBuffer ")?;
                for element in elements {
                    write!(f, "{element}, ")?;
                }
                write!(f, "fmt: {fmt}, buf: {buffer}")
            }
            Insn::DupArrayInclude { ary, target, .. } => {
                write!(f, "DupArrayInclude {} | {}", ary.print(self.ptr_map), target)
            }
            Insn::ArrayDup { val, .. } => { write!(f, "ArrayDup {val}") }
            Insn::HashDup { val, .. } => { write!(f, "HashDup {val}") }
            Insn::HashAref { hash, key, .. } => { write!(f, "HashAref {hash}, {key}")}
            Insn::HashAset { hash, key, val, .. } => { write!(f, "HashAset {hash}, {key}, {val}")}
            Insn::ObjectAlloc { val, .. } => { write!(f, "ObjectAlloc {val}") }
            &Insn::ObjectAllocClass { class, .. } => {
                let class_name = get_class_name(class);
                write!(f, "ObjectAllocClass {class_name}:{}", class.print(self.ptr_map))
            }
            Insn::StringCopy { val, .. } => { write!(f, "StringCopy {val}") }
            Insn::StringConcat { strings, .. } => {
                write!(f, "StringConcat")?;
                let mut prefix = " ";
                for string in strings {
                    write!(f, "{prefix}{string}")?;
                    prefix = ", ";
                }

                Ok(())
            }
            Insn::StringGetbyte { string, index, .. } => {
                write!(f, "StringGetbyte {string}, {index}")
            }
            Insn::StringSetbyteFixnum { string, index, value, .. } => {
                write!(f, "StringSetbyteFixnum {string}, {index}, {value}")
            }
            Insn::StringAppend { recv, other, .. } => {
                write!(f, "StringAppend {recv}, {other}")
            }
            Insn::StringAppendCodepoint { recv, other, .. } => {
                write!(f, "StringAppendCodepoint {recv}, {other}")
            }
            Insn::ToRegexp { values, opt, .. } => {
                write!(f, "ToRegexp")?;
                let mut prefix = " ";
                for value in values {
                    write!(f, "{prefix}{value}")?;
                    prefix = ", ";
                }

                let opt = *opt as u32;
                if opt != 0 {
                    write!(f, ", ")?;
                    let mut sep = "";
                    for (flag, name) in REGEXP_FLAGS {
                        if opt & flag != 0 {
                            write!(f, "{sep}{name}")?;
                            sep = "|";
                        }
                    }
                }

                Ok(())
            }
            Insn::Test { val } => { write!(f, "Test {val}") }
            Insn::IsNil { val } => { write!(f, "IsNil {val}") }
            Insn::IsMethodCfunc { val, cd, .. } => { write!(f, "IsMethodCFunc {val}, :{}", ruby_call_method_name(*cd)) }
            Insn::IsBitEqual { left, right } => write!(f, "IsBitEqual {left}, {right}"),
            Insn::IsBitNotEqual { left, right } => write!(f, "IsBitNotEqual {left}, {right}"),
            Insn::BoxBool { val } => write!(f, "BoxBool {val}"),
            Insn::BoxFixnum { val, .. } => write!(f, "BoxFixnum {val}"),
            Insn::UnboxFixnum { val } => write!(f, "UnboxFixnum {val}"),
            Insn::Jump(target) => { write!(f, "Jump {target}") }
            Insn::IfTrue { val, target } => { write!(f, "IfTrue {val}, {target}") }
            Insn::IfFalse { val, target } => { write!(f, "IfFalse {val}, {target}") }
            Insn::SendWithoutBlock { recv, cd, args, reason, .. } => {
                write!(f, "SendWithoutBlock {recv}, :{}", ruby_call_method_name(*cd))?;
                for arg in args {
                    write!(f, ", {arg}")?;
                }
                write!(f, " # SendFallbackReason: {reason}")?;
                Ok(())
            }
            Insn::SendWithoutBlockDirect { recv, cd, iseq, args, .. } => {
                write!(f, "SendWithoutBlockDirect {recv}, :{} ({:?})", ruby_call_method_name(*cd), self.ptr_map.map_ptr(iseq))?;
                for arg in args {
                    write!(f, ", {arg}")?;
                }
                Ok(())
            }
            Insn::Send { recv, cd, args, blockiseq, reason, .. } => {
                // For tests, we want to check HIR snippets textually. Addresses change
                // between runs, making tests fail. Instead, pick an arbitrary hex value to
                // use as a "pointer" so we can check the rest of the HIR.
                write!(f, "Send {recv}, {:p}, :{}", self.ptr_map.map_ptr(blockiseq), ruby_call_method_name(*cd))?;
                for arg in args {
                    write!(f, ", {arg}")?;
                }
                write!(f, " # SendFallbackReason: {reason}")?;
                Ok(())
            }
            Insn::SendForward { recv, cd, args, blockiseq, reason, .. } => {
                write!(f, "SendForward {recv}, {:p}, :{}", self.ptr_map.map_ptr(blockiseq), ruby_call_method_name(*cd))?;
                for arg in args {
                    write!(f, ", {arg}")?;
                }
                write!(f, " # SendFallbackReason: {reason}")?;
                Ok(())
            }
            Insn::InvokeSuper { recv, blockiseq, args, reason, .. } => {
                write!(f, "InvokeSuper {recv}, {:p}", self.ptr_map.map_ptr(blockiseq))?;
                for arg in args {
                    write!(f, ", {arg}")?;
                }
                write!(f, " # SendFallbackReason: {reason}")?;
                Ok(())
            }
            Insn::InvokeBlock { args, reason, .. } => {
                write!(f, "InvokeBlock")?;
                for arg in args {
                    write!(f, ", {arg}")?;
                }
                write!(f, " # SendFallbackReason: {reason}")?;
                Ok(())
            }
            Insn::InvokeBuiltin { bf, args, leaf, .. } => {
                let bf_name = unsafe { CStr::from_ptr(bf.name) }.to_str().unwrap();
                write!(f, "InvokeBuiltin{} {}",
                           if *leaf { " leaf" } else { "" },
                           // e.g. Code that use `Primitive.cexpr!`. From BUILTIN_INLINE_PREFIX.
                           if bf_name.starts_with("_bi") { "<inline_expr>" } else { bf_name })?;
                for arg in args {
                    write!(f, ", {arg}")?;
                }
                Ok(())
            }
            &Insn::EntryPoint { jit_entry_idx: Some(idx) } => write!(f, "EntryPoint JIT({idx})"),
            &Insn::EntryPoint { jit_entry_idx: None } => write!(f, "EntryPoint interpreter"),
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
            Insn::FixnumXor  { left, right, .. } => { write!(f, "FixnumXor {left}, {right}") },
            Insn::FixnumLShift { left, right, .. } => { write!(f, "FixnumLShift {left}, {right}") },
            Insn::FixnumRShift { left, right, .. } => { write!(f, "FixnumRShift {left}, {right}") },
            Insn::GuardType { val, guard_type, .. } => { write!(f, "GuardType {val}, {}", guard_type.print(self.ptr_map)) },
            Insn::GuardTypeNot { val, guard_type, .. } => { write!(f, "GuardTypeNot {val}, {}", guard_type.print(self.ptr_map)) },
            Insn::GuardBitEquals { val, expected, .. } => { write!(f, "GuardBitEquals {val}, {}", expected.print(self.ptr_map)) },
            &Insn::GuardShape { val, shape, .. } => { write!(f, "GuardShape {val}, {:p}", self.ptr_map.map_shape(shape)) },
            Insn::GuardBlockParamProxy { level, .. } => write!(f, "GuardBlockParamProxy l{level}"),
            Insn::GuardNotFrozen { recv, .. } => write!(f, "GuardNotFrozen {recv}"),
            Insn::GuardLess { left, right, .. } => write!(f, "GuardLess {left}, {right}"),
            Insn::GuardGreaterEq { left, right, .. } => write!(f, "GuardGreaterEq {left}, {right}"),
            Insn::PatchPoint { invariant, .. } => { write!(f, "PatchPoint {}", invariant.print(self.ptr_map)) },
            Insn::GetConstantPath { ic, .. } => { write!(f, "GetConstantPath {:p}", self.ptr_map.map_ptr(ic)) },
            Insn::IsBlockGiven => { write!(f, "IsBlockGiven") },
            Insn::FixnumBitCheck {val, index} => { write!(f, "FixnumBitCheck {val}, {index}") },
            Insn::CCall { cfunc, recv, args, name, return_type: _, elidable: _ } => {
                write!(f, "CCall {recv}, :{}@{:p}", name.contents_lossy(), self.ptr_map.map_ptr(cfunc))?;
                for arg in args {
                    write!(f, ", {arg}")?;
                }
                Ok(())
            },
            Insn::CCallWithFrame { cfunc, recv, args, name, blockiseq, .. } => {
                write!(f, "CCallWithFrame {recv}, :{}@{:p}", name.contents_lossy(), self.ptr_map.map_ptr(cfunc))?;
                for arg in args {
                    write!(f, ", {arg}")?;
                }
                if let Some(blockiseq) = blockiseq {
                    write!(f, ", block={:p}", self.ptr_map.map_ptr(blockiseq))?;
                }
                Ok(())
            },
            Insn::CCallVariadic { cfunc, recv, args, name, .. } => {
                write!(f, "CCallVariadic {recv}, :{}@{:p}", name.contents_lossy(), self.ptr_map.map_ptr(cfunc))?;
                for arg in args {
                    write!(f, ", {arg}")?;
                }
                Ok(())
            },
            Insn::IncrCounterPtr { .. } => write!(f, "IncrCounterPtr"),
            Insn::Snapshot { state } => write!(f, "Snapshot {}", state.print(self.ptr_map)),
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
            Insn::LoadPC => write!(f, "LoadPC"),
            Insn::LoadEC => write!(f, "LoadEC"),
            Insn::LoadSelf => write!(f, "LoadSelf"),
            &Insn::LoadField { recv, id, offset, return_type: _ } => write!(f, "LoadField {recv}, :{}@{:p}", id.contents_lossy(), self.ptr_map.map_offset(offset)),
            &Insn::StoreField { recv, id, offset, val } => write!(f, "StoreField {recv}, :{}@{:p}, {val}", id.contents_lossy(), self.ptr_map.map_offset(offset)),
            &Insn::WriteBarrier { recv, val } => write!(f, "WriteBarrier {recv}, {val}"),
            Insn::SetIvar { self_val, id, val, .. } => write!(f, "SetIvar {self_val}, :{}, {val}", id.contents_lossy()),
            Insn::GetGlobal { id, .. } => write!(f, "GetGlobal :{}", id.contents_lossy()),
            Insn::SetGlobal { id, val, .. } => write!(f, "SetGlobal :{}, {val}", id.contents_lossy()),
            &Insn::GetLocal { level, ep_offset, use_sp: true, rest_param } => {
                let name = get_local_var_name_for_printer(self.iseq, level, ep_offset).map_or(String::new(), |x| format!("{x}, "));
                write!(f, "GetLocal {name}l{level}, SP@{}{}", ep_offset + 1, if rest_param { ", *" } else { "" })
            },
            &Insn::GetLocal { level, ep_offset, use_sp: false, rest_param } => {
                let name = get_local_var_name_for_printer(self.iseq, level, ep_offset).map_or(String::new(), |x| format!("{x}, "));
                write!(f, "GetLocal {name}l{level}, EP@{ep_offset}{}", if rest_param { ", *" } else { "" })
            },
            &Insn::SetLocal { val, level, ep_offset } => {
                let name = get_local_var_name_for_printer(self.iseq, level, ep_offset).map_or(String::new(), |x| format!("{x}, "));
                write!(f, "SetLocal {name}l{level}, EP@{ep_offset}, {val}")
            },
            Insn::GetSpecialSymbol { symbol_type, .. } => write!(f, "GetSpecialSymbol {symbol_type:?}"),
            Insn::GetSpecialNumber { nth, .. } => write!(f, "GetSpecialNumber {nth}"),
            Insn::GetClassVar { id, .. } => write!(f, "GetClassVar :{}", id.contents_lossy()),
            Insn::SetClassVar { id, val, .. } => write!(f, "SetClassVar :{}, {val}", id.contents_lossy()),
            Insn::ToArray { val, .. } => write!(f, "ToArray {val}"),
            Insn::ToNewArray { val, .. } => write!(f, "ToNewArray {val}"),
            Insn::ArrayExtend { left, right, .. } => write!(f, "ArrayExtend {left}, {right}"),
            Insn::ArrayPush { array, val, .. } => write!(f, "ArrayPush {array}, {val}"),
            Insn::ObjToString { val, .. } => { write!(f, "ObjToString {val}") },
            Insn::StringIntern { val, .. } => { write!(f, "StringIntern {val}") },
            Insn::AnyToString { val, str, .. } => { write!(f, "AnyToString {val}, str: {str}") },
            Insn::SideExit { reason, .. } => write!(f, "SideExit {reason}"),
            Insn::PutSpecialObject { value_type } => write!(f, "PutSpecialObject {value_type}"),
            Insn::Throw { throw_state, val, .. } => {
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
            Insn::CheckInterrupts { .. } => write!(f, "CheckInterrupts"),
            Insn::IsA { val, class } => write!(f, "IsA {val}, {class}"),
        }
    }
}

impl std::fmt::Display for Insn {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        self.print(&PtrPrintMap::identity(), None).fmt(f)
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
    pub fn params(&self) -> Iter<'_, InsnId> {
        self.params.iter()
    }

    /// Return an iterator over insns
    pub fn insns(&self) -> Iter<'_, InsnId> {
        self.insns.iter()
    }
}

/// Pretty printer for [`Function`].
pub struct FunctionPrinter<'a> {
    fun: &'a Function,
    display_snapshot_and_tp_patchpoints: bool,
    ptr_map: PtrPrintMap,
}

impl<'a> FunctionPrinter<'a> {
    pub fn without_snapshot(fun: &'a Function) -> Self {
        let mut ptr_map = PtrPrintMap::identity();
        if cfg!(test) {
            ptr_map.map_ptrs = true;
        }
        Self { fun, display_snapshot_and_tp_patchpoints: false, ptr_map }
    }

    pub fn with_snapshot(fun: &'a Function) -> FunctionPrinter<'a> {
        let mut printer = Self::without_snapshot(fun);
        printer.display_snapshot_and_tp_patchpoints = true;
        printer
    }
}

/// Pretty printer for [`Function`].
pub struct FunctionGraphvizPrinter<'a> {
    fun: &'a Function,
    ptr_map: PtrPrintMap,
}

impl<'a> FunctionGraphvizPrinter<'a> {
    pub fn new(fun: &'a Function) -> Self {
        let mut ptr_map = PtrPrintMap::identity();
        if cfg!(test) {
            ptr_map.map_ptrs = true;
        }
        Self { fun, ptr_map }
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
        self.forwarded.get(idx.into()).copied().flatten()
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

#[derive(Clone, Debug, PartialEq)]
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
    /// The offending instruction, its operand, expected type string, actual type string
    MismatchedOperandType(InsnId, InsnId, String, String),
    MiscValidationError(InsnId, String),
}

fn can_direct_send(function: &mut Function, block: BlockId, iseq: *const rb_iseq_t, send_insn: InsnId, args: &[InsnId]) -> bool {
    let mut can_send = true;
    let mut count_failure = |counter| {
        can_send = false;
        function.push_insn(block, Insn::IncrCounter(counter));
    };
    let params = unsafe { iseq.params() };

    use Counter::*;
    if 0 != params.flags.has_rest()    { count_failure(complex_arg_pass_param_rest) }
    if 0 != params.flags.has_post()    { count_failure(complex_arg_pass_param_post) }
    if 0 != params.flags.has_block()   { count_failure(complex_arg_pass_param_block) }
    if 0 != params.flags.forwardable() { count_failure(complex_arg_pass_param_forwardable) }

    if 0 != params.flags.has_kwrest()  { count_failure(complex_arg_pass_param_kwrest) }
    if 0 != params.flags.has_kw() {
        let keyword = params.keyword;
        if !keyword.is_null() {
            let num = unsafe { (*keyword).num };
            let required_num = unsafe { (*keyword).required_num };
            // Only support required keywords for now (no optional keywords)
            if num != required_num {
                count_failure(complex_arg_pass_param_kw_opt)
            }
        }
    }

    if !can_send {
        function.set_dynamic_send_reason(send_insn, ComplexArgPass);
        return false;
    }

    // Because we exclude e.g. post parameters above, they are also excluded from the sum below.
    let lead_num = params.lead_num;
    let opt_num = params.opt_num;
    let keyword = params.keyword;
    let kw_req_num = if keyword.is_null() { 0 } else { unsafe { (*keyword).required_num } };
    let req_num = lead_num + kw_req_num;
    can_send = c_int::try_from(args.len())
        .as_ref()
        .map(|argc| (req_num..=req_num + opt_num).contains(argc))
        .unwrap_or(false);
    if !can_send {
        function.set_dynamic_send_reason(send_insn, ArgcParamMismatch);
        return false
    }

    can_send
}

/// A [`Function`], which is analogous to a Ruby ISeq, is a control-flow graph of [`Block`]s
/// containing instructions.
#[derive(Debug)]
pub struct Function {
    // ISEQ this function refers to
    iseq: *const rb_iseq_t,
    /// The types for the parameters of this function. They are copied to the type
    /// of entry block params after infer_types() fills Empty to all insn_types.
    param_types: Vec<Type>,

    insns: Vec<Insn>,
    union_find: std::cell::RefCell<UnionFind<InsnId>>,
    insn_types: Vec<Type>,
    blocks: Vec<Block>,
    /// Entry block for the interpreter
    entry_block: BlockId,
    /// Entry block for JIT-to-JIT calls. Length will be `opt_num+1`, for callers
    /// fulfilling `(0..=opt_num)` optional parameters.
    jit_entry_blocks: Vec<BlockId>,
    profiles: Option<ProfileOracle>,
}

/// The kind of a value an ISEQ returns
enum IseqReturn {
    Value(VALUE),
    LocalVariable(u32),
    Receiver,
    // Builtin descriptor and return type (if known)
    InvokeLeafBuiltin(rb_builtin_function, Option<Type>),
}

unsafe extern "C" {
    fn rb_simple_iseq_p(iseq: IseqPtr) -> bool;
}

/// Return the ISEQ's return value if it consists of one simple instruction and leave.
fn iseq_get_return_value(iseq: IseqPtr, captured_opnd: Option<InsnId>, ci_flags: u32) -> Option<IseqReturn> {
    // Expect only two instructions and one possible operand
    // NOTE: If an ISEQ has an optional keyword parameter with a default value that requires
    // computation, the ISEQ will always have more than two instructions and won't be inlined.

    // Get the first two instructions
    let first_insn = iseq_opcode_at_idx(iseq, 0);
    let second_insn = iseq_opcode_at_idx(iseq, insn_len(first_insn as usize));

    // Extract the return value if known
    if second_insn != YARVINSN_leave {
        return None;
    }
    match first_insn {
        YARVINSN_getlocal_WC_0  => {
            // Accept only cases where only positional arguments are used by both the callee and the caller.
            // Keyword arguments may be specified by the callee or the caller but not used.
            if captured_opnd.is_some()
                // Equivalent to `VM_CALL_ARGS_SIMPLE - VM_CALL_KWARG - has_block_iseq`
                || ci_flags & (
                      VM_CALL_ARGS_SPLAT
                    | VM_CALL_KW_SPLAT
                    | VM_CALL_ARGS_BLOCKARG
                    | VM_CALL_FORWARDING
                ) != 0
                 {
                return None;
            }

            let ep_offset = unsafe { *rb_iseq_pc_at_idx(iseq, 1) }.as_u32();
            let local_idx = ep_offset_to_local_idx(iseq, ep_offset);

            // Only inline if the local is a parameter (not a method-defined local) as we are indexing args.
            let param_size = unsafe { rb_get_iseq_body_param_size(iseq) } as usize;
            if local_idx >= param_size {
                return None;
            }

            if unsafe { rb_simple_iseq_p(iseq) } {
                return Some(IseqReturn::LocalVariable(local_idx.try_into().unwrap()));
            }

            // TODO(max): Support only_kwparam case where the local_idx is a positional parameter

            None
        }
        YARVINSN_putnil => Some(IseqReturn::Value(Qnil)),
        YARVINSN_putobject => Some(IseqReturn::Value(unsafe { *rb_iseq_pc_at_idx(iseq, 1) })),
        YARVINSN_putobject_INT2FIX_0_ => Some(IseqReturn::Value(VALUE::fixnum_from_usize(0))),
        YARVINSN_putobject_INT2FIX_1_ => Some(IseqReturn::Value(VALUE::fixnum_from_usize(1))),
        // We don't support invokeblock for now. Such ISEQs are likely not used by blocks anyway.
        YARVINSN_putself if captured_opnd.is_none() => Some(IseqReturn::Receiver),
        YARVINSN_opt_invokebuiltin_delegate_leave => {
            let pc = unsafe { rb_iseq_pc_at_idx(iseq, 0) };
            let bf: rb_builtin_function = unsafe { *get_arg(pc, 0).as_ptr() };
            let argc = bf.argc as usize;
            if argc != 0 { return None; }
            let builtin_attrs = unsafe { rb_jit_iseq_builtin_attrs(iseq) };
            let leaf = builtin_attrs & BUILTIN_ATTR_LEAF != 0;
            if !leaf { return None; }
            // Check if this builtin is annotated
            let return_type = ZJITState::get_method_annotations()
                .get_builtin_properties(&bf)
                .map(|props| props.return_type);
            Some(IseqReturn::InvokeLeafBuiltin(bf, return_type))
        }
        _ => None,
    }
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
            jit_entry_blocks: vec![],
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
    pub fn push_insn(&mut self, block: BlockId, insn: Insn) -> InsnId {
        let is_param = matches!(insn, Insn::Param);
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
        let block = Block {
            insn_idx,
            .. Block::default()
        };
        self.blocks.push(block);
        id
    }

    fn remove_block(&mut self, block_id: BlockId) {
        if BlockId(self.blocks.len() - 1) != block_id {
            panic!("Can only remove the last block");
        }
        self.blocks.pop();
    }

    /// Return a reference to the Block at the given index.
    pub fn block(&self, block_id: BlockId) -> &Block {
        &self.blocks[block_id.0]
    }

    /// Return a reference to the entry block.
    pub fn entry_block(&self) -> &Block {
        &self.blocks[self.entry_block.0]
    }

    /// Return the number of blocks
    pub fn num_blocks(&self) -> usize {
        self.blocks.len()
    }

    pub fn assume_single_ractor_mode(&mut self, block: BlockId, state: InsnId) -> bool {
        if unsafe { rb_jit_multi_ractor_p() } {
            false
        } else {
            self.push_insn(block, Insn::PatchPoint { invariant: Invariant::SingleRactorMode, state });
            true
        }
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
                    | Param
                    | GetConstantPath {..}
                    | IsBlockGiven
                    | PatchPoint {..}
                    | PutSpecialObject {..}
                    | GetGlobal {..}
                    | GetLocal {..}
                    | SideExit {..}
                    | EntryPoint {..}
                    | LoadPC
                    | LoadEC
                    | LoadSelf
                    | IncrCounterPtr {..}
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
            &FixnumBitCheck { val, index } => FixnumBitCheck { val: find!(val), index },
            &Throw { throw_state, val, state } => Throw { throw_state, val: find!(val), state },
            &StringCopy { val, chilled, state } => StringCopy { val: find!(val), chilled, state },
            &StringIntern { val, state } => StringIntern { val: find!(val), state: find!(state) },
            &StringConcat { ref strings, state } => StringConcat { strings: find_vec!(strings), state: find!(state) },
            &StringGetbyte { string, index } => StringGetbyte { string: find!(string), index: find!(index) },
            &StringSetbyteFixnum { string, index, value } => StringSetbyteFixnum { string: find!(string), index: find!(index), value: find!(value) },
            &StringAppend { recv, other, state } => StringAppend { recv: find!(recv), other: find!(other), state: find!(state) },
            &StringAppendCodepoint { recv, other, state } => StringAppendCodepoint { recv: find!(recv), other: find!(other), state: find!(state) },
            &ToRegexp { opt, ref values, state } => ToRegexp { opt, values: find_vec!(values), state },
            &Test { val } => Test { val: find!(val) },
            &IsNil { val } => IsNil { val: find!(val) },
            &IsMethodCfunc { val, cd, cfunc, state } => IsMethodCfunc { val: find!(val), cd, cfunc, state },
            &IsBitEqual { left, right } => IsBitEqual { left: find!(left), right: find!(right) },
            &IsBitNotEqual { left, right } => IsBitNotEqual { left: find!(left), right: find!(right) },
            &BoxBool { val } => BoxBool { val: find!(val) },
            &BoxFixnum { val, state } => BoxFixnum { val: find!(val), state: find!(state) },
            &UnboxFixnum { val } => UnboxFixnum { val: find!(val) },
            Jump(target) => Jump(find_branch_edge!(target)),
            &IfTrue { val, ref target } => IfTrue { val: find!(val), target: find_branch_edge!(target) },
            &IfFalse { val, ref target } => IfFalse { val: find!(val), target: find_branch_edge!(target) },
            &GuardType { val, guard_type, state } => GuardType { val: find!(val), guard_type, state },
            &GuardTypeNot { val, guard_type, state } => GuardTypeNot { val: find!(val), guard_type, state },
            &GuardBitEquals { val, expected, state } => GuardBitEquals { val: find!(val), expected, state },
            &GuardShape { val, shape, state } => GuardShape { val: find!(val), shape, state },
            &GuardBlockParamProxy { level, state } => GuardBlockParamProxy { level, state: find!(state) },
            &GuardNotFrozen { recv, state } => GuardNotFrozen { recv: find!(recv), state },
            &GuardGreaterEq { left, right, state } => GuardGreaterEq { left: find!(left), right: find!(right), state },
            &GuardLess { left, right, state } => GuardLess { left: find!(left), right: find!(right), state },
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
            &FixnumXor { left, right } => FixnumXor { left: find!(left), right: find!(right) },
            &FixnumLShift { left, right, state } => FixnumLShift { left: find!(left), right: find!(right), state },
            &FixnumRShift { left, right } => FixnumRShift { left: find!(left), right: find!(right) },
            &ObjToString { val, cd, state } => ObjToString {
                val: find!(val),
                cd,
                state,
            },
            &AnyToString { val, str, state } => AnyToString {
                val: find!(val),
                str: find!(str),
                state,
            },
            &SendWithoutBlock { recv, cd, ref args, state, reason } => SendWithoutBlock {
                recv: find!(recv),
                cd,
                args: find_vec!(args),
                state,
                reason,
            },
            &SendWithoutBlockDirect { recv, cd, cme, iseq, ref args, state } => SendWithoutBlockDirect {
                recv: find!(recv),
                cd,
                cme,
                iseq,
                args: find_vec!(args),
                state,
            },
            &Send { recv, cd, blockiseq, ref args, state, reason } => Send {
                recv: find!(recv),
                cd,
                blockiseq,
                args: find_vec!(args),
                state,
                reason,
            },
            &SendForward { recv, cd, blockiseq, ref args, state, reason } => SendForward {
                recv: find!(recv),
                cd,
                blockiseq,
                args: find_vec!(args),
                state,
                reason,
            },
            &InvokeSuper { recv, cd, blockiseq, ref args, state, reason } => InvokeSuper {
                recv: find!(recv),
                cd,
                blockiseq,
                args: find_vec!(args),
                state,
                reason,
            },
            &InvokeBlock { cd, ref args, state, reason } => InvokeBlock {
                cd,
                args: find_vec!(args),
                state,
                reason,
            },
            &InvokeBuiltin { bf, recv, ref args, state, leaf, return_type } => InvokeBuiltin { bf, recv: find!(recv), args: find_vec!(args), state, leaf, return_type },
            &ArrayDup { val, state } => ArrayDup { val: find!(val), state },
            &HashDup { val, state } => HashDup { val: find!(val), state },
            &HashAref { hash, key, state } => HashAref { hash: find!(hash), key: find!(key), state },
            &HashAset { hash, key, val, state } => HashAset { hash: find!(hash), key: find!(key), val: find!(val), state },
            &ObjectAlloc { val, state } => ObjectAlloc { val: find!(val), state },
            &ObjectAllocClass { class, state } => ObjectAllocClass { class, state: find!(state) },
            &CCall { cfunc, recv, ref args, name, return_type, elidable } => CCall { cfunc, recv: find!(recv), args: find_vec!(args), name, return_type, elidable },
            &CCallWithFrame { cd, cfunc, recv, ref args, cme, name, state, return_type, elidable, blockiseq } => CCallWithFrame {
                cd,
                cfunc,
                recv: find!(recv),
                args: find_vec!(args),
                cme,
                name,
                state: find!(state),
                return_type,
                elidable,
                blockiseq,
            },
            &CCallVariadic { cfunc, recv, ref args, cme, name, state, return_type, elidable, blockiseq } => CCallVariadic {
                cfunc, recv: find!(recv), args: find_vec!(args), cme, name, state, return_type, elidable, blockiseq
            },
            &Defined { op_type, obj, pushval, v, state } => Defined { op_type, obj, pushval, v: find!(v), state: find!(state) },
            &DefinedIvar { self_val, pushval, id, state } => DefinedIvar { self_val: find!(self_val), pushval, id, state },
            &NewArray { ref elements, state } => NewArray { elements: find_vec!(elements), state: find!(state) },
            &NewHash { ref elements, state } => NewHash { elements: find_vec!(elements), state: find!(state) },
            &NewRange { low, high, flag, state } => NewRange { low: find!(low), high: find!(high), flag, state: find!(state) },
            &NewRangeFixnum { low, high, flag, state } => NewRangeFixnum { low: find!(low), high: find!(high), flag, state: find!(state) },
            &ArrayArefFixnum { array, index } => ArrayArefFixnum { array: find!(array), index: find!(index) },
            &ArrayPop { array, state } => ArrayPop { array: find!(array), state: find!(state) },
            &ArrayLength { array } => ArrayLength { array: find!(array) },
            &ArrayMax { ref elements, state } => ArrayMax { elements: find_vec!(elements), state: find!(state) },
            &ArrayInclude { ref elements, target, state } => ArrayInclude { elements: find_vec!(elements), target: find!(target), state: find!(state) },
            &ArrayPackBuffer { ref elements, fmt, buffer, state } => ArrayPackBuffer { elements: find_vec!(elements), fmt: find!(fmt), buffer: find!(buffer), state: find!(state) },
            &DupArrayInclude { ary, target, state } => DupArrayInclude { ary, target: find!(target), state: find!(state) },
            &ArrayHash { ref elements, state } => ArrayHash { elements: find_vec!(elements), state },
            &SetGlobal { id, val, state } => SetGlobal { id, val: find!(val), state },
            &GetIvar { self_val, id, ic, state } => GetIvar { self_val: find!(self_val), id, ic, state },
            &LoadField { recv, id, offset, return_type } => LoadField { recv: find!(recv), id, offset, return_type },
            &StoreField { recv, id, offset, val } => StoreField { recv: find!(recv), id, offset, val: find!(val) },
            &WriteBarrier { recv, val } => WriteBarrier { recv: find!(recv), val: find!(val) },
            &SetIvar { self_val, id, ic, val, state } => SetIvar { self_val: find!(self_val), id, ic, val: find!(val), state },
            &GetClassVar { id, ic, state } => GetClassVar { id, ic, state },
            &SetClassVar { id, val, ic, state } => SetClassVar { id, val: find!(val), ic, state },
            &SetLocal { val, ep_offset, level } => SetLocal { val: find!(val), ep_offset, level },
            &GetSpecialSymbol { symbol_type, state } => GetSpecialSymbol { symbol_type, state },
            &GetSpecialNumber { nth, state } => GetSpecialNumber { nth, state },
            &ToArray { val, state } => ToArray { val: find!(val), state },
            &ToNewArray { val, state } => ToNewArray { val: find!(val), state },
            &ArrayExtend { left, right, state } => ArrayExtend { left: find!(left), right: find!(right), state },
            &ArrayPush { array, val, state } => ArrayPush { array: find!(array), val: find!(val), state },
            &CheckInterrupts { state } => CheckInterrupts { state },
            &IsA { val, class } => IsA { val: find!(val), class: find!(class) },
        }
    }

    /// Update DynamicSendReason for the instruction at insn_id
    fn set_dynamic_send_reason(&mut self, insn_id: InsnId, dynamic_send_reason: SendFallbackReason) {
        use Insn::*;
        if get_option!(stats) || get_option!(dump_hir_opt).is_some() || cfg!(test) {
            match self.insns.get_mut(insn_id.0).unwrap() {
                Send { reason, .. }
                | SendForward { reason, .. }
                | SendWithoutBlock { reason, .. }
                | InvokeSuper { reason, .. }
                | InvokeBlock { reason, .. }
                => *reason = dynamic_send_reason,
                _ => unreachable!("unexpected instruction {} at {insn_id}", self.find(insn_id))
            }
        }
    }

    /// Replace `insn` with the new instruction `replacement`, which will get appended to `insns`.
    fn make_equal_to(&mut self, insn: InsnId, replacement: InsnId) {
        assert!(self.insns[insn.0].has_output(),
                "Don't use make_equal_to for instruction with no output");
        assert!(self.insns[replacement.0].has_output(),
                "Can't replace instruction that has output with instruction that has no output");
        // Don't push it to the block
        self.union_find.borrow_mut().make_equal_to(insn, replacement);
    }

    pub fn type_of(&self, insn: InsnId) -> Type {
        assert!(self.insns[insn.0].has_output());
        self.insn_types[self.union_find.borrow_mut().find(insn).0]
    }

    /// Check if the type of `insn` is a subtype of `ty`.
    pub fn is_a(&self, insn: InsnId, ty: Type) -> bool {
        self.type_of(insn).is_subtype(ty)
    }

    fn infer_type(&self, insn: InsnId) -> Type {
        assert!(self.insns[insn.0].has_output());
        match &self.insns[insn.0] {
            Insn::Param => unimplemented!("params should not be present in block.insns"),
            Insn::SetGlobal { .. } | Insn::Jump(_) | Insn::EntryPoint { .. }
            | Insn::IfTrue { .. } | Insn::IfFalse { .. } | Insn::Return { .. } | Insn::Throw { .. }
            | Insn::PatchPoint { .. } | Insn::SetIvar { .. } | Insn::SetClassVar { .. } | Insn::ArrayExtend { .. }
            | Insn::ArrayPush { .. } | Insn::SideExit { .. } | Insn::SetLocal { .. } | Insn::IncrCounter(_)
            | Insn::CheckInterrupts { .. } | Insn::GuardBlockParamProxy { .. } | Insn::IncrCounterPtr { .. }
            | Insn::StoreField { .. } | Insn::WriteBarrier { .. } | Insn::HashAset { .. } =>
                panic!("Cannot infer type of instruction with no output: {}. See Insn::has_output().", self.insns[insn.0]),
            Insn::Const { val: Const::Value(val) } => Type::from_value(*val),
            Insn::Const { val: Const::CBool(val) } => Type::from_cbool(*val),
            Insn::Const { val: Const::CInt8(val) } => Type::from_cint(types::CInt8, *val as i64),
            Insn::Const { val: Const::CInt16(val) } => Type::from_cint(types::CInt16, *val as i64),
            Insn::Const { val: Const::CInt32(val) } => Type::from_cint(types::CInt32, *val as i64),
            Insn::Const { val: Const::CInt64(val) } => Type::from_cint(types::CInt64, *val),
            Insn::Const { val: Const::CUInt8(val) } => Type::from_cint(types::CUInt8, *val as i64),
            Insn::Const { val: Const::CUInt16(val) } => Type::from_cint(types::CUInt16, *val as i64),
            Insn::Const { val: Const::CUInt32(val) } => Type::from_cint(types::CUInt32, *val as i64),
            Insn::Const { val: Const::CShape(val) } => Type::from_cint(types::CShape, val.0 as i64),
            Insn::Const { val: Const::CUInt64(val) } => Type::from_cint(types::CUInt64, *val as i64),
            Insn::Const { val: Const::CPtr(val) } => Type::from_cptr(*val),
            Insn::Const { val: Const::CDouble(val) } => Type::from_double(*val),
            Insn::Test { val } if self.type_of(*val).is_known_falsy() => Type::from_cbool(false),
            Insn::Test { val } if self.type_of(*val).is_known_truthy() => Type::from_cbool(true),
            Insn::Test { .. } => types::CBool,
            Insn::IsNil { val } if self.is_a(*val, types::NilClass) => Type::from_cbool(true),
            Insn::IsNil { val } if !self.type_of(*val).could_be(types::NilClass) => Type::from_cbool(false),
            Insn::IsNil { .. } => types::CBool,
            Insn::IsMethodCfunc { .. } => types::CBool,
            Insn::IsBitEqual { .. } => types::CBool,
            Insn::IsBitNotEqual { .. } => types::CBool,
            Insn::BoxBool { .. } => types::BoolExact,
            Insn::BoxFixnum { .. } => types::Fixnum,
            Insn::UnboxFixnum { .. } => types::CInt64,
            Insn::StringCopy { .. } => types::StringExact,
            Insn::StringIntern { .. } => types::Symbol,
            Insn::StringConcat { .. } => types::StringExact,
            Insn::StringGetbyte { .. } => types::Fixnum,
            Insn::StringSetbyteFixnum { .. } => types::Fixnum,
            Insn::StringAppend { .. } => types::StringExact,
            Insn::StringAppendCodepoint { .. } => types::StringExact,
            Insn::ToRegexp { .. } => types::RegexpExact,
            Insn::NewArray { .. } => types::ArrayExact,
            Insn::ArrayDup { .. } => types::ArrayExact,
            Insn::ArrayArefFixnum { .. } => types::BasicObject,
            Insn::ArrayPop { .. } => types::BasicObject,
            Insn::ArrayLength { .. } => types::CInt64,
            Insn::HashAref { .. } => types::BasicObject,
            Insn::NewHash { .. } => types::HashExact,
            Insn::HashDup { .. } => types::HashExact,
            Insn::NewRange { .. } => types::RangeExact,
            Insn::NewRangeFixnum { .. } => types::RangeExact,
            Insn::ObjectAlloc { .. } => types::HeapBasicObject,
            Insn::ObjectAllocClass { class, .. } => Type::from_class(*class),
            &Insn::CCallWithFrame { return_type, .. } => return_type,
            Insn::CCall { return_type, .. } => *return_type,
            &Insn::CCallVariadic { return_type, .. } => return_type,
            Insn::GuardType { val, guard_type, .. } => self.type_of(*val).intersection(*guard_type),
            Insn::GuardTypeNot { .. } => types::BasicObject,
            Insn::GuardBitEquals { val, expected, .. } => self.type_of(*val).intersection(Type::from_const(*expected)),
            Insn::GuardShape { val, .. } => self.type_of(*val),
            Insn::GuardNotFrozen { recv, .. } => self.type_of(*recv),
            Insn::GuardLess { left, .. } => self.type_of(*left),
            Insn::GuardGreaterEq { left, .. } => self.type_of(*left),
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
            Insn::FixnumXor  { .. } => types::Fixnum,
            Insn::FixnumLShift { .. } => types::Fixnum,
            Insn::FixnumRShift { .. } => types::Fixnum,
            Insn::PutSpecialObject { .. } => types::BasicObject,
            Insn::SendWithoutBlock { .. } => types::BasicObject,
            Insn::SendWithoutBlockDirect { .. } => types::BasicObject,
            Insn::Send { .. } => types::BasicObject,
            Insn::SendForward { .. } => types::BasicObject,
            Insn::InvokeSuper { .. } => types::BasicObject,
            Insn::InvokeBlock { .. } => types::BasicObject,
            Insn::InvokeBuiltin { return_type, .. } => return_type.unwrap_or(types::BasicObject),
            Insn::Defined { pushval, .. } => Type::from_value(*pushval).union(types::NilClass),
            Insn::DefinedIvar { pushval, .. } => Type::from_value(*pushval).union(types::NilClass),
            Insn::GetConstantPath { .. } => types::BasicObject,
            Insn::IsBlockGiven => types::BoolExact,
            Insn::FixnumBitCheck { .. } => types::BoolExact,
            Insn::ArrayMax { .. } => types::BasicObject,
            Insn::ArrayInclude { .. } => types::BoolExact,
            Insn::ArrayPackBuffer { .. } => types::String,
            Insn::DupArrayInclude { .. } => types::BoolExact,
            Insn::ArrayHash { .. } => types::Fixnum,
            Insn::GetGlobal { .. } => types::BasicObject,
            Insn::GetIvar { .. } => types::BasicObject,
            Insn::LoadPC => types::CPtr,
            Insn::LoadEC => types::CPtr,
            Insn::LoadSelf => types::BasicObject,
            &Insn::LoadField { return_type, .. } => return_type,
            Insn::GetSpecialSymbol { .. } => types::BasicObject,
            Insn::GetSpecialNumber { .. } => types::BasicObject,
            Insn::GetClassVar { .. } => types::BasicObject,
            Insn::ToNewArray { .. } => types::ArrayExact,
            Insn::ToArray { .. } => types::ArrayExact,
            Insn::ObjToString { .. } => types::BasicObject,
            Insn::AnyToString { .. } => types::String,
            Insn::GetLocal { rest_param: true, .. } => types::ArrayExact,
            Insn::GetLocal { .. } => types::BasicObject,
            // The type of Snapshot doesn't really matter; it's never materialized. It's used only
            // as a reference for FrameState, which we use to generate side-exit code.
            Insn::Snapshot { .. } => types::Any,
            Insn::IsA { .. } => types::BoolExact,
        }
    }

    /// Set self.param_types. They are copied to the param types of jit_entry_blocks.
    fn set_param_types(&mut self) {
        let iseq = self.iseq;
        let params = unsafe { iseq.params() };
        let param_size = params.size.to_usize();
        let rest_param_idx = iseq_rest_param_idx(params);

        self.param_types.push(types::BasicObject); // self
        for local_idx in 0..param_size {
            let param_type = if Some(local_idx as i32) == rest_param_idx {
                types::ArrayExact // Rest parameters are always ArrayExact
            } else {
                types::BasicObject
            };
            self.param_types.push(param_type);
        }
    }

    /// Copy self.param_types to the param types of jit_entry_blocks.
    fn copy_param_types(&mut self) {
        for jit_entry_block in self.jit_entry_blocks.iter() {
            let entry_params = self.blocks[jit_entry_block.0].params.iter();
            let param_types = self.param_types.iter();
            assert!(
                param_types.len() >= entry_params.len(),
                "param types should be initialized before type inference",
            );
            for (param, param_type) in std::iter::zip(entry_params, param_types) {
                // We know that function parameters are BasicObject or some subclass
                self.insn_types[param.0] = *param_type;
            }
        }
    }

    fn infer_types(&mut self) {
        // Reset all types
        self.insn_types.fill(types::Empty);

        // Fill entry parameter types
        self.copy_param_types();

        let mut reachable = BlockSet::with_capacity(self.blocks.len());
        for entry_block in self.entry_blocks() {
            reachable.insert(entry_block);
        }

        // Walk the graph, computing types until fixpoint
        let rpo = self.rpo();
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

    fn chase_insn(&self, insn: InsnId) -> InsnId {
        let id = self.union_find.borrow().find_const(insn);
        match self.insns[id.0] {
            Insn::GuardType { val, .. }
            | Insn::GuardTypeNot { val, .. }
            | Insn::GuardShape { val, .. }
            | Insn::GuardBitEquals { val, .. } => self.chase_insn(val),
            _ => id,
        }
    }

    /// Return the profiled type of the HIR instruction at the given ISEQ instruction
    /// index, if it is known to be monomorphic or skewed polymorphic. This historical type
    /// record is not a guarantee and must be checked with a GuardType or similar.
    fn profiled_type_of_at(&self, insn: InsnId, iseq_insn_idx: usize) -> Option<ProfiledType> {
        match self.resolve_receiver_type_from_profile(insn, iseq_insn_idx) {
            ReceiverTypeResolution::Monomorphic { profiled_type }
            | ReceiverTypeResolution::SkewedPolymorphic { profiled_type } => Some(profiled_type),
            _ => None,
        }
    }

    /// Reorder keyword arguments to match the callee's expectation.
    ///
    /// Returns Ok with reordered arguments if successful, or Err with the fallback reason if not.
    fn reorder_keyword_arguments(
        &self,
        args: &[InsnId],
        kwarg: *const rb_callinfo_kwarg,
        iseq: IseqPtr,
    ) -> Result<Vec<InsnId>, SendFallbackReason> {
        let callee_keyword = unsafe { rb_get_iseq_body_param_keyword(iseq) };
        if callee_keyword.is_null() {
            // Caller is passing kwargs but callee doesn't expect them.
            return Err(SendWithoutBlockDirectKeywordMismatch);
        }

        let caller_kw_count = unsafe { get_cikw_keyword_len(kwarg) } as usize;
        let callee_kw_count = unsafe { (*callee_keyword).num } as usize;
        let callee_kw_required = unsafe { (*callee_keyword).required_num } as usize;
        let callee_kw_table = unsafe { (*callee_keyword).table };

        // For now, only handle the case where all keywords are required.
        if callee_kw_count != callee_kw_required {
            return Err(SendWithoutBlockDirectOptionalKeywords);
        }
        if caller_kw_count != callee_kw_count {
            return Err(SendWithoutBlockDirectKeywordCountMismatch);
        }

        // The keyword arguments are the last arguments in the args vector.
        let kw_args_start = args.len() - caller_kw_count;

        // Build a mapping from caller keywords to their positions.
        let mut caller_kw_order: Vec<ID> = Vec::with_capacity(caller_kw_count);
        for i in 0..caller_kw_count {
            let sym = unsafe { get_cikw_keywords_idx(kwarg, i as i32) };
            let id = unsafe { rb_sym2id(sym) };
            caller_kw_order.push(id);
        }

        // Reorder keyword arguments to match callee expectation.
        let mut reordered_kw_args: Vec<InsnId> = Vec::with_capacity(callee_kw_count);
        for i in 0..callee_kw_count {
            let expected_id = unsafe { *callee_kw_table.add(i) };

            // Find where this keyword is in the caller's order
            let mut found = false;
            for (j, &caller_id) in caller_kw_order.iter().enumerate() {
                if caller_id == expected_id {
                    reordered_kw_args.push(args[kw_args_start + j]);
                    found = true;
                    break;
                }
            }

            if !found {
                // Required keyword not provided by caller which will raise an ArgumentError.
                return Err(SendWithoutBlockDirectMissingKeyword);
            }
        }

        // Replace the keyword arguments with the reordered ones.
        let mut processed_args = args[..kw_args_start].to_vec();
        processed_args.extend(reordered_kw_args);
        Ok(processed_args)
    }

    /// Resolve the receiver type for method dispatch optimization.
    ///
    /// Takes the receiver's Type, receiver HIR instruction, and ISEQ instruction index.
    /// First checks if the receiver's class is statically known, otherwise consults profile data.
    ///
    /// Returns:
    /// - `StaticallyKnown` if the receiver's exact class is known at compile-time
    /// - Result of [`Self::resolve_receiver_type_from_profile`] if we need to check profile data
    fn resolve_receiver_type(&self, recv: InsnId, recv_type: Type, insn_idx: usize) -> ReceiverTypeResolution {
        if let Some(class) = recv_type.runtime_exact_ruby_class() {
            return ReceiverTypeResolution::StaticallyKnown { class };
        }
        self.resolve_receiver_type_from_profile(recv, insn_idx)
    }

    /// Resolve the receiver type for method dispatch optimization from profile data.
    ///
    /// Returns:
    /// - `Monomorphic`/`SkewedPolymorphic` if we have usable profile data
    /// - `Polymorphic` if the receiver has multiple types
    /// - `Megamorphic`/`SkewedMegamorphic` if the receiver has too many types to optimize
    ///   (SkewedMegamorphic may be optimized in the future, but for now we don't)
    /// - `NoProfile` if we have no type information
    fn resolve_receiver_type_from_profile(&self, recv: InsnId, insn_idx: usize) -> ReceiverTypeResolution {
        let Some(profiles) = self.profiles.as_ref() else {
            return ReceiverTypeResolution::NoProfile;
        };
        let Some(entries) = profiles.types.get(&insn_idx) else {
            return ReceiverTypeResolution::NoProfile;
        };
        let recv = self.chase_insn(recv);

        for (entry_insn, entry_type_summary) in entries {
            if self.union_find.borrow().find_const(*entry_insn) == recv {
                if entry_type_summary.is_monomorphic() {
                    let profiled_type = entry_type_summary.bucket(0);
                    return ReceiverTypeResolution::Monomorphic { profiled_type };
                } else if entry_type_summary.is_skewed_polymorphic() {
                    let profiled_type = entry_type_summary.bucket(0);
                    return ReceiverTypeResolution::SkewedPolymorphic { profiled_type };
                } else if entry_type_summary.is_skewed_megamorphic() {
                    let profiled_type = entry_type_summary.bucket(0);
                    return ReceiverTypeResolution::SkewedMegamorphic { profiled_type };
                } else if entry_type_summary.is_polymorphic() {
                    return ReceiverTypeResolution::Polymorphic;
                } else if entry_type_summary.is_megamorphic() {
                    return ReceiverTypeResolution::Megamorphic;
                }
            }
        }

        ReceiverTypeResolution::NoProfile
    }

    pub fn assume_expected_cfunc(&mut self, block: BlockId, class: VALUE, method_id: ID, cfunc: *mut c_void, state: InsnId) -> bool {
        let cme = unsafe { rb_callable_method_entry(class, method_id) };
        if cme.is_null() { return false; }
        let def_type = unsafe { get_cme_def_type(cme) };
        if def_type != VM_METHOD_TYPE_CFUNC { return false; }
        if unsafe { get_mct_func(get_cme_def_body_cfunc(cme)) } != cfunc {
            return false;
        }
        self.gen_patch_points_for_optimized_ccall(block, class, method_id, cme, state);
        if class.instance_can_have_singleton_class() {
            self.push_insn(block, Insn::PatchPoint { invariant: Invariant::NoSingletonClass { klass: class }, state });
        }
        true
    }

    pub fn likely_a(&self, val: InsnId, ty: Type, state: InsnId) -> bool {
        if self.type_of(val).is_subtype(ty) {
            return true;
        }
        let frame_state = self.frame_state(state);
        let iseq_insn_idx = frame_state.insn_idx;
        let Some(profiled_type) = self.profiled_type_of_at(val, iseq_insn_idx) else {
            return false;
        };
        Type::from_profiled_type(profiled_type).is_subtype(ty)
    }

    pub fn coerce_to(&mut self, block: BlockId, val: InsnId, guard_type: Type, state: InsnId) -> InsnId {
        if self.is_a(val, guard_type) { return val; }
        self.push_insn(block, Insn::GuardType { val, guard_type, state })
    }

    fn count_complex_call_features(&mut self, block: BlockId, ci_flags: c_uint) {
        use Counter::*;
        if 0 != ci_flags & VM_CALL_ARGS_SPLAT     { self.push_insn(block, Insn::IncrCounter(complex_arg_pass_caller_splat));      }
        if 0 != ci_flags & VM_CALL_ARGS_BLOCKARG  { self.push_insn(block, Insn::IncrCounter(complex_arg_pass_caller_blockarg));   }
        if 0 != ci_flags & VM_CALL_KWARG          { self.push_insn(block, Insn::IncrCounter(complex_arg_pass_caller_kwarg));      }
        if 0 != ci_flags & VM_CALL_KW_SPLAT       { self.push_insn(block, Insn::IncrCounter(complex_arg_pass_caller_kw_splat));   }
        if 0 != ci_flags & VM_CALL_TAILCALL       { self.push_insn(block, Insn::IncrCounter(complex_arg_pass_caller_tailcall));   }
        if 0 != ci_flags & VM_CALL_SUPER          { self.push_insn(block, Insn::IncrCounter(complex_arg_pass_caller_super));      }
        if 0 != ci_flags & VM_CALL_ZSUPER         { self.push_insn(block, Insn::IncrCounter(complex_arg_pass_caller_zsuper));     }
        if 0 != ci_flags & VM_CALL_FORWARDING     { self.push_insn(block, Insn::IncrCounter(complex_arg_pass_caller_forwarding)); }
    }

    fn rewrite_if_frozen(&mut self, block: BlockId, orig_insn_id: InsnId, self_val: InsnId, klass: u32, bop: u32, state: InsnId) {
        if !unsafe { rb_BASIC_OP_UNREDEFINED_P(bop, klass) } {
            // If the basic operation is already redefined, we cannot optimize it.
            self.set_dynamic_send_reason(orig_insn_id, SendWithoutBlockBopRedefined);
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

    fn is_metaclass(&self, object: VALUE) -> bool {
        unsafe {
            if RB_TYPE_P(object, RUBY_T_CLASS) && rb_zjit_singleton_class_p(object) {
                let attached = rb_class_attached_object(object);
                RB_TYPE_P(attached, RUBY_T_CLASS) || RB_TYPE_P(attached, RUBY_T_MODULE)
            } else {
                false
            }
        }
    }

    /// Rewrite SendWithoutBlock opcodes into SendWithoutBlockDirect opcodes if we know the target
    /// ISEQ statically. This removes run-time method lookups and opens the door for inlining.
    /// Also try and inline constant caches, specialize object allocations, and more.
    fn type_specialize(&mut self) {
        for block in self.rpo() {
            let old_insns = std::mem::take(&mut self.blocks[block.0].insns);
            assert!(self.blocks[block.0].insns.is_empty());
            for insn_id in old_insns {
                match self.find(insn_id) {
                    Insn::SendWithoutBlock { recv, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(freeze) && args.is_empty() =>
                        self.try_rewrite_freeze(block, insn_id, recv, state),
                    Insn::SendWithoutBlock { recv, args, state, cd, .. } if ruby_call_method_id(cd) == ID!(minusat) && args.is_empty() =>
                        self.try_rewrite_uminus(block, insn_id, recv, state),
                    Insn::SendWithoutBlock { mut recv, cd, args, state, .. } => {
                        let frame_state = self.frame_state(state);
                        let (klass, profiled_type) = match self.resolve_receiver_type(recv, self.type_of(recv), frame_state.insn_idx) {
                            ReceiverTypeResolution::StaticallyKnown { class } => (class, None),
                            ReceiverTypeResolution::Monomorphic { profiled_type }
                            | ReceiverTypeResolution::SkewedPolymorphic { profiled_type } => (profiled_type.class(), Some(profiled_type)),
                            ReceiverTypeResolution::SkewedMegamorphic { .. }
                            | ReceiverTypeResolution::Megamorphic => {
                                if get_option!(stats) {
                                    self.set_dynamic_send_reason(insn_id, SendWithoutBlockMegamorphic);
                                }
                                self.push_insn_id(block, insn_id);
                                continue;
                            }
                            ReceiverTypeResolution::Polymorphic => {
                                if get_option!(stats) {
                                    self.set_dynamic_send_reason(insn_id, SendWithoutBlockPolymorphic);
                                }
                                self.push_insn_id(block, insn_id);
                                continue;
                            }
                            ReceiverTypeResolution::NoProfile => {
                                if get_option!(stats) {
                                    self.set_dynamic_send_reason(insn_id, SendWithoutBlockNoProfiles);
                                }
                                self.push_insn_id(block, insn_id);
                                continue;
                            }
                        };
                        let ci = unsafe { get_call_data_ci(cd) }; // info about the call site

                        // If the call site info indicates that the `Function` has overly complex arguments, then
                        // do not optimize into a `SendWithoutBlockDirect`.
                        let flags = unsafe { rb_vm_ci_flag(ci) };
                        if unspecializable_call_type(flags) {
                            self.count_complex_call_features(block, flags);
                            self.set_dynamic_send_reason(insn_id, ComplexArgPass);
                            self.push_insn_id(block, insn_id); continue;
                        }

                        let mid = unsafe { vm_ci_mid(ci) };
                        // Do method lookup
                        let mut cme = unsafe { rb_callable_method_entry(klass, mid) };
                        if cme.is_null() {
                            self.set_dynamic_send_reason(insn_id, SendWithoutBlockNotOptimizedMethodType(MethodType::Null));
                            self.push_insn_id(block, insn_id); continue;
                        }
                        // Load an overloaded cme if applicable. See vm_search_cc().
                        // It allows you to use a faster ISEQ if possible.
                        cme = unsafe { rb_check_overloaded_cme(cme, ci) };
                        let visibility = unsafe { METHOD_ENTRY_VISI(cme) };
                        match (visibility, flags & VM_CALL_FCALL != 0) {
                            (METHOD_VISI_PUBLIC, _) => {}
                            (METHOD_VISI_PRIVATE, true) => {}
                            (METHOD_VISI_PROTECTED, true) => {}
                            _ => {
                                self.set_dynamic_send_reason(insn_id, SendWithoutBlockNotOptimizedNeedPermission);
                                self.push_insn_id(block, insn_id); continue;
                            }
                        }
                        let mut def_type = unsafe { get_cme_def_type(cme) };
                        while def_type == VM_METHOD_TYPE_ALIAS {
                            cme = unsafe { rb_aliased_callable_method_entry(cme) };
                            def_type = unsafe { get_cme_def_type(cme) };
                        }

                        if def_type == VM_METHOD_TYPE_ISEQ {
                            // TODO(max): Allow non-iseq; cache cme
                            // Only specialize positional-positional calls
                            // TODO(max): Handle other kinds of parameter passing
                            let iseq = unsafe { get_def_iseq_ptr((*cme).def) };
                            if !can_direct_send(self, block, iseq, insn_id, args.as_slice()) {
                                self.push_insn_id(block, insn_id); continue;
                            }
                            self.push_insn(block, Insn::PatchPoint { invariant: Invariant::MethodRedefined { klass, method: mid, cme }, state });
                            if klass.instance_can_have_singleton_class() {
                                self.push_insn(block, Insn::PatchPoint { invariant: Invariant::NoSingletonClass { klass }, state });
                            }
                            if let Some(profiled_type) = profiled_type {
                                recv = self.push_insn(block, Insn::GuardType { val: recv, guard_type: Type::from_profiled_type(profiled_type), state });
                            }

                            let kwarg = unsafe { rb_vm_ci_kwarg(ci) };
                            let processed_args = if !kwarg.is_null() {
                                match self.reorder_keyword_arguments(&args, kwarg, iseq) {
                                    Ok(reordered) => reordered,
                                    Err(reason) => {
                                        self.set_dynamic_send_reason(insn_id, reason);
                                        self.push_insn_id(block, insn_id); continue;
                                    }
                                }
                            } else {
                                args.clone()
                            };

                            let send_direct = self.push_insn(block, Insn::SendWithoutBlockDirect { recv, cd, cme, iseq, args: processed_args, state });
                            self.make_equal_to(insn_id, send_direct);
                        } else if def_type == VM_METHOD_TYPE_BMETHOD {
                            let procv = unsafe { rb_get_def_bmethod_proc((*cme).def) };
                            let proc = unsafe { rb_jit_get_proc_ptr(procv) };
                            let proc_block = unsafe { &(*proc).block };
                            // Target ISEQ bmethods. Can't handle for example, `define_method(:foo, &:foo)`
                            // which makes a `block_type_symbol` bmethod.
                            if proc_block.type_ != block_type_iseq {
                                self.set_dynamic_send_reason(insn_id, BmethodNonIseqProc);
                                self.push_insn_id(block, insn_id); continue;
                            }
                            let capture = unsafe { proc_block.as_.captured.as_ref() };
                            let iseq = unsafe { *capture.code.iseq.as_ref() };

                            if !can_direct_send(self, block, iseq, insn_id, args.as_slice()) {
                                self.push_insn_id(block, insn_id); continue;
                            }
                            // Can't pass a block to a block for now
                            assert!((unsafe { rb_vm_ci_flag(ci) } & VM_CALL_ARGS_BLOCKARG) == 0, "SendWithoutBlock but has a block arg");

                            // Patch points:
                            // Check for "defined with an un-shareable Proc in a different Ractor"
                            if !procv.shareable_p() && !self.assume_single_ractor_mode(block, state) {
                                // TODO(alan): Turn this into a ractor belonging guard to work better in multi ractor mode.
                                self.push_insn_id(block, insn_id); continue;
                            }
                            self.push_insn(block, Insn::PatchPoint { invariant: Invariant::MethodRedefined { klass, method: mid, cme }, state });
                            if klass.instance_can_have_singleton_class() {
                                self.push_insn(block, Insn::PatchPoint { invariant: Invariant::NoSingletonClass { klass }, state });
                            }

                            if let Some(profiled_type) = profiled_type {
                                recv = self.push_insn(block, Insn::GuardType { val: recv, guard_type: Type::from_profiled_type(profiled_type), state });
                            }

                            let kwarg = unsafe { rb_vm_ci_kwarg(ci) };
                            let processed_args = if !kwarg.is_null() {
                                match self.reorder_keyword_arguments(&args, kwarg, iseq) {
                                    Ok(reordered) => reordered,
                                    Err(reason) => {
                                        self.set_dynamic_send_reason(insn_id, reason);
                                        self.push_insn_id(block, insn_id); continue;
                                    }
                                }
                            } else {
                                args.clone()
                            };

                            let send_direct = self.push_insn(block, Insn::SendWithoutBlockDirect { recv, cd, cme, iseq, args: processed_args, state });
                            self.make_equal_to(insn_id, send_direct);
                        } else if def_type == VM_METHOD_TYPE_IVAR && args.is_empty() {
                            // Check if we're accessing ivars of a Class or Module object as they require single-ractor mode.
                            // We omit gen_prepare_non_leaf_call on gen_getivar, so it's unsafe to raise for multi-ractor mode.
                            if self.is_metaclass(klass) && !self.assume_single_ractor_mode(block, state) {
                                self.push_insn_id(block, insn_id); continue;
                            }

                            self.push_insn(block, Insn::PatchPoint { invariant: Invariant::MethodRedefined { klass, method: mid, cme }, state });
                            if klass.instance_can_have_singleton_class() {
                                self.push_insn(block, Insn::PatchPoint { invariant: Invariant::NoSingletonClass { klass }, state });
                            }
                            if let Some(profiled_type) = profiled_type {
                                recv = self.push_insn(block, Insn::GuardType { val: recv, guard_type: Type::from_profiled_type(profiled_type), state });
                            }
                            let id = unsafe { get_cme_def_body_attr_id(cme) };

                            let getivar = self.push_insn(block, Insn::GetIvar { self_val: recv, id, ic: std::ptr::null(), state });
                            self.make_equal_to(insn_id, getivar);
                        } else if let (VM_METHOD_TYPE_ATTRSET, &[val]) = (def_type, args.as_slice()) {
                            // Check if we're accessing ivars of a Class or Module object as they require single-ractor mode.
                            // We omit gen_prepare_non_leaf_call on gen_getivar, so it's unsafe to raise for multi-ractor mode.
                            if self.is_metaclass(klass) && !self.assume_single_ractor_mode(block, state) {
                                self.push_insn_id(block, insn_id); continue;
                            }

                            self.push_insn(block, Insn::PatchPoint { invariant: Invariant::MethodRedefined { klass, method: mid, cme }, state });
                            if let Some(profiled_type) = profiled_type {
                                recv = self.push_insn(block, Insn::GuardType { val: recv, guard_type: Type::from_profiled_type(profiled_type), state });
                            }
                            let id = unsafe { get_cme_def_body_attr_id(cme) };

                            self.push_insn(block, Insn::SetIvar { self_val: recv, id, ic: std::ptr::null(), val, state });
                            self.make_equal_to(insn_id, val);
                        } else if def_type == VM_METHOD_TYPE_OPTIMIZED {
                            let opt_type: OptimizedMethodType = unsafe { get_cme_def_body_optimized_type(cme) }.into();
                            match (opt_type, args.as_slice()) {
                                (OptimizedMethodType::StructAref, &[]) | (OptimizedMethodType::StructAset, &[_]) => {
                                    let index: i32 = unsafe { get_cme_def_body_optimized_index(cme) }
                                                    .try_into()
                                                    .unwrap();
                                    // We are going to use an encoding that takes a 4-byte immediate which
                                    // limits the offset to INT32_MAX.
                                    {
                                        let native_index = (index as i64) * (SIZEOF_VALUE as i64);
                                        if native_index > (i32::MAX as i64) {
                                            self.push_insn_id(block, insn_id); continue;
                                        }
                                    }
                                    // Get the profiled type to check if the fields is embedded or heap allocated.
                                    let Some(is_embedded) = self.profiled_type_of_at(recv, frame_state.insn_idx).map(|t| t.flags().is_struct_embedded()) else {
                                        // No (monomorphic/skewed polymorphic) profile info
                                        self.push_insn_id(block, insn_id); continue;
                                    };
                                    self.push_insn(block, Insn::PatchPoint { invariant: Invariant::MethodRedefined { klass, method: mid, cme }, state });
                                    if klass.instance_can_have_singleton_class() {
                                        self.push_insn(block, Insn::PatchPoint { invariant: Invariant::NoSingletonClass { klass }, state });
                                    }
                                    if let Some(profiled_type) = profiled_type {
                                        recv = self.push_insn(block, Insn::GuardType { val: recv, guard_type: Type::from_profiled_type(profiled_type), state });
                                    }
                                    // All structs from the same Struct class should have the same
                                    // length. So if our recv is embedded all runtime
                                    // structs of the same class should be as well, and the same is
                                    // true of the converse.
                                    //
                                    // No need for a GuardShape.
                                    if let OptimizedMethodType::StructAset = opt_type {
                                        // We know that all Struct are HeapObject, so no need to insert a GuardType(HeapObject).
                                        recv = self.push_insn(block, Insn::GuardNotFrozen { recv, state });
                                    }

                                    let (target, offset) = if is_embedded {
                                        let offset = RUBY_OFFSET_RSTRUCT_AS_ARY + (SIZEOF_VALUE_I32 * index);
                                        (recv, offset)
                                    } else {
                                        let as_heap = self.push_insn(block, Insn::LoadField { recv, id: ID!(_as_heap), offset: RUBY_OFFSET_RSTRUCT_AS_HEAP_PTR, return_type: types::CPtr });
                                        let offset = SIZEOF_VALUE_I32 * index;
                                        (as_heap, offset)
                                    };

                                    let replacement = if let (OptimizedMethodType::StructAset, &[val]) = (opt_type, args.as_slice()) {
                                        self.push_insn(block, Insn::StoreField { recv: target, id: mid, offset, val });
                                        self.push_insn(block, Insn::WriteBarrier { recv, val });
                                        val
                                    } else { // StructAref
                                        self.push_insn(block, Insn::LoadField { recv: target, id: mid, offset, return_type: types::BasicObject })
                                    };
                                    self.make_equal_to(insn_id, replacement);
                                },
                                _ => {
                                    self.set_dynamic_send_reason(insn_id, SendWithoutBlockNotOptimizedMethodTypeOptimized(OptimizedMethodType::from(opt_type)));
                                    self.push_insn_id(block, insn_id); continue;
                                },
                            };
                        } else {
                            self.set_dynamic_send_reason(insn_id, SendWithoutBlockNotOptimizedMethodType(MethodType::from(def_type)));
                            self.push_insn_id(block, insn_id); continue;
                        }
                    }
                    // This doesn't actually optimize Send yet, just replaces the fallback reason to be more precise.
                    // The actual optimization is done in reduce_send_to_ccall.
                    Insn::Send { recv, cd, state, .. } => {
                        let frame_state = self.frame_state(state);
                        let klass = match self.resolve_receiver_type(recv, self.type_of(recv), frame_state.insn_idx) {
                            ReceiverTypeResolution::StaticallyKnown { class } => class,
                            ReceiverTypeResolution::Monomorphic { profiled_type }
                            | ReceiverTypeResolution::SkewedPolymorphic { profiled_type } => profiled_type.class(),
                            ReceiverTypeResolution::SkewedMegamorphic { .. }
                            | ReceiverTypeResolution::Megamorphic => {
                                if get_option!(stats) {
                                    self.set_dynamic_send_reason(insn_id, SendMegamorphic);
                                }
                                self.push_insn_id(block, insn_id);
                                continue;
                            }
                            ReceiverTypeResolution::Polymorphic => {
                                if get_option!(stats) {
                                    self.set_dynamic_send_reason(insn_id, SendPolymorphic);
                                }
                                self.push_insn_id(block, insn_id);
                                continue;
                            }
                            ReceiverTypeResolution::NoProfile => {
                                if get_option!(stats) {
                                    self.set_dynamic_send_reason(insn_id, SendNoProfiles);
                                }
                                self.push_insn_id(block, insn_id);
                                continue;
                            }
                        };
                        let ci = unsafe { get_call_data_ci(cd) }; // info about the call site
                        let mid = unsafe { vm_ci_mid(ci) };
                        // Do method lookup
                        let mut cme = unsafe { rb_callable_method_entry(klass, mid) };
                        if cme.is_null() {
                            self.set_dynamic_send_reason(insn_id, SendNotOptimizedMethodType(MethodType::Null));
                            self.push_insn_id(block, insn_id); continue;
                        }
                        // Load an overloaded cme if applicable. See vm_search_cc().
                        // It allows you to use a faster ISEQ if possible.
                        cme = unsafe { rb_check_overloaded_cme(cme, ci) };
                        let mut def_type = unsafe { get_cme_def_type(cme) };
                        while def_type == VM_METHOD_TYPE_ALIAS {
                            cme = unsafe { rb_aliased_callable_method_entry(cme) };
                            def_type = unsafe { get_cme_def_type(cme) };
                        }
                        self.set_dynamic_send_reason(insn_id, SendNotOptimizedMethodType(MethodType::from(def_type)));
                        self.push_insn_id(block, insn_id); continue;
                    }
                    Insn::GetConstantPath { ic, state, .. } => {
                        let idlist: *const ID = unsafe { (*ic).segments };
                        let ice = unsafe { (*ic).entry };
                        if ice.is_null() {
                            self.push_insn_id(block, insn_id); continue;
                        }
                        let cref_sensitive = !unsafe { (*ice).ic_cref }.is_null();
                        if cref_sensitive || !self.assume_single_ractor_mode(block, state) {
                            self.push_insn_id(block, insn_id); continue;
                        }
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
                            self.make_equal_to(insn_id, val); continue;
                        }

                        let frame_state = self.frame_state(state);
                        let Some(recv_type) = self.profiled_type_of_at(val, frame_state.insn_idx) else {
                            self.push_insn_id(block, insn_id); continue
                        };

                        if recv_type.is_string() {
                            self.push_insn(block, Insn::PatchPoint { invariant: Invariant::NoSingletonClass { klass: recv_type.class() }, state });
                            let guard = self.push_insn(block, Insn::GuardType { val, guard_type: types::String, state });
                            // Infer type so AnyToString can fold off this
                            self.insn_types[guard.0] = self.infer_type(guard);
                            self.make_equal_to(insn_id, guard);
                        } else {
                            let recv = self.push_insn(block, Insn::GuardType { val, guard_type: Type::from_profiled_type(recv_type), state});
                            let send_to_s = self.push_insn(block, Insn::SendWithoutBlock { recv, cd, args: vec![], state, reason: ObjToStringNotString });
                            self.make_equal_to(insn_id, send_to_s);
                        }
                    }
                    Insn::AnyToString { str, .. } => {
                        if self.is_a(str, types::String) {
                            self.make_equal_to(insn_id, str);
                        } else {
                            self.push_insn_id(block, insn_id);
                        }
                    }
                    Insn::IsMethodCfunc { val, cd, cfunc, state } if self.type_of(val).ruby_object_known() => {
                        let class = self.type_of(val).ruby_object().unwrap();
                        let cme = unsafe { rb_zjit_vm_search_method(self.iseq.into(), cd as *mut rb_call_data, class) };
                        let is_expected_cfunc = unsafe { rb_zjit_cme_is_cfunc(cme, cfunc as *const c_void) };
                        let method = unsafe { rb_vm_ci_mid((*cd).ci) };
                        self.push_insn(block, Insn::PatchPoint { invariant: Invariant::MethodRedefined { klass: class, method, cme }, state });
                        let replacement = self.push_insn(block, Insn::Const { val: Const::CBool(is_expected_cfunc) });
                        self.insn_types[replacement.0] = self.infer_type(replacement);
                        self.make_equal_to(insn_id, replacement);
                    }
                    Insn::ObjectAlloc { val, state } => {
                        let val_type = self.type_of(val);
                        if !val_type.is_subtype(types::Class) {
                            self.push_insn_id(block, insn_id); continue;
                        }
                        let Some(class) = val_type.ruby_object() else {
                            self.push_insn_id(block, insn_id); continue;
                        };
                        // See class_get_alloc_func in object.c; if the class isn't initialized, is
                        // a singleton class, or has a custom allocator, ObjectAlloc might raise an
                        // exception or run arbitrary code.
                        //
                        // We also need to check if the class is initialized or a singleton before
                        // trying to read the allocator, otherwise it might raise.
                        if !unsafe { rb_zjit_class_initialized_p(class) } {
                            self.push_insn_id(block, insn_id); continue;
                        }
                        if unsafe { rb_zjit_singleton_class_p(class) } {
                            self.push_insn_id(block, insn_id); continue;
                        }
                        if !class_has_leaf_allocator(class) {
                            // Custom, known unsafe, or NULL allocator; could run arbitrary code.
                            self.push_insn_id(block, insn_id); continue;
                        }
                        let replacement = self.push_insn(block, Insn::ObjectAllocClass { class, state });
                        self.insn_types[replacement.0] = self.infer_type(replacement);
                        self.make_equal_to(insn_id, replacement);
                    }
                    Insn::NewRange { low, high, flag, state } => {
                        let low_is_fix  = self.is_a(low,  types::Fixnum);
                        let high_is_fix = self.is_a(high, types::Fixnum);

                        if low_is_fix || high_is_fix {
                            let low_fix = self.coerce_to(block, low, types::Fixnum, state);
                            let high_fix = self.coerce_to(block, high, types::Fixnum, state);
                            let replacement = self.push_insn(block, Insn::NewRangeFixnum { low: low_fix, high: high_fix, flag, state });
                            self.make_equal_to(insn_id, replacement);
                            self.insn_types[replacement.0] = self.infer_type(replacement);
                        } else {
                            self.push_insn_id(block, insn_id);
                        };
                    }
                    _ => { self.push_insn_id(block, insn_id); }
                }
            }
        }
        self.infer_types();
    }

    fn inline(&mut self) {
        for block in self.rpo() {
            let old_insns = std::mem::take(&mut self.blocks[block.0].insns);
            assert!(self.blocks[block.0].insns.is_empty());
            for insn_id in old_insns {
                match self.find(insn_id) {
                    // Reject block ISEQs to avoid autosplat and other block parameter complications.
                    Insn::SendWithoutBlockDirect { recv, iseq, cd, args, state, .. } => {
                        let call_info = unsafe { (*cd).ci };
                        let ci_flags = unsafe { vm_ci_flag(call_info) };
                        // .send call is not currently supported for builtins
                        if ci_flags & VM_CALL_OPT_SEND != 0 {
                            self.push_insn_id(block, insn_id); continue;
                        }
                        let Some(value) = iseq_get_return_value(iseq, None, ci_flags) else {
                            self.push_insn_id(block, insn_id); continue;
                        };
                        match value {
                            IseqReturn::LocalVariable(idx) => {
                                self.push_insn(block, Insn::IncrCounter(Counter::inline_iseq_optimized_send_count));
                                self.make_equal_to(insn_id, args[idx as usize]);
                            }
                            IseqReturn::Value(value) => {
                                self.push_insn(block, Insn::IncrCounter(Counter::inline_iseq_optimized_send_count));
                                let replacement = self.push_insn(block, Insn::Const { val: Const::Value(value) });
                                self.make_equal_to(insn_id, replacement);
                            }
                            IseqReturn::Receiver => {
                                self.push_insn(block, Insn::IncrCounter(Counter::inline_iseq_optimized_send_count));
                                self.make_equal_to(insn_id, recv);
                            }
                            IseqReturn::InvokeLeafBuiltin(bf, return_type) => {
                                self.push_insn(block, Insn::IncrCounter(Counter::inline_iseq_optimized_send_count));
                                let replacement = self.push_insn(block, Insn::InvokeBuiltin {
                                    bf,
                                    recv,
                                    args: vec![recv],
                                    state,
                                    leaf: true,
                                    return_type,
                                });
                                self.make_equal_to(insn_id, replacement);
                            }
                        }
                    }
                    _ => { self.push_insn_id(block, insn_id); }
                }
            }
        }
        self.infer_types();
    }

    fn optimize_getivar(&mut self) {
        for block in self.rpo() {
            let old_insns = std::mem::take(&mut self.blocks[block.0].insns);
            assert!(self.blocks[block.0].insns.is_empty());
            for insn_id in old_insns {
                match self.find(insn_id) {
                    Insn::GetIvar { self_val, id, ic: _, state } => {
                        let frame_state = self.frame_state(state);
                        let Some(recv_type) = self.profiled_type_of_at(self_val, frame_state.insn_idx) else {
                            // No (monomorphic/skewed polymorphic) profile info
                            self.push_insn(block, Insn::IncrCounter(Counter::getivar_fallback_not_monomorphic));
                            self.push_insn_id(block, insn_id); continue;
                        };
                        if recv_type.flags().is_immediate() {
                            // Instance variable lookups on immediate values are always nil
                            self.push_insn(block, Insn::IncrCounter(Counter::getivar_fallback_immediate));
                            self.push_insn_id(block, insn_id); continue;
                        }
                        assert!(recv_type.shape().is_valid());
                        if recv_type.shape().is_too_complex() {
                            // too-complex shapes can't use index access
                            self.push_insn(block, Insn::IncrCounter(Counter::getivar_fallback_too_complex));
                            self.push_insn_id(block, insn_id); continue;
                        }
                        let self_val = self.push_insn(block, Insn::GuardType { val: self_val, guard_type: types::HeapBasicObject, state });
                        let self_val = self.push_insn(block, Insn::GuardShape { val: self_val, shape: recv_type.shape(), state });
                        let mut ivar_index: u16 = 0;
                        let replacement = if ! unsafe { rb_shape_get_iv_index(recv_type.shape().0, id, &mut ivar_index) } {
                            // If there is no IVAR index, then the ivar was undefined when we
                            // entered the compiler.  That means we can just return nil for this
                            // shape + iv name
                            self.push_insn(block, Insn::Const { val: Const::Value(Qnil) })
                        } else if !recv_type.flags().is_t_object() {
                            // NOTE: it's fine to use rb_ivar_get_at_no_ractor_check because
                            // getinstancevariable does assume_single_ractor_mode()
                            let ivar_index_insn: InsnId = self.push_insn(block, Insn::Const { val: Const::CUInt16(ivar_index as u16) });
                            self.push_insn(block, Insn::CCall {
                                cfunc: rb_ivar_get_at_no_ractor_check as *const u8,
                                recv: self_val,
                                args: vec![ivar_index_insn],
                                name: ID!(rb_ivar_get_at_no_ractor_check),
                                return_type: types::BasicObject,
                                elidable: true })
                        } else if recv_type.flags().is_embedded() {
                            // See ROBJECT_FIELDS() from include/ruby/internal/core/robject.h
                            let offset = ROBJECT_OFFSET_AS_ARY as i32 + (SIZEOF_VALUE * ivar_index.to_usize()) as i32;
                            self.push_insn(block, Insn::LoadField { recv: self_val, id, offset, return_type: types::BasicObject })
                        } else {
                            let as_heap =  self.push_insn(block, Insn::LoadField { recv: self_val, id: ID!(_as_heap), offset: ROBJECT_OFFSET_AS_HEAP_FIELDS as i32, return_type: types::CPtr });

                            let offset = SIZEOF_VALUE_I32 * ivar_index as i32;
                            self.push_insn(block, Insn::LoadField { recv: as_heap, id, offset, return_type: types::BasicObject })
                        };
                        self.make_equal_to(insn_id, replacement);
                    }
                    Insn::DefinedIvar { self_val, id, pushval, state } => {
                        let frame_state = self.frame_state(state);
                        let Some(recv_type) = self.profiled_type_of_at(self_val, frame_state.insn_idx) else {
                            // No (monomorphic/skewed polymorphic) profile info
                            self.push_insn(block, Insn::IncrCounter(Counter::definedivar_fallback_not_monomorphic));
                            self.push_insn_id(block, insn_id); continue;
                        };
                        if recv_type.flags().is_immediate() {
                            // Instance variable lookups on immediate values are always nil
                            self.push_insn(block, Insn::IncrCounter(Counter::definedivar_fallback_immediate));
                            self.push_insn_id(block, insn_id); continue;
                        }
                        assert!(recv_type.shape().is_valid());
                        if !recv_type.flags().is_t_object() {
                            // Check if the receiver is a T_OBJECT
                            self.push_insn(block, Insn::IncrCounter(Counter::definedivar_fallback_not_t_object));
                            self.push_insn_id(block, insn_id); continue;
                        }
                        if recv_type.shape().is_too_complex() {
                            // too-complex shapes can't use index access
                            self.push_insn(block, Insn::IncrCounter(Counter::definedivar_fallback_too_complex));
                            self.push_insn_id(block, insn_id); continue;
                        }
                        let self_val = self.push_insn(block, Insn::GuardType { val: self_val, guard_type: types::HeapBasicObject, state });
                        let _ = self.push_insn(block, Insn::GuardShape { val: self_val, shape: recv_type.shape(), state });
                        let mut ivar_index: u16 = 0;
                        let replacement = if unsafe { rb_shape_get_iv_index(recv_type.shape().0, id, &mut ivar_index) } {
                            self.push_insn(block, Insn::Const { val: Const::Value(pushval) })
                        } else {
                            // If there is no IVAR index, then the ivar was undefined when we
                            // entered the compiler.  That means we can just return nil for this
                            // shape + iv name
                            self.push_insn(block, Insn::Const { val: Const::Value(Qnil) })
                        };
                        self.make_equal_to(insn_id, replacement);
                    }
                    Insn::SetIvar { self_val, id, val, state, ic: _ } => {
                        let frame_state = self.frame_state(state);
                        let Some(recv_type) = self.profiled_type_of_at(self_val, frame_state.insn_idx) else {
                            // No (monomorphic/skewed polymorphic) profile info
                            self.push_insn(block, Insn::IncrCounter(Counter::setivar_fallback_not_monomorphic));
                            self.push_insn_id(block, insn_id); continue;
                        };
                        if recv_type.flags().is_immediate() {
                            // Instance variable lookups on immediate values are always nil
                            self.push_insn(block, Insn::IncrCounter(Counter::setivar_fallback_immediate));
                            self.push_insn_id(block, insn_id); continue;
                        }
                        assert!(recv_type.shape().is_valid());
                        if !recv_type.flags().is_t_object() {
                            // Check if the receiver is a T_OBJECT
                            self.push_insn(block, Insn::IncrCounter(Counter::setivar_fallback_not_t_object));
                            self.push_insn_id(block, insn_id); continue;
                        }
                        if recv_type.shape().is_too_complex() {
                            // too-complex shapes can't use index access
                            self.push_insn(block, Insn::IncrCounter(Counter::setivar_fallback_too_complex));
                            self.push_insn_id(block, insn_id); continue;
                        }
                        if recv_type.shape().is_frozen() {
                            // Can't set ivars on frozen objects
                            self.push_insn(block, Insn::IncrCounter(Counter::setivar_fallback_frozen));
                            self.push_insn_id(block, insn_id); continue;
                        }
                        let mut ivar_index: u16 = 0;
                        let mut next_shape_id = recv_type.shape();
                        if !unsafe { rb_shape_get_iv_index(recv_type.shape().0, id, &mut ivar_index) } {
                            // Current shape does not contain this ivar; do a shape transition.
                            let current_shape_id = recv_type.shape();
                            let class = recv_type.class();
                            // We're only looking at T_OBJECT so ignore all of the imemo stuff.
                            assert!(recv_type.flags().is_t_object());
                            next_shape_id = ShapeId(unsafe { rb_shape_transition_add_ivar_no_warnings(class, current_shape_id.0, id) });
                            // If the VM ran out of shapes, or this class generated too many leaf,
                            // it may be de-optimized into OBJ_TOO_COMPLEX_SHAPE (hash-table).
                            let new_shape_too_complex = unsafe { rb_jit_shape_too_complex_p(next_shape_id.0) };
                            // TODO(max): Is it OK to bail out here after making a shape transition?
                            if new_shape_too_complex {
                                self.push_insn(block, Insn::IncrCounter(Counter::setivar_fallback_new_shape_too_complex));
                                self.push_insn_id(block, insn_id); continue;
                            }
                            let ivar_result = unsafe { rb_shape_get_iv_index(next_shape_id.0, id, &mut ivar_index) };
                            assert!(ivar_result, "New shape must have the ivar index");
                            let current_capacity = unsafe { rb_jit_shape_capacity(current_shape_id.0) };
                            let next_capacity = unsafe { rb_jit_shape_capacity(next_shape_id.0) };
                            // If the new shape has a different capacity, or is TOO_COMPLEX, we'll have to
                            // reallocate it.
                            let needs_extension = next_capacity != current_capacity;
                            if needs_extension {
                                self.push_insn(block, Insn::IncrCounter(Counter::setivar_fallback_new_shape_needs_extension));
                                self.push_insn_id(block, insn_id); continue;
                            }
                            // Fall through to emitting the ivar write
                        }
                        let self_val = self.push_insn(block, Insn::GuardType { val: self_val, guard_type: types::HeapBasicObject, state });
                        let self_val = self.push_insn(block, Insn::GuardShape { val: self_val, shape: recv_type.shape(), state });
                        // Current shape contains this ivar
                        let (ivar_storage, offset) = if recv_type.flags().is_embedded() {
                            // See ROBJECT_FIELDS() from include/ruby/internal/core/robject.h
                            let offset = ROBJECT_OFFSET_AS_ARY as i32 + (SIZEOF_VALUE * ivar_index.to_usize()) as i32;
                            (self_val, offset)
                        } else {
                            let as_heap = self.push_insn(block, Insn::LoadField { recv: self_val, id: ID!(_as_heap), offset: ROBJECT_OFFSET_AS_HEAP_FIELDS as i32, return_type: types::CPtr });
                            let offset = SIZEOF_VALUE_I32 * ivar_index as i32;
                            (as_heap, offset)
                        };
                        self.push_insn(block, Insn::StoreField { recv: ivar_storage, id, offset, val });
                        self.push_insn(block, Insn::WriteBarrier { recv: self_val, val });
                        if next_shape_id != recv_type.shape() {
                            // Write the new shape ID
                            let shape_id = self.push_insn(block, Insn::Const { val: Const::CShape(next_shape_id) });
                            let shape_id_offset = unsafe { rb_shape_id_offset() };
                            self.push_insn(block, Insn::StoreField { recv: self_val, id: ID!(_shape_id), offset: shape_id_offset, val: shape_id });
                        }
                    }
                    _ => { self.push_insn_id(block, insn_id); }
                }
            }
        }
        self.infer_types();
    }

    fn gen_patch_points_for_optimized_ccall(&mut self, block: BlockId, recv_class: VALUE, method_id: ID, cme: *const rb_callable_method_entry_struct, state: InsnId) {
        self.push_insn(block, Insn::PatchPoint { invariant: Invariant::NoTracePoint, state });
        self.push_insn(block, Insn::PatchPoint { invariant: Invariant::MethodRedefined { klass: recv_class, method: method_id, cme }, state });
    }

    /// Optimize SendWithoutBlock that land in a C method to a direct CCall without
    /// runtime lookup.
    fn optimize_c_calls(&mut self) {
        if unsafe { rb_zjit_method_tracing_currently_enabled() } {
            return;
        }

        // Try to reduce a Send insn to a CCallWithFrame
        fn reduce_send_to_ccall(
            fun: &mut Function,
            block: BlockId,
            self_type: Type,
            send: Insn,
            send_insn_id: InsnId,
        ) -> Result<(), ()> {
            let Insn::Send { mut recv, cd, blockiseq, args, state, .. } = send else {
                return Err(());
            };

            let call_info = unsafe { (*cd).ci };
            let argc = unsafe { vm_ci_argc(call_info) };
            let method_id = unsafe { rb_vm_ci_mid(call_info) };

            // If we have info about the class of the receiver
            let iseq_insn_idx = fun.frame_state(state).insn_idx;
            let (recv_class, profiled_type) = match fun.resolve_receiver_type(recv, self_type, iseq_insn_idx) {
                ReceiverTypeResolution::StaticallyKnown { class } => (class, None),
                ReceiverTypeResolution::Monomorphic { profiled_type }
                | ReceiverTypeResolution::SkewedPolymorphic { profiled_type} => (profiled_type.class(), Some(profiled_type)),
                ReceiverTypeResolution::SkewedMegamorphic { .. } | ReceiverTypeResolution::Polymorphic | ReceiverTypeResolution::Megamorphic | ReceiverTypeResolution::NoProfile => return Err(()),
            };

            // Do method lookup
            let cme: *const rb_callable_method_entry_struct = unsafe { rb_callable_method_entry(recv_class, method_id) };
            if cme.is_null() {
                fun.set_dynamic_send_reason(send_insn_id, SendNotOptimizedMethodType(MethodType::Null));
                return Err(());
            }

            // Filter for C methods
            // TODO(max): Handle VM_METHOD_TYPE_ALIAS
            let def_type = unsafe { get_cme_def_type(cme) };
            if def_type != VM_METHOD_TYPE_CFUNC {
                return Err(());
            }


            let ci_flags = unsafe { vm_ci_flag(call_info) };
            let visibility = unsafe { METHOD_ENTRY_VISI(cme) };
            match (visibility, ci_flags & VM_CALL_FCALL != 0) {
                (METHOD_VISI_PUBLIC, _) => {}
                (METHOD_VISI_PRIVATE, true) => {}
                (METHOD_VISI_PROTECTED, true) => {}
                _ => {
                    fun.set_dynamic_send_reason(send_insn_id, SendNotOptimizedNeedPermission);
                    return Err(());
                }
            }

            // When seeing &block argument, fall back to dynamic dispatch for now
            // TODO: Support block forwarding
            if unspecializable_c_call_type(ci_flags) {
                fun.count_complex_call_features(block, ci_flags);
                fun.set_dynamic_send_reason(send_insn_id, ComplexArgPass);
                return Err(());
            }

            let blockiseq = if blockiseq.is_null() { None } else { Some(blockiseq) };

            let cfunc = unsafe { get_cme_def_body_cfunc(cme) };
            // Find the `argc` (arity) of the C method, which describes the parameters it expects
            let cfunc_argc = unsafe { get_mct_argc(cfunc) };
            let cfunc_ptr = unsafe { get_mct_func(cfunc) }.cast();

            match cfunc_argc {
                0.. => {
                    // (self, arg0, arg1, ..., argc) form
                    //
                    // Bail on argc mismatch
                    if argc != cfunc_argc as u32 {
                        return Err(());
                    }

                    // Commit to the replacement. Put PatchPoint.
                    fun.gen_patch_points_for_optimized_ccall(block, recv_class, method_id, cme, state);
                    if recv_class.instance_can_have_singleton_class() {
                        fun.push_insn(block, Insn::PatchPoint { invariant: Invariant::NoSingletonClass { klass: recv_class }, state });
                    }

                    if let Some(profiled_type) = profiled_type {
                        // Guard receiver class
                        recv = fun.push_insn(block, Insn::GuardType { val: recv, guard_type: Type::from_profiled_type(profiled_type), state });
                        fun.insn_types[recv.0] = fun.infer_type(recv);
                    }

                    // Emit a call
                    let cfunc = unsafe { get_mct_func(cfunc) }.cast();

                    let name = rust_str_to_id(&qualified_method_name(unsafe { (*cme).owner }, unsafe { (*cme).called_id }));
                    let ccall = fun.push_insn(block, Insn::CCallWithFrame {
                        cd,
                        cfunc,
                        recv,
                        args,
                        cme,
                        name,
                        state,
                        return_type: types::BasicObject,
                        elidable: false,
                        blockiseq,
                    });
                    fun.make_equal_to(send_insn_id, ccall);
                    Ok(())
                }
                // Variadic method
                -1 => {
                    // The method gets a pointer to the first argument
                    // func(int argc, VALUE *argv, VALUE recv)
                    fun.gen_patch_points_for_optimized_ccall(block, recv_class, method_id, cme, state);

                    if recv_class.instance_can_have_singleton_class() {
                        fun.push_insn(block, Insn::PatchPoint { invariant: Invariant::NoSingletonClass { klass: recv_class }, state });
                    }
                    if let Some(profiled_type) = profiled_type {
                        // Guard receiver class
                        recv = fun.push_insn(block, Insn::GuardType { val: recv, guard_type: Type::from_profiled_type(profiled_type), state });
                        fun.insn_types[recv.0] = fun.infer_type(recv);
                    }

                    if get_option!(stats) {
                        count_not_inlined_cfunc(fun, block, cme);
                    }

                    let ccall = fun.push_insn(block, Insn::CCallVariadic {
                        cfunc: cfunc_ptr,
                        recv,
                        args,
                        cme,
                        name: method_id,
                        state,
                        return_type: types::BasicObject,
                        elidable: false,
                        blockiseq
                    });

                    fun.make_equal_to(send_insn_id, ccall);
                    Ok(())
                }
                -2 => {
                    // (self, args_ruby_array)
                    fun.set_dynamic_send_reason(send_insn_id, SendCfuncArrayVariadic);
                    Err(())
                }
                _ => unreachable!("unknown cfunc kind: argc={argc}")
            }
        }

        // Try to reduce a SendWithoutBlock insn to a CCall/CCallWithFrame
        fn reduce_send_without_block_to_ccall(
            fun: &mut Function,
            block: BlockId,
            self_type: Type,
            send: Insn,
            send_insn_id: InsnId,
        ) -> Result<(), ()> {
            let Insn::SendWithoutBlock { mut recv, cd, args, state, .. } = send else {
                return Err(());
            };

            let call_info = unsafe { (*cd).ci };
            let argc = unsafe { vm_ci_argc(call_info) };
            let method_id = unsafe { rb_vm_ci_mid(call_info) };

            // If we have info about the class of the receiver
            let iseq_insn_idx = fun.frame_state(state).insn_idx;
            let (recv_class, profiled_type) = match fun.resolve_receiver_type(recv, self_type, iseq_insn_idx) {
                ReceiverTypeResolution::StaticallyKnown { class } => (class, None),
                ReceiverTypeResolution::Monomorphic { profiled_type }
                | ReceiverTypeResolution::SkewedPolymorphic { profiled_type } => (profiled_type.class(), Some(profiled_type)),
                ReceiverTypeResolution::SkewedMegamorphic { .. } | ReceiverTypeResolution::Polymorphic | ReceiverTypeResolution::Megamorphic | ReceiverTypeResolution::NoProfile => return Err(()),
            };

            // Do method lookup
            let mut cme: *const rb_callable_method_entry_struct = unsafe { rb_callable_method_entry(recv_class, method_id) };
            if cme.is_null() {
                fun.set_dynamic_send_reason(send_insn_id, SendWithoutBlockNotOptimizedMethodType(MethodType::Null));
                return Err(());
            }

            // Filter for C methods
            let mut def_type = unsafe { get_cme_def_type(cme) };
            while def_type == VM_METHOD_TYPE_ALIAS {
                cme = unsafe { rb_aliased_callable_method_entry(cme) };
                def_type = unsafe { get_cme_def_type(cme) };
            }
            if def_type != VM_METHOD_TYPE_CFUNC {
                return Err(());
            }

            let ci_flags = unsafe { vm_ci_flag(call_info) };
            let visibility = unsafe { METHOD_ENTRY_VISI(cme) };
            match (visibility, ci_flags & VM_CALL_FCALL != 0) {
                (METHOD_VISI_PUBLIC, _) => {}
                (METHOD_VISI_PRIVATE, true) => {}
                (METHOD_VISI_PROTECTED, true) => {}
                _ => {
                    fun.set_dynamic_send_reason(send_insn_id, SendWithoutBlockNotOptimizedNeedPermission);
                    return Err(());
                }
            }

            // Find the `argc` (arity) of the C method, which describes the parameters it expects
            let cfunc = unsafe { get_cme_def_body_cfunc(cme) };
            let cfunc_argc = unsafe { get_mct_argc(cfunc) };
            match cfunc_argc {
                0.. => {
                    // (self, arg0, arg1, ..., argc) form
                    //
                    // Bail on argc mismatch
                    if argc != cfunc_argc as u32 {
                        return Err(());
                    }

                    // Filter for simple call sites (i.e. no splats etc.)
                    if ci_flags & VM_CALL_ARGS_SIMPLE == 0 {
                        fun.count_complex_call_features(block, ci_flags);
                        fun.set_dynamic_send_reason(send_insn_id, ComplexArgPass);
                        return Err(());
                    }

                    // Commit to the replacement. Put PatchPoint.
                    fun.gen_patch_points_for_optimized_ccall(block, recv_class, method_id, cme, state);
                    if recv_class.instance_can_have_singleton_class() {
                        fun.push_insn(block, Insn::PatchPoint { invariant: Invariant::NoSingletonClass { klass: recv_class }, state });
                    }

                    let props = ZJITState::get_method_annotations().get_cfunc_properties(cme);
                    if props.is_none() && get_option!(stats) {
                        count_not_annotated_cfunc(fun, block, cme);
                    }
                    let props = props.unwrap_or_default();

                    if let Some(profiled_type) = profiled_type {
                        // Guard receiver class
                        recv = fun.push_insn(block, Insn::GuardType { val: recv, guard_type: Type::from_profiled_type(profiled_type), state });
                        fun.insn_types[recv.0] = fun.infer_type(recv);
                    }

                    // Try inlining the cfunc into HIR
                    let tmp_block = fun.new_block(u32::MAX);
                    if let Some(replacement) = (props.inline)(fun, tmp_block, recv, &args, state) {
                        // Copy contents of tmp_block to block
                        assert_ne!(block, tmp_block);
                        let insns = std::mem::take(&mut fun.blocks[tmp_block.0].insns);
                        fun.blocks[block.0].insns.extend(insns);
                        fun.push_insn(block, Insn::IncrCounter(Counter::inline_cfunc_optimized_send_count));
                        fun.make_equal_to(send_insn_id, replacement);
                        if fun.type_of(replacement).bit_equal(types::Any) {
                            // Not set yet; infer type
                            fun.insn_types[replacement.0] = fun.infer_type(replacement);
                        }
                        fun.remove_block(tmp_block);
                        return Ok(());
                    }

                    // No inlining; emit a call
                    let cfunc = unsafe { get_mct_func(cfunc) }.cast();
                    let name = rust_str_to_id(&qualified_method_name(unsafe { (*cme).owner }, unsafe { (*cme).called_id }));
                    let return_type = props.return_type;
                    let elidable = props.elidable;
                    // Filter for a leaf and GC free function
                    if props.leaf && props.no_gc {
                        fun.push_insn(block, Insn::IncrCounter(Counter::inline_cfunc_optimized_send_count));
                        let ccall = fun.push_insn(block, Insn::CCall { cfunc, recv, args, name, return_type, elidable });
                        fun.make_equal_to(send_insn_id, ccall);
                    } else {
                        if get_option!(stats) {
                            count_not_inlined_cfunc(fun, block, cme);
                        }
                        let ccall = fun.push_insn(block, Insn::CCallWithFrame {
                            cd,
                            cfunc,
                            recv,
                            args,
                            cme,
                            name,
                            state,
                            return_type,
                            elidable,
                            blockiseq: None,
                        });
                        fun.make_equal_to(send_insn_id, ccall);
                    }

                    return Ok(());
                }
                // Variadic method
                -1 => {
                    // The method gets a pointer to the first argument
                    // func(int argc, VALUE *argv, VALUE recv)
                    let ci_flags = unsafe { vm_ci_flag(call_info) };
                    if ci_flags & VM_CALL_ARGS_SIMPLE == 0 {
                        // TODO(alan): Add fun.count_complex_call_features() here without double
                        // counting splat
                        fun.set_dynamic_send_reason(send_insn_id, ComplexArgPass);
                        return Err(());
                    } else {
                        fun.gen_patch_points_for_optimized_ccall(block, recv_class, method_id, cme, state);

                        if recv_class.instance_can_have_singleton_class() {
                            fun.push_insn(block, Insn::PatchPoint { invariant: Invariant::NoSingletonClass { klass: recv_class }, state });
                        }
                        if let Some(profiled_type) = profiled_type {
                            // Guard receiver class
                            recv = fun.push_insn(block, Insn::GuardType { val: recv, guard_type: Type::from_profiled_type(profiled_type), state });
                            fun.insn_types[recv.0] = fun.infer_type(recv);
                        }

                        let cfunc = unsafe { get_mct_func(cfunc) }.cast();
                        let props = ZJITState::get_method_annotations().get_cfunc_properties(cme);
                        if props.is_none() && get_option!(stats) {
                            count_not_annotated_cfunc(fun, block, cme);
                        }
                        let props = props.unwrap_or_default();

                        // Try inlining the cfunc into HIR
                        let tmp_block = fun.new_block(u32::MAX);
                        if let Some(replacement) = (props.inline)(fun, tmp_block, recv, &args, state) {
                            // Copy contents of tmp_block to block
                            assert_ne!(block, tmp_block);
                            let insns = std::mem::take(&mut fun.blocks[tmp_block.0].insns);
                            fun.blocks[block.0].insns.extend(insns);
                            fun.push_insn(block, Insn::IncrCounter(Counter::inline_cfunc_optimized_send_count));
                            fun.make_equal_to(send_insn_id, replacement);
                            if fun.type_of(replacement).bit_equal(types::Any) {
                                // Not set yet; infer type
                                fun.insn_types[replacement.0] = fun.infer_type(replacement);
                            }
                            fun.remove_block(tmp_block);
                            return Ok(());
                        }

                        // No inlining; emit a call
                        if get_option!(stats) {
                            count_not_inlined_cfunc(fun, block, cme);
                        }
                        let return_type = props.return_type;
                        let elidable = props.elidable;
                        let name = rust_str_to_id(&qualified_method_name(unsafe { (*cme).owner }, unsafe { (*cme).called_id }));
                        let ccall = fun.push_insn(block, Insn::CCallVariadic {
                            cfunc,
                            recv,
                            args,
                            cme,
                            name,
                            state,
                            return_type,
                            elidable,
                            blockiseq: None,
                        });

                        fun.make_equal_to(send_insn_id, ccall);
                        return Ok(())
                    }

                    // Fall through for complex cases (splat, kwargs, etc.)
                }
                -2 => {
                    // (self, args_ruby_array) parameter form
                    // Falling through for now
                    fun.set_dynamic_send_reason(send_insn_id, SendWithoutBlockCfuncArrayVariadic);
                }
                _ => unreachable!("unknown cfunc kind: argc={argc}")
            }

            Err(())
        }

        fn qualified_method_name(class: VALUE, method_id: ID) -> String {
            let method_name = method_id.contents_lossy();
            // rb_zjit_singleton_class_p also checks if it's a class
            if unsafe { rb_zjit_singleton_class_p(class) } {
                let class_name = get_class_name(unsafe { rb_class_attached_object(class) });
                format!("{class_name}.{method_name}")
            } else {
                let class_name = get_class_name(class);
                format!("{class_name}#{method_name}")
            }
        }

        fn count_not_inlined_cfunc(fun: &mut Function, block: BlockId, cme: *const rb_callable_method_entry_t) {
            let owner = unsafe { (*cme).owner };
            let called_id = unsafe { (*cme).called_id };
            let qualified_method_name = qualified_method_name(owner, called_id);
            let not_inlined_cfunc_counter_pointers = ZJITState::get_not_inlined_cfunc_counter_pointers();
            let counter_ptr = not_inlined_cfunc_counter_pointers.entry(qualified_method_name.clone()).or_insert_with(|| Box::new(0));
            let counter_ptr = &mut **counter_ptr as *mut u64;

            fun.push_insn(block, Insn::IncrCounterPtr { counter_ptr });
        }

        fn count_not_annotated_cfunc(fun: &mut Function, block: BlockId, cme: *const rb_callable_method_entry_t) {
            let owner = unsafe { (*cme).owner };
            let called_id = unsafe { (*cme).called_id };
            let qualified_method_name = qualified_method_name(owner, called_id);
            let not_annotated_cfunc_counter_pointers = ZJITState::get_not_annotated_cfunc_counter_pointers();
            let counter_ptr = not_annotated_cfunc_counter_pointers.entry(qualified_method_name.clone()).or_insert_with(|| Box::new(0));
            let counter_ptr = &mut **counter_ptr as *mut u64;

            fun.push_insn(block, Insn::IncrCounterPtr { counter_ptr });
        }

        for block in self.rpo() {
            let old_insns = std::mem::take(&mut self.blocks[block.0].insns);
            assert!(self.blocks[block.0].insns.is_empty());
            for insn_id in old_insns {
                let send = self.find(insn_id);
                match send {
                    send @ Insn::SendWithoutBlock { recv, .. } => {
                        let recv_type = self.type_of(recv);
                        if reduce_send_without_block_to_ccall(self, block, recv_type, send, insn_id).is_ok() {
                            continue;
                        }
                    }
                    send @ Insn::Send { recv, .. } => {
                        let recv_type = self.type_of(recv);
                        if reduce_send_to_ccall(self, block, recv_type, send, insn_id).is_ok() {
                            continue;
                        }
                    }
                    Insn::InvokeBuiltin { bf, recv, args, state, .. } => {
                        let props = ZJITState::get_method_annotations().get_builtin_properties(&bf).unwrap_or_default();
                        // Try inlining the cfunc into HIR
                        let tmp_block = self.new_block(u32::MAX);
                        if let Some(replacement) = (props.inline)(self, tmp_block, recv, &args, state) {
                            // Copy contents of tmp_block to block
                            assert_ne!(block, tmp_block);
                            let insns = std::mem::take(&mut self.blocks[tmp_block.0].insns);
                            self.blocks[block.0].insns.extend(insns);
                            self.push_insn(block, Insn::IncrCounter(Counter::inline_cfunc_optimized_send_count));
                            self.make_equal_to(insn_id, replacement);
                            if self.type_of(replacement).bit_equal(types::Any) {
                                // Not set yet; infer type
                                self.insn_types[replacement.0] = self.infer_type(replacement);
                            }
                            self.remove_block(tmp_block);
                            continue;
                        }
                    }
                    _ => {}
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
                    Insn::LoadField { recv, offset, return_type, .. } if return_type.is_subtype(types::BasicObject) &&
                            u32::try_from(offset).is_ok() => {
                        let offset = (offset as u32).to_usize();
                        let recv_type = self.type_of(recv);
                        match recv_type.ruby_object() {
                            Some(recv_obj) if recv_obj.is_frozen() => {
                                let recv_ptr = recv_obj.as_ptr() as *const VALUE;
                                let val = unsafe { recv_ptr.byte_add(offset).read() };
                                self.new_insn(Insn::Const { val: Const::Value(val) })
                            }
                            _ => insn_id,
                        }
                    }
                    Insn::AnyToString { str, .. } if self.is_a(str, types::String) => {
                        self.make_equal_to(insn_id, str);
                        // Don't bother re-inferring the type of str; we already know it.
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
                    Insn::ArrayArefFixnum { array, index } if self.type_of(array).ruby_object_known()
                                                           && self.type_of(index).ruby_object_known() => {
                        let array_obj = self.type_of(array).ruby_object().unwrap();
                        if array_obj.is_frozen() {
                            let index = self.type_of(index).fixnum_value().unwrap();
                            let val = unsafe { rb_yarv_ary_entry_internal(array_obj, index) };
                            self.new_insn(Insn::Const { val: Const::Value(val) })
                        } else {
                            insn_id
                        }
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
                if insn_id != replacement_id && self.insns[replacement_id.0].has_output() {
                    self.make_equal_to(insn_id, replacement_id);
                    self.insn_types[replacement_id.0] = self.infer_type(replacement_id);
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
            | &Insn::Param
            | &Insn::EntryPoint { .. }
            | &Insn::LoadPC
            | &Insn::LoadEC
            | &Insn::LoadSelf
            | &Insn::GetLocal { .. }
            | &Insn::PutSpecialObject { .. }
            | &Insn::IsBlockGiven
            | &Insn::IncrCounter(_)
            | &Insn::IncrCounterPtr { .. } =>
                {}
            &Insn::PatchPoint { state, .. }
            | &Insn::CheckInterrupts { state }
            | &Insn::GetConstantPath { ic: _, state } => {
                worklist.push_back(state);
            }
            &Insn::FixnumBitCheck { val, index: _ } => {
                worklist.push_back(val)
            }
            &Insn::ArrayMax { ref elements, state }
            | &Insn::ArrayHash { ref elements, state }
            | &Insn::NewHash { ref elements, state }
            | &Insn::NewArray { ref elements, state } => {
                worklist.extend(elements);
                worklist.push_back(state);
            }
            &Insn::ArrayInclude { ref elements, target, state } => {
                worklist.extend(elements);
                worklist.push_back(target);
                worklist.push_back(state);
            }
            &Insn::ArrayPackBuffer { ref elements, fmt, buffer, state } => {
                worklist.extend(elements);
                worklist.push_back(fmt);
                worklist.push_back(buffer);
                worklist.push_back(state);
            }
            &Insn::DupArrayInclude { target, state, .. } => {
                worklist.push_back(target);
                worklist.push_back(state);
            }
            &Insn::NewRange { low, high, state, .. }
            | &Insn::NewRangeFixnum { low, high, state, .. } => {
                worklist.push_back(low);
                worklist.push_back(high);
                worklist.push_back(state);
            }
            &Insn::StringConcat { ref strings, state, .. } => {
                worklist.extend(strings);
                worklist.push_back(state);
            }
            &Insn::StringGetbyte { string, index } => {
                worklist.push_back(string);
                worklist.push_back(index);
            }
            &Insn::StringSetbyteFixnum { string, index, value } => {
                worklist.push_back(string);
                worklist.push_back(index);
                worklist.push_back(value);
            }
            &Insn::StringAppend { recv, other, state }
            | &Insn::StringAppendCodepoint { recv, other, state }
            => {
                worklist.push_back(recv);
                worklist.push_back(other);
                worklist.push_back(state);
            }
            &Insn::ToRegexp { ref values, state, .. } => {
                worklist.extend(values);
                worklist.push_back(state);
            }
            | &Insn::Return { val }
            | &Insn::Test { val }
            | &Insn::SetLocal { val, .. }
            | &Insn::BoxBool { val }
            | &Insn::IsNil { val } =>
                worklist.push_back(val),
            &Insn::SetGlobal { val, state, .. }
            | &Insn::Defined { v: val, state, .. }
            | &Insn::StringIntern { val, state }
            | &Insn::StringCopy { val, state, .. }
            | &Insn::ObjectAlloc { val, state }
            | &Insn::GuardType { val, state, .. }
            | &Insn::GuardTypeNot { val, state, .. }
            | &Insn::GuardBitEquals { val, state, .. }
            | &Insn::GuardShape { val, state, .. }
            | &Insn::GuardNotFrozen { recv: val, state }
            | &Insn::ToArray { val, state }
            | &Insn::IsMethodCfunc { val, state, .. }
            | &Insn::ToNewArray { val, state }
            | &Insn::BoxFixnum { val, state } => {
                worklist.push_back(val);
                worklist.push_back(state);
            }
            &Insn::GuardGreaterEq { left, right, state } => {
                worklist.push_back(left);
                worklist.push_back(right);
                worklist.push_back(state);
            }
            &Insn::GuardLess { left, right, state } => {
                worklist.push_back(left);
                worklist.push_back(right);
                worklist.push_back(state);
            }
            Insn::Snapshot { state } => {
                worklist.extend(&state.stack);
                worklist.extend(&state.locals);
            }
            &Insn::FixnumAdd { left, right, state }
            | &Insn::FixnumSub { left, right, state }
            | &Insn::FixnumMult { left, right, state }
            | &Insn::FixnumDiv { left, right, state }
            | &Insn::FixnumMod { left, right, state }
            | &Insn::ArrayExtend { left, right, state }
            | &Insn::FixnumLShift { left, right, state }
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
            | &Insn::FixnumXor { left, right }
            | &Insn::FixnumRShift { left, right }
            | &Insn::IsBitEqual { left, right }
            | &Insn::IsBitNotEqual { left, right }
            => {
                worklist.push_back(left);
                worklist.push_back(right);
            }
            &Insn::Jump(BranchEdge { ref args, .. }) => worklist.extend(args),
            &Insn::IfTrue { val, target: BranchEdge { ref args, .. } } | &Insn::IfFalse { val, target: BranchEdge { ref args, .. } } => {
                worklist.push_back(val);
                worklist.extend(args);
            }
            &Insn::ArrayDup { val, state }
            | &Insn::Throw { val, state, .. }
            | &Insn::HashDup { val, state } => {
                worklist.push_back(val);
                worklist.push_back(state);
            }
            &Insn::ArrayArefFixnum { array, index } => {
                worklist.push_back(array);
                worklist.push_back(index);
            }
            &Insn::ArrayPop { array, state } => {
                worklist.push_back(array);
                worklist.push_back(state);
            }
            &Insn::ArrayLength { array } => {
                worklist.push_back(array);
            }
            &Insn::HashAref { hash, key, state } => {
                worklist.push_back(hash);
                worklist.push_back(key);
                worklist.push_back(state);
            }
            &Insn::HashAset { hash, key, val, state } => {
                worklist.push_back(hash);
                worklist.push_back(key);
                worklist.push_back(val);
                worklist.push_back(state);
            }
            &Insn::Send { recv, ref args, state, .. }
            | &Insn::SendForward { recv, ref args, state, .. }
            | &Insn::SendWithoutBlock { recv, ref args, state, .. }
            | &Insn::CCallVariadic { recv, ref args, state, .. }
            | &Insn::CCallWithFrame { recv, ref args, state, .. }
            | &Insn::SendWithoutBlockDirect { recv, ref args, state, .. }
            | &Insn::InvokeBuiltin { recv, ref args, state, .. }
            | &Insn::InvokeSuper { recv, ref args, state, .. } => {
                worklist.push_back(recv);
                worklist.extend(args);
                worklist.push_back(state);
            }
            &Insn::InvokeBlock { ref args, state, .. } => {
                worklist.extend(args);
                worklist.push_back(state)
            }
            &Insn::CCall { recv, ref args, .. } => {
                worklist.push_back(recv);
                worklist.extend(args);
            }
            &Insn::GetIvar { self_val, state, .. } | &Insn::DefinedIvar { self_val, state, .. } => {
                worklist.push_back(self_val);
                worklist.push_back(state);
            }
            &Insn::SetIvar { self_val, val, state, .. } => {
                worklist.push_back(self_val);
                worklist.push_back(val);
                worklist.push_back(state);
            }
            &Insn::GetClassVar { state, .. } => {
                worklist.push_back(state);
            }
            &Insn::SetClassVar { val, state, .. } => {
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
            &Insn::LoadField { recv, .. } => {
                worklist.push_back(recv);
            }
            &Insn::StoreField { recv, val, .. }
            | &Insn::WriteBarrier { recv, val } => {
                worklist.push_back(recv);
                worklist.push_back(val);
            }
            &Insn::GuardBlockParamProxy { state, .. } |
            &Insn::GetGlobal { state, .. } |
            &Insn::GetSpecialSymbol { state, .. } |
            &Insn::GetSpecialNumber { state, .. } |
            &Insn::ObjectAllocClass { state, .. } |
            &Insn::SideExit { state, .. } => worklist.push_back(state),
            &Insn::UnboxFixnum { val } => worklist.push_back(val),
            &Insn::IsA { val, class } => {
                worklist.push_back(val);
                worklist.push_back(class);
            }
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

    fn absorb_dst_block(&mut self, num_in_edges: &[u32], block: BlockId) -> bool {
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

    /// Return a list that has entry_block and then jit_entry_blocks
    fn entry_blocks(&self) -> Vec<BlockId> {
        let mut entry_blocks = self.jit_entry_blocks.clone();
        entry_blocks.insert(0, self.entry_block);
        entry_blocks
    }

    /// Return a traversal of the `Function`'s `BlockId`s in reverse post-order.
    pub fn rpo(&self) -> Vec<BlockId> {
        let mut result = self.po_from(self.entry_blocks());
        result.reverse();
        result
    }

    fn po_from(&self, starts: Vec<BlockId>) -> Vec<BlockId> {
        #[derive(PartialEq)]
        enum Action {
            VisitEdges,
            VisitSelf,
        }
        let mut result = vec![];
        let mut seen = BlockSet::with_capacity(self.blocks.len());
        let mut stack: Vec<_> = starts.iter().map(|&start| (start, Action::VisitEdges)).collect();
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

    /// Helper function to make an Iongraph JSON "instruction".
    /// `uses`, `memInputs` and `attributes` are left empty for now, but may be populated
    /// in the future.
    fn make_iongraph_instr(id: InsnId, inputs: Vec<Json>, opcode: &str, ty: &str) -> Json {
        Json::object()
            // Add an offset of 0x1000 to avoid the `ptr` being 0x0, which iongraph rejects.
            .insert("ptr", id.0 + 0x1000)
            .insert("id", id.0)
            .insert("opcode", opcode)
            .insert("attributes", Json::empty_array())
            .insert("inputs", Json::Array(inputs))
            .insert("uses", Json::empty_array())
            .insert("memInputs", Json::empty_array())
            .insert("type", ty)
            .build()
    }

    /// Helper function to make an Iongraph JSON "block".
    fn make_iongraph_block(id: BlockId, predecessors: Vec<BlockId>, successors: Vec<BlockId>, instructions: Vec<Json>, attributes: Vec<&str>, loop_depth: u32) -> Json {
        Json::object()
            // Add an offset of 0x1000 to avoid the `ptr` being 0x0, which iongraph rejects.
            .insert("ptr", id.0 + 0x1000)
            .insert("id", id.0)
            .insert("loopDepth", loop_depth)
            .insert("attributes", Json::array(attributes))
            .insert("predecessors", Json::array(predecessors.iter().map(|x| x.0).collect::<Vec<usize>>()))
            .insert("successors", Json::array(successors.iter().map(|x| x.0).collect::<Vec<usize>>()))
            .insert("instructions", Json::array(instructions))
            .build()
    }

    /// Helper function to make an Iongraph JSON "function".
    /// Note that `lir` is unpopulated right now as ZJIT doesn't use its functionality.
    fn make_iongraph_function(pass_name: &str, hir_blocks: Vec<Json>) -> Json {
        Json::object()
            .insert("name", pass_name)
            .insert("mir", Json::object()
                .insert("blocks", Json::array(hir_blocks))
                .build()
            )
            .insert("lir", Json::object()
                .insert("blocks", Json::empty_array())
                .build()
            )
            .build()
    }

    /// Generate an iongraph JSON pass representation for this function.
    pub fn to_iongraph_pass(&self, pass_name: &str) -> Json {
        let mut ptr_map = PtrPrintMap::identity();
        if cfg!(test) {
            ptr_map.map_ptrs = true;
        }

        let mut hir_blocks = Vec::new();
        let cfi = ControlFlowInfo::new(self);
        let dominators = Dominators::new(self);
        let loop_info = LoopInfo::new(&cfi, &dominators);

        // Push each block from the iteration in reverse post order to `hir_blocks`.
        for block_id in self.rpo() {
            // Create the block with instructions.
            let block = &self.blocks[block_id.0];
            let predecessors = cfi.predecessors(block_id).collect();
            let successors = cfi.successors(block_id).collect();
            let mut instructions = Vec::new();

            // Process all instructions (parameters and body instructions).
            // Parameters are currently guaranteed to be Parameter instructions, but in the future
            // they might be refined to other instruction kinds by the optimizer.
            for insn_id in block.params.iter().chain(block.insns.iter()) {
                let insn_id = self.union_find.borrow().find_const(*insn_id);
                let insn = self.find(insn_id);

                // Snapshots are not serialized, so skip them.
                if matches!(insn, Insn::Snapshot {..}) {
                    continue;
                }

                // Instructions with no output or an empty type should have an empty type field.
                let type_str = if insn.has_output() {
                    let insn_type = self.type_of(insn_id);
                    if insn_type.is_subtype(types::Empty) {
                        String::new()
                    } else {
                        insn_type.print(&ptr_map).to_string()
                    }
                } else {
                    String::new()
                };


                let opcode = insn.print(&ptr_map, Some(self.iseq)).to_string();

                // Traverse the worklist to get inputs for a given instruction.
                let mut inputs = VecDeque::new();
                self.worklist_traverse_single_insn(&insn, &mut inputs);
                let inputs: Vec<Json> = inputs.into_iter().map(|x| x.0.into()).collect();

                instructions.push(
                    Self::make_iongraph_instr(
                        insn_id,
                        inputs,
                        &opcode,
                        &type_str
                    )
                );
            }

            let mut attributes = vec![];
            if loop_info.is_back_edge_source(block_id) {
                attributes.push("backedge");
            }
            if loop_info.is_loop_header(block_id) {
                attributes.push("loopheader");
            }
            let loop_depth = loop_info.loop_depth(block_id);

            hir_blocks.push(Self::make_iongraph_block(
                block_id,
                predecessors,
                successors,
                instructions,
                attributes,
                loop_depth,
            ));
        }

        Self::make_iongraph_function(pass_name, hir_blocks)
    }

    /// Run all the optimization passes we have.
    pub fn optimize(&mut self) {
        let mut passes: Vec<Json> = Vec::new();
        let should_dump = get_option!(dump_hir_iongraph);

        macro_rules! run_pass {
            ($name:ident) => {
                self.$name();
                #[cfg(debug_assertions)] self.assert_validates();
                if should_dump {
                    passes.push(
                        self.to_iongraph_pass(stringify!($name))
                    );
                }
            }
        }

        if should_dump {
            passes.push(self.to_iongraph_pass("unoptimized"));
        }

        // Function is assumed to have types inferred already
        run_pass!(type_specialize);
        run_pass!(inline);
        run_pass!(optimize_getivar);
        run_pass!(optimize_c_calls);
        run_pass!(fold_constants);
        run_pass!(clean_cfg);
        run_pass!(eliminate_dead_code);

        if should_dump {
            let iseq_name = iseq_get_location(self.iseq, 0);
            self.dump_iongraph(&iseq_name, passes);
        }
    }

    /// Dump HIR passed to codegen if specified by options.
    pub fn dump_hir(&self) {
        // Dump HIR after optimization
        match get_option!(dump_hir_opt) {
            Some(DumpHIR::WithoutSnapshot) => println!("Optimized HIR:\n{}", FunctionPrinter::without_snapshot(self)),
            Some(DumpHIR::All) => println!("Optimized HIR:\n{}", FunctionPrinter::with_snapshot(self)),
            Some(DumpHIR::Debug) => println!("Optimized HIR:\n{:#?}", &self),
            None => {},
        }

        if let Some(filename) = &get_option!(dump_hir_graphviz) {
            use std::fs::OpenOptions;
            use std::io::Write;
            let mut file = OpenOptions::new().append(true).open(filename).unwrap();
            writeln!(file, "{}", FunctionGraphvizPrinter::new(self)).unwrap();
        }
    }

    pub fn dump_iongraph(&self, function_name: &str, passes: Vec<Json>) {
        fn sanitize_for_filename(name: &str) -> String {
            name.chars()
                .map(|c| {
                    if c.is_ascii_alphanumeric() || c == '_' || c == '-' {
                        c
                    } else {
                        '_'
                    }
                })
                .collect()
        }

        use std::io::Write;
        let dir = format!("/tmp/zjit-iongraph-{}", std::process::id());
        std::fs::create_dir_all(&dir).expect("Unable to create directory.");
        let sanitized = sanitize_for_filename(function_name);
        let path = format!("{dir}/func_{sanitized}.json");
        let mut file = std::fs::File::create(path).unwrap();
        let json = Json::object()
            .insert("name", function_name)
            .insert("passes", passes)
            .build();
        writeln!(file, "{json}").unwrap();
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
        // Begin with every block having every variable defined, except for the entry blocks, which
        // start with nothing defined.
        let entry_blocks = self.entry_blocks();
        for &block in &rpo {
            if entry_blocks.contains(&block) {
                assigned_in[block.0] = Some(InsnSet::with_capacity(self.insns.len()));
            } else {
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

    fn assert_subtype(&self, user: InsnId, operand: InsnId, expected: Type) -> Result<(), ValidationError> {
        let actual = self.type_of(operand);
        if !actual.is_subtype(expected) {
            return Err(ValidationError::MismatchedOperandType(user, operand, format!("{expected}"), format!("{actual}")));
        }
        Ok(())
    }

    fn validate_insn_type(&self, insn_id: InsnId) -> Result<(), ValidationError> {
        let insn_id = self.union_find.borrow().find_const(insn_id);
        let insn = self.find(insn_id);
        match insn {
            // Instructions with no InsnId operands (except state) or nothing to assert
            Insn::Const { .. }
            | Insn::Param
            | Insn::PutSpecialObject { .. }
            | Insn::LoadField { .. }
            | Insn::GetConstantPath { .. }
            | Insn::IsBlockGiven
            | Insn::GetGlobal { .. }
            | Insn::LoadPC
            | Insn::LoadEC
            | Insn::LoadSelf
            | Insn::Snapshot { .. }
            | Insn::Jump { .. }
            | Insn::EntryPoint { .. }
            | Insn::GuardBlockParamProxy { .. }
            | Insn::PatchPoint { .. }
            | Insn::SideExit { .. }
            | Insn::IncrCounter { .. }
            | Insn::IncrCounterPtr { .. }
            | Insn::CheckInterrupts { .. }
            | Insn::GetClassVar { .. }
            | Insn::GetSpecialNumber { .. }
            | Insn::GetSpecialSymbol { .. }
            | Insn::GetLocal { .. }
            | Insn::StoreField { .. } => {
                Ok(())
            }
            // Instructions with 1 Ruby object operand
            Insn::Test { val }
            | Insn::IsNil { val }
            | Insn::IsMethodCfunc { val, .. }
            | Insn::GuardShape { val, .. }
            | Insn::SetGlobal { val, .. }
            | Insn::SetLocal { val, .. }
            | Insn::SetClassVar { val, .. }
            | Insn::Return { val }
            | Insn::Throw { val, .. }
            | Insn::ObjToString { val, .. }
            | Insn::GuardType { val, .. }
            | Insn::GuardTypeNot { val, .. }
            | Insn::ToArray { val, .. }
            | Insn::ToNewArray { val, .. }
            | Insn::Defined { v: val, .. }
            | Insn::ObjectAlloc { val, .. }
            | Insn::DupArrayInclude { target: val, .. }
            | Insn::GetIvar { self_val: val, .. }
            | Insn::CCall { recv: val, .. }
            | Insn::FixnumBitCheck { val, .. } // TODO (https://github.com/Shopify/ruby/issues/859) this should check Fixnum, but then test_checkkeyword_tests_fixnum_bit fails
            | Insn::DefinedIvar { self_val: val, .. } => {
                self.assert_subtype(insn_id, val, types::BasicObject)
            }
            Insn::GuardNotFrozen { recv, .. } => {
                self.assert_subtype(insn_id, recv, types::HeapBasicObject)
            }
            // Instructions with 2 Ruby object operands
            Insn::SetIvar { self_val: left, val: right, .. }
            | Insn::NewRange { low: left, high: right, .. }
            | Insn::AnyToString { val: left, str: right, .. }
            | Insn::WriteBarrier { recv: left, val: right } => {
                self.assert_subtype(insn_id, left, types::BasicObject)?;
                self.assert_subtype(insn_id, right, types::BasicObject)
            }
            // Instructions with recv and a Vec of Ruby objects
            Insn::SendWithoutBlock { recv, ref args, .. }
            | Insn::SendWithoutBlockDirect { recv, ref args, .. }
            | Insn::Send { recv, ref args, .. }
            | Insn::SendForward { recv, ref args, .. }
            | Insn::InvokeSuper { recv, ref args, .. }
            | Insn::CCallWithFrame { recv, ref args, .. }
            | Insn::CCallVariadic { recv, ref args, .. }
            | Insn::InvokeBuiltin { recv, ref args, .. }
            | Insn::ArrayInclude { target: recv, elements: ref args, .. } => {
                self.assert_subtype(insn_id, recv, types::BasicObject)?;
                for &arg in args {
                    self.assert_subtype(insn_id, arg, types::BasicObject)?;
                }
                Ok(())
            }
            Insn::ArrayPackBuffer { ref elements, fmt, buffer, .. } => {
                self.assert_subtype(insn_id, fmt, types::BasicObject)?;
                self.assert_subtype(insn_id, buffer, types::BasicObject)?;
                for &element in elements {
                    self.assert_subtype(insn_id, element, types::BasicObject)?;
                }
                Ok(())
            }
            // Instructions with a Vec of Ruby objects
            Insn::InvokeBlock { ref args, .. }
            | Insn::NewArray { elements: ref args, .. }
            | Insn::ArrayHash { elements: ref args, .. }
            | Insn::ArrayMax { elements: ref args, .. } => {
                for &arg in args {
                    self.assert_subtype(insn_id, arg, types::BasicObject)?;
                }
                Ok(())
            }
            Insn::NewHash { ref elements, .. } => {
                if elements.len() % 2 != 0 {
                    return Err(ValidationError::MiscValidationError(insn_id, "NewHash elements length is not even".to_string()));
                }
                for &element in elements {
                    self.assert_subtype(insn_id, element, types::BasicObject)?;
                }
                Ok(())
            }
            Insn::StringConcat { ref strings, .. }
            | Insn::ToRegexp { values: ref strings, .. } => {
                for &string in strings {
                    self.assert_subtype(insn_id, string, types::String)?;
                }
                Ok(())
            }
            // Instructions with String operands
            Insn::StringCopy { val, .. } => self.assert_subtype(insn_id, val, types::StringExact),
            Insn::StringIntern { val, .. } => self.assert_subtype(insn_id, val, types::StringExact),
            Insn::StringAppend { recv, other, .. } => {
                self.assert_subtype(insn_id, recv, types::StringExact)?;
                self.assert_subtype(insn_id, other, types::String)
            }
            Insn::StringAppendCodepoint { recv, other, .. } => {
                self.assert_subtype(insn_id, recv, types::StringExact)?;
                self.assert_subtype(insn_id, other, types::Fixnum)
            }
            // Instructions with Array operands
            Insn::ArrayDup { val, .. } => self.assert_subtype(insn_id, val, types::ArrayExact),
            Insn::ArrayExtend { left, right, .. } => {
                // TODO(max): Do left and right need to be ArrayExact?
                self.assert_subtype(insn_id, left, types::Array)?;
                self.assert_subtype(insn_id, right, types::Array)
            }
            Insn::ArrayPush { array, .. }
            | Insn::ArrayPop { array, .. }
            | Insn::ArrayLength { array, .. } => {
                self.assert_subtype(insn_id, array, types::Array)
            }
            Insn::ArrayArefFixnum { array, index } => {
                self.assert_subtype(insn_id, array, types::Array)?;
                self.assert_subtype(insn_id, index, types::Fixnum)
            }
            // Instructions with Hash operands
            Insn::HashAref { hash, .. }
            | Insn::HashAset { hash, .. } => self.assert_subtype(insn_id, hash, types::HashExact),
            Insn::HashDup { val, .. } => self.assert_subtype(insn_id, val, types::HashExact),
            // Other
            Insn::ObjectAllocClass { class, .. } => {
                let has_leaf_allocator = unsafe { rb_zjit_class_has_default_allocator(class) } || class_has_leaf_allocator(class);
                if !has_leaf_allocator {
                    return Err(ValidationError::MiscValidationError(insn_id, "ObjectAllocClass must have leaf allocator".to_string()));
                }
                Ok(())
            }
            Insn::IsBitEqual { left, right }
            | Insn::IsBitNotEqual { left, right } => {
                if self.is_a(left, types::CInt) && self.is_a(right, types::CInt) {
                    // TODO(max): Check that int sizes match
                    Ok(())
                } else if self.is_a(left, types::CPtr) && self.is_a(right, types::CPtr) {
                    Ok(())
                } else if self.is_a(left, types::RubyValue) && self.is_a(right, types::RubyValue) {
                    Ok(())
                } else {
                    return Err(ValidationError::MiscValidationError(insn_id, "IsBitEqual can only compare CInt/CInt or RubyValue/RubyValue".to_string()));
                }
            }
            Insn::BoxBool { val }
            | Insn::IfTrue { val, .. }
            | Insn::IfFalse { val, .. } => {
                self.assert_subtype(insn_id, val, types::CBool)
            }
            Insn::BoxFixnum { val, .. } => self.assert_subtype(insn_id, val, types::CInt64),
            Insn::UnboxFixnum { val } => {
                self.assert_subtype(insn_id, val, types::Fixnum)
            }
            Insn::FixnumAdd { left, right, .. }
            | Insn::FixnumSub { left, right, .. }
            | Insn::FixnumMult { left, right, .. }
            | Insn::FixnumDiv { left, right, .. }
            | Insn::FixnumMod { left, right, .. }
            | Insn::FixnumEq { left, right }
            | Insn::FixnumNeq { left, right }
            | Insn::FixnumLt { left, right }
            | Insn::FixnumLe { left, right }
            | Insn::FixnumGt { left, right }
            | Insn::FixnumGe { left, right }
            | Insn::FixnumAnd { left, right }
            | Insn::FixnumOr { left, right }
            | Insn::FixnumXor { left, right }
            | Insn::NewRangeFixnum { low: left, high: right, .. }
            => {
                self.assert_subtype(insn_id, left, types::Fixnum)?;
                self.assert_subtype(insn_id, right, types::Fixnum)
            }
            Insn::FixnumLShift { left, right, .. }
            | Insn::FixnumRShift { left, right, .. } => {
                self.assert_subtype(insn_id, left, types::Fixnum)?;
                self.assert_subtype(insn_id, right, types::Fixnum)?;
                let Some(obj) = self.type_of(right).fixnum_value() else {
                    return Err(ValidationError::MismatchedOperandType(insn_id, right, "<a compile-time constant>".into(), "<unknown>".into()));
                };
                if obj < 0 {
                    return Err(ValidationError::MismatchedOperandType(insn_id, right, "<positive>".into(), format!("{obj}")));
                }
                if obj > 63 {
                    return Err(ValidationError::MismatchedOperandType(insn_id, right, "<less than 64>".into(), format!("{obj}")));
                }
                Ok(())
            }
            Insn::GuardBitEquals { val, expected, .. } => {
                match expected {
                    Const::Value(_) => self.assert_subtype(insn_id, val, types::RubyValue),
                    Const::CInt8(_) => self.assert_subtype(insn_id, val, types::CInt8),
                    Const::CInt16(_) => self.assert_subtype(insn_id, val, types::CInt16),
                    Const::CInt32(_) => self.assert_subtype(insn_id, val, types::CInt32),
                    Const::CInt64(_) => self.assert_subtype(insn_id, val, types::CInt64),
                    Const::CUInt8(_) => self.assert_subtype(insn_id, val, types::CUInt8),
                    Const::CUInt16(_) => self.assert_subtype(insn_id, val, types::CUInt16),
                    Const::CUInt32(_) => self.assert_subtype(insn_id, val, types::CUInt32),
                    Const::CShape(_) => self.assert_subtype(insn_id, val, types::CShape),
                    Const::CUInt64(_) => self.assert_subtype(insn_id, val, types::CUInt64),
                    Const::CBool(_) => self.assert_subtype(insn_id, val, types::CBool),
                    Const::CDouble(_) => self.assert_subtype(insn_id, val, types::CDouble),
                    Const::CPtr(_) => self.assert_subtype(insn_id, val, types::CPtr),
                }
            }
            Insn::GuardLess { left, right, .. }
            | Insn::GuardGreaterEq { left, right, .. } => {
                self.assert_subtype(insn_id, left, types::CInt64)?;
                self.assert_subtype(insn_id, right, types::CInt64)
            },
            Insn::StringGetbyte { string, index } => {
                self.assert_subtype(insn_id, string, types::String)?;
                self.assert_subtype(insn_id, index, types::CInt64)
            },
            Insn::StringSetbyteFixnum { string, index, value } => {
                self.assert_subtype(insn_id, string, types::String)?;
                self.assert_subtype(insn_id, index, types::Fixnum)?;
                self.assert_subtype(insn_id, value, types::Fixnum)
            }
            Insn::IsA { val, class } => {
                self.assert_subtype(insn_id, val, types::BasicObject)?;
                self.assert_subtype(insn_id, class, types::Class)
            }
        }
    }

    /// Check that insn types match the expected types for each instruction.
    fn validate_types(&self) -> Result<(), ValidationError> {
        for block_id in self.rpo() {
            for &insn_id in &self.blocks[block_id.0].insns {
                self.validate_insn_type(insn_id)?;
            }
        }
        Ok(())
    }

    /// Run all validation passes we have.
    pub fn validate(&self) -> Result<(), ValidationError> {
        self.validate_block_terminators_and_jumps()?;
        self.validate_definite_assignment()?;
        self.validate_insn_uniqueness()?;
        self.validate_types()?;
        Ok(())
    }
}

impl<'a> std::fmt::Display for FunctionPrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let fun = &self.fun;
        // In tests, there may not be an iseq to get location from.
        let iseq_name = if fun.iseq.is_null() {
            String::from("<manual>")
        } else {
            iseq_get_location(fun.iseq, 0)
        };

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
                if !self.display_snapshot_and_tp_patchpoints &&
                    matches!(insn, Insn::Snapshot {..} | Insn::PatchPoint { invariant: Invariant::NoTracePoint, .. }) {
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
                writeln!(f, "{}", insn.print(&self.ptr_map, Some(fun.iseq)))?;
            }
        }
        Ok(())
    }
}

struct HtmlEncoder<'a, 'b> {
    formatter: &'a mut std::fmt::Formatter<'b>,
}

impl<'a, 'b> std::fmt::Write for HtmlEncoder<'a, 'b> {
    fn write_str(&mut self, s: &str) -> std::fmt::Result {
        for ch in s.chars() {
            match ch {
                '<' => self.formatter.write_str("&lt;")?,
                '>' => self.formatter.write_str("&gt;")?,
                '&' => self.formatter.write_str("&amp;")?,
                '"' => self.formatter.write_str("&quot;")?,
                '\'' => self.formatter.write_str("&#39;")?,
                _ => self.formatter.write_char(ch)?,
            }
        }
        Ok(())
    }
}

impl<'a> std::fmt::Display for FunctionGraphvizPrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        macro_rules! write_encoded {
            ($f:ident, $($arg:tt)*) => {
                HtmlEncoder { formatter: $f }.write_fmt(format_args!($($arg)*))
            };
        }
        use std::fmt::Write;
        let fun = &self.fun;
        let iseq_name = iseq_get_location(fun.iseq, 0);
        write!(f, "digraph G {{ # ")?;
        write_encoded!(f, "{iseq_name}")?;
        writeln!(f)?;
        writeln!(f, "node [shape=plaintext];")?;
        writeln!(f, "mode=hier; overlap=false; splines=true;")?;
        for block_id in fun.rpo() {
            writeln!(f, r#"  {block_id} [label=<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0">"#)?;
            write!(f, r#"<TR><TD ALIGN="LEFT" PORT="params" BGCOLOR="gray">{block_id}("#)?;
            if !fun.blocks[block_id.0].params.is_empty() {
                let mut sep = "";
                for param in &fun.blocks[block_id.0].params {
                    write_encoded!(f, "{sep}{param}")?;
                    let insn_type = fun.type_of(*param);
                    if !insn_type.is_subtype(types::Empty) {
                        write_encoded!(f, ":{}", insn_type.print(&self.ptr_map))?;
                    }
                    sep = ", ";
                }
            }
            let mut edges = vec![];
            writeln!(f, ")&nbsp;</TD></TR>")?;
            for insn_id in &fun.blocks[block_id.0].insns {
                let insn_id = fun.union_find.borrow().find_const(*insn_id);
                let insn = fun.find(insn_id);
                if matches!(insn, Insn::Snapshot {..}) {
                    continue;
                }
                write!(f, r#"<TR><TD ALIGN="left" PORT="{insn_id}">"#)?;
                if insn.has_output() {
                    let insn_type = fun.type_of(insn_id);
                    if insn_type.is_subtype(types::Empty) {
                        write_encoded!(f, "{insn_id} = ")?;
                    } else {
                        write_encoded!(f, "{insn_id}:{} = ", insn_type.print(&self.ptr_map))?;
                    }
                }
                if let Insn::Jump(ref target) | Insn::IfTrue { ref target, .. } | Insn::IfFalse { ref target, .. } = insn {
                    edges.push((insn_id, target.target));
                }
                write_encoded!(f, "{}", insn.print(&self.ptr_map, Some(fun.iseq)))?;
                writeln!(f, "&nbsp;</TD></TR>")?;
            }
            writeln!(f, "</TABLE>>];")?;
            for (src, dst) in edges {
                writeln!(f, "  {block_id}:{src} -> {dst}:params:n;")?;
            }
        }
        writeln!(f, "}}")
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
    /// Return itself without locals. Useful for side-exiting without spilling locals.
    fn without_locals(&self) -> Self {
        let mut state = self.clone();
        state.locals.clear();
        state
    }

    /// Return itself without stack. Used by leaf calls with GC to reset SP to the base pointer.
    pub fn without_stack(&self) -> Self {
        let mut state = self.clone();
        state.stack.clear();
        state
    }
}

/// Print adaptor for [`FrameState`]. See [`PtrPrintMap`].
pub struct FrameStatePrinter<'a> {
    inner: &'a FrameState,
    ptr_map: &'a PtrPrintMap,
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
    pub fn stack(&self) -> Iter<'_, InsnId> {
        self.stack.iter()
    }

    /// Iterate over all local variables
    pub fn locals(&self) -> Iter<'_, InsnId> {
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

    fn stack_pop_n(&mut self, count: usize) -> Result<Vec<InsnId>, ParseError> {
        // Check if we have enough values on the stack
        let stack_len = self.stack.len();
        if stack_len < count {
            return Err(ParseError::StackUnderflow(self.clone()));
        }

        Ok(self.stack.split_off(stack_len - count))
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
        args.extend(self.locals.iter().chain(self.stack.iter()).copied());
        args
    }

    /// Get the opcode for the current instruction
    pub fn get_opcode(&self) -> i32 {
        unsafe { rb_iseq_opcode_at_pc(self.iseq, self.pc) }
    }

    pub fn print<'a>(&'a self, ptr_map: &'a PtrPrintMap) -> FrameStatePrinter<'a> {
        FrameStatePrinter { inner: self, ptr_map }
    }
}

impl Display for FrameStatePrinter<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let inner = self.inner;
        write!(f, "FrameState {{ pc: {:?}, stack: ", self.ptr_map.map_ptr(inner.pc))?;
        write_vec(f, &inner.stack)?;
        write!(f, ", locals: [")?;
        for (idx, local) in inner.locals.iter().enumerate() {
            let name: ID = unsafe { rb_zjit_local_id(inner.iseq, idx.try_into().unwrap()) };
            let name = name.contents_lossy();
            if idx > 0 { write!(f, ", ")?; }
            write!(f, "{name}={local}")?;
        }
        write!(f, "] }}")
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

/// List of insn_idx that starts a JIT entry block
pub fn jit_entry_insns(iseq: IseqPtr) -> Vec<u32> {
    // TODO(alan): Make an iterator type for this instead of copying all of the opt_table each call
    let params = unsafe { iseq.params() };
    let opt_num = params.opt_num;
    if opt_num > 0 {
        let mut result = vec![];

        let opt_table = params.opt_table; // `opt_num + 1` entries
        for opt_idx in 0..=opt_num as isize {
            let insn_idx = unsafe { opt_table.offset(opt_idx).read().as_u32() };
            result.push(insn_idx);
        }
        result
    } else {
        vec![0]
    }
}

struct BytecodeInfo {
    jump_targets: Vec<u32>,
    has_blockiseq: bool,
}

fn compute_bytecode_info(iseq: *const rb_iseq_t, opt_table: &[u32]) -> BytecodeInfo {
    let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
    let mut insn_idx = 0;
    let mut jump_targets: HashSet<u32> = opt_table.iter().copied().collect();
    let mut has_blockiseq = false;
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
            YARVINSN_send | YARVINSN_invokesuper => {
                let blockiseq: IseqPtr = get_arg(pc, 1).as_iseq();
                if !blockiseq.is_null() {
                    has_blockiseq = true;
                }
            }
            _ => {}
        }
    }
    let mut result = jump_targets.into_iter().collect::<Vec<_>>();
    result.sort();
    BytecodeInfo { jump_targets: result, has_blockiseq }
}

#[derive(Debug, PartialEq, Clone, Copy)]
pub enum CallType {
    Splat,
    Kwarg,
    Tailcall,
}

#[derive(Clone, Debug, PartialEq)]
pub enum ParseError {
    StackUnderflow(FrameState),
    MalformedIseq(u32), // insn_idx into iseq_encoded
    Validation(ValidationError),
    NotAllowed,
}

/// Return the number of locals in the current ISEQ (includes parameters)
fn num_locals(iseq: *const rb_iseq_t) -> usize {
    (unsafe { get_iseq_body_local_table_size(iseq) }).to_usize()
}

/// If we can't handle the type of send (yet), bail out.
fn unhandled_call_type(flags: u32) -> Result<(), CallType> {
    if (flags & VM_CALL_TAILCALL) != 0 { return Err(CallType::Tailcall); }
    Ok(())
}

/// If a given call to a c func uses overly complex arguments, then we won't specialize.
fn unspecializable_c_call_type(flags: u32) -> bool {
    ((flags & VM_CALL_KWARG) != 0) ||
    unspecializable_call_type(flags)
}

/// If a given call uses overly complex arguments, then we won't specialize.
fn unspecializable_call_type(flags: u32) -> bool {
    ((flags & VM_CALL_ARGS_SPLAT) != 0) ||
    ((flags & VM_CALL_KW_SPLAT) != 0) ||
    ((flags & VM_CALL_ARGS_BLOCKARG) != 0)
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
        let entry = self.types.entry(iseq_insn_idx).or_default();
        // operand_types is always going to be <= stack size (otherwise it would have an underflow
        // at run-time) so use that to drive iteration.
        for (idx, insn_type_distribution) in operand_types.iter().rev().enumerate() {
            let insn = state.stack_topn(idx).expect("Unexpected stack underflow in profiling");
            entry.push((insn, TypeDistributionSummary::new(insn_type_distribution)))
        }
    }

    /// Map the interpreter-recorded types of self onto the HIR self
    fn profile_self(&mut self, state: &FrameState, self_param: InsnId) {
        let iseq_insn_idx = state.insn_idx;
        let Some(operand_types) = self.payload.profile.get_operand_types(iseq_insn_idx) else { return };
        let entry = self.types.entry(iseq_insn_idx).or_default();
        if operand_types.is_empty() {
           return;
        }
        let self_type_distribution = &operand_types[0];
        entry.push((self_param, TypeDistributionSummary::new(self_type_distribution)))
    }
}

fn invalidates_locals(opcode: u32, operands: *const VALUE) -> bool {
    match opcode {
        // Control-flow is non-leaf in the interpreter because it can execute arbitrary code on
        // interrupt. But in the JIT, we side-exit if there is a pending interrupt.
        YARVINSN_jump
        | YARVINSN_branchunless
        | YARVINSN_branchif
        | YARVINSN_branchnil
        | YARVINSN_leave => false,
        // TODO(max): Read the invokebuiltin target from operands and determine if it's leaf
        _ => unsafe { !rb_zjit_insn_leaf(opcode as i32, operands) }
    }
}

/// The index of the self parameter in the HIR function
pub const SELF_PARAM_IDX: usize = 0;

/// Compile ISEQ into High-level IR
pub fn iseq_to_hir(iseq: *const rb_iseq_t) -> Result<Function, ParseError> {
    if !ZJITState::can_compile_iseq(iseq) {
        return Err(ParseError::NotAllowed);
    }
    let payload = get_or_create_iseq_payload(iseq);
    let mut profiles = ProfileOracle::new(payload);
    let mut fun = Function::new(iseq);

    // Compute a map of PC->Block by finding jump targets
    let jit_entry_insns = jit_entry_insns(iseq);
    let BytecodeInfo { jump_targets, has_blockiseq } = compute_bytecode_info(iseq, &jit_entry_insns);

    // Make all empty basic blocks. The ordering of the BBs matters for getting fallthrough jumps
    // in good places, but it's not necessary for correctness. TODO: Higher quality scheduling during lowering.
    let mut insn_idx_to_block = HashMap::new();
    // Make blocks for optionals first, and put them right next to their JIT entrypoint
    for insn_idx in jit_entry_insns.iter().copied() {
        let jit_entry_block = fun.new_block(insn_idx);
        fun.jit_entry_blocks.push(jit_entry_block);
        insn_idx_to_block.entry(insn_idx).or_insert_with(|| fun.new_block(insn_idx));
    }
    // Make blocks for the rest of the jump targets
    for insn_idx in jump_targets {
        insn_idx_to_block.entry(insn_idx).or_insert_with(|| fun.new_block(insn_idx));
    }
    // Done, drop `mut`.
    let insn_idx_to_block = insn_idx_to_block;

    // Compile an entry_block for the interpreter
    compile_entry_block(&mut fun, jit_entry_insns.as_slice(), &insn_idx_to_block);

    // Compile all JIT-to-JIT entry blocks
    for (jit_entry_idx, insn_idx) in jit_entry_insns.iter().enumerate() {
        let target_block = insn_idx_to_block.get(insn_idx)
            .copied()
            .expect("we make a block for each jump target and \
                     each entry in the ISEQ opt_table is a jump target");
        compile_jit_entry_block(&mut fun, jit_entry_idx, target_block);
    }

    // Check if the EP is escaped for the ISEQ from the beginning. We give up
    // optimizing locals in that case because they're shared with other frames.
    let ep_escaped = iseq_escapes_ep(iseq);

    // Iteratively fill out basic blocks using a queue.
    // TODO(max): Basic block arguments at edges
    let mut queue = VecDeque::new();
    for &insn_idx in jit_entry_insns.iter() {
        queue.push_back((FrameState::new(iseq), insn_idx_to_block[&insn_idx], /*insn_idx=*/insn_idx, /*local_inval=*/false));
    }

    // Keep compiling blocks until the queue becomes empty
    let mut visited = HashSet::new();
    let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
    while let Some((incoming_state, block, mut insn_idx, mut local_inval)) = queue.pop_front() {
        // Compile each block only once
        if visited.contains(&block) { continue; }
        visited.insert(block);

        // Load basic block params first
        let self_param = fun.push_insn(block, Insn::Param);
        let mut state = {
            let mut result = FrameState::new(iseq);
            let local_size = if jit_entry_insns.contains(&insn_idx) { num_locals(iseq) } else { incoming_state.locals.len() };
            for _ in 0..local_size {
                result.locals.push(fun.push_insn(block, Insn::Param));
            }
            for _ in incoming_state.stack {
                result.stack.push(fun.push_insn(block, Insn::Param));
            }
            result
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

            // try_into() call below is unfortunate. Maybe pick i32 instead of usize for opcodes.
            let opcode: u32 = unsafe { rb_iseq_opcode_at_pc(iseq, pc) }
                .try_into()
                .unwrap();

            // If TracePoint has been enabled after we have collected profiles, we'll see
            // trace_getinstancevariable in the ISEQ. We have to treat it like getinstancevariable
            // for profiling purposes: there is no operand on the stack to look up; we have
            // profiled cfp->self.
            if opcode == YARVINSN_getinstancevariable || opcode == YARVINSN_trace_getinstancevariable {
                profiles.profile_self(&exit_state, self_param);
            } else if opcode == YARVINSN_setinstancevariable || opcode == YARVINSN_trace_setinstancevariable {
                profiles.profile_self(&exit_state, self_param);
            } else if opcode == YARVINSN_definedivar || opcode == YARVINSN_trace_definedivar {
                profiles.profile_self(&exit_state, self_param);
            } else if opcode == YARVINSN_invokeblock || opcode == YARVINSN_trace_invokeblock {
                if get_option!(stats) {
                    let iseq_insn_idx = exit_state.insn_idx;
                    if let Some(operand_types) = profiles.payload.profile.get_operand_types(iseq_insn_idx) {
                        if let [self_type_distribution] = &operand_types[..] {
                            let summary = TypeDistributionSummary::new(&self_type_distribution);
                            if summary.is_monomorphic() {
                                let obj = summary.bucket(0).class();
                                if unsafe { rb_IMEMO_TYPE_P(obj, imemo_iseq) == 1 } {
                                    fun.push_insn(block, Insn::IncrCounter(Counter::invokeblock_handler_monomorphic_iseq));
                                } else if unsafe { rb_IMEMO_TYPE_P(obj, imemo_ifunc) == 1 } {
                                    fun.push_insn(block, Insn::IncrCounter(Counter::invokeblock_handler_monomorphic_ifunc));
                                } else {
                                    fun.push_insn(block, Insn::IncrCounter(Counter::invokeblock_handler_monomorphic_other));
                                }
                            } else if summary.is_skewed_polymorphic() || summary.is_polymorphic() {
                                fun.push_insn(block, Insn::IncrCounter(Counter::invokeblock_handler_polymorphic));
                            } else if summary.is_skewed_megamorphic() || summary.is_megamorphic() {
                                fun.push_insn(block, Insn::IncrCounter(Counter::invokeblock_handler_megamorphic));
                            } else {
                                fun.push_insn(block, Insn::IncrCounter(Counter::invokeblock_handler_no_profiles));
                            }
                        } else {
                            fun.push_insn(block, Insn::IncrCounter(Counter::invokeblock_handler_no_profiles));
                        }
                    }
                }
            } else {
                profiles.profile_stack(&exit_state);
            }

            // Flag a future getlocal/setlocal to add a patch point if this instruction is not leaf.
            if invalidates_locals(opcode, unsafe { pc.offset(1) }) {
                local_inval = true;
            }

            // We add NoTracePoint patch points before every instruction that could be affected by TracePoint.
            // This ensures that if TracePoint is enabled, we can exit the generated code as fast as possible.
            unsafe extern "C" {
                fn rb_iseq_event_flags(iseq: IseqPtr, pos: usize) -> rb_event_flag_t;
            }
            let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state.clone() });
            if unsafe { rb_iseq_event_flags(iseq, insn_idx as usize) } != 0 {
                fun.push_insn(block, Insn::PatchPoint { invariant: Invariant::NoTracePoint, state: exit_id });
            }

            // Increment zjit_insn_count for each YARV instruction if --zjit-stats is enabled.
            if get_option!(stats) {
                fun.push_insn(block, Insn::IncrCounter(Counter::zjit_insn_count));
            }
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
                    let insn_id = fun.push_insn(block, Insn::StringCopy { val, chilled: false, state: exit_id });
                    state.stack_push(insn_id);
                }
                YARVINSN_putchilledstring => {
                    let val = fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) });
                    let insn_id = fun.push_insn(block, Insn::StringCopy { val, chilled: true, state: exit_id });
                    state.stack_push(insn_id);
                }
                YARVINSN_putself => { state.stack_push(self_param); }
                YARVINSN_intern => {
                    let val = state.stack_pop()?;
                    let insn_id = fun.push_insn(block, Insn::StringIntern { val, state: exit_id });
                    state.stack_push(insn_id);
                }
                YARVINSN_concatstrings => {
                    let count = get_arg(pc, 0).as_u32();
                    let strings = state.stack_pop_n(count as usize)?;
                    let insn_id = fun.push_insn(block, Insn::StringConcat { strings, state: exit_id });
                    state.stack_push(insn_id);
                }
                YARVINSN_toregexp => {
                    // First arg contains the options (multiline, extended, ignorecase) used to create the regexp
                    let opt = get_arg(pc, 0).as_usize();
                    let count = get_arg(pc, 1).as_usize();
                    let values = state.stack_pop_n(count)?;
                    let insn_id = fun.push_insn(block, Insn::ToRegexp { opt, values, state: exit_id });
                    state.stack_push(insn_id);
                }
                YARVINSN_newarray => {
                    let count = get_arg(pc, 0).as_usize();
                    let elements = state.stack_pop_n(count)?;
                    state.stack_push(fun.push_insn(block, Insn::NewArray { elements, state: exit_id }));
                }
                YARVINSN_opt_newarray_send => {
                    let count = get_arg(pc, 0).as_usize();
                    let method = get_arg(pc, 1).as_u32();
                    let (bop, insn) = match method {
                        VM_OPT_NEWARRAY_SEND_MAX => {
                            let elements = state.stack_pop_n(count)?;
                            (BOP_MAX, Insn::ArrayMax { elements, state: exit_id })
                        }
                        VM_OPT_NEWARRAY_SEND_HASH => {
                            let elements = state.stack_pop_n(count)?;
                            (BOP_HASH, Insn::ArrayHash { elements, state: exit_id })
                        }
                        VM_OPT_NEWARRAY_SEND_INCLUDE_P => {
                            let target = state.stack_pop()?;
                            let elements = state.stack_pop_n(count - 1)?;
                            (BOP_INCLUDE_P, Insn::ArrayInclude { elements, target, state: exit_id })
                        }
                        VM_OPT_NEWARRAY_SEND_PACK_BUFFER => {
                            let buffer = state.stack_pop()?;
                            let fmt = state.stack_pop()?;
                            let elements = state.stack_pop_n(count - 2)?;
                            (BOP_PACK, Insn::ArrayPackBuffer { elements, fmt, buffer, state: exit_id })
                        }
                        _ => {
                            // Unknown opcode; side-exit into the interpreter
                            fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnhandledNewarraySend(method) });
                            break;  // End the block
                        }
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
                    let insn_id = fun.push_insn(block, Insn::ArrayDup { val, state: exit_id });
                    state.stack_push(insn_id);
                }
                YARVINSN_opt_duparray_send => {
                    let ary = get_arg(pc, 0);
                    let method_id = get_arg(pc, 1).as_u64();
                    let argc = get_arg(pc, 2).as_usize();
                    if argc != 1 {
                        break;
                    }
                    let target = state.stack_pop()?;
                    let bop = match method_id {
                        x if x == ID!(include_p).0 => BOP_INCLUDE_P,
                        _ => {
                            fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnhandledDuparraySend(method_id) });
                            break;
                        },
                    };
                    if !unsafe { rb_BASIC_OP_UNREDEFINED_P(bop, ARRAY_REDEFINED_OP_FLAG) } {
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::PatchPoint(Invariant::BOPRedefined { klass: ARRAY_REDEFINED_OP_FLAG, bop }) });
                        break;
                    }
                    fun.push_insn(block, Insn::PatchPoint { invariant: Invariant::BOPRedefined { klass: ARRAY_REDEFINED_OP_FLAG, bop }, state: exit_id });
                    let insn_id = fun.push_insn(block, Insn::DupArrayInclude { ary, target, state: exit_id });
                    state.stack_push(insn_id);
                }
                YARVINSN_newhash => {
                    let count = get_arg(pc, 0).as_usize();
                    assert!(count % 2 == 0, "newhash count should be even");
                    let mut elements = vec![];
                    for _ in 0..(count/2) {
                        let value = state.stack_pop()?;
                        let key = state.stack_pop()?;
                        elements.push(value);
                        elements.push(key);
                    }
                    elements.reverse();
                    state.stack_push(fun.push_insn(block, Insn::NewHash { elements, state: exit_id }));
                }
                YARVINSN_duphash => {
                    let val = fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) });
                    let insn_id = fun.push_insn(block, Insn::HashDup { val, state: exit_id });
                    state.stack_push(insn_id);
                }
                YARVINSN_splatarray => {
                    let flag = get_arg(pc, 0);
                    let result_must_be_mutable = flag.test();
                    let val = state.stack_pop()?;
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
                    let right_array = fun.push_insn(block, Insn::ToArray { val: right, state: exit_id });
                    fun.push_insn(block, Insn::ArrayExtend { left, right: right_array, state: exit_id });
                    state.stack_push(left);
                }
                YARVINSN_pushtoarray => {
                    let count = get_arg(pc, 0).as_usize();
                    let vals = state.stack_pop_n(count)?;
                    let array = state.stack_pop()?;
                    for val in vals.into_iter() {
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
                    state.stack_push(fun.push_insn(block, Insn::Defined { op_type, obj, pushval, v, state: exit_id }));
                }
                YARVINSN_definedivar => {
                    // (ID id, IVC ic, VALUE pushval)
                    let id = ID(get_arg(pc, 0).as_u64());
                    let pushval = get_arg(pc, 2);
                    state.stack_push(fun.push_insn(block, Insn::DefinedIvar { self_val: self_param, id, pushval, state: exit_id }));
                }
                YARVINSN_checkkeyword => {
                    // When a keyword is unspecified past index 32, a hash will be used instead.
                    // This can only happen in iseqs taking more than 32 keywords.
                    // In this case, we side exit to the interpreter.
                    if unsafe {(*rb_get_iseq_body_param_keyword(iseq)).num >= VM_KW_SPECIFIED_BITS_MAX.try_into().unwrap()} {
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::TooManyKeywordParameters });
                        break;
                    }
                    let ep_offset = get_arg(pc, 0).as_u32();
                    let index = get_arg(pc, 1).as_u64();
                    let index: u8 = index.try_into().map_err(|_| ParseError::MalformedIseq(insn_idx))?;
                    let val = fun.push_insn(block, Insn::GetLocal { ep_offset, level: 0, use_sp: false, rest_param: false });
                    state.stack_push(fun.push_insn(block, Insn::FixnumBitCheck { val, index }));
                }
                YARVINSN_opt_getconstant_path => {
                    let ic = get_arg(pc, 0).as_ptr();
                    let snapshot = fun.push_insn(block, Insn::Snapshot { state: exit_state });
                    state.stack_push(fun.push_insn(block, Insn::GetConstantPath { ic, state: snapshot }));
                }
                YARVINSN_branchunless => {
                    fun.push_insn(block, Insn::CheckInterrupts { state: exit_id });
                    let offset = get_arg(pc, 0).as_i64();
                    let val = state.stack_pop()?;
                    let test_id = fun.push_insn(block, Insn::Test { val });
                    let target_idx = insn_idx_at_offset(insn_idx, offset);
                    let target = insn_idx_to_block[&target_idx];
                    let _branch_id = fun.push_insn(block, Insn::IfFalse {
                        val: test_id,
                        target: BranchEdge { target, args: state.as_args(self_param) }
                    });
                    queue.push_back((state.clone(), target, target_idx, local_inval));
                }
                YARVINSN_branchif => {
                    fun.push_insn(block, Insn::CheckInterrupts { state: exit_id });
                    let offset = get_arg(pc, 0).as_i64();
                    let val = state.stack_pop()?;
                    let test_id = fun.push_insn(block, Insn::Test { val });
                    let target_idx = insn_idx_at_offset(insn_idx, offset);
                    let target = insn_idx_to_block[&target_idx];
                    let _branch_id = fun.push_insn(block, Insn::IfTrue {
                        val: test_id,
                        target: BranchEdge { target, args: state.as_args(self_param) }
                    });
                    queue.push_back((state.clone(), target, target_idx, local_inval));
                }
                YARVINSN_branchnil => {
                    fun.push_insn(block, Insn::CheckInterrupts { state: exit_id });
                    let offset = get_arg(pc, 0).as_i64();
                    let val = state.stack_pop()?;
                    let test_id = fun.push_insn(block, Insn::IsNil { val });
                    let target_idx = insn_idx_at_offset(insn_idx, offset);
                    let target = insn_idx_to_block[&target_idx];
                    let _branch_id = fun.push_insn(block, Insn::IfTrue {
                        val: test_id,
                        target: BranchEdge { target, args: state.as_args(self_param) }
                    });
                    queue.push_back((state.clone(), target, target_idx, local_inval));
                }
                YARVINSN_opt_case_dispatch => {
                    // TODO: Some keys are visible at compile time, so in the future we can
                    // compile jump targets for certain cases
                    // Pop the key from the stack and fallback to the === branches for now
                    state.stack_pop()?;
                }
                YARVINSN_opt_new => {
                    let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                    let dst = get_arg(pc, 1).as_i64();

                    // Check if #new resolves to rb_class_new_instance_pass_kw.
                    // TODO: Guard on a profiled class and add a patch point for #new redefinition
                    let argc = unsafe { vm_ci_argc((*cd).ci) } as usize;
                    let val = state.stack_topn(argc)?;
                    let test_id = fun.push_insn(block, Insn::IsMethodCfunc { val, cd, cfunc: rb_class_new_instance_pass_kw as *const u8, state: exit_id });

                    // Jump to the fallback block if it's not the expected function.
                    // Skip CheckInterrupts since the #new call will do it very soon anyway.
                    let target_idx = insn_idx_at_offset(insn_idx, dst);
                    let target = insn_idx_to_block[&target_idx];
                    let _branch_id = fun.push_insn(block, Insn::IfFalse {
                        val: test_id,
                        target: BranchEdge { target, args: state.as_args(self_param) }
                    });
                    queue.push_back((state.clone(), target, target_idx, local_inval));

                    // Move on to the fast path
                    let insn_id = fun.push_insn(block, Insn::ObjectAlloc { val, state: exit_id });
                    state.stack_setn(argc, insn_id);
                    state.stack_setn(argc + 1, insn_id);
                }
                YARVINSN_jump => {
                    let offset = get_arg(pc, 0).as_i64();
                    fun.push_insn(block, Insn::CheckInterrupts { state: exit_id });
                    let target_idx = insn_idx_at_offset(insn_idx, offset);
                    let target = insn_idx_to_block[&target_idx];
                    let _branch_id = fun.push_insn(block, Insn::Jump(
                        BranchEdge { target, args: state.as_args(self_param) }
                    ));
                    queue.push_back((state.clone(), target, target_idx, local_inval));
                    break;  // Don't enqueue the next block as a successor
                }
                YARVINSN_getlocal_WC_0 => {
                    let ep_offset = get_arg(pc, 0).as_u32();
                    if !local_inval {
                        // The FrameState is the source of truth for locals until invalidated.
                        // In case of JIT-to-JIT send locals might never end up in EP memory.
                        let val = state.getlocal(ep_offset);
                        state.stack_push(val);
                    } else if ep_escaped || has_blockiseq { // TODO: figure out how to drop has_blockiseq here
                        // Read the local using EP
                        let val = fun.push_insn(block, Insn::GetLocal { ep_offset, level: 0, use_sp: false, rest_param: false });
                        state.setlocal(ep_offset, val); // remember the result to spill on side-exits
                        state.stack_push(val);
                    } else {
                        assert!(local_inval); // if check above
                        // There has been some non-leaf call since JIT entry or the last patch point,
                        // so add a patch point to make sure locals have not been escaped.
                        let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state.without_locals() }); // skip spilling locals
                        fun.push_insn(block, Insn::PatchPoint { invariant: Invariant::NoEPEscape(iseq), state: exit_id });
                        local_inval = false;

                        // Read the local from FrameState
                        let val = state.getlocal(ep_offset);
                        state.stack_push(val);
                    }
                }
                YARVINSN_setlocal_WC_0 => {
                    let ep_offset = get_arg(pc, 0).as_u32();
                    let val = state.stack_pop()?;
                    if ep_escaped || has_blockiseq { // TODO: figure out how to drop has_blockiseq here
                        // Write the local using EP
                        fun.push_insn(block, Insn::SetLocal { val, ep_offset, level: 0 });
                    } else if local_inval {
                        // If there has been any non-leaf call since JIT entry or the last patch point,
                        // add a patch point to make sure locals have not been escaped.
                        let exit_id = fun.push_insn(block, Insn::Snapshot { state: exit_state.without_locals() }); // skip spilling locals
                        fun.push_insn(block, Insn::PatchPoint { invariant: Invariant::NoEPEscape(iseq), state: exit_id });
                        local_inval = false;
                    }
                    // Write the local into FrameState
                    state.setlocal(ep_offset, val);
                }
                YARVINSN_getlocal_WC_1 => {
                    let ep_offset = get_arg(pc, 0).as_u32();
                    state.stack_push(fun.push_insn(block, Insn::GetLocal { ep_offset, level: 1, use_sp: false, rest_param: false }));
                }
                YARVINSN_setlocal_WC_1 => {
                    let ep_offset = get_arg(pc, 0).as_u32();
                    fun.push_insn(block, Insn::SetLocal { val: state.stack_pop()?, ep_offset, level: 1 });
                }
                YARVINSN_getlocal => {
                    let ep_offset = get_arg(pc, 0).as_u32();
                    let level = get_arg(pc, 1).as_u32();
                    state.stack_push(fun.push_insn(block, Insn::GetLocal { ep_offset, level, use_sp: false, rest_param: false }));
                }
                YARVINSN_setlocal => {
                    let ep_offset = get_arg(pc, 0).as_u32();
                    let level = get_arg(pc, 1).as_u32();
                    fun.push_insn(block, Insn::SetLocal { val: state.stack_pop()?, ep_offset, level });
                }
                YARVINSN_getblockparamproxy => {
                    let level = get_arg(pc, 1).as_u32();
                    fun.push_insn(block, Insn::GuardBlockParamProxy { level, state: exit_id });
                    // TODO(Shopify/ruby#753): GC root, so we should be able to avoid unnecessary GC tracing
                    state.stack_push(fun.push_insn(block, Insn::Const { val: Const::Value(unsafe { rb_block_param_proxy }) }));
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
                YARVINSN_opt_neq => {
                    // NB: opt_neq has two cd; get_arg(0) is for eq and get_arg(1) is for neq
                    let cd: *const rb_call_data = get_arg(pc, 1).as_ptr();
                    let call_info = unsafe { rb_get_call_data_ci(cd) };
                    let flags = unsafe { rb_vm_ci_flag(call_info) };
                    if let Err(call_type) = unhandled_call_type(flags) {
                        // Can't handle the call type; side-exit into the interpreter
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnhandledCallType(call_type) });
                        break;  // End the block
                    }
                    let argc = unsafe { vm_ci_argc((*cd).ci) };

                    let args = state.stack_pop_n(argc as usize)?;
                    let recv = state.stack_pop()?;
                    let send = fun.push_insn(block, Insn::SendWithoutBlock { recv, cd, args, state: exit_id, reason: Uncategorized(opcode) });
                    state.stack_push(send);
                }
                YARVINSN_opt_hash_freeze => {
                    let klass = HASH_REDEFINED_OP_FLAG;
                    let bop = BOP_FREEZE;
                    if unsafe { rb_BASIC_OP_UNREDEFINED_P(bop, klass) } {
                        fun.push_insn(block, Insn::PatchPoint { invariant: Invariant::BOPRedefined { klass, bop }, state: exit_id });
                        let recv = fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) });
                        state.stack_push(recv);
                    } else {
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::PatchPoint(Invariant::BOPRedefined { klass, bop }) });
                        break;  // End the block
                    }
                }
                YARVINSN_opt_ary_freeze => {
                    let klass = ARRAY_REDEFINED_OP_FLAG;
                    let bop = BOP_FREEZE;
                    if unsafe { rb_BASIC_OP_UNREDEFINED_P(bop, klass) } {
                        fun.push_insn(block, Insn::PatchPoint { invariant: Invariant::BOPRedefined { klass, bop }, state: exit_id });
                        let recv = fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) });
                        state.stack_push(recv);
                    } else {
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::PatchPoint(Invariant::BOPRedefined { klass, bop }) });
                        break;  // End the block
                    }
                }
                YARVINSN_opt_str_freeze => {
                    let klass = STRING_REDEFINED_OP_FLAG;
                    let bop = BOP_FREEZE;
                    if unsafe { rb_BASIC_OP_UNREDEFINED_P(bop, klass) } {
                        fun.push_insn(block, Insn::PatchPoint { invariant: Invariant::BOPRedefined { klass, bop }, state: exit_id });
                        let recv = fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) });
                        state.stack_push(recv);
                    } else {
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::PatchPoint(Invariant::BOPRedefined { klass, bop }) });
                        break;  // End the block
                    }
                }
                YARVINSN_opt_str_uminus => {
                    let klass = STRING_REDEFINED_OP_FLAG;
                    let bop = BOP_UMINUS;
                    if unsafe { rb_BASIC_OP_UNREDEFINED_P(bop, klass) } {
                        fun.push_insn(block, Insn::PatchPoint { invariant: Invariant::BOPRedefined { klass, bop }, state: exit_id });
                        let recv = fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) });
                        state.stack_push(recv);
                    } else {
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::PatchPoint(Invariant::BOPRedefined { klass, bop }) });
                        break;  // End the block
                    }
                }
                YARVINSN_leave => {
                    fun.push_insn(block, Insn::CheckInterrupts { state: exit_id });
                    fun.push_insn(block, Insn::Return { val: state.stack_pop()? });
                    break;  // Don't enqueue the next block as a successor
                }
                YARVINSN_throw => {
                    fun.push_insn(block, Insn::Throw { throw_state: get_arg(pc, 0).as_u32(), val: state.stack_pop()?, state: exit_id });
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
                    let flags = unsafe { rb_vm_ci_flag(call_info) };
                    if let Err(call_type) = unhandled_call_type(flags) {
                        // Can't handle tailcall; side-exit into the interpreter
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnhandledCallType(call_type) });
                        break;  // End the block
                    }
                    let argc = unsafe { vm_ci_argc((*cd).ci) };

                    let args = state.stack_pop_n(argc as usize)?;
                    let recv = state.stack_pop()?;
                    let send = fun.push_insn(block, Insn::SendWithoutBlock { recv, cd, args, state: exit_id, reason: Uncategorized(opcode) });
                    state.stack_push(send);
                }
                YARVINSN_send => {
                    let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                    let blockiseq: IseqPtr = get_arg(pc, 1).as_iseq();
                    let call_info = unsafe { rb_get_call_data_ci(cd) };
                    let flags = unsafe { rb_vm_ci_flag(call_info) };
                    if let Err(call_type) = unhandled_call_type(flags) {
                        // Can't handle tailcall; side-exit into the interpreter
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnhandledCallType(call_type) });
                        break;  // End the block
                    }
                    let argc = unsafe { vm_ci_argc((*cd).ci) };
                    let block_arg = (flags & VM_CALL_ARGS_BLOCKARG) != 0;

                    let args = state.stack_pop_n(argc as usize + usize::from(block_arg))?;
                    let recv = state.stack_pop()?;
                    let send = fun.push_insn(block, Insn::Send { recv, cd, blockiseq, args, state: exit_id, reason: Uncategorized(opcode) });
                    state.stack_push(send);

                    if !blockiseq.is_null() {
                        // Reload locals that may have been modified by the blockiseq.
                        // TODO: Avoid reloading locals that are not referenced by the blockiseq
                        // or not used after this. Max thinks we could eventually DCE them.
                        for local_idx in 0..state.locals.len() {
                            let ep_offset = local_idx_to_ep_offset(iseq, local_idx) as u32;
                            // TODO: We could use `use_sp: true` with PatchPoint
                            let val = fun.push_insn(block, Insn::GetLocal { ep_offset, level: 0, use_sp: false, rest_param: false });
                            state.setlocal(ep_offset, val);
                        }
                    }
                }
                YARVINSN_sendforward => {
                    let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                    let blockiseq: IseqPtr = get_arg(pc, 1).as_iseq();
                    let call_info = unsafe { rb_get_call_data_ci(cd) };
                    let flags = unsafe { rb_vm_ci_flag(call_info) };
                    let forwarding = (flags & VM_CALL_FORWARDING) != 0;
                    if let Err(call_type) = unhandled_call_type(flags) {
                        // Can't handle the call type; side-exit into the interpreter
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnhandledCallType(call_type) });
                        break;  // End the block
                    }
                    let argc = unsafe { vm_ci_argc((*cd).ci) };

                    let args = state.stack_pop_n(argc as usize + usize::from(forwarding))?;
                    let recv = state.stack_pop()?;
                    let send_forward = fun.push_insn(block, Insn::SendForward { recv, cd, blockiseq, args, state: exit_id, reason: Uncategorized(opcode) });
                    state.stack_push(send_forward);

                    if !blockiseq.is_null() {
                        // Reload locals that may have been modified by the blockiseq.
                        for local_idx in 0..state.locals.len() {
                            let ep_offset = local_idx_to_ep_offset(iseq, local_idx) as u32;
                            // TODO: We could use `use_sp: true` with PatchPoint
                            let val = fun.push_insn(block, Insn::GetLocal { ep_offset, level: 0, use_sp: false, rest_param: false });
                            state.setlocal(ep_offset, val);
                        }
                    }
                }
                YARVINSN_invokesuper => {
                    let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                    let call_info = unsafe { rb_get_call_data_ci(cd) };
                    let flags = unsafe { rb_vm_ci_flag(call_info) };
                    if let Err(call_type) = unhandled_call_type(flags) {
                        // Can't handle tailcall; side-exit into the interpreter
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnhandledCallType(call_type) });
                        break;  // End the block
                    }
                    let argc = unsafe { vm_ci_argc((*cd).ci) };
                    let block_arg = (flags & VM_CALL_ARGS_BLOCKARG) != 0;
                    let args = state.stack_pop_n(argc as usize + usize::from(block_arg))?;
                    let recv = state.stack_pop()?;
                    let blockiseq: IseqPtr = get_arg(pc, 1).as_ptr();
                    let result = fun.push_insn(block, Insn::InvokeSuper { recv, cd, blockiseq, args, state: exit_id, reason: Uncategorized(opcode) });
                    state.stack_push(result);

                    if !blockiseq.is_null() {
                        // Reload locals that may have been modified by the blockiseq.
                        // TODO: Avoid reloading locals that are not referenced by the blockiseq
                        // or not used after this. Max thinks we could eventually DCE them.
                        for local_idx in 0..state.locals.len() {
                            let ep_offset = local_idx_to_ep_offset(iseq, local_idx) as u32;
                            // TODO: We could use `use_sp: true` with PatchPoint
                            let val = fun.push_insn(block, Insn::GetLocal { ep_offset, level: 0, use_sp: false, rest_param: false });
                            state.setlocal(ep_offset, val);
                        }
                    }
                }
                YARVINSN_invokeblock => {
                    let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                    let call_info = unsafe { rb_get_call_data_ci(cd) };
                    let flags = unsafe { rb_vm_ci_flag(call_info) };
                    if let Err(call_type) = unhandled_call_type(flags) {
                        // Can't handle tailcall; side-exit into the interpreter
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnhandledCallType(call_type) });
                        break;  // End the block
                    }
                    let argc = unsafe { vm_ci_argc((*cd).ci) };
                    let block_arg = (flags & VM_CALL_ARGS_BLOCKARG) != 0;
                    let args = state.stack_pop_n(argc as usize + usize::from(block_arg))?;
                    let result = fun.push_insn(block, Insn::InvokeBlock { cd, args, state: exit_id, reason: Uncategorized(opcode) });
                    state.stack_push(result);
                }
                YARVINSN_getglobal => {
                    let id = ID(get_arg(pc, 0).as_u64());
                    let result = fun.push_insn(block, Insn::GetGlobal { id, state: exit_id });
                    state.stack_push(result);
                }
                YARVINSN_setglobal => {
                    let id = ID(get_arg(pc, 0).as_u64());
                    let val = state.stack_pop()?;
                    fun.push_insn(block, Insn::SetGlobal { id, val, state: exit_id });
                }
                YARVINSN_getinstancevariable => {
                    let id = ID(get_arg(pc, 0).as_u64());
                    let ic = get_arg(pc, 1).as_ptr();
                    // ic is in arg 1
                    // Assume single-Ractor mode to omit gen_prepare_non_leaf_call on gen_getivar
                    // TODO: We only really need this if self_val is a class/module
                    if !fun.assume_single_ractor_mode(block, exit_id) {
                        // gen_getivar assumes single Ractor; side-exit into the interpreter
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnhandledYARVInsn(opcode) });
                        break;  // End the block
                    }
                    let result = fun.push_insn(block, Insn::GetIvar { self_val: self_param, id, ic, state: exit_id });
                    state.stack_push(result);
                }
                YARVINSN_setinstancevariable => {
                    let id = ID(get_arg(pc, 0).as_u64());
                    let ic = get_arg(pc, 1).as_ptr();
                    // Assume single-Ractor mode to omit gen_prepare_non_leaf_call on gen_setivar
                    // TODO: We only really need this if self_val is a class/module
                    if !fun.assume_single_ractor_mode(block, exit_id) {
                        // gen_setivar assumes single Ractor; side-exit into the interpreter
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnhandledYARVInsn(opcode) });
                        break;  // End the block
                    }
                    let val = state.stack_pop()?;
                    fun.push_insn(block, Insn::SetIvar { self_val: self_param, id, ic, val, state: exit_id });
                }
                YARVINSN_getclassvariable => {
                    let id = ID(get_arg(pc, 0).as_u64());
                    let ic = get_arg(pc, 1).as_ptr();
                    let result = fun.push_insn(block, Insn::GetClassVar { id, ic, state: exit_id });
                    state.stack_push(result);
                }
                YARVINSN_setclassvariable => {
                    let id = ID(get_arg(pc, 0).as_u64());
                    let ic = get_arg(pc, 1).as_ptr();
                    let val = state.stack_pop()?;
                    fun.push_insn(block, Insn::SetClassVar { id, val, ic, state: exit_id });
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

                    // Check if this builtin is annotated
                    let return_type = ZJITState::get_method_annotations()
                        .get_builtin_properties(&bf)
                        .map(|props| props.return_type);

                    let builtin_attrs = unsafe { rb_jit_iseq_builtin_attrs(iseq) };
                    let leaf = builtin_attrs & BUILTIN_ATTR_LEAF != 0;

                    let insn_id = fun.push_insn(block, Insn::InvokeBuiltin {
                        bf,
                        recv: self_param,
                        args,
                        state: exit_id,
                        leaf,
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

                    // Check if this builtin is annotated
                    let return_type = ZJITState::get_method_annotations()
                        .get_builtin_properties(&bf)
                        .map(|props| props.return_type);

                    let builtin_attrs = unsafe { rb_jit_iseq_builtin_attrs(iseq) };
                    let leaf = builtin_attrs & BUILTIN_ATTR_LEAF != 0;

                    let insn_id = fun.push_insn(block, Insn::InvokeBuiltin {
                        bf,
                        recv: self_param,
                        args,
                        state: exit_id,
                        leaf,
                        return_type,
                    });
                    state.stack_push(insn_id);
                }
                YARVINSN_objtostring => {
                    let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                    let argc = unsafe { vm_ci_argc((*cd).ci) };
                    assert_eq!(0, argc, "objtostring should not have args");

                    let recv = state.stack_pop()?;
                    let objtostring = fun.push_insn(block, Insn::ObjToString { val: recv, cd, state: exit_id });
                    state.stack_push(objtostring)
                }
                YARVINSN_anytostring => {
                    let str = state.stack_pop()?;
                    let val = state.stack_pop()?;

                    let anytostring = fun.push_insn(block, Insn::AnyToString { val, str, state: exit_id });
                    state.stack_push(anytostring);
                }
                YARVINSN_getspecial => {
                    let key = get_arg(pc, 0).as_u64();
                    let svar = get_arg(pc, 1).as_u64();

                    if svar == 0 {
                        // TODO: Handle non-backref
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnknownSpecialVariable(key) });
                        // End the block
                        break;
                    } else if svar & 0x01 != 0 {
                        // Handle symbol backrefs like $&, $`, $', $+
                        let shifted_svar: u8 = (svar >> 1).try_into().unwrap();
                        let symbol_type = SpecialBackrefSymbol::try_from(shifted_svar).expect("invalid backref symbol");
                        let result = fun.push_insn(block, Insn::GetSpecialSymbol { symbol_type, state: exit_id });
                        state.stack_push(result);
                    } else {
                        // Handle number backrefs like $1, $2, $3
                        let result = fun.push_insn(block, Insn::GetSpecialNumber { nth: svar, state: exit_id });
                        state.stack_push(result);
                    }
                }
                YARVINSN_expandarray => {
                    let num = get_arg(pc, 0).as_u64();
                    let flag = get_arg(pc, 1).as_u64();
                    if flag != 0 {
                        // We don't (yet) handle 0x01 (rest args), 0x02 (post args), or 0x04
                        // (reverse?)
                        //
                        // Unhandled opcode; side-exit into the interpreter
                        fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnhandledYARVInsn(opcode) });
                        break;  // End the block
                    }
                    let val = state.stack_pop()?;
                    let array = fun.push_insn(block, Insn::GuardType { val, guard_type: types::ArrayExact, state: exit_id, });
                    let length = fun.push_insn(block, Insn::ArrayLength { array });
                    fun.push_insn(block, Insn::GuardBitEquals { val: length, expected: Const::CInt64(num as i64), state: exit_id });
                    for i in (0..num).rev() {
                        // TODO(max): Add a short-cut path for long indices into an array where the
                        // index is known to be in-bounds
                        let index = fun.push_insn(block, Insn::Const { val: Const::Value(VALUE::fixnum_from_usize(i.try_into().unwrap())) });
                        let element = fun.push_insn(block, Insn::ArrayArefFixnum { array, index });
                        state.stack_push(element);
                    }
                }
                _ => {
                    // Unhandled opcode; side-exit into the interpreter
                    fun.push_insn(block, Insn::SideExit { state: exit_id, reason: SideExitReason::UnhandledYARVInsn(opcode) });
                    break;  // End the block
                }
            }

            if insn_idx_to_block.contains_key(&insn_idx) {
                let target = insn_idx_to_block[&insn_idx];
                fun.push_insn(block, Insn::Jump(BranchEdge { target, args: state.as_args(self_param) }));
                queue.push_back((state, target, insn_idx, local_inval));
                break;  // End the block
            }
        }
    }

    fun.set_param_types();
    fun.infer_types();

    match get_option!(dump_hir_init) {
        Some(DumpHIR::WithoutSnapshot) => println!("Initial HIR:\n{}", FunctionPrinter::without_snapshot(&fun)),
        Some(DumpHIR::All) => println!("Initial HIR:\n{}", FunctionPrinter::with_snapshot(&fun)),
        Some(DumpHIR::Debug) => println!("Initial HIR:\n{:#?}", &fun),
        None => {},
    }

    fun.profiles = Some(profiles);
    if let Err(err) = fun.validate() {
        debug!("ZJIT: {err:?}: Initial HIR:\n{}", FunctionPrinter::without_snapshot(&fun));
        return Err(ParseError::Validation(err));
    }
    Ok(fun)
}

/// Compile an entry_block for the interpreter
fn compile_entry_block(fun: &mut Function, jit_entry_insns: &[u32], insn_idx_to_block: &HashMap<u32, BlockId>) {
    let entry_block = fun.entry_block;
    let (self_param, entry_state) = compile_entry_state(fun);
    let mut pc: Option<InsnId> = None;
    let &all_opts_passed_insn_idx = jit_entry_insns.last().unwrap();

    // Check-and-jump for each missing optional PC
    for &jit_entry_insn in jit_entry_insns.iter() {
        if jit_entry_insn == all_opts_passed_insn_idx {
            continue;
        }
        let target_block = insn_idx_to_block.get(&jit_entry_insn)
            .copied()
            .expect("we make a block for each jump target and \
                     each entry in the ISEQ opt_table is a jump target");
        // Load PC once at the start of the block, shared among all cases
        let pc = *pc.get_or_insert_with(|| fun.push_insn(entry_block, Insn::LoadPC));
        let expected_pc = fun.push_insn(entry_block, Insn::Const {
            val: Const::CPtr(unsafe { rb_iseq_pc_at_idx(fun.iseq, jit_entry_insn) } as *const u8),
        });
        let test_id = fun.push_insn(entry_block, Insn::IsBitEqual { left: pc, right: expected_pc });
        fun.push_insn(entry_block, Insn::IfTrue {
            val: test_id,
            target: BranchEdge { target: target_block, args: entry_state.as_args(self_param) },
        });
    }

    // Terminate the block with a jump to the block with all optionals passed
    let target_block = insn_idx_to_block.get(&all_opts_passed_insn_idx)
        .copied()
        .expect("we make a block for each jump target and \
                 each entry in the ISEQ opt_table is a jump target");
    fun.push_insn(entry_block, Insn::Jump(BranchEdge { target: target_block, args: entry_state.as_args(self_param) }));
}

/// Compile initial locals for an entry_block for the interpreter
fn compile_entry_state(fun: &mut Function) -> (InsnId, FrameState) {
    let entry_block = fun.entry_block;
    fun.push_insn(entry_block, Insn::EntryPoint { jit_entry_idx: None });

    let iseq = fun.iseq;
    let params = unsafe { iseq.params() };
    let param_size = params.size.to_usize();
    let rest_param_idx = iseq_rest_param_idx(params);

    let self_param = fun.push_insn(entry_block, Insn::LoadSelf);
    let mut entry_state = FrameState::new(iseq);
    for local_idx in 0..num_locals(iseq) {
        if local_idx < param_size {
            let ep_offset = local_idx_to_ep_offset(iseq, local_idx) as u32;
            let use_sp = !iseq_escapes_ep(iseq); // If the ISEQ does not escape EP, we can assume EP + 1 == SP
            let rest_param = Some(local_idx as i32) == rest_param_idx;
            entry_state.locals.push(fun.push_insn(entry_block, Insn::GetLocal { level: 0, ep_offset, use_sp, rest_param }));
        } else {
            entry_state.locals.push(fun.push_insn(entry_block, Insn::Const { val: Const::Value(Qnil) }));
        }
    }
    (self_param, entry_state)
}

/// Compile a jit_entry_block
fn compile_jit_entry_block(fun: &mut Function, jit_entry_idx: usize, target_block: BlockId) {
    let jit_entry_block = fun.jit_entry_blocks[jit_entry_idx];
    fun.push_insn(jit_entry_block, Insn::EntryPoint { jit_entry_idx: Some(jit_entry_idx) });

    // Prepare entry_state with basic block params
    let (self_param, entry_state) = compile_jit_entry_state(fun, jit_entry_block, jit_entry_idx);

    // Jump to target_block
    fun.push_insn(jit_entry_block, Insn::Jump(BranchEdge { target: target_block, args: entry_state.as_args(self_param) }));
}

/// Compile params and initial locals for a jit_entry_block
fn compile_jit_entry_state(fun: &mut Function, jit_entry_block: BlockId, jit_entry_idx: usize) -> (InsnId, FrameState) {
    let iseq = fun.iseq;
    let params = unsafe { iseq.params() };
    let param_size = params.size.to_usize();
    let opt_num: usize = params.opt_num.try_into().expect("iseq param opt_num >= 0");
    let lead_num: usize = params.lead_num.try_into().expect("iseq param lead_num >= 0");
    let passed_opt_num = jit_entry_idx;

    // If the iseq has keyword parameters, the keyword bits local will be appended to the local table.
    let kw_bits_idx: Option<usize> = if unsafe { rb_get_iseq_flags_has_kw(iseq) } {
        let keyword = unsafe { rb_get_iseq_body_param_keyword(iseq) };
        if !keyword.is_null() {
            Some(unsafe { (*keyword).bits_start } as usize)
        } else {
            None
        }
    } else {
        None
    };

    let self_param = fun.push_insn(jit_entry_block, Insn::Param);
    let mut entry_state = FrameState::new(iseq);
    for local_idx in 0..num_locals(iseq) {
        if (lead_num + passed_opt_num..lead_num + opt_num).contains(&local_idx) {
            // Omitted optionals are locals, so they start as nils before their code run
            entry_state.locals.push(fun.push_insn(jit_entry_block, Insn::Const { val: Const::Value(Qnil) }));
        } else if Some(local_idx) == kw_bits_idx {
            // We currently only support required keywords so the unspecified bits will always be zero.
            // TODO: Make this a parameter when we start writing anything other than zero.
            let unspecified_bits = VALUE::fixnum_from_usize(0);
            entry_state.locals.push(fun.push_insn(jit_entry_block, Insn::Const { val: Const::Value(unspecified_bits) }));
        } else if local_idx < param_size {
            entry_state.locals.push(fun.push_insn(jit_entry_block, Insn::Param));
        } else {
            entry_state.locals.push(fun.push_insn(jit_entry_block, Insn::Const { val: Const::Value(Qnil) }));
        }
    }
    (self_param, entry_state)
}

pub struct Dominators<'a> {
    f: &'a Function,
    dominators: Vec<Vec<BlockId>>,
}

impl<'a> Dominators<'a> {
    pub fn new(f: &'a Function) -> Self {
        let mut cfi = ControlFlowInfo::new(f);
        Self::with_cfi(f, &mut cfi)
    }

    pub fn with_cfi(f: &'a Function, cfi: &mut ControlFlowInfo) -> Self {
        let block_ids = f.rpo();
        let mut dominators = vec![vec![]; f.blocks.len()];

        // Compute dominators for each node using fixed point iteration.
        // Approach can be found in Figure 1 of:
        // https://www.cs.tufts.edu/~nr/cs257/archive/keith-cooper/dom14.pdf
        //
        // Initially we set:
        //
        // dom(entry) = {entry} for each entry block
        // dom(b != entry) = {all nodes}
        //
        // Iteratively, apply:
        //
        // dom(b) = {b} union intersect(dom(p) for p in predecessors(b))
        //
        // When we've run the algorithm and the dominator set no longer changes
        // between iterations, then we have found the dominator sets.

        // Set up entry blocks.
        // Entry blocks are only dominated by themselves.
        for entry_block in &f.entry_blocks() {
            dominators[entry_block.0] = vec![*entry_block];
        }

        // Setup the initial dominator sets.
        for block_id in &block_ids {
            if !f.entry_blocks().contains(block_id) {
                // Non entry blocks are initially dominated by all other blocks.
                dominators[block_id.0] = block_ids.clone();
            }
        }

        let mut changed = true;
        while changed {
            changed = false;

            for block_id in &block_ids {
                if *block_id == f.entry_block {
                    continue;
                }

                // Get all predecessors for a given block.
                let block_preds: Vec<BlockId> = cfi.predecessors(*block_id).collect();
                if block_preds.is_empty() {
                    continue;
                }

                let mut new_doms = dominators[block_preds[0].0].clone();

                // Compute the intersection of predecessor dominator sets into `new_doms`.
                for pred_id in &block_preds[1..] {
                    let pred_doms = &dominators[pred_id.0];
                    // Only keep a dominator in `new_doms` if it is also found in pred_doms
                    new_doms.retain(|d| pred_doms.contains(d));
                }

                // Insert sorted into `new_doms`.
                match new_doms.binary_search(block_id) {
                    Ok(_) => {}
                    Err(pos) => new_doms.insert(pos, *block_id)
                }

                // If we have computed a new dominator set, then we can update
                // the dominators and mark that we need another iteration.
                if dominators[block_id.0] != new_doms {
                    dominators[block_id.0] = new_doms;
                    changed = true;
                }
            }
        }

        Self { f, dominators }
    }


    pub fn is_dominated_by(&self, left: BlockId, right: BlockId) -> bool {
        self.dominators(left).any(|&b| b == right)
    }

    pub fn dominators(&self, block: BlockId) -> Iter<'_, BlockId> {
        self.dominators[block.0].iter()
    }
}

pub struct ControlFlowInfo<'a> {
    function: &'a Function,
    successor_map: HashMap<BlockId, Vec<BlockId>>,
    predecessor_map: HashMap<BlockId, Vec<BlockId>>,
}

impl<'a> ControlFlowInfo<'a> {
    pub fn new(function: &'a Function) -> Self {
        let mut successor_map: HashMap<BlockId, Vec<BlockId>> = HashMap::new();
        let mut predecessor_map: HashMap<BlockId, Vec<BlockId>> = HashMap::new();
        let uf = function.union_find.borrow();

        for block_id in function.rpo() {
            let block = &function.blocks[block_id.0];

            // Since ZJIT uses extended basic blocks, one must check all instructions
            // for their ability to jump to another basic block, rather than just
            // the instructions at the end of a given basic block.
            //
            // Use BTreeSet to avoid duplicates and maintain an ordering. Also
            // `BTreeSet<BlockId>` provides conversion trivially back to an `Vec<BlockId>`.
            // Ordering is important so that the expect tests that serialize the predecessors
            // and successors don't fail intermittently.
            // todo(aidenfoxivey): Use `BlockSet` in lieu of `BTreeSet<BlockId>`
            let successors: BTreeSet<BlockId> = block
                .insns
                .iter()
                .map(|&insn_id| uf.find_const(insn_id))
                .filter_map(|insn_id| {
                    Self::extract_jump_target(&function.insns[insn_id.0])
                })
                .collect();

            // Update predecessors for successor blocks.
            for &succ_id in &successors {
                predecessor_map
                    .entry(succ_id)
                    .or_default()
                    .push(block_id);
            }

            // Store successors for this block.
            // Convert successors from a `BTreeSet<BlockId>` to a `Vec<BlockId>`.
            successor_map.insert(block_id, successors.iter().copied().collect());
        }

        Self {
            function,
            successor_map,
            predecessor_map,
        }
    }

    pub fn is_succeeded_by(&self, left: BlockId, right: BlockId) -> bool {
        self.successor_map.get(&right).is_some_and(|set| set.contains(&left))
    }

    pub fn is_preceded_by(&self, left: BlockId, right: BlockId) -> bool {
        self.predecessor_map.get(&right).is_some_and(|set| set.contains(&left))
    }

    pub fn predecessors(&self, block: BlockId) -> impl Iterator<Item = BlockId> {
        self.predecessor_map.get(&block).into_iter().flatten().copied()
    }

    pub fn successors(&self, block: BlockId) -> impl Iterator<Item = BlockId> {
        self.successor_map.get(&block).into_iter().flatten().copied()
    }

    /// Helper function to extract the target of a jump instruction.
    fn extract_jump_target(insn: &Insn) -> Option<BlockId> {
        match insn {
            Insn::Jump(target)
            | Insn::IfTrue { target, .. }
            | Insn::IfFalse { target, .. } => Some(target.target),
            _ => None,
        }
    }
}

pub struct LoopInfo<'a> {
    cfi: &'a ControlFlowInfo<'a>,
    dominators: &'a Dominators<'a>,
    loop_depths: HashMap<BlockId, u32>,
    loop_headers: BlockSet,
    back_edge_sources: BlockSet,
}

impl<'a> LoopInfo<'a> {
    pub fn new(cfi: &'a ControlFlowInfo<'a>, dominators: &'a Dominators<'a>) -> Self {
        let mut loop_headers: BlockSet = BlockSet::with_capacity(cfi.function.num_blocks());
        let mut loop_depths: HashMap<BlockId, u32> = HashMap::new();
        let mut back_edge_sources: BlockSet = BlockSet::with_capacity(cfi.function.num_blocks());
        let rpo = cfi.function.rpo();

        for &block in &rpo {
            loop_depths.insert(block, 0);
        }

        // Collect loop headers.
        for &block in &rpo {
            // Initialize the loop depths.
            for predecessor in cfi.predecessors(block) {
                if dominators.is_dominated_by(predecessor, block) {
                    // Found a loop header, so then identify the natural loop.
                    loop_headers.insert(block);
                    back_edge_sources.insert(predecessor);
                    let loop_blocks = Self::find_natural_loop(cfi, block, predecessor);
                    // Increment the loop depth.
                    for loop_block in &loop_blocks {
                        *loop_depths.get_mut(loop_block).expect("Loop block should be populated.") += 1;
                    }
                }
            }
        }

        Self {
            cfi,
            dominators,
            loop_depths,
            loop_headers,
            back_edge_sources,
        }
    }

    fn find_natural_loop(
        cfi: &ControlFlowInfo,
        header: BlockId,
        back_edge_source: BlockId,
    ) -> HashSet<BlockId> {
        // todo(aidenfoxivey): Reimplement using BlockSet
        let mut loop_blocks = HashSet::new();
        let mut stack = vec![back_edge_source];

        loop_blocks.insert(header);
        loop_blocks.insert(back_edge_source);

        while let Some(block) = stack.pop() {
            for pred in cfi.predecessors(block) {
                // Pushes to stack only if `pred` wasn't already in `loop_blocks`.
                if loop_blocks.insert(pred) {
                    stack.push(pred)
                }
            }
        }

        loop_blocks
    }

    pub fn loop_depth(&self, block: BlockId) -> u32 {
        self.loop_depths.get(&block).copied().unwrap_or(0)
    }

    pub fn is_back_edge_source(&self, block: BlockId) -> bool {
        self.back_edge_sources.get(block)
    }

    pub fn is_loop_header(&self, block: BlockId) -> bool {
        self.loop_headers.get(block)
    }
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
            Ok(_) => panic!("Expected validation error"),
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
        let block = function.new_block(0);
        function.push_insn(function.entry_block, Insn::Jump(BranchEdge { target: block, args: vec![] }));
        let val = function.push_insn(block, Insn::Const { val: Const::Value(Qnil) });
        function.push_insn_id(block, val);
        function.push_insn(block, Insn::Return { val });
        assert_matches_err(function.validate(), ValidationError::DuplicateInstruction(block, val));
    }

    #[test]
    fn instruction_appears_twice_with_different_ids() {
        let mut function = Function::new(std::ptr::null());
        let block = function.new_block(0);
        function.push_insn(function.entry_block, Insn::Jump(BranchEdge { target: block, args: vec![] }));
        let val0 = function.push_insn(block, Insn::Const { val: Const::Value(Qnil) });
        let val1 = function.push_insn(block, Insn::Const { val: Const::Value(Qnil) });
        function.make_equal_to(val1, val0);
        function.push_insn(block, Insn::Return { val: val0 });
        assert_matches_err(function.validate(), ValidationError::DuplicateInstruction(block, val0));
    }

    #[test]
    fn instruction_appears_twice_in_different_blocks() {
        let mut function = Function::new(std::ptr::null());
        let block = function.new_block(0);
        function.push_insn(function.entry_block, Insn::Jump(BranchEdge { target: block, args: vec![] }));
        let val = function.push_insn(block, Insn::Const { val: Const::Value(Qnil) });
        let exit = function.new_block(0);
        function.push_insn(block, Insn::Jump(BranchEdge { target: exit, args: vec![] }));
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
        let param = function.push_insn(exit, Insn::Param);
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
        let param = function.push_insn(exit, Insn::Param);
        crate::cruby::with_rubyvm(|| {
            function.infer_types();
            assert_bit_equal(function.type_of(param), types::TrueClass.union(types::FalseClass));
        });
    }
}

#[cfg(test)]
mod graphviz_tests {
    use super::*;
    use insta::assert_snapshot;

    #[track_caller]
    fn hir_string(method: &str) -> String {
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq("self", method));
        unsafe { crate::cruby::rb_zjit_profile_disable(iseq) };
        let mut function = iseq_to_hir(iseq).unwrap();
        function.optimize();
        function.validate().unwrap();
        format!("{}", FunctionGraphvizPrinter::new(&function))
    }

    #[test]
    fn test_guard_fixnum_or_fixnum() {
        eval(r#"
            def test(x, y) = x | y

            test(1, 2)
        "#);
        assert_snapshot!(hir_string("test"), @r#"
        digraph G { # test@&lt;compiled&gt;:2
        node [shape=plaintext];
        mode=hier; overlap=false; splines=true;
          bb0 [label=<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0">
        <TR><TD ALIGN="LEFT" PORT="params" BGCOLOR="gray">bb0()&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v0">EntryPoint interpreter&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v1">v1:BasicObject = LoadSelf&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v2">v2:BasicObject = GetLocal :x, l0, SP@5&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v3">v3:BasicObject = GetLocal :y, l0, SP@4&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v4">Jump bb2(v1, v2, v3)&nbsp;</TD></TR>
        </TABLE>>];
          bb0:v4 -> bb2:params:n;
          bb1 [label=<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0">
        <TR><TD ALIGN="LEFT" PORT="params" BGCOLOR="gray">bb1(v6:BasicObject, v7:BasicObject, v8:BasicObject)&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v5">EntryPoint JIT(0)&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v9">Jump bb2(v6, v7, v8)&nbsp;</TD></TR>
        </TABLE>>];
          bb1:v9 -> bb2:params:n;
          bb2 [label=<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0">
        <TR><TD ALIGN="LEFT" PORT="params" BGCOLOR="gray">bb2(v10:BasicObject, v11:BasicObject, v12:BasicObject)&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v15">PatchPoint NoTracePoint&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v18">PatchPoint NoTracePoint&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v24">PatchPoint NoTracePoint&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v25">PatchPoint MethodRedefined(Integer@0x1000, |@0x1008, cme:0x1010)&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v26">v26:Fixnum = GuardType v11, Fixnum&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v27">v27:Fixnum = GuardType v12, Fixnum&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v28">v28:Fixnum = FixnumOr v26, v27&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v29">IncrCounter inline_cfunc_optimized_send_count&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v21">PatchPoint NoTracePoint&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v22">CheckInterrupts&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v23">Return v28&nbsp;</TD></TR>
        </TABLE>>];
        }
        "#);
    }

    #[test]
    fn test_multiple_blocks() {
        eval(r#"
            def test(c)
              if c
                3
              else
                4
              end
            end

            test(1)
            test("x")
        "#);
        assert_snapshot!(hir_string("test"), @r#"
        digraph G { # test@&lt;compiled&gt;:3
        node [shape=plaintext];
        mode=hier; overlap=false; splines=true;
          bb0 [label=<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0">
        <TR><TD ALIGN="LEFT" PORT="params" BGCOLOR="gray">bb0()&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v0">EntryPoint interpreter&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v1">v1:BasicObject = LoadSelf&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v2">v2:BasicObject = GetLocal :c, l0, SP@4&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v3">Jump bb2(v1, v2)&nbsp;</TD></TR>
        </TABLE>>];
          bb0:v3 -> bb2:params:n;
          bb1 [label=<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0">
        <TR><TD ALIGN="LEFT" PORT="params" BGCOLOR="gray">bb1(v5:BasicObject, v6:BasicObject)&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v4">EntryPoint JIT(0)&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v7">Jump bb2(v5, v6)&nbsp;</TD></TR>
        </TABLE>>];
          bb1:v7 -> bb2:params:n;
          bb2 [label=<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0">
        <TR><TD ALIGN="LEFT" PORT="params" BGCOLOR="gray">bb2(v8:BasicObject, v9:BasicObject)&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v12">PatchPoint NoTracePoint&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v14">CheckInterrupts&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v15">v15:CBool = Test v9&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v16">IfFalse v15, bb3(v8, v9)&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v18">PatchPoint NoTracePoint&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v19">v19:Fixnum[3] = Const Value(3)&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v21">PatchPoint NoTracePoint&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v22">CheckInterrupts&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v23">Return v19&nbsp;</TD></TR>
        </TABLE>>];
          bb2:v16 -> bb3:params:n;
          bb3 [label=<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0">
        <TR><TD ALIGN="LEFT" PORT="params" BGCOLOR="gray">bb3(v24:BasicObject, v25:BasicObject)&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v28">PatchPoint NoTracePoint&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v29">v29:Fixnum[4] = Const Value(4)&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v31">PatchPoint NoTracePoint&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v32">CheckInterrupts&nbsp;</TD></TR>
        <TR><TD ALIGN="left" PORT="v33">Return v29&nbsp;</TD></TR>
        </TABLE>>];
        }
        "#);
    }
}
