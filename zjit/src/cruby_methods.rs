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
use crate::hir;

pub struct Annotations {
    cfuncs: HashMap<*mut c_void, FnProperties>,
    builtin_funcs: HashMap<*mut c_void, FnProperties>,
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
    pub inline: fn(&mut hir::Function, hir::BlockId, hir::InsnId, &[hir::InsnId], hir::InsnId) -> Option<hir::InsnId>,
}

/// A safe default for un-annotated Ruby methods: we can't optimize them or their returned values.
impl Default for FnProperties {
    fn default() -> Self {
        Self {
            no_gc: false,
            leaf: false,
            return_type: types::BasicObject,
            elidable: false,
            inline: no_inline,
        }
    }
}

impl Annotations {
    /// Query about properties of a C method
    pub fn get_cfunc_properties(&self, method: *const rb_callable_method_entry_t) -> Option<FnProperties> {
        let fn_ptr = unsafe {
            if VM_METHOD_TYPE_CFUNC != get_cme_def_type(method) {
                return None;
            }
            get_mct_func(get_cme_def_body_cfunc(method.cast()))
        };
        self.cfuncs.get(&fn_ptr).copied()
    }

    /// Query about properties of a builtin function by its pointer
    pub fn get_builtin_properties(&self, bf: *const rb_builtin_function) -> Option<FnProperties> {
        let func_ptr = unsafe { (*bf).func_ptr as *mut c_void };
        self.builtin_funcs.get(&func_ptr).copied()
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

/// Look up a method and find its builtin function pointer by parsing its ISEQ
/// We currently only support methods with exactly one invokebuiltin instruction
fn annotate_builtin_method(props_map: &mut HashMap<*mut c_void, FnProperties>, class: VALUE, method_name: &'static str, props: FnProperties) {
    unsafe {
        let method_id = rb_intern2(method_name.as_ptr().cast(), method_name.len().try_into().unwrap());
        let method = rb_method_entry_at(class, method_id);
        if method.is_null() {
            panic!("Method {}#{} not found", std::ffi::CStr::from_ptr(rb_class2name(class)).to_str().unwrap_or("?"), method_name);
        }

        // Cast ME to CME - they have identical layout
        let cme = method.cast::<rb_callable_method_entry_t>();
        let def_type = get_cme_def_type(cme);

        if def_type != VM_METHOD_TYPE_ISEQ {
            panic!("Method {}#{} is not an ISEQ method (type: {})",
                std::ffi::CStr::from_ptr(rb_class2name(class)).to_str().unwrap_or("?"),
                method_name, def_type);
        }

        // Get the ISEQ from the method definition
        let iseq = get_def_iseq_ptr((*cme).def);
        if iseq.is_null() {
            panic!("Failed to get ISEQ for {}#{}",
                std::ffi::CStr::from_ptr(rb_class2name(class)).to_str().unwrap_or("?"),
                method_name);
        }

        // Get the size of the ISEQ in instruction units
        let encoded_size = rb_iseq_encoded_size(iseq);

        // Scan through the ISEQ to find invokebuiltin instructions
        let mut insn_idx: u32 = 0;
        let mut func_ptr = std::ptr::null_mut::<c_void>();

        while insn_idx < encoded_size {
            // Get the PC for this instruction index
            let pc = rb_iseq_pc_at_idx(iseq, insn_idx);

            // Get the opcode using the proper decoder
            let opcode = rb_iseq_opcode_at_pc(iseq, pc);

            if opcode == YARVINSN_invokebuiltin as i32 ||
               opcode == YARVINSN_opt_invokebuiltin_delegate as i32 ||
               opcode == YARVINSN_opt_invokebuiltin_delegate_leave as i32 {
                // The first operand is the builtin function pointer
                let bf_value = *pc.add(1);
                let bf_ptr: *const rb_builtin_function = bf_value.as_ptr();

                if func_ptr.is_null() {
                    func_ptr = (*bf_ptr).func_ptr as *mut c_void;
                } else {
                    panic!("Multiple invokebuiltin instructions found in ISEQ for {}#{}",
                        std::ffi::CStr::from_ptr(rb_class2name(class)).to_str().unwrap_or("?"),
                        method_name);
                }
            }

            // Move to the next instruction using the proper length
            insn_idx = insn_idx.saturating_add(rb_insn_len(VALUE(opcode as usize)).try_into().unwrap());
        }

        // Only insert the properties if its iseq has exactly one invokebuiltin instruction
        props_map.insert(func_ptr, props);
    }
}

/// Gather annotations. Run this right after boot since the annotations
/// are about the stock versions of methods.
pub fn init() -> Annotations {
    let cfuncs = &mut HashMap::new();
    let builtin_funcs = &mut HashMap::new();

    macro_rules! annotate {
        ($module:ident, $method_name:literal, $inline:ident) => {
            let props = FnProperties { no_gc: false, leaf: false, elidable: false, return_type: types::BasicObject, inline: $inline };
            annotate_c_method(cfuncs, unsafe { $module }, $method_name, props);
        };
        ($module:ident, $method_name:literal, $return_type:expr $(, $properties:ident)*) => {
            #[allow(unused_mut)]
            let mut props = FnProperties { no_gc: false, leaf: false, elidable: false, return_type: $return_type, inline: no_inline };
            $(
                props.$properties = true;
            )*
            #[allow(unused_unsafe)]
            annotate_c_method(cfuncs, unsafe { $module }, $method_name, props);
        }
    }

    macro_rules! annotate_builtin {
        ($module:ident, $method_name:literal, $return_type:expr) => {
            annotate_builtin!($module, $method_name, $return_type, no_gc, leaf, elidable)
        };
        ($module:ident, $method_name:literal, $return_type:expr, $($properties:ident),+) => {
            let mut props = FnProperties {
                no_gc: false,
                leaf: false,
                elidable: false,
                return_type: $return_type,
                inline: no_inline,
            };
            $(props.$properties = true;)+
            annotate_builtin_method(builtin_funcs, unsafe { $module }, $method_name, props);
        }
    }

    annotate!(rb_mKernel, "itself", inline_kernel_itself);
    annotate!(rb_cString, "bytesize", types::Fixnum, no_gc, leaf);
    annotate!(rb_cString, "to_s", types::StringExact);
    annotate!(rb_cModule, "name", types::StringExact.union(types::NilClass), no_gc, leaf, elidable);
    annotate!(rb_cModule, "===", types::BoolExact, no_gc, leaf);
    annotate!(rb_cArray, "length", types::Fixnum, no_gc, leaf, elidable);
    annotate!(rb_cArray, "size", types::Fixnum, no_gc, leaf, elidable);
    annotate!(rb_cArray, "empty?", types::BoolExact, no_gc, leaf, elidable);
    annotate!(rb_cArray, "reverse", types::ArrayExact, leaf, elidable);
    annotate!(rb_cArray, "join", types::StringExact);
    annotate!(rb_cArray, "[]", inline_array_aref);
    annotate!(rb_cHash, "[]", inline_hash_aref);
    annotate!(rb_cHash, "empty?", types::BoolExact, no_gc, leaf, elidable);
    annotate!(rb_cNilClass, "nil?", types::TrueClass, no_gc, leaf, elidable);
    annotate!(rb_mKernel, "nil?", types::FalseClass, no_gc, leaf, elidable);
    annotate!(rb_cBasicObject, "==", types::BoolExact, no_gc, leaf, elidable);
    annotate!(rb_cBasicObject, "!", types::BoolExact, no_gc, leaf, elidable);
    annotate!(rb_cBasicObject, "initialize", types::NilClass, no_gc, leaf, elidable);
    annotate!(rb_cString, "to_s", inline_string_to_s);
    let thread_singleton = unsafe { rb_singleton_class(rb_cThread) };
    annotate!(thread_singleton, "current", types::BasicObject, no_gc, leaf);

    annotate_builtin!(rb_mKernel, "Float", types::Float);
    annotate_builtin!(rb_mKernel, "Integer", types::Integer);
    annotate_builtin!(rb_mKernel, "class", types::Class, leaf);

    Annotations {
        cfuncs: std::mem::take(cfuncs),
        builtin_funcs: std::mem::take(builtin_funcs),
    }
}

fn no_inline(_fun: &mut hir::Function, _block: hir::BlockId, _recv: hir::InsnId, _args: &[hir::InsnId], _state: hir::InsnId) -> Option<hir::InsnId> {
    None
}

fn inline_string_to_s(fun: &mut hir::Function, block: hir::BlockId, recv: hir::InsnId, args: &[hir::InsnId], state: hir::InsnId) -> Option<hir::InsnId> {
    if args.len() == 0 && fun.likely_a(recv, types::StringExact, state) {
        let recv = fun.coerce_to(block, recv, types::StringExact, state);
        return Some(recv);
    }
    None
}

fn inline_kernel_itself(_fun: &mut hir::Function, _block: hir::BlockId, recv: hir::InsnId, args: &[hir::InsnId], _state: hir::InsnId) -> Option<hir::InsnId> {
    if args.len() == 0 {
        // No need to coerce the receiver; that is done by the SendWithoutBlock rewriting.
        return Some(recv);
    }
    None
}

fn inline_array_aref(fun: &mut hir::Function, block: hir::BlockId, recv: hir::InsnId, args: &[hir::InsnId], state: hir::InsnId) -> Option<hir::InsnId> {
    if let &[index] = args {
        if fun.likely_a(index, types::Fixnum, state) {
            let index = fun.coerce_to(block, index, types::Fixnum, state);
            let result = fun.push_insn(block, hir::Insn::ArrayArefFixnum { array: recv, index });
            return Some(result);
        }
    }
    None
}

fn inline_hash_aref(fun: &mut hir::Function, block: hir::BlockId, recv: hir::InsnId, args: &[hir::InsnId], state: hir::InsnId) -> Option<hir::InsnId> {
    if let &[key] = args  {
        let result = fun.push_insn(block, hir::Insn::HashAref { hash: recv, key, state });
        return Some(result);
    }
    None
}
