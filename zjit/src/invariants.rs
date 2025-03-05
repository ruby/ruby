use crate::{cruby::{ruby_basic_operators, RedefinitionFlag}, zjit_enabled_p};

/// Called when a basic operator is redefined. Note that all the blocks assuming
/// the stability of different operators are invalidated together and we don't
/// do fine-grained tracking.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_bop_redefined(_klass: RedefinitionFlag, _bop: ruby_basic_operators) {
    // If ZJIT isn't enabled, do nothing
    if !zjit_enabled_p() {
        return;
    }

    unimplemented!("Invalidation on BOP redefinition is not implemented yet");
}
