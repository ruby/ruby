/// There are a lot of instructions in the AArch64 architectrue that take an
/// offset in terms of number of instructions. Usually they are jump
/// instructions or instructions that load a value relative to the current PC.
///
/// This struct is used to mark those locations instead of a generic operand in
/// order to give better clarity to the developer when reading the AArch64
/// backend code. It also helps to clarify that everything is in terms of a
/// number of instructions and not a number of bytes (i.e., the offset is the
/// number of bytes divided by 4).
#[derive(Copy, Clone)]
pub struct InstructionOffset(i32);

impl InstructionOffset {
    /// Create a new instruction offset.
    pub fn from_insns(insns: i32) -> Self {
        InstructionOffset(insns)
    }

    /// Create a new instruction offset from a number of bytes.
    pub fn from_bytes(bytes: i32) -> Self {
        assert_eq!(bytes % 4, 0, "Byte offset must be a multiple of 4");
        InstructionOffset(bytes / 4)
    }
}

impl From<i32> for InstructionOffset {
    /// Convert an i64 into an instruction offset.
    fn from(value: i32) -> Self {
        InstructionOffset(value)
    }
}

impl From<InstructionOffset> for i32 {
    /// Convert an instruction offset into a number of instructions as an i32.
    fn from(offset: InstructionOffset) -> Self {
        offset.0
    }
}

impl From<InstructionOffset> for i64 {
    /// Convert an instruction offset into a number of instructions as an i64.
    /// This is useful for when we're checking how many bits this offset fits
    /// into.
    fn from(offset: InstructionOffset) -> Self {
        offset.0.into()
    }
}
