use std::hash::{Hash, Hasher};
use std::collections::HashMap;
use super::{Insn, InsnId};

/// Wrapper for using Insn as a HashMap key with value numbering semantics
#[derive(Clone, Debug)]
pub struct ValueNumber(Insn);

impl ValueNumber {
    /// Try to create a key for value numbering. Returns None for non-numberable instructions.
    pub fn new(insn: &Insn) -> Option<Self> {
        match insn {
                        Insn::FixnumAdd { .. } |
            Insn::FixnumSub { .. } |
            Insn::FixnumMult { .. } |
            Insn::FixnumEq { .. } |
            Insn::FixnumNeq { .. } |
            Insn::FixnumLt { .. } |
            Insn::FixnumLe { .. } |
            Insn::FixnumGt { .. } |
            Insn::FixnumGe { .. } |
            Insn::LoadField { .. } |
            Insn::UnboxFixnum { .. } |
            Insn::BoxBool { .. } |
            Insn::Test { .. } |
            Insn::IsNil { .. } |
            Insn::IsBitEqual { .. } |
            Insn::IsBitNotEqual { .. } => Some(ValueNumber(insn.clone())),
            _ => None, // Not numberable
        }
    }
}

impl Hash for ValueNumber {
    fn hash<H: Hasher>(&self, hasher: &mut H) {
        use std::mem::discriminant;

        match &self.0 {
            Insn::FixnumAdd { left, right, .. } => {
            discriminant(&self.0).hash(hasher);
            left.hash(hasher);
                right.hash(hasher);
        },
            Insn::FixnumSub { left, right, .. } => {
            discriminant(&self.0).hash(hasher);
            left.hash(hasher);
                right.hash(hasher);
        },
            Insn::FixnumMult { left, right, .. } => {
            discriminant(&self.0).hash(hasher);
            left.hash(hasher);
                right.hash(hasher);
        },
            Insn::FixnumEq { left, right, .. } => {
            discriminant(&self.0).hash(hasher);
            left.hash(hasher);
                right.hash(hasher);
        },
            Insn::FixnumNeq { left, right, .. } => {
            discriminant(&self.0).hash(hasher);
            left.hash(hasher);
                right.hash(hasher);
        },
            Insn::FixnumLt { left, right, .. } => {
            discriminant(&self.0).hash(hasher);
            left.hash(hasher);
                right.hash(hasher);
        },
            Insn::FixnumLe { left, right, .. } => {
            discriminant(&self.0).hash(hasher);
            left.hash(hasher);
                right.hash(hasher);
        },
            Insn::FixnumGt { left, right, .. } => {
            discriminant(&self.0).hash(hasher);
            left.hash(hasher);
                right.hash(hasher);
        },
            Insn::FixnumGe { left, right, .. } => {
            discriminant(&self.0).hash(hasher);
            left.hash(hasher);
                right.hash(hasher);
        },
            Insn::LoadField { recv, offset, .. } => {
            discriminant(&self.0).hash(hasher);
            recv.hash(hasher);
                offset.hash(hasher);
        },
            Insn::UnboxFixnum { val, .. } => {
            discriminant(&self.0).hash(hasher);
            val.hash(hasher);
        },
            Insn::BoxBool { val, .. } => {
            discriminant(&self.0).hash(hasher);
            val.hash(hasher);
        },
            Insn::Test { val, .. } => {
            discriminant(&self.0).hash(hasher);
            val.hash(hasher);
        },
            Insn::IsNil { val, .. } => {
            discriminant(&self.0).hash(hasher);
            val.hash(hasher);
        },
            Insn::IsBitEqual { left, right, .. } => {
            discriminant(&self.0).hash(hasher);
            left.hash(hasher);
                right.hash(hasher);
        },
            Insn::IsBitNotEqual { left, right, .. } => {
            discriminant(&self.0).hash(hasher);
            left.hash(hasher);
                right.hash(hasher);
        },
            _ => unreachable!("ValueNumber::new should prevent non-numberable instructions"),
        }
    }
}

impl PartialEq for ValueNumber {
    fn eq(&self, other: &Self) -> bool {
        match (&self.0, &other.0) {
            (Insn::FixnumAdd { left: left1, right: right1, .. },
         Insn::FixnumAdd { left: left2, right: right2, .. }) =>
            left1 == left2 && right1 == right2,
            (Insn::FixnumSub { left: left1, right: right1, .. },
         Insn::FixnumSub { left: left2, right: right2, .. }) =>
            left1 == left2 && right1 == right2,
            (Insn::FixnumMult { left: left1, right: right1, .. },
         Insn::FixnumMult { left: left2, right: right2, .. }) =>
            left1 == left2 && right1 == right2,
            (Insn::FixnumEq { left: left1, right: right1, .. },
         Insn::FixnumEq { left: left2, right: right2, .. }) =>
            left1 == left2 && right1 == right2,
            (Insn::FixnumNeq { left: left1, right: right1, .. },
         Insn::FixnumNeq { left: left2, right: right2, .. }) =>
            left1 == left2 && right1 == right2,
            (Insn::FixnumLt { left: left1, right: right1, .. },
         Insn::FixnumLt { left: left2, right: right2, .. }) =>
            left1 == left2 && right1 == right2,
            (Insn::FixnumLe { left: left1, right: right1, .. },
         Insn::FixnumLe { left: left2, right: right2, .. }) =>
            left1 == left2 && right1 == right2,
            (Insn::FixnumGt { left: left1, right: right1, .. },
         Insn::FixnumGt { left: left2, right: right2, .. }) =>
            left1 == left2 && right1 == right2,
            (Insn::FixnumGe { left: left1, right: right1, .. },
         Insn::FixnumGe { left: left2, right: right2, .. }) =>
            left1 == left2 && right1 == right2,
            (Insn::LoadField { recv: recv1, offset: offset1, .. },
         Insn::LoadField { recv: recv2, offset: offset2, .. }) =>
            recv1 == recv2 && offset1 == offset2,
            (Insn::UnboxFixnum { val: val1, .. },
         Insn::UnboxFixnum { val: val2, .. }) =>
            val1 == val2,
            (Insn::BoxBool { val: val1, .. },
         Insn::BoxBool { val: val2, .. }) =>
            val1 == val2,
            (Insn::Test { val: val1, .. },
         Insn::Test { val: val2, .. }) =>
            val1 == val2,
            (Insn::IsNil { val: val1, .. },
         Insn::IsNil { val: val2, .. }) =>
            val1 == val2,
            (Insn::IsBitEqual { left: left1, right: right1, .. },
         Insn::IsBitEqual { left: left2, right: right2, .. }) =>
            left1 == left2 && right1 == right2,
            (Insn::IsBitNotEqual { left: left1, right: right1, .. },
         Insn::IsBitNotEqual { left: left2, right: right2, .. }) =>
            left1 == left2 && right1 == right2,
            _ => false,
        }
    }
}

impl Eq for ValueNumber {}
