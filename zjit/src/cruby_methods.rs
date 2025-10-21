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
    annotate!(rb_mKernel, "block_given?", inline_kernel_block_given_p);
    annotate!(rb_cString, "bytesize", types::Fixnum, no_gc, leaf);
    annotate!(rb_cString, "bytesize", types::Fixnum, no_gc, leaf, elidable);
    annotate!(rb_cString, "size", types::Fixnum, no_gc, leaf, elidable);
    annotate!(rb_cString, "length", types::Fixnum, no_gc, leaf, elidable);
    annotate!(rb_cString, "to_s", types::StringExact);
    annotate!(rb_cString, "getbyte", inline_string_getbyte);
    annotate!(rb_cString, "empty?", types::BoolExact, no_gc, leaf, elidable);
    annotate!(rb_cString, "<<", inline_string_append);
    annotate!(rb_cString, "==", inline_string_eq);
    annotate!(rb_cModule, "name", types::StringExact.union(types::NilClass), no_gc, leaf, elidable);
    annotate!(rb_cModule, "===", types::BoolExact, no_gc, leaf);
    annotate!(rb_cArray, "length", types::Fixnum, no_gc, leaf, elidable);
    annotate!(rb_cArray, "size", types::Fixnum, no_gc, leaf, elidable);
    annotate!(rb_cArray, "empty?", types::BoolExact, no_gc, leaf, elidable);
    annotate!(rb_cArray, "reverse", types::ArrayExact, leaf, elidable);
    annotate!(rb_cArray, "join", types::StringExact);
    annotate!(rb_cArray, "[]", inline_array_aref);
    annotate!(rb_cArray, "<<", inline_array_push);
    annotate!(rb_cArray, "push", inline_array_push);
    annotate!(rb_cHash, "[]", inline_hash_aref);
    annotate!(rb_cHash, "size", types::Fixnum, no_gc, leaf, elidable);
    annotate!(rb_cHash, "empty?", types::BoolExact, no_gc, leaf, elidable);
    annotate!(rb_cNilClass, "nil?", types::TrueClass, no_gc, leaf, elidable);
    annotate!(rb_mKernel, "nil?", types::FalseClass, no_gc, leaf, elidable);
    annotate!(rb_mKernel, "respond_to?", inline_kernel_respond_to_p);
    annotate!(rb_cBasicObject, "==", types::BoolExact, no_gc, leaf, elidable);
    annotate!(rb_cBasicObject, "!", types::BoolExact, no_gc, leaf, elidable);
    annotate!(rb_cBasicObject, "initialize", inline_basic_object_initialize);
    annotate!(rb_cInteger, "succ", inline_integer_succ);
    annotate!(rb_cInteger, "^", inline_integer_xor);
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

fn inline_kernel_block_given_p(fun: &mut hir::Function, block: hir::BlockId, _recv: hir::InsnId, args: &[hir::InsnId], _state: hir::InsnId) -> Option<hir::InsnId> {
    let &[] = args else { return None; };
    // TODO(max): In local iseq types that are not ISEQ_TYPE_METHOD, rewrite to Constant false.
    let result = fun.push_insn(block, hir::Insn::IsBlockGiven);
    return Some(result);
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

fn inline_array_push(fun: &mut hir::Function, block: hir::BlockId, recv: hir::InsnId, args: &[hir::InsnId], state: hir::InsnId) -> Option<hir::InsnId> {
    // Inline only the case of `<<` or `push` when called with a single argument.
    if let &[val] = args {
        let _ = fun.push_insn(block, hir::Insn::ArrayPush { array: recv, val, state });
        return Some(recv);
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

fn inline_string_getbyte(fun: &mut hir::Function, block: hir::BlockId, recv: hir::InsnId, args: &[hir::InsnId], state: hir::InsnId) -> Option<hir::InsnId> {
    let &[index] = args else { return None; };
    if fun.likely_a(index, types::Fixnum, state) {
        // String#getbyte with a Fixnum is leaf and nogc; otherwise it may run arbitrary Ruby code
        // when converting the index to a C integer.
        let index = fun.coerce_to(block, index, types::Fixnum, state);
        let result = fun.push_insn(block, hir::Insn::StringGetbyteFixnum { string: recv, index });
        return Some(result);
    }
    None
}

fn inline_string_append(fun: &mut hir::Function, block: hir::BlockId, recv: hir::InsnId, args: &[hir::InsnId], state: hir::InsnId) -> Option<hir::InsnId> {
    let &[other] = args else { return None; };
    // Inline only StringExact << String, which matches original type check from
    // `vm_opt_ltlt`, which checks `RB_TYPE_P(obj, T_STRING)`.
    if fun.likely_a(recv, types::StringExact, state) && fun.likely_a(other, types::String, state) {
        let recv = fun.coerce_to(block, recv, types::StringExact, state);
        let other = fun.coerce_to(block, other, types::String, state);
        let _ = fun.push_insn(block, hir::Insn::StringAppend { recv, other, state });
        Some(recv)
    } else {
        None
    }
}

fn inline_string_eq(fun: &mut hir::Function, block: hir::BlockId, recv: hir::InsnId, args: &[hir::InsnId], state: hir::InsnId) -> Option<hir::InsnId> {
    let &[other] = args else { return None; };
    if fun.likely_a(recv, types::String, state) && fun.likely_a(other, types::String, state) {
        let recv = fun.coerce_to(block, recv, types::String, state);
        let other = fun.coerce_to(block, other, types::String, state);
        let return_type = types::BoolExact;
        let elidable = true;
        // TODO(max): Make StringEqual its own opcode so that we can later constant-fold StringEqual(a, a) => true
        let result = fun.push_insn(block, hir::Insn::CCall {
            cfunc: rb_yarv_str_eql_internal as *const u8,
            args: vec![recv, other],
            name: ID!(string_eq),
            return_type,
            elidable,
        });
        return Some(result);
    }
    None
}

fn inline_integer_succ(fun: &mut hir::Function, block: hir::BlockId, recv: hir::InsnId, args: &[hir::InsnId], state: hir::InsnId) -> Option<hir::InsnId> {
    if !args.is_empty() { return None; }
    if fun.likely_a(recv, types::Fixnum, state) {
        let left = fun.coerce_to(block, recv, types::Fixnum, state);
        let right = fun.push_insn(block, hir::Insn::Const { val: hir::Const::Value(VALUE::fixnum_from_usize(1)) });
        let result = fun.push_insn(block, hir::Insn::FixnumAdd { left, right, state });
        return Some(result);
    }
    None
}

fn inline_integer_xor(fun: &mut hir::Function, block: hir::BlockId, recv: hir::InsnId, args: &[hir::InsnId], state: hir::InsnId) -> Option<hir::InsnId> {
    let &[right] = args else { return None; };
    if fun.likely_a(recv, types::Fixnum, state) && fun.likely_a(right, types::Fixnum, state) {
        let left = fun.coerce_to(block, recv, types::Fixnum, state);
        let right = fun.coerce_to(block, right, types::Fixnum, state);
        let result = fun.push_insn(block, hir::Insn::FixnumXor { left, right });
        return Some(result);
    }
    None
}

fn inline_basic_object_initialize(fun: &mut hir::Function, block: hir::BlockId, _recv: hir::InsnId, args: &[hir::InsnId], _state: hir::InsnId) -> Option<hir::InsnId> {
    if !args.is_empty() { return None; }
    let result = fun.push_insn(block, hir::Insn::Const { val: hir::Const::Value(Qnil) });
    Some(result)
}

fn inline_kernel_respond_to_p(
    fun: &mut hir::Function,
    block: hir::BlockId,
    recv: hir::InsnId,
    args: &[hir::InsnId],
    state: hir::InsnId,
) -> Option<hir::InsnId> {
    // Parse arguments: respond_to?(method_name, allow_priv = false)
    let (method_name, allow_priv) = match *args {
        [method_name] => (method_name, false),
        [method_name, arg] => match fun.type_of(arg) {
            t if t.is_known_truthy() => (method_name, true),
            t if t.is_known_falsy() => (method_name, false),
            // Unknown type; bail out
            _ => return None,
        },
        // Unknown args; bail out
        _ => return None,
    };

    // Method name must be a static symbol
    let method_name = fun.type_of(method_name).ruby_object()?;
    if !method_name.static_sym_p() {
        return None;
    }

    // The receiver must have a known class to call `respond_to?` on
    // TODO: This is technically overly strict. This would also work if all of the
    // observed objects at this point agree on `respond_to?` and we can add many patchpoints.
    let recv_class = fun.type_of(recv).runtime_exact_ruby_class()?;

    // Get the method ID and its corresponding callable method entry
    let mid = unsafe { rb_sym2id(method_name) };
    let target_cme = unsafe { rb_callable_method_entry_or_negative(recv_class, mid) };
    assert!(
        !target_cme.is_null(),
        "Should never be null, as in that case we will be returned a \"negative CME\""
    );

    let cme_def_type = unsafe { get_cme_def_type(target_cme) };

    // Cannot inline a refined method, since their refinement depends on lexical scope
    if cme_def_type == VM_METHOD_TYPE_REFINED {
        return None;
    }

    let visibility = match cme_def_type {
        VM_METHOD_TYPE_UNDEF => METHOD_VISI_UNDEF,
        _ => unsafe { METHOD_ENTRY_VISI(target_cme) },
    };

    let result = match (visibility, allow_priv) {
        // Method undefined; check `respond_to_missing?`
        (METHOD_VISI_UNDEF, _) => {
            let respond_to_missing = ID!(respond_to_missing);
            if unsafe { rb_method_basic_definition_p(recv_class, respond_to_missing) } == 0 {
                return None; // Custom definition of respond_to_missing?, so cannot inline
            }
            let respond_to_missing_cme =
                unsafe { rb_callable_method_entry(recv_class, respond_to_missing) };
            // Protect against redefinition of `respond_to_missing?`
            fun.push_insn(
                block,
                hir::Insn::PatchPoint {
                    invariant: hir::Invariant::NoTracePoint,
                    state,
                },
            );
            fun.push_insn(
                block,
                hir::Insn::PatchPoint {
                    invariant: hir::Invariant::MethodRedefined {
                        klass: recv_class,
                        method: respond_to_missing,
                        cme: respond_to_missing_cme,
                    },
                    state,
                },
            );
            Qfalse
        }
        // Private method with allow priv=false, so `respond_to?` returns false
        (METHOD_VISI_PRIVATE, false) => Qfalse,
        // Public method or allow_priv=true: check if implemented
        (METHOD_VISI_PUBLIC, _) | (_, true) => {
            if cme_def_type == VM_METHOD_TYPE_NOTIMPLEMENTED {
                // C method with rb_f_notimplement(). `respond_to?` returns false
                // without consulting `respond_to_missing?`. See also: rb_add_method_cfunc()
                Qfalse
            } else {
                Qtrue
            }
        }
        (_, _) => return None, // not public and include_all not known, can't compile
    };
    fun.push_insn(block, hir::Insn::PatchPoint { invariant: hir::Invariant::NoTracePoint, state });
    fun.push_insn(block, hir::Insn::PatchPoint {
        invariant: hir::Invariant::MethodRedefined {
            klass: recv_class,
            method: mid,
            cme: target_cme
        }, state
    });
    if recv_class.instance_can_have_singleton_class() {
        fun.push_insn(block, hir::Insn::PatchPoint {
            invariant: hir::Invariant::NoSingletonClass { klass: recv_class }, state
        });
    }
    Some(fun.push_insn(block, hir::Insn::Const { val: hir::Const::Value(result) }))
}
