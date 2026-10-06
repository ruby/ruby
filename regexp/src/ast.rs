//! The parse tree, ported from regparse.h. Nodes live in an arena and refer
//! to each other by index, so the rewrites done by the compiler (which in C
//! overwrite or swap whole nodes) become plain assignments.

use crate::enc::CodePoint;

pub type NodeId = usize;

pub const REPEAT_INFINITE: i32 = -1;

#[inline]
pub fn is_repeat_infinite(n: i32) -> bool {
    n == REPEAT_INFINITE
}

pub const ONIG_LAST_CODE_POINT: CodePoint = !0;

// StrNode flags
pub const NSTR_RAW: u32 = 1 << 0;
pub const NSTR_AMBIG: u32 = 1 << 1;
pub const NSTR_DONT_GET_OPT_INFO: u32 = 1 << 2;

// QtfrNode target_empty_info
pub const NQ_TARGET_ISNOT_EMPTY: i32 = 0;
pub const NQ_TARGET_IS_EMPTY: i32 = 1;
pub const NQ_TARGET_IS_EMPTY_MEM: i32 = 2;
pub const NQ_TARGET_IS_EMPTY_REC: i32 = 3;

// status bits
pub const NST_MIN_FIXED: i32 = 1 << 0;
pub const NST_MAX_FIXED: i32 = 1 << 1;
pub const NST_CLEN_FIXED: i32 = 1 << 2;
pub const NST_MARK1: i32 = 1 << 3;
pub const NST_MARK2: i32 = 1 << 4;
pub const NST_MEM_BACKREFED: i32 = 1 << 5;
pub const NST_STOP_BT_SIMPLE_REPEAT: i32 = 1 << 6;
pub const NST_RECURSION: i32 = 1 << 7;
pub const NST_CALLED: i32 = 1 << 8;
pub const NST_ADDR_FIXED: i32 = 1 << 9;
pub const NST_NAMED_GROUP: i32 = 1 << 10;
pub const NST_NAME_REF: i32 = 1 << 11;
pub const NST_IN_REPEAT: i32 = 1 << 12;
pub const NST_NEST_LEVEL: i32 = 1 << 13;
pub const NST_BY_NUMBER: i32 = 1 << 14;

// EncloseNode type
pub const ENCLOSE_MEMORY: i32 = 1 << 0;
pub const ENCLOSE_OPTION: i32 = 1 << 1;
pub const ENCLOSE_STOP_BACKTRACK: i32 = 1 << 2;
pub const ENCLOSE_CONDITION: i32 = 1 << 3;
pub const ENCLOSE_ABSENT: i32 = 1 << 4;

// anchors (regint.h)
pub const ANCHOR_BEGIN_BUF: i32 = 1 << 0;
pub const ANCHOR_BEGIN_LINE: i32 = 1 << 1;
pub const ANCHOR_BEGIN_POSITION: i32 = 1 << 2;
pub const ANCHOR_END_BUF: i32 = 1 << 3;
pub const ANCHOR_SEMI_END_BUF: i32 = 1 << 4;
pub const ANCHOR_END_LINE: i32 = 1 << 5;
pub const ANCHOR_WORD_BOUND: i32 = 1 << 6;
pub const ANCHOR_NOT_WORD_BOUND: i32 = 1 << 7;
pub const ANCHOR_WORD_BEGIN: i32 = 1 << 8;
pub const ANCHOR_WORD_END: i32 = 1 << 9;
pub const ANCHOR_PREC_READ: i32 = 1 << 10;
pub const ANCHOR_PREC_READ_NOT: i32 = 1 << 11;
pub const ANCHOR_LOOK_BEHIND: i32 = 1 << 12;
pub const ANCHOR_LOOK_BEHIND_NOT: i32 = 1 << 13;
pub const ANCHOR_ANYCHAR_STAR: i32 = 1 << 14;
pub const ANCHOR_ANYCHAR_STAR_ML: i32 = 1 << 15;
pub const ANCHOR_KEEP: i32 = 1 << 16;

pub const ANCHOR_ANYCHAR_STAR_MASK: i32 = ANCHOR_ANYCHAR_STAR | ANCHOR_ANYCHAR_STAR_ML;
pub const ANCHOR_END_BUF_MASK: i32 = ANCHOR_END_BUF | ANCHOR_SEMI_END_BUF;

// node type bits, for checks like `check_type_tree`
pub const NT_STR: i32 = 0;
pub const NT_CCLASS: i32 = 1;
pub const NT_CTYPE: i32 = 2;
pub const NT_CANY: i32 = 3;
pub const NT_BREF: i32 = 4;
pub const NT_QTFR: i32 = 5;
pub const NT_ENCLOSE: i32 = 6;
pub const NT_ANCHOR: i32 = 7;
pub const NT_LIST: i32 = 8;
pub const NT_ALT: i32 = 9;
pub const NT_CALL: i32 = 10;

#[inline]
pub const fn ntype2bit(t: i32) -> i32 {
    1 << t
}

pub const BIT_NT_STR: i32 = ntype2bit(NT_STR);
pub const BIT_NT_CCLASS: i32 = ntype2bit(NT_CCLASS);
pub const BIT_NT_CTYPE: i32 = ntype2bit(NT_CTYPE);
pub const BIT_NT_CANY: i32 = ntype2bit(NT_CANY);
pub const BIT_NT_BREF: i32 = ntype2bit(NT_BREF);
pub const BIT_NT_QTFR: i32 = ntype2bit(NT_QTFR);
pub const BIT_NT_ENCLOSE: i32 = ntype2bit(NT_ENCLOSE);
pub const BIT_NT_ANCHOR: i32 = ntype2bit(NT_ANCHOR);
pub const BIT_NT_LIST: i32 = ntype2bit(NT_LIST);
pub const BIT_NT_ALT: i32 = ntype2bit(NT_ALT);
pub const BIT_NT_CALL: i32 = ntype2bit(NT_CALL);

/// 256-bit set of single-byte codes, `BitSet` in regint.h.
#[derive(Clone, Copy, Default, PartialEq, Eq, Debug)]
pub struct BitSet(pub [u32; 8]);

pub const BITS_IN_ROOM: usize = 32;
pub const BITSET_SIZE: usize = 8;
pub const SINGLE_BYTE_SIZE: u32 = 256;

impl BitSet {
    #[inline]
    pub fn at(&self, pos: u32) -> bool {
        let pos = pos as usize;
        (self.0[pos / BITS_IN_ROOM] & (1u32 << (pos % BITS_IN_ROOM))) != 0
    }
    #[inline]
    pub fn set(&mut self, pos: u32) {
        let pos = pos as usize;
        self.0[pos / BITS_IN_ROOM] |= 1u32 << (pos % BITS_IN_ROOM);
    }
    #[inline]
    pub fn clear_bit(&mut self, pos: u32) {
        let pos = pos as usize;
        self.0[pos / BITS_IN_ROOM] &= !(1u32 << (pos % BITS_IN_ROOM));
    }
    pub fn invert(&mut self) {
        for w in self.0.iter_mut() {
            *w = !*w;
        }
    }
    pub fn inverted(&self) -> BitSet {
        let mut b = *self;
        b.invert();
        b
    }
    pub fn and(&mut self, o: &BitSet) {
        for i in 0..BITSET_SIZE {
            self.0[i] &= o.0[i];
        }
    }
    pub fn or(&mut self, o: &BitSet) {
        for i in 0..BITSET_SIZE {
            self.0[i] |= o.0[i];
        }
    }
    pub fn is_empty(&self) -> bool {
        self.0.iter().all(|&w| w == 0)
    }
    pub fn count(&self) -> u32 {
        self.0.iter().map(|w| w.count_ones()).sum()
    }
}

/// Sorted, non-overlapping code point ranges: the multi-byte part of a
/// character class (`BBuf* mbuf` in C).
pub type CodeRanges = Vec<(CodePoint, CodePoint)>;

pub const FLAG_NCCLASS_NOT: u32 = 1 << 0;

#[derive(Clone, Default, Debug)]
pub struct CClass {
    pub flags: u32,
    pub bs: BitSet,
    pub mbuf: Option<CodeRanges>,
}

impl CClass {
    #[inline]
    pub fn is_not(&self) -> bool {
        (self.flags & FLAG_NCCLASS_NOT) != 0
    }
    pub fn set_not(&mut self) {
        self.flags |= FLAG_NCCLASS_NOT;
    }
    pub fn clear_not(&mut self) {
        self.flags &= !FLAG_NCCLASS_NOT;
    }
}

const BYTES_INLINE: usize = 30;

/// The bytes of a string node. Up to `BYTES_INLINE` of them stay in the
/// node, so the short strings of most patterns need no allocation.
#[derive(Clone)]
pub enum Bytes {
    Inline(u8, [u8; BYTES_INLINE]),
    Heap(Vec<u8>),
}

impl Default for Bytes {
    fn default() -> Self {
        Bytes::Inline(0, [0; BYTES_INLINE])
    }
}

impl std::ops::Deref for Bytes {
    type Target = [u8];
    fn deref(&self) -> &[u8] {
        match self {
            Bytes::Inline(n, b) => &b[..usize::from(*n)],
            Bytes::Heap(v) => v,
        }
    }
}

impl std::fmt::Debug for Bytes {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        (**self).fmt(f)
    }
}

impl From<&[u8]> for Bytes {
    fn from(s: &[u8]) -> Self {
        let mut b = Bytes::default();
        b.extend_from_slice(s);
        b
    }
}

impl From<Vec<u8>> for Bytes {
    fn from(v: Vec<u8>) -> Self {
        Bytes::Heap(v)
    }
}

impl Bytes {
    pub fn extend_from_slice(&mut self, s: &[u8]) {
        match self {
            Bytes::Inline(n, b) if usize::from(*n) + s.len() <= BYTES_INLINE => {
                let at = usize::from(*n);
                b[at..at + s.len()].copy_from_slice(s);
                *n += s.len() as u8;
            }
            Bytes::Inline(..) => {
                let mut v = Vec::with_capacity(self.len() + s.len());
                v.extend_from_slice(self);
                v.extend_from_slice(s);
                *self = Bytes::Heap(v);
            }
            Bytes::Heap(v) => v.extend_from_slice(s),
        }
    }

    pub fn push(&mut self, c: u8) {
        self.extend_from_slice(&[c]);
    }

    pub fn truncate(&mut self, len: usize) {
        match self {
            Bytes::Inline(n, _) => *n = (*n).min(len.min(BYTES_INLINE) as u8),
            Bytes::Heap(v) => v.truncate(len),
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct StrNode {
    pub s: Bytes,
    pub flag: u32,
}

impl StrNode {
    pub fn is_raw(&self) -> bool {
        self.flag & NSTR_RAW != 0
    }
    pub fn is_ambig(&self) -> bool {
        self.flag & NSTR_AMBIG != 0
    }
    pub fn is_dont_get_opt_info(&self) -> bool {
        self.flag & NSTR_DONT_GET_OPT_INFO != 0
    }
}

#[derive(Clone, Debug)]
pub struct QtfrNode {
    pub state: i32,
    pub target: Option<NodeId>,
    pub lower: i32,
    pub upper: i32,
    pub greedy: bool,
    pub target_empty_info: i32,
    pub head_exact: Option<NodeId>,
    pub next_head_exact: Option<NodeId>,
    pub is_referred: bool,
}

impl QtfrNode {
    pub fn new(lower: i32, upper: i32, by_number: bool) -> QtfrNode {
        QtfrNode {
            state: if by_number { NST_BY_NUMBER } else { 0 },
            target: None,
            lower,
            upper,
            greedy: true,
            target_empty_info: NQ_TARGET_ISNOT_EMPTY,
            head_exact: None,
            next_head_exact: None,
            is_referred: false,
        }
    }
}

#[derive(Clone, Debug)]
pub struct EncloseNode {
    pub state: i32,
    pub typ: i32,
    pub regnum: i32,
    pub option: u32,
    pub call_addr: i32,
    pub target: Option<NodeId>,
    pub min_len: usize,
    pub max_len: usize,
    pub char_len: i32,
    pub opt_count: i32,
}

impl EncloseNode {
    pub fn new(typ: i32) -> EncloseNode {
        EncloseNode {
            state: 0,
            typ,
            regnum: 0,
            option: 0,
            call_addr: -1,
            target: None,
            min_len: 0,
            max_len: 0,
            char_len: 0,
            opt_count: 0,
        }
    }
}

#[derive(Clone, Debug)]
pub struct CallNode {
    pub state: i32,
    pub group_num: i32,
    pub name: Vec<u8>,
    pub target: Option<NodeId>,
}

#[derive(Clone, Debug)]
pub struct BRefNode {
    pub state: i32,
    pub back: Vec<i32>,
    pub nest_level: i32,
}

#[derive(Clone, Debug)]
pub struct AnchorNode {
    pub typ: i32,
    pub target: Option<NodeId>,
    pub char_len: i32,
    pub ascii_range: bool,
}

#[derive(Clone, Debug)]
pub struct CTypeNode {
    pub ctype: u32,
    pub not: bool,
    pub ascii_range: bool,
}

#[derive(Clone, Debug)]
pub enum Node {
    Str(StrNode),
    CClass(CClass),
    CType(CTypeNode),
    CAny,
    BRef(BRefNode),
    Qtfr(QtfrNode),
    Enclose(EncloseNode),
    Anchor(AnchorNode),
    List { car: NodeId, cdr: Option<NodeId> },
    Alt { car: NodeId, cdr: Option<NodeId> },
    Call(CallNode),
    /// A slot whose node was freed or moved; never reachable from the root.
    Freed,
}

impl Node {
    pub fn ntype(&self) -> i32 {
        match self {
            Node::Str(_) => NT_STR,
            Node::CClass(_) => NT_CCLASS,
            Node::CType(_) => NT_CTYPE,
            Node::CAny => NT_CANY,
            Node::BRef(_) => NT_BREF,
            Node::Qtfr(_) => NT_QTFR,
            Node::Enclose(_) => NT_ENCLOSE,
            Node::Anchor(_) => NT_ANCHOR,
            Node::List { .. } => NT_LIST,
            Node::Alt { .. } => NT_ALT,
            Node::Call(_) => NT_CALL,
            Node::Freed => panic!("freed node"),
        }
    }
}

#[derive(Default, Debug)]
pub struct Ast {
    pub nodes: Vec<Node>,
}

macro_rules! accessor {
    ($name:ident, $name_mut:ident, $variant:ident, $ty:ty) => {
        #[track_caller]
        pub fn $name(&self, id: NodeId) -> &$ty {
            match &self.nodes[id] {
                Node::$variant(x) => x,
                n => panic!(concat!("not a ", stringify!($variant), ": {:?}"), n),
            }
        }
        #[track_caller]
        pub fn $name_mut(&mut self, id: NodeId) -> &mut $ty {
            match &mut self.nodes[id] {
                Node::$variant(x) => x,
                n => panic!(concat!("not a ", stringify!($variant), ": {:?}"), n),
            }
        }
    };
}

impl Ast {
    pub fn add(&mut self, node: Node) -> NodeId {
        self.nodes.push(node);
        self.nodes.len() - 1
    }

    #[inline]
    pub fn ntype(&self, id: NodeId) -> i32 {
        self.nodes[id].ntype()
    }

    accessor!(str, str_mut, Str, StrNode);
    accessor!(cclass, cclass_mut, CClass, CClass);
    accessor!(ctype, ctype_mut, CType, CTypeNode);
    accessor!(bref, bref_mut, BRef, BRefNode);
    accessor!(qtfr, qtfr_mut, Qtfr, QtfrNode);
    accessor!(enclose, enclose_mut, Enclose, EncloseNode);
    accessor!(anchor, anchor_mut, Anchor, AnchorNode);
    accessor!(call, call_mut, Call, CallNode);

    /// `NCAR` of a list or alternation node.
    #[track_caller]
    pub fn car(&self, id: NodeId) -> NodeId {
        match self.nodes[id] {
            Node::List { car, .. } | Node::Alt { car, .. } => car,
            ref n => panic!("not a cons: {:?}", n),
        }
    }

    /// `NCDR` of a list or alternation node.
    #[track_caller]
    pub fn cdr(&self, id: NodeId) -> Option<NodeId> {
        match self.nodes[id] {
            Node::List { cdr, .. } | Node::Alt { cdr, .. } => cdr,
            ref n => panic!("not a cons: {:?}", n),
        }
    }

    #[track_caller]
    pub fn set_car(&mut self, id: NodeId, v: NodeId) {
        match &mut self.nodes[id] {
            Node::List { car, .. } | Node::Alt { car, .. } => *car = v,
            n => panic!("not a cons: {:?}", n),
        }
    }

    #[track_caller]
    pub fn set_cdr(&mut self, id: NodeId, v: Option<NodeId>) {
        match &mut self.nodes[id] {
            Node::List { cdr, .. } | Node::Alt { cdr, .. } => *cdr = v,
            n => panic!("not a cons: {:?}", n),
        }
    }

    /// The `target` of a quantifier, enclosure or anchor.
    pub fn target(&self, id: NodeId) -> Option<NodeId> {
        match &self.nodes[id] {
            Node::Qtfr(q) => q.target,
            Node::Enclose(e) => e.target,
            Node::Anchor(a) => a.target,
            Node::Call(c) => c.target,
            _ => None,
        }
    }

    pub fn new_str(&mut self, s: &[u8]) -> NodeId {
        self.add(Node::Str(StrNode { s: s.into(), flag: 0 }))
    }

    pub fn new_str_raw(&mut self, s: &[u8]) -> NodeId {
        self.add(Node::Str(StrNode { s: s.into(), flag: NSTR_RAW }))
    }

    pub fn new_empty(&mut self) -> NodeId {
        self.new_str(&[])
    }

    pub fn new_list(&mut self, car: NodeId, cdr: Option<NodeId>) -> NodeId {
        self.add(Node::List { car, cdr })
    }

    pub fn new_alt(&mut self, car: NodeId, cdr: Option<NodeId>) -> NodeId {
        self.add(Node::Alt { car, cdr })
    }

    pub fn new_anchor(&mut self, typ: i32) -> NodeId {
        self.add(Node::Anchor(AnchorNode { typ, target: None, char_len: -1, ascii_range: false }))
    }

    pub fn new_enclose(&mut self, typ: i32) -> NodeId {
        self.add(Node::Enclose(EncloseNode::new(typ)))
    }

    pub fn new_option(&mut self, option: u32) -> NodeId {
        let mut e = EncloseNode::new(ENCLOSE_OPTION);
        e.option = option;
        self.add(Node::Enclose(e))
    }

    pub fn new_quantifier(&mut self, lower: i32, upper: i32, by_number: bool) -> NodeId {
        self.add(Node::Qtfr(QtfrNode::new(lower, upper, by_number)))
    }

    pub fn new_cclass(&mut self) -> NodeId {
        self.add(Node::CClass(CClass::default()))
    }

    pub fn new_anychar(&mut self) -> NodeId {
        self.add(Node::CAny)
    }

    /// Swaps the contents of two nodes (`swap_node` in regcomp.c).
    pub fn swap(&mut self, a: NodeId, b: NodeId) {
        self.nodes.swap(a, b);
    }
}
