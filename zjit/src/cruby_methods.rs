/*! This module contains assertions we make about runtime properties of core library methods.
 * Some properties that influence codegen:
 *  - Whether the method has been redefined since boot
 *  - Whether the C method can yield to the GC
 *  - Whether the C method makes any method calls
 *
 * For Ruby methods, many of these properties can be inferred through analyzing the
 * bytecode, but for C methods we resort to annotation and validation in debug builds.
 */

use crate::cruby::*;
use std::collections::HashMap;
use std::ffi::c_void;
use crate::hir_type::{types, Type};

pub struct Annotations {
    cfuncs: HashMap<*mut c_void, FnProperties>,
}

/// Runtime behaviors of C functions that implement a Ruby method
#[derive(Clone, Copy)]
pub struct FnProperties {
    /// Whether it's possible for the function to yield to the GC
    pub no_gc: bool,
    /// Whether it's possible for the function to make a ruby call
    pub leaf: bool,
    /// What Type the C function returns
    pub return_type: Type,
    /// Whether it's legal to remove the call if the result is unused
    pub elidable: bool,
}

impl Annotations {
    /// Query about properties of a C method
    pub fn get_cfunc_properties(&self, method: *const rb_callable_method_entry_t) -> Option<FnProperties> {
        let fn_ptr = unsafe {
            if VM_METHOD_TYPE_CFUNC != get_cme_def_type(method) {
                return None;
            }
            rb_get_mct_func(rb_get_cme_def_body_cfunc(method.cast()))
        };
        self.cfuncs.get(&fn_ptr).copied()
    }
}

fn annotate_c_method(props_map: &mut HashMap<*mut c_void, FnProperties>, class: VALUE, method_name: &'static str, props: FnProperties) {
    // Lookup function pointer of the C method
    let fn_ptr = unsafe {
        // TODO(alan): (side quest) make rust methods and clean up glue code for rb_method_cfunc_t and
        // rb_method_definition_t.
        let method_id = rb_intern2(method_name.as_ptr().cast(), method_name.len() as _);
        let method = rb_method_entry_at(class, method_id);
        assert!(!method.is_null());
        // ME-to-CME cast is fine due to identical layout
        debug_assert_eq!(VM_METHOD_TYPE_CFUNC, get_cme_def_type(method.cast()));
        get_mct_func(get_cme_def_body_cfunc(method.cast()))
    };

    props_map.insert(fn_ptr, props);
}

/// Gather annotations. Run this right after boot since the annotations
/// are about the stock versions of methods.
pub fn init() -> Annotations {
    let cfuncs = &mut HashMap::new();

    macro_rules! annotate {
        ($module:ident, $method_name:literal, $return_type:expr, $($properties:ident),*) => {
            #[allow(unused_mut)]
            let mut props = FnProperties { no_gc: false, leaf: false, elidable: false, return_type: $return_type };
            $(
                props.$properties = true;
            )*
            annotate_c_method(cfuncs, unsafe { $module }, $method_name, props);
        }
    }

    annotate!(rb_mKernel, "itself", types::BasicObject, no_gc, leaf, elidable);
    annotate!(rb_cString, "bytesize", types::Fixnum, no_gc, leaf);
    annotate!(rb_cModule, "name", types::StringExact.union(types::NilClassExact), no_gc, leaf, elidable);
    annotate!(rb_cModule, "===", types::BoolExact, no_gc, leaf);
    annotate!(rb_cArray, "length", types::Fixnum, no_gc, leaf, elidable);
    annotate!(rb_cArray, "size", types::Fixnum, no_gc, leaf, elidable);
    annotate!(rb_cInteger, "+", types::IntegerExact,);

    Annotations {
        cfuncs: std::mem::take(cfuncs)
    }
}
