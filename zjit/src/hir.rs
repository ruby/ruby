// We use the YARV bytecode constants which have a CRuby-style name
#![allow(non_upper_case_globals)]

use crate::{
    cruby::*, options::get_option, hir_type::types::Fixnum, options::DumpHIR, profile::get_or_create_iseq_payload
};
use std::{cell::RefCell, collections::{HashMap, HashSet}, ffi::c_void, mem::{align_of, size_of}, ptr, slice::Iter};
use crate::hir_type::{Type, types};

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

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub struct BlockId(pub usize);

impl std::fmt::Display for BlockId {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "bb{}", self.0)
    }
}

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

#[derive(Debug, PartialEq, Clone)]
pub struct CallInfo {
    pub method_name: String,
}

/// Invalidation reasons
#[derive(Debug, Clone)]
pub enum Invariant {
    /// Basic operation is redefined
    BOPRedefined {
        /// {klass}_REDEFINED_OP_FLAG
        klass: RedefinitionFlag,
        /// BOP_{bop}
        bop: ruby_basic_operators,
    },
}

impl std::fmt::Display for Invariant {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            Self::BOPRedefined { klass, bop } => {
                write!(f, "BOPRedefined(")?;
                match *klass {
                    INTEGER_REDEFINED_OP_FLAG => write!(f, "INTEGER_REDEFINED_OP_FLAG")?,
                    _ => write!(f, "{klass}")?,
                }
                write!(f, ", ")?;
                match *bop {
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
                    _ => write!(f, "{bop}")?,
                }
                write!(f, ")")
            }
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
}

#[derive(Debug, Clone)]
pub enum Insn {
    PutSelf,
    Const { val: Const },
    // SSA block parameter. Also used for function parameters in the function's entry block.
    Param { idx: usize },

    StringCopy { val: InsnId },
    StringIntern { val: InsnId },

    NewArray { count: usize },
    ArraySet { array: InsnId, idx: usize, val: InsnId },
    ArrayDup { val: InsnId },

    // Check if the value is truthy and "return" a C boolean. In reality, we will likely fuse this
    // with IfTrue/IfFalse in the backend to generate jcc.
    Test { val: InsnId },
    Defined { op_type: usize, obj: VALUE, pushval: VALUE, v: InsnId },
    GetConstantPath { ic: *const u8 },

    //NewObject?
    //SetIvar {},
    //GetIvar {},

    // Own a FrameStateId so that instructions can look up their dominating FrameStateId when
    // generating deopt side-exits and frame reconstruction metadata. Does not directly generate
    // any code.
    Snapshot { state: FrameStateId },

    // Unconditional jump
    Jump(BranchEdge),

    // Conditional branch instructions
    IfTrue { val: InsnId, target: BranchEdge },
    IfFalse { val: InsnId, target: BranchEdge },

    // Call a C function
    // NOTE: should we store the C function name for pretty-printing?
    //       or can we backtranslate the function pointer into a name string?
    CCall { cfun: *const u8, args: Vec<InsnId> },

    // Send without block with dynamic dispatch
    // Ignoring keyword arguments etc for now
    SendWithoutBlock { self_val: InsnId, call_info: CallInfo, cd: *const rb_call_data, args: Vec<InsnId>, state: FrameStateId },
    Send { self_val: InsnId, call_info: CallInfo, cd: *const rb_call_data, blockiseq: IseqPtr, args: Vec<InsnId>, state: FrameStateId },

    // Control flow instructions
    Return { val: InsnId },

    /// Fixnum +, -, *, /, %, ==, !=, <, <=, >, >=
    FixnumAdd  { left: InsnId, right: InsnId, state: FrameStateId },
    FixnumSub  { left: InsnId, right: InsnId, state: FrameStateId },
    FixnumMult { left: InsnId, right: InsnId, state: FrameStateId },
    FixnumDiv  { left: InsnId, right: InsnId, state: FrameStateId },
    FixnumMod  { left: InsnId, right: InsnId, state: FrameStateId },
    FixnumEq   { left: InsnId, right: InsnId },
    FixnumNeq  { left: InsnId, right: InsnId },
    FixnumLt   { left: InsnId, right: InsnId },
    FixnumLe   { left: InsnId, right: InsnId },
    FixnumGt   { left: InsnId, right: InsnId },
    FixnumGe   { left: InsnId, right: InsnId },

    /// Side-exist if val doesn't have the expected type.
    GuardType { val: InsnId, guard_type: Type, state: FrameStateId },

    /// Generate no code (or padding if necessary) and insert a patch point
    /// that can be rewritten to a side exit when the Invariant is broken.
    PatchPoint(Invariant),
}

impl Insn {
    /// Not every instruction returns a value. Return true if the instruction does and false otherwise.
    pub fn has_output(&self) -> bool {
        match self {
            Insn::ArraySet { .. } | Insn::Snapshot { .. } | Insn::Jump(_)
            | Insn::IfTrue { .. } | Insn::IfFalse { .. } | Insn::Return { .. }
            | Insn::PatchPoint { .. } => false,
            _ => true,
        }
    }

    /// Return true if the instruction ends a basic block and false otherwise.
    pub fn is_terminator(&self) -> bool {
        match self {
            Insn::Jump(_) | Insn::Return { .. } => true,
            _ => false,
        }
    }
}

#[derive(Default, Debug)]
pub struct Block {
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

struct FunctionPrinter<'a> {
    fun: &'a Function,
    display_snapshot: bool,
    ptr_map: PtrPrintMap,
}

impl<'a> FunctionPrinter<'a> {
    fn without_snapshot(fun: &'a Function) -> Self {
        let mut ptr_map = PtrPrintMap::identity();
        ptr_map.map_ptrs = true;
        Self { fun, display_snapshot: false, ptr_map }
    }

    fn with_snapshot(fun: &'a Function) -> FunctionPrinter<'a> {
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
    pub fn find_const(&self, insn: T) -> T {
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

#[derive(Debug)]
pub struct Function {
    // ISEQ this function refers to
    iseq: *const rb_iseq_t,

    // TODO: get method name and source location from the ISEQ

    insns: Vec<Insn>,
    union_find: UnionFind<InsnId>,
    insn_types: Vec<Type>,
    blocks: Vec<Block>,
    entry_block: BlockId,
    frame_states: Vec<FrameState>,
}

impl Function {
    fn new(iseq: *const rb_iseq_t) -> Function {
        Function {
            iseq,
            insns: vec![],
            insn_types: vec![],
            union_find: UnionFind::new(),
            blocks: vec![Block::default()],
            entry_block: BlockId(0),
            frame_states: vec![],
        }
    }

    // Add an instruction to the function without adding it to any block
    fn new_insn(&mut self, insn: Insn) -> InsnId {
        let id = InsnId(self.insns.len());
        self.insns.push(insn);
        self.insn_types.push(types::Empty);
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

    /// Return the number of instructions
    pub fn num_insns(&self) -> usize {
        self.insns.len()
    }

    /// Store the given FrameState on the Function so that it can be cheaply referenced by
    /// instructions.
    fn push_frame_state(&mut self, state: FrameState) -> FrameStateId {
        let id = FrameStateId(self.frame_states.len());
        self.frame_states.push(state);
        id
    }

    /// Return a reference to the FrameState at the given index.
    pub fn frame_state(&self, id: FrameStateId) -> &FrameState {
        &self.frame_states[id.0]
    }

    fn new_block(&mut self) -> BlockId {
        let id = BlockId(self.blocks.len());
        self.blocks.push(Block::default());
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
    /// Use for pattern matching over instructions in a union-find-safe way. For example:
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
                    self.union_find.find_const($x)
                }
            };
        }
        let insn_id = self.union_find.find_const(insn_id);
        use Insn::*;
        match &self.insns[insn_id.0] {
            result@(PutSelf | Const {..} | Param {..} | NewArray {..} | GetConstantPath {..} | Snapshot {..}
                    | Jump(_) | PatchPoint {..}) => result.clone(),
            Return { val } => Return { val: find!(*val) },
            StringCopy { val } => StringCopy { val: find!(*val) },
            StringIntern { val } => StringIntern { val: find!(*val) },
            Test { val } => Test { val: find!(*val) },
            IfTrue { val, target } => IfTrue { val: find!(*val), target: target.clone() },
            IfFalse { val, target } => IfFalse { val: find!(*val), target: target.clone() },
            GuardType { val, guard_type, state } => GuardType { val: find!(*val), guard_type: *guard_type, state: *state },
            FixnumAdd { left, right, state } => FixnumAdd { left: find!(*left), right: find!(*right), state: *state },
            FixnumSub { left, right, state } => FixnumSub { left: find!(*left), right: find!(*right), state: *state },
            FixnumMult { left, right, state } => FixnumMult { left: find!(*left), right: find!(*right), state: *state },
            FixnumDiv { left, right, state } => FixnumDiv { left: find!(*left), right: find!(*right), state: *state },
            FixnumMod { left, right, state } => FixnumMod { left: find!(*left), right: find!(*right), state: *state },
            FixnumNeq { left, right } => FixnumNeq { left: find!(*left), right: find!(*right) },
            FixnumEq { left, right } => FixnumEq { left: find!(*left), right: find!(*right) },
            FixnumGt { left, right } => FixnumGt { left: find!(*left), right: find!(*right) },
            FixnumGe { left, right } => FixnumGe { left: find!(*left), right: find!(*right) },
            FixnumLt { left, right } => FixnumLt { left: find!(*left), right: find!(*right) },
            FixnumLe { left, right } => FixnumLe { left: find!(*left), right: find!(*right) },
            SendWithoutBlock { self_val, call_info, cd, args, state } => SendWithoutBlock {
                self_val: find!(*self_val),
                call_info: call_info.clone(),
                cd: cd.clone(),
                args: args.iter().map(|arg| find!(*arg)).collect(),
                state: *state,
            },
            Send { self_val, call_info, cd, blockiseq, args, state } => Send {
                self_val: find!(*self_val),
                call_info: call_info.clone(),
                cd: cd.clone(),
                blockiseq: *blockiseq,
                args: args.iter().map(|arg| find!(*arg)).collect(),
                state: *state,
            },
            ArraySet { array, idx, val } => ArraySet { array: find!(*array), idx: *idx, val: find!(*val) },
            ArrayDup { val } => ArrayDup { val: find!(*val) },
            CCall { cfun, args } => CCall { cfun: *cfun, args: args.iter().map(|arg| find!(*arg)).collect() },
            Defined { .. } => todo!("find(Defined)"),
        }
    }

    /// Replace `insn` with the new instruction `replacement`, which will get appended to `insns`.
    fn make_equal_to(&mut self, insn: InsnId, replacement: InsnId) {
        // Don't push it to the block
        self.union_find.make_equal_to(insn, replacement);
    }

    fn type_of(&self, insn: InsnId) -> Type {
        assert!(self.insns[insn.0].has_output());
        self.insn_types[insn.0]
    }

    /// Check if the type of `insn` is a subtype of `ty`.
    fn is_a(&self, insn: InsnId, ty: Type) -> bool {
        self.type_of(insn).is_subtype(ty)
    }

    fn infer_type(&self, insn: InsnId) -> Type {
        assert!(self.insns[insn.0].has_output());
        match &self.insns[insn.0] {
            Insn::Param { .. } => unimplemented!("params should not be present in block.insns"),
            Insn::ArraySet { .. } | Insn::Snapshot { .. } | Insn::Jump(_)
            | Insn::IfTrue { .. } | Insn::IfFalse { .. } | Insn::Return { .. }
            | Insn::PatchPoint { .. } =>
                panic!("Cannot infer type of instruction with no output"),
            Insn::Const { val: Const::Value(val) } => Type::from_value(*val),
            Insn::Const { val: Const::CBool(val) } => Type::from_cbool(*val),
            Insn::Const { val: Const::CInt8(val) } => Type::from_cint(types::CInt8, *val as i64),
            Insn::Const { val: Const::CInt16(val) } => Type::from_cint(types::CInt16, *val as i64),
            Insn::Const { val: Const::CInt32(val) } => Type::from_cint(types::CInt32, *val as i64),
            Insn::Const { val: Const::CInt64(val) } => Type::from_cint(types::CInt64, *val as i64),
            Insn::Const { val: Const::CUInt8(val) } => Type::from_cint(types::CUInt8, *val as i64),
            Insn::Const { val: Const::CUInt16(val) } => Type::from_cint(types::CUInt16, *val as i64),
            Insn::Const { val: Const::CUInt32(val) } => Type::from_cint(types::CUInt32, *val as i64),
            Insn::Const { val: Const::CUInt64(val) } => Type::from_cint(types::CUInt64, *val as i64),
            Insn::Const { val: Const::CPtr(val) } => Type::from_cint(types::CPtr, *val as i64),
            Insn::Const { val: Const::CDouble(val) } => Type::from_double(*val),
            Insn::Test { val } if self.type_of(*val).is_known_falsy() => Type::from_cbool(false),
            Insn::Test { val } if self.type_of(*val).is_known_truthy() => Type::from_cbool(true),
            Insn::Test { .. } => types::CBool,
            Insn::StringCopy { .. } => types::StringExact,
            Insn::StringIntern { .. } => types::StringExact,
            Insn::NewArray { .. } => types::ArrayExact,
            Insn::ArrayDup { .. } => types::ArrayExact,
            Insn::CCall { .. } => types::Any,
            Insn::GuardType { val, guard_type, .. } => self.type_of(*val).intersection(*guard_type),
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
            Insn::SendWithoutBlock { .. } => types::BasicObject,
            Insn::Send { .. } => types::BasicObject,
            Insn::PutSelf => types::BasicObject,
            Insn::Defined { .. } => types::BasicObject,
            Insn::GetConstantPath { .. } => types::BasicObject,
        }
    }

    fn infer_types(&mut self) {
        // Reset all types
        self.insn_types.fill(types::Empty);
        for param in &self.blocks[self.entry_block.0].params {
            // We know that function parameters are BasicObject or some subclass
            self.insn_types[param.0] = types::BasicObject;
        }
        let rpo = self.rpo();
        // Walk the graph, computing types until fixpoint
        let mut reachable = vec![false; self.blocks.len()];
        reachable[self.entry_block.0] = true;
        loop {
            let mut changed = false;
            for block in &rpo {
                if !reachable[block.0] { continue; }
                for insn_id in &self.blocks[block.0].insns {
                    let insn = self.find(*insn_id);
                    let insn_type = match insn {
                        Insn::IfTrue { val, target: BranchEdge { target, args } } => {
                            assert!(!self.type_of(val).bit_equal(types::Empty));
                            if self.type_of(val).could_be(Type::from_cbool(true)) {
                                reachable[target.0] = true;
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
                                reachable[target.0] = true;
                                for (idx, arg) in args.iter().enumerate() {
                                    let param = self.blocks[target.0].params[idx];
                                    self.insn_types[param.0] = self.type_of(param).union(self.type_of(*arg));
                                }
                            }
                            continue;
                        }
                        Insn::Jump(BranchEdge { target, args }) => {
                            reachable[target.0] = true;
                            for (idx, arg) in args.iter().enumerate() {
                                let param = self.blocks[target.0].params[idx];
                                self.insn_types[param.0] = self.type_of(param).union(self.type_of(*arg));
                            }
                            continue;
                        }
                        _ if insn.has_output() => self.infer_type(*insn_id),
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
                        match (self.type_of(left).fixnum_value(), self.type_of(right).fixnum_value()) {
                            (Some(l), Some(r)) => {
                                let result = l + r;
                                if result >= (RUBY_FIXNUM_MIN as i64) && result <= (RUBY_FIXNUM_MAX as i64) {
                                    self.new_insn(Insn::Const { val: Const::Value(VALUE::fixnum_from_usize(result as usize)) })
                                } else {
                                    // Instead of allocating a Bignum at compile-time, defer the add and allocation to run-time.
                                    insn_id
                                }
                            }
                            _ => insn_id,
                        }
                    }
                    Insn::FixnumLt { left, right, .. } => {
                        match (self.type_of(left).fixnum_value(), self.type_of(right).fixnum_value()) {
                            (Some(l), Some(r)) => {
                                if l < r {
                                    self.new_insn(Insn::Const { val: Const::Value(Qtrue) })
                                } else {
                                    self.new_insn(Insn::Const { val: Const::Value(Qfalse) })
                                }
                            }
                            _ => insn_id,
                        }
                    }
                    Insn::FixnumEq { left, right, .. } => {
                        match (self.type_of(left).fixnum_value(), self.type_of(right).fixnum_value()) {
                            (Some(l), Some(r)) => {
                                if l == r {
                                    self.new_insn(Insn::Const { val: Const::Value(Qtrue) })
                                } else {
                                    self.new_insn(Insn::Const { val: Const::Value(Qfalse) })
                                }
                            }
                            _ => insn_id,
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
        let mut seen = HashSet::new();
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

    /// Run all the optimization passes we have.
    pub fn optimize(&mut self) {
        // Function is assumed to have types inferred already
        self.fold_constants();
    }
}

impl<'a> std::fmt::Display for FunctionPrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let fun = &self.fun;
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
                match insn {
                    Insn::Const { val } => { write!(f, "Const {}", val.print(&self.ptr_map))?; }
                    Insn::Param { idx } => { write!(f, "Param {idx}")?; }
                    Insn::NewArray { count } => { write!(f, "NewArray {count}")?; }
                    Insn::ArraySet { array, idx, val } => { write!(f, "ArraySet {array}, {idx}, {val}")?; }
                    Insn::ArrayDup { val } => { write!(f, "ArrayDup {val}")?; }
                    Insn::Test { val } => { write!(f, "Test {val}")?; }
                    Insn::Snapshot { state } => { write!(f, "Snapshot {}", fun.frame_state(state))?; }
                    Insn::Jump(target) => { write!(f, "Jump {target}")?; }
                    Insn::IfTrue { val, target } => { write!(f, "IfTrue {val}, {target}")?; }
                    Insn::IfFalse { val, target } => { write!(f, "IfFalse {val}, {target}")?; }
                    Insn::SendWithoutBlock { self_val, call_info, args, .. } => {
                        write!(f, "SendWithoutBlock {self_val}, :{}", call_info.method_name)?;
                        for arg in args {
                            write!(f, ", {arg}")?;
                        }
                    }
                    Insn::Send { self_val, call_info, args, blockiseq, .. } => {
                        // For tests, we want to check HIR snippets textually. Addresses change
                        // between runs, making tests fail. Instead, pick an arbitrary hex value to
                        // use as a "pointer" so we can check the rest of the HIR.
                        write!(f, "Send {self_val}, {:p}, :{}", self.ptr_map.map_ptr(blockiseq), call_info.method_name)?;
                        for arg in args {
                            write!(f, ", {arg}")?;
                        }
                    }
                    Insn::Return { val } => { write!(f, "Return {val}")?; }
                    Insn::FixnumAdd  { left, right, .. } => { write!(f, "FixnumAdd {left}, {right}")?; },
                    Insn::FixnumSub  { left, right, .. } => { write!(f, "FixnumSub {left}, {right}")?; },
                    Insn::FixnumMult { left, right, .. } => { write!(f, "FixnumMult {left}, {right}")?; },
                    Insn::FixnumDiv  { left, right, .. } => { write!(f, "FixnumDiv {left}, {right}")?; },
                    Insn::FixnumMod  { left, right, .. } => { write!(f, "FixnumMod {left}, {right}")?; },
                    Insn::FixnumEq   { left, right, .. } => { write!(f, "FixnumEq {left}, {right}")?; },
                    Insn::FixnumNeq  { left, right, .. } => { write!(f, "FixnumNeq {left}, {right}")?; },
                    Insn::FixnumLt   { left, right, .. } => { write!(f, "FixnumLt {left}, {right}")?; },
                    Insn::FixnumLe   { left, right, .. } => { write!(f, "FixnumLe {left}, {right}")?; },
                    Insn::FixnumGt   { left, right, .. } => { write!(f, "FixnumGt {left}, {right}")?; },
                    Insn::FixnumGe   { left, right, .. } => { write!(f, "FixnumGe {left}, {right}")?; },
                    Insn::GuardType { val, guard_type, .. } => { write!(f, "GuardType {val}, {guard_type}")?; },
                    Insn::PatchPoint(invariant) => { write!(f, "PatchPoint {invariant:}")?; },
                    insn => { write!(f, "{insn:?}")?; }
                }
                writeln!(f, "")?;
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone)]
pub struct FrameState {
    iseq: IseqPtr,
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

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub struct FrameStateId(pub usize);

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
        FrameState { iseq, pc: 0 as *const VALUE, stack: vec![], locals: vec![] }
    }

    /// Get the number of stack operands
    pub fn stack_size(&self) -> usize {
        self.stack.len()
    }

    /// Iterate over all stack slots
    pub fn stack(&self) -> Iter<InsnId> {
        self.stack.iter()
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

    /// Get a stack operand at idx
    fn stack_opnd(&self, idx: usize) -> Result<InsnId, ParseError> {
        match self.stack.get(self.stack.len() - idx - 1) {
            Some(&opnd) => Ok(opnd),
            _ => Err(ParseError::StackUnderflow(self.clone())),
        }
    }

    /// Set a stack operand at idx
    fn stack_setn(&mut self, idx: usize, opnd: InsnId) {
        let idx = self.stack.len() - idx - 1;
        self.stack[idx] = opnd;
    }

    fn setlocal(&mut self, ep_offset: u32, opnd: InsnId) {
        let idx = ep_offset_to_local_idx(self.iseq, ep_offset);
        self.locals[idx] = opnd;
    }

    fn getlocal(&mut self, ep_offset: u32) -> InsnId {
        let idx = ep_offset_to_local_idx(self.iseq, ep_offset);
        self.locals[idx]
    }

    fn as_args(&self) -> Vec<InsnId> {
        self.locals.iter().chain(self.stack.iter()).map(|op| op.clone()).collect()
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
        let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx.into()) };

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

#[derive(Debug)]
pub enum ParseError {
    StackUnderflow(FrameState),
    UnknownOpcode(String),
}

fn num_lead_params(iseq: *const rb_iseq_t) -> usize {
    let result = unsafe { rb_get_iseq_body_param_lead_num(iseq) };
    assert!(result >= 0, "Can't have negative # of parameters");
    result as usize
}

/// Return the number of locals in the current ISEQ (includes parameters)
fn num_locals(iseq: *const rb_iseq_t) -> usize {
    (unsafe { get_iseq_body_local_table_size(iseq) }) as usize
}

/// Compile ISEQ into High-level IR
pub fn iseq_to_hir(iseq: *const rb_iseq_t) -> Result<Function, ParseError> {
    let mut fun = Function::new(iseq);
    // Compute a map of PC->Block by finding jump targets
    let jump_targets = compute_jump_targets(iseq);
    let mut insn_idx_to_block = HashMap::new();
    for insn_idx in jump_targets {
        if insn_idx == 0 {
            todo!("Separate entry block for param/self/...");
        }
        insn_idx_to_block.insert(insn_idx, fun.new_block());
    }

    // Iteratively fill out basic blocks using a queue
    // TODO(max): Basic block arguments at edges
    let mut queue = std::collections::VecDeque::new();
    let mut entry_state = FrameState::new(iseq);
    for idx in 0..num_locals(iseq) {
        if idx < num_lead_params(iseq) {
            entry_state.locals.push(fun.push_insn(fun.entry_block, Insn::Param { idx }));
        } else {
            entry_state.locals.push(fun.push_insn(fun.entry_block, Insn::Const { val: Const::Value(Qnil) }));
        }
    }
    queue.push_back((entry_state, fun.entry_block, /*insn_idx=*/0 as u32));

    let mut visited = HashSet::new();

    let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
    let payload = get_or_create_iseq_payload(iseq);
    while let Some((incoming_state, block, mut insn_idx)) = queue.pop_front() {
        if visited.contains(&block) { continue; }
        visited.insert(block);
        let mut state = if insn_idx == 0 { incoming_state.clone() } else {
            let mut result = FrameState::new(iseq);
            let mut idx = 0;
            for _ in 0..incoming_state.locals.len() {
                result.locals.push(fun.push_insn(block, Insn::Param { idx }));
                idx += 1;
            }
            for _ in incoming_state.stack {
                result.stack.push(fun.push_insn(block, Insn::Param { idx }));
                idx += 1;
            }
            result
        };
        while insn_idx < iseq_size {
            // Get the current pc and opcode
            let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx.into()) };
            state.pc = pc;
            let exit_state = fun.push_frame_state(state.clone());
            fun.push_insn(block, Insn::Snapshot { state: exit_state });

            // try_into() call below is unfortunate. Maybe pick i32 instead of usize for opcodes.
            let opcode: u32 = unsafe { rb_iseq_opcode_at_pc(iseq, pc) }
                .try_into()
                .unwrap();
            // Preserve the actual index for the instruction being compiled
            let current_insn_idx = insn_idx;
            // Move to the next instruction to compile
            insn_idx += insn_len(opcode as usize);

            // Push a FixnumXxx instruction if profiled operand types are fixnums
            macro_rules! push_fixnum_insn {
                ($insn:ident, $method_name:expr, $bop:ident$(, $key:ident: $value:expr)?) => {
                    if payload.have_two_fixnums(current_insn_idx as usize) {
                        fun.push_insn(block, Insn::PatchPoint(Invariant::BOPRedefined { klass: INTEGER_REDEFINED_OP_FLAG, bop: $bop }));
                        let (left, right) = guard_two_fixnums(&mut state, exit_state, &mut fun, block)?;
                        state.stack_push(fun.push_insn(block, Insn::$insn { left, right$(, $key: $value)? }));
                    } else {
                        let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                        let right = state.stack_pop()?;
                        let left = state.stack_pop()?;
                        state.stack_push(fun.push_insn(block, Insn::SendWithoutBlock { self_val: left, call_info: CallInfo { method_name: $method_name.into() }, cd, args: vec![right], state: exit_state }));
                    }
                };
            }

            match opcode {
                YARVINSN_nop => {},
                YARVINSN_putnil => { state.stack_push(fun.push_insn(block, Insn::Const { val: Const::Value(Qnil) })); },
                YARVINSN_putobject => { state.stack_push(fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) })); },
                YARVINSN_putstring | YARVINSN_putchilledstring => {
                    // TODO(max): Do something different for chilled string
                    let val = fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) });
                    let insn_id = fun.push_insn(block, Insn::StringCopy { val });
                    state.stack_push(insn_id);
                }
                YARVINSN_putself => { state.stack_push(fun.push_insn(block, Insn::PutSelf)); }
                YARVINSN_intern => {
                    let val = state.stack_pop()?;
                    let insn_id = fun.push_insn(block, Insn::StringIntern { val });
                    state.stack_push(insn_id);
                }
                YARVINSN_newarray => {
                    let count = get_arg(pc, 0).as_usize();
                    let array = fun.push_insn(block, Insn::NewArray { count });
                    for idx in (0..count).rev() {
                        fun.push_insn(block, Insn::ArraySet { array, idx, val: state.stack_pop()? });
                    }
                    state.stack_push(array);
                }
                YARVINSN_duparray => {
                    let val = fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) });
                    let insn_id = fun.push_insn(block, Insn::ArrayDup { val });
                    state.stack_push(insn_id);
                }
                YARVINSN_putobject_INT2FIX_0_ => {
                    state.stack_push(fun.push_insn(block, Insn::Const { val: Const::Value(VALUE::fixnum_from_usize(0)) }));
                }
                YARVINSN_putobject_INT2FIX_1_ => {
                    state.stack_push(fun.push_insn(block, Insn::Const { val: Const::Value(VALUE::fixnum_from_usize(1)) }));
                }
                YARVINSN_defined => {
                    let op_type = get_arg(pc, 0).as_usize();
                    let obj = get_arg(pc, 0);
                    let pushval = get_arg(pc, 0);
                    let v = state.stack_pop()?;
                    state.stack_push(fun.push_insn(block, Insn::Defined { op_type, obj, pushval, v }));
                }
                YARVINSN_opt_getconstant_path => {
                    let ic = get_arg(pc, 0).as_ptr::<u8>();
                    state.stack_push(fun.push_insn(block, Insn::GetConstantPath { ic }));
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
                        target: BranchEdge { target, args: state.as_args() }
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
                        target: BranchEdge { target, args: state.as_args() }
                    });
                    queue.push_back((state.clone(), target, target_idx));
                }
                YARVINSN_jump => {
                    let offset = get_arg(pc, 0).as_i64();
                    // TODO(max): Check interrupts
                    let target_idx = insn_idx_at_offset(insn_idx, offset);
                    let target = insn_idx_to_block[&target_idx];
                    let _branch_id = fun.push_insn(block, Insn::Jump(
                        BranchEdge { target, args: state.as_args() }
                    ));
                    queue.push_back((state.clone(), target, target_idx));
                    break;  // Don't enqueue the next block as a successor
                }
                YARVINSN_opt_nil_p => {
                    let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                    let recv = state.stack_pop()?;
                    state.stack_push(fun.push_insn(block, Insn::SendWithoutBlock { self_val: recv, call_info: CallInfo { method_name: "nil?".into() }, cd, args: vec![], state: exit_state }));
                }
                YARVINSN_getlocal_WC_0 => {
                    let ep_offset = get_arg(pc, 0).as_u32();
                    let val = state.getlocal(ep_offset);
                    state.stack_push(val);
                }
                YARVINSN_setlocal_WC_0 => {
                    let ep_offset = get_arg(pc, 0).as_u32();
                    let val = state.stack_pop()?;
                    state.setlocal(ep_offset, val);
                }
                YARVINSN_pop => { state.stack_pop()?; }
                YARVINSN_dup => { state.stack_push(state.stack_top()?); }
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

                YARVINSN_opt_plus | YARVINSN_zjit_opt_plus => {
                    push_fixnum_insn!(FixnumAdd, "+", BOP_PLUS, state: exit_state);
                }
                YARVINSN_opt_minus | YARVINSN_zjit_opt_minus => {
                    push_fixnum_insn!(FixnumSub, "-", BOP_MINUS, state: exit_state);
                }
                YARVINSN_opt_mult | YARVINSN_zjit_opt_mult => {
                    push_fixnum_insn!(FixnumMult, "*", BOP_MULT, state: exit_state);
                }
                YARVINSN_opt_div | YARVINSN_zjit_opt_div => {
                    push_fixnum_insn!(FixnumDiv, "/", BOP_DIV, state: exit_state);
                }
                YARVINSN_opt_mod | YARVINSN_zjit_opt_mod => {
                    push_fixnum_insn!(FixnumMod, "%", BOP_MOD, state: exit_state);
                }

                YARVINSN_opt_eq | YARVINSN_zjit_opt_eq => {
                    push_fixnum_insn!(FixnumEq, "==", BOP_EQ);
                }
                YARVINSN_opt_neq | YARVINSN_zjit_opt_neq => {
                    push_fixnum_insn!(FixnumNeq, "!=", BOP_NEQ);
                }
                YARVINSN_opt_lt | YARVINSN_zjit_opt_lt => {
                    push_fixnum_insn!(FixnumLt, "<", BOP_LT);
                }
                YARVINSN_opt_le | YARVINSN_zjit_opt_le => {
                    push_fixnum_insn!(FixnumLe, "<=", BOP_LE);
                }
                YARVINSN_opt_gt | YARVINSN_zjit_opt_gt => {
                    push_fixnum_insn!(FixnumGt, ">", BOP_GT);
                }
                YARVINSN_opt_ge | YARVINSN_zjit_opt_ge => {
                    push_fixnum_insn!(FixnumGe, ">==", BOP_GE);
                }
                YARVINSN_opt_ltlt => {
                    let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                    let right = state.stack_pop()?;
                    let left = state.stack_pop()?;
                    state.stack_push(fun.push_insn(block, Insn::SendWithoutBlock { self_val: left, call_info: CallInfo { method_name: "<<".into() }, cd, args: vec![right], state: exit_state }));
                }
                YARVINSN_opt_aset => {
                    let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                    let set = state.stack_pop()?;
                    let obj = state.stack_pop()?;
                    let recv = state.stack_pop()?;
                    fun.push_insn(block, Insn::SendWithoutBlock { self_val: recv, call_info: CallInfo { method_name: "[]=".into() }, cd, args: vec![obj, set], state: exit_state });
                    state.stack_push(set);
                }

                YARVINSN_leave => {
                    fun.push_insn(block, Insn::Return { val: state.stack_pop()? });
                    break;  // Don't enqueue the next block as a successor
                }

                YARVINSN_opt_send_without_block => {
                    let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                    let call_info = unsafe { rb_get_call_data_ci(cd) };
                    let argc = unsafe { vm_ci_argc((*cd).ci) };


                    let method_name = unsafe {
                        let mid = rb_vm_ci_mid(call_info);
                        cstr_to_rust_string(rb_id2name(mid)).unwrap_or_else(|| "<unknown>".to_owned())
                    };
                    let mut args = vec![];
                    for _ in 0..argc {
                        args.push(state.stack_pop()?);
                    }
                    args.reverse();

                    let recv = state.stack_pop()?;
                    state.stack_push(fun.push_insn(block, Insn::SendWithoutBlock { self_val: recv, call_info: CallInfo { method_name }, cd, args, state: exit_state }));
                }
                YARVINSN_send => {
                    let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                    let blockiseq: IseqPtr = get_arg(pc, 1).as_iseq();
                    let call_info = unsafe { rb_get_call_data_ci(cd) };
                    let argc = unsafe { vm_ci_argc((*cd).ci) };

                    let method_name = unsafe {
                        let mid = rb_vm_ci_mid(call_info);
                        cstr_to_rust_string(rb_id2name(mid)).unwrap_or_else(|| "<unknown>".to_owned())
                    };
                    let mut args = vec![];
                    for _ in 0..argc {
                        args.push(state.stack_pop()?);
                    }
                    args.reverse();

                    let recv = state.stack_pop()?;
                    state.stack_push(fun.push_insn(block, Insn::Send { self_val: recv, call_info: CallInfo { method_name }, cd, blockiseq, args, state: exit_state }));
                }
                _ => return Err(ParseError::UnknownOpcode(insn_name(opcode as usize))),
            }

            if insn_idx_to_block.contains_key(&insn_idx) {
                let target = insn_idx_to_block[&insn_idx];
                fun.push_insn(block, Insn::Jump(BranchEdge { target, args: state.as_args() }));
                queue.push_back((state, target, insn_idx));
                break;  // End the block
            }
        }
    }

    fun.infer_types();

    match get_option!(dump_hir) {
        Some(DumpHIR::WithoutSnapshot) => println!("HIR:\n{}", FunctionPrinter::without_snapshot(&fun)),
        Some(DumpHIR::All) => println!("HIR:\n{}", FunctionPrinter::with_snapshot(&fun)),
        Some(DumpHIR::Raw) => println!("HIR:\n{:#?}", &fun),
        None => {},
    }

    Ok(fun)
}

/// Generate guards for two fixnum outputs
fn guard_two_fixnums(state: &mut FrameState, exit_state: FrameStateId, fun: &mut Function, block: BlockId) -> Result<(InsnId, InsnId), ParseError> {
    let left = fun.push_insn(block, Insn::GuardType { val: state.stack_opnd(1)?, guard_type: Fixnum, state: exit_state });
    let right = fun.push_insn(block, Insn::GuardType { val: state.stack_opnd(0)?, guard_type: Fixnum, state: exit_state });

    // Pop operands after guards for side exits
    state.stack_pop()?;
    state.stack_pop()?;

    Ok((left, right))
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
    fn test_find_const_returns_target() {
        let mut uf = UnionFind::new();
        uf.make_equal_to(3, 4);
        assert_eq!(uf.find_const(3usize), 4);
    }

    #[test]
    fn test_find_const_returns_transitive_target() {
        let mut uf = UnionFind::new();
        uf.make_equal_to(3, 4);
        uf.make_equal_to(4, 5);
        assert_eq!(uf.find_const(3usize), 5);
        assert_eq!(uf.find_const(4usize), 5);
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
        let exit = function.new_block();
        function.push_insn(entry, Insn::Jump(BranchEdge { target: exit, args: vec![] }));
        let val = function.push_insn(entry, Insn::Const { val: Const::Value(Qnil) });
        function.push_insn(entry, Insn::Return { val });
        assert_eq!(function.rpo(), vec![entry, exit]);
    }

    #[test]
    fn diamond_iftrue() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let side = function.new_block();
        let exit = function.new_block();
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
        let side = function.new_block();
        let exit = function.new_block();
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
        assert_bit_equal(function.infer_type(val), types::NilClassExact);
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
            let param = function.push_insn(function.entry_block, Insn::PutSelf);
            let val = function.push_insn(function.entry_block, Insn::Test { val: param });
            function.infer_types();
            assert_bit_equal(function.type_of(val), types::CBool);
        });
    }

    #[test]
    fn newarray() {
        let mut function = Function::new(std::ptr::null());
        let val = function.push_insn(function.entry_block, Insn::NewArray { count: 0 });
        assert_bit_equal(function.infer_type(val), types::ArrayExact);
    }

    #[test]
    fn arraydup() {
        let mut function = Function::new(std::ptr::null());
        let arr = function.push_insn(function.entry_block, Insn::NewArray { count: 0 });
        let val = function.push_insn(function.entry_block, Insn::ArrayDup { val: arr });
        assert_bit_equal(function.infer_type(val), types::ArrayExact);
    }

    #[test]
    fn diamond_iffalse_merge_fixnum() {
        let mut function = Function::new(std::ptr::null());
        let entry = function.entry_block;
        let side = function.new_block();
        let exit = function.new_block();
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
        let side = function.new_block();
        let exit = function.new_block();
        let v0 = function.push_insn(side, Insn::Const { val: Const::Value(Qtrue) });
        function.push_insn(side, Insn::Jump(BranchEdge { target: exit, args: vec![v0] }));
        let val = function.push_insn(entry, Insn::Const { val: Const::CBool(false) });
        function.push_insn(entry, Insn::IfFalse { val, target: BranchEdge { target: side, args: vec![] } });
        let v1 = function.push_insn(entry, Insn::Const { val: Const::Value(Qfalse) });
        function.push_insn(entry, Insn::Jump(BranchEdge { target: exit, args: vec![v1] }));
        let param = function.push_insn(exit, Insn::Param { idx: 0 });
        crate::cruby::with_rubyvm(|| {
            function.infer_types();
            assert_bit_equal(function.type_of(param), types::TrueClassExact.union(types::FalseClassExact));
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
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq(method));
        let function = iseq_to_hir(iseq).unwrap();
        assert_function_hir(function, hir);
    }

    #[track_caller]
    pub fn assert_function_hir(function: Function, expected_hir: Expect) {
        let actual_hir = format!("{}", FunctionPrinter::without_snapshot(&function));
        expected_hir.assert_eq(&actual_hir);
    }

    #[test]
    fn test_putobject() {
        eval("def test = 123");
        assert_method_hir("test", expect![[r#"
            bb0():
              v1:Fixnum[123] = Const Value(123)
              Return v1
        "#]]);
    }

    #[test]
    fn test_new_array() {
        eval("def test = []");
        assert_method_hir("test", expect![[r#"
            bb0():
              v1:ArrayExact = NewArray 0
              Return v1
        "#]]);
    }

    #[test]
    fn test_array_dup() {
        eval("def test = [1, 2, 3]");
        assert_method_hir("test", expect![[r#"
            bb0():
              v1:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v2:ArrayExact = ArrayDup v1
              Return v2
        "#]]);
    }

    // TODO(max): Test newhash when we have it

    #[test]
    fn test_string_copy() {
        eval("def test = \"hello\"");
        assert_method_hir("test", expect![[r#"
            bb0():
              v1:StringExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v2:StringExact = StringCopy { val: InsnId(1) }
              Return v2
        "#]]);
    }

    #[test]
    fn test_bignum() {
        eval("def test = 999999999999999999999999999999999999");
        assert_method_hir("test", expect![[r#"
            bb0():
              v1:Bignum[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              Return v1
        "#]]);
    }

    #[test]
    fn test_flonum() {
        eval("def test = 1.5");
        assert_method_hir("test", expect![[r#"
            bb0():
              v1:Flonum[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              Return v1
        "#]]);
    }

    #[test]
    fn test_heap_float() {
        eval("def test = 1.7976931348623157e+308");
        assert_method_hir("test", expect![[r#"
            bb0():
              v1:HeapFloat[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              Return v1
        "#]]);
    }

    #[test]
    fn test_static_sym() {
        eval("def test = :foo");
        assert_method_hir("test", expect![[r#"
            bb0():
              v1:StaticSymbol[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              Return v1
        "#]]);
    }

    #[test]
    fn test_opt_plus() {
        eval("def test = 1+2");
        assert_method_hir("test", expect![[r#"
            bb0():
              v1:Fixnum[1] = Const Value(1)
              v3:Fixnum[2] = Const Value(2)
              v5:BasicObject = SendWithoutBlock v1, :+, v3
              Return v5
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
        assert_method_hir("test", expect![[r#"
            bb0():
              v0:NilClassExact = Const Value(nil)
              v2:Fixnum[1] = Const Value(1)
              Return v2
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
        assert_method_hir("test", expect![[r#"
            bb0(v0:BasicObject):
              v3:CBool = Test v0
              IfFalse v3, bb1(v0)
              v6:Fixnum[3] = Const Value(3)
              Return v6
            bb1(v9:BasicObject):
              v11:Fixnum[4] = Const Value(4)
              Return v11
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
            bb0(v0:BasicObject):
              v1:NilClassExact = Const Value(nil)
              v4:CBool = Test v0
              IfFalse v4, bb1(v0, v1)
              v7:Fixnum[3] = Const Value(3)
              Jump bb2(v0, v7)
            bb1(v11:BasicObject, v12:NilClassExact):
              v14:Fixnum[4] = Const Value(4)
              Jump bb2(v11, v14)
            bb2(v17:BasicObject, v18:Fixnum):
              Return v18
        "#]]);
    }

    #[test]
    fn test_opt_plus_fixnum() {
        eval("
            def test(a, b) = a + b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir("test", expect![[r#"
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
              v6:Fixnum = GuardType v0, Fixnum
              v7:Fixnum = GuardType v1, Fixnum
              v8:Fixnum = FixnumAdd v6, v7
              Return v8
        "#]]);
    }

    #[test]
    fn test_opt_minus_fixnum() {
        eval("
            def test(a, b) = a - b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir("test", expect![[r#"
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MINUS)
              v6:Fixnum = GuardType v0, Fixnum
              v7:Fixnum = GuardType v1, Fixnum
              v8:Fixnum = FixnumSub v6, v7
              Return v8
        "#]]);
    }

    #[test]
    fn test_opt_mult_fixnum() {
        eval("
            def test(a, b) = a * b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir("test", expect![[r#"
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MULT)
              v6:Fixnum = GuardType v0, Fixnum
              v7:Fixnum = GuardType v1, Fixnum
              v8:Fixnum = FixnumMult v6, v7
              Return v8
        "#]]);
    }

    #[test]
    fn test_opt_div_fixnum() {
        eval("
            def test(a, b) = a / b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir("test", expect![[r#"
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_DIV)
              v6:Fixnum = GuardType v0, Fixnum
              v7:Fixnum = GuardType v1, Fixnum
              v8:Fixnum = FixnumDiv v6, v7
              Return v8
        "#]]);
    }

    #[test]
    fn test_opt_mod_fixnum() {
        eval("
            def test(a, b) = a % b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir("test", expect![[r#"
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MOD)
              v6:Fixnum = GuardType v0, Fixnum
              v7:Fixnum = GuardType v1, Fixnum
              v8:Fixnum = FixnumMod v6, v7
              Return v8
        "#]]);
    }

    #[test]
    fn test_opt_eq_fixnum() {
        eval("
            def test(a, b) = a == b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir("test", expect![[r#"
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
              v6:Fixnum = GuardType v0, Fixnum
              v7:Fixnum = GuardType v1, Fixnum
              v8:BoolExact = FixnumEq v6, v7
              Return v8
        "#]]);
    }

    #[test]
    fn test_opt_neq_fixnum() {
        eval("
            def test(a, b) = a != b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir("test", expect![[r#"
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_NEQ)
              v6:Fixnum = GuardType v0, Fixnum
              v7:Fixnum = GuardType v1, Fixnum
              v8:BoolExact = FixnumNeq v6, v7
              Return v8
        "#]]);
    }

    #[test]
    fn test_opt_lt_fixnum() {
        eval("
            def test(a, b) = a < b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir("test", expect![[r#"
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LT)
              v6:Fixnum = GuardType v0, Fixnum
              v7:Fixnum = GuardType v1, Fixnum
              v8:BoolExact = FixnumLt v6, v7
              Return v8
        "#]]);
    }

    #[test]
    fn test_opt_le_fixnum() {
        eval("
            def test(a, b) = a <= b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir("test", expect![[r#"
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LE)
              v6:Fixnum = GuardType v0, Fixnum
              v7:Fixnum = GuardType v1, Fixnum
              v8:BoolExact = FixnumLe v6, v7
              Return v8
        "#]]);
    }

    #[test]
    fn test_opt_gt_fixnum() {
        eval("
            def test(a, b) = a > b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir("test", expect![[r#"
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_GT)
              v6:Fixnum = GuardType v0, Fixnum
              v7:Fixnum = GuardType v1, Fixnum
              v8:BoolExact = FixnumGt v6, v7
              Return v8
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
            bb0():
              v0:NilClassExact = Const Value(nil)
              v1:NilClassExact = Const Value(nil)
              v3:Fixnum[0] = Const Value(0)
              v6:Fixnum[10] = Const Value(10)
              Jump bb2(v3, v6)
            bb2(v10:Fixnum, v11:Fixnum):
              v14:Fixnum[0] = Const Value(0)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_GT)
              v17:Fixnum = GuardType v11, Fixnum
              v18:Fixnum[0] = GuardType v14, Fixnum
              v19:BoolExact = FixnumGt v17, v18
              v21:CBool = Test v19
              IfTrue v21, bb1(v10, v11)
              v24:NilClassExact = Const Value(nil)
              Return v10
            bb1(v29:Fixnum, v30:Fixnum):
              v33:Fixnum[1] = Const Value(1)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
              v36:Fixnum = GuardType v29, Fixnum
              v37:Fixnum[1] = GuardType v33, Fixnum
              v38:Fixnum = FixnumAdd v36, v37
              v42:Fixnum[1] = Const Value(1)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MINUS)
              v45:Fixnum = GuardType v30, Fixnum
              v46:Fixnum[1] = GuardType v42, Fixnum
              v47:Fixnum = FixnumSub v45, v46
              Jump bb2(v38, v47)
        "#]]);
    }

    #[test]
    fn test_opt_ge_fixnum() {
        eval("
            def test(a, b) = a >= b
            test(1, 2); test(1, 2)
        ");
        assert_method_hir("test", expect![[r#"
            bb0(v0:BasicObject, v1:BasicObject):
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_GE)
              v6:Fixnum = GuardType v0, Fixnum
              v7:Fixnum = GuardType v1, Fixnum
              v8:BoolExact = FixnumGe v6, v7
              Return v8
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
            bb0():
              v0:NilClassExact = Const Value(nil)
              v2:TrueClassExact = Const Value(true)
              v6:CBool[true] = Test v2
              IfFalse v6, bb1(v2)
              v9:Fixnum[3] = Const Value(3)
              Return v9
            bb1(v12):
              v14 = Const Value(4)
              Return v14
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
            test
        ");
        assert_method_hir("test",  expect![[r#"
            bb0():
              v1:BasicObject = PutSelf
              v3:Fixnum[2] = Const Value(2)
              v5:Fixnum[3] = Const Value(3)
              v7:BasicObject = SendWithoutBlock v1, :bar, v3, v5
              Return v7
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
        assert_method_hir("test",  expect![[r#"
            bb0(v0:BasicObject):
              v3:BasicObject = Send v0, 0x1000, :each
              Return v3
        "#]]);
    }

    #[test]
    fn different_objects_get_addresses() {
        eval("def test = unknown_method([0], [1], '2', '2')");

        // The 2 string literals have the same address because they're deduped.
        assert_method_hir("test",  expect![[r#"
            bb0():
              v1:BasicObject = PutSelf
              v3:ArrayExact[VALUE(0x1000)] = Const Value(VALUE(0x1000))
              v4:ArrayExact = ArrayDup v3
              v6:ArrayExact[VALUE(0x1008)] = Const Value(VALUE(0x1008))
              v7:ArrayExact = ArrayDup v6
              v9:StringExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
              v10:StringExact = StringCopy { val: InsnId(9) }
              v12:StringExact[VALUE(0x1010)] = Const Value(VALUE(0x1010))
              v13:StringExact = StringCopy { val: InsnId(12) }
              v15:BasicObject = SendWithoutBlock v1, :unknown_method, v4, v7, v10, v13
              Return v15
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
        let iseq = crate::cruby::with_rubyvm(|| get_method_iseq(method));
        let mut function = iseq_to_hir(iseq).unwrap();
        function.optimize();
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
            bb0():
              v0:NilClassExact = Const Value(nil)
              v2:TrueClassExact = Const Value(true)
              v17:CBool[true] = Const CBool(true)
              v9:Fixnum[3] = Const Value(3)
              Return v9
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
            bb0():
              v0:NilClassExact = Const Value(nil)
              v2:FalseClassExact = Const Value(false)
              v17:CBool[false] = Const CBool(false)
              Jump bb1(v2)
            bb1(v12:FalseClassExact):
              v14:Fixnum[4] = Const Value(4)
              Return v14
            "#]]);
    }

    #[test]
    fn test_fold_fixnum_add() {
        eval("
            def test
                1 + 2 + 3
            end
            test; test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            bb0():
              v1:Fixnum[1] = Const Value(1)
              v3:Fixnum[2] = Const Value(2)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
              v18:Fixnum[3] = Const Value(3)
              v10:Fixnum[3] = Const Value(3)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
              v19:Fixnum[6] = Const Value(6)
              Return v19
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
            test; test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            bb0():
              v1:Fixnum[1] = Const Value(1)
              v3:Fixnum[2] = Const Value(2)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LT)
              v20:TrueClassExact = Const Value(true)
              v21:CBool[true] = Const CBool(true)
              v13:Fixnum[3] = Const Value(3)
              Return v13
            "#]]);
    }

    #[test]
    fn test_fold_fixnum_eq_true() {
        eval("
            def test
              if 1 == 2
                3
              else
                4
              end
            end
            test; test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            bb0():
              v1:Fixnum[1] = Const Value(1)
              v3:Fixnum[2] = Const Value(2)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
              v20:FalseClassExact = Const Value(false)
              v21:CBool[false] = Const CBool(false)
              Jump bb1()
            bb1():
              v17:Fixnum[4] = Const Value(4)
              Return v17
            "#]]);
    }

    #[test]
    fn test_fold_fixnum_eq_false() {
        eval("
            def test
              if 2 == 2
                3
              else
                4
              end
            end
            test; test
        ");
        assert_optimized_method_hir("test", expect![[r#"
            bb0():
              v1:Fixnum[2] = Const Value(2)
              v3:Fixnum[2] = Const Value(2)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
              v20:TrueClassExact = Const Value(true)
              v21:CBool[true] = Const CBool(true)
              v13:Fixnum[3] = Const Value(3)
              Return v13
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
            bb0(v0:BasicObject):
              v3:Fixnum[1] = Const Value(1)
              PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
              v6:Fixnum = GuardType v0, Fixnum
              v8:Fixnum = FixnumAdd v6, v3
              Return v8
            "#]]);
    }
}
