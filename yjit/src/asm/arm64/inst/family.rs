/// These are the top-level encodings. They're effectively the family of
/// instructions, as each instruction within those groups shares these same
/// bits (28-25).
///
/// In the documentation, you can see that some of the bits are
/// optional (e.g., x1x0 for loads and stores). We represent that here as 0100
/// since we're bitwise ORing the family into the resulting encoding.
///
/// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding?lang=en
pub enum Family {
    /// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Reserved?lang=en
    Reserved = 0b0000,

    /// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/SME-encodings?lang=en
    SMEEncodings = 0b0001,

    /// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/SVE-encodings?lang=en
    SVEEncodings = 0b0010,

    /// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Data-Processing----Immediate?lang=en
    DataProcessingImmediate = 0b1000,

    /// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Branches--Exception-Generating-and-System-instructions?lang=en
    BranchesAndSystem = 0b1010,

    /// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Loads-and-Stores?lang=en
    LoadsAndStores = 0b0100,

    /// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Data-Processing----Register?lang=en
    DataProcessingRegister = 0b0101,

    /// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Data-Processing----Scalar-Floating-Point-and-Advanced-SIMD?lang=en
    DataProcessingScalar = 0b0111
}
