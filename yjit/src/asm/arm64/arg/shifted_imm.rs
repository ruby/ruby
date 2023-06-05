/// How much to shift the immediate by.
pub enum Shift {
    LSL0 = 0b0, // no shift
    LSL12 = 0b1 // logical shift left by 12 bits
}

/// Some instructions accept a 12-bit immediate that has an optional shift
/// attached to it. This allows encoding larger values than just fit into 12
/// bits. We attempt to encode those here. If the values are too large we have
/// to bail out.
pub struct ShiftedImmediate {
    shift: Shift,
    value: u16
}

impl TryFrom<u64> for ShiftedImmediate {
    type Error = ();

    /// Attempt to convert a u64 into a BitmaskImm.
    fn try_from(value: u64) -> Result<Self, Self::Error> {
        let current = value;
        if current < 2_u64.pow(12) {
            return Ok(ShiftedImmediate { shift: Shift::LSL0, value: current as u16 });
        }

        if (current & (2_u64.pow(12) - 1) == 0) && ((current >> 12) < 2_u64.pow(12)) {
            return Ok(ShiftedImmediate { shift: Shift::LSL12, value: (current >> 12) as u16 });
        }

        Err(())
    }
}

impl From<ShiftedImmediate> for u32 {
    /// Encode a bitmask immediate into a 32-bit value.
    fn from(imm: ShiftedImmediate) -> Self {
        0
        | (((imm.shift as u32) & 1) << 12)
        | (imm.value as u32)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_no_shift() {
        let expected_value = 256;
        let result = ShiftedImmediate::try_from(expected_value);

        match result {
            Ok(ShiftedImmediate { shift: Shift::LSL0, value }) => assert_eq!(value as u64, expected_value),
            _ => panic!("Unexpected shift value")
        }
    }

    #[test]
    fn test_maximum_no_shift() {
        let expected_value = (1 << 12) - 1;
        let result = ShiftedImmediate::try_from(expected_value);

        match result {
            Ok(ShiftedImmediate { shift: Shift::LSL0, value }) => assert_eq!(value as u64, expected_value),
            _ => panic!("Unexpected shift value")
        }
    }

    #[test]
    fn test_with_shift() {
        let result = ShiftedImmediate::try_from(256 << 12);

        assert!(matches!(result, Ok(ShiftedImmediate { shift: Shift::LSL12, value: 256 })));
    }

    #[test]
    fn test_unencodable() {
        let result = ShiftedImmediate::try_from((256 << 12) + 1);
        assert!(matches!(result, Err(())));
    }
}
