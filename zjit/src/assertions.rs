/// Assert that CodeBlock has the code specified with hex. In addition, if tested with
/// `cargo test --all-features`, it also checks it generates the specified disasm.
#[cfg(test)]
macro_rules! assert_disasm {
    ($cb:expr, $hex:expr, $disasm:expr) => {
        #[cfg(feature = "disasm")]
        {
            use $crate::disasm::disasm_addr_range;
            use $crate::cruby::unindent;
            let disasm = disasm_addr_range(
                &$cb,
                $cb.get_ptr(0).raw_addr(&$cb),
                $cb.get_write_ptr().raw_addr(&$cb),
            );
            assert_eq!(unindent(&disasm, false), unindent(&$disasm, true));
        }
        assert_eq!(format!("{:x}", $cb), $hex);
    };
}
#[cfg(test)]
pub(crate) use assert_disasm;
