use std::ffi::c_void;

use crate::backend::lir::{self, Assembler, EC, Opnd, Target, asm_comment};
use crate::cruby::{
    RB_GC_ZJIT_FASTPATH_DEFAULT, RB_GC_ZJIT_FASTPATH_MMTK,
    RUBY_OFFSET_EC_THREAD_PTR, RUBY_OFFSET_RBASIC_FLAGS, RUBY_OFFSET_RBASIC_KLASS,
    RUBY_OFFSET_THREAD_RACTOR, VALUE, VALUE_BITS, rb_zjit_offset_ractor_newobj_cache,
};
use super::JITState;

#[repr(C)]
#[derive(Clone, Copy)]
struct RbGcZjitDefaultNewObjFastpath {
    cursor_offset: usize,
    cursor_end_offset: usize,
    slot_size: usize,
    flags: VALUE,
    klass: VALUE,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct RbGcZjitMmtkNewObjFastpath {
    objspace: *const c_void,
    objspace_total_allocated_objects_offset: usize,
    ractor_cache_mutator_offset: usize,
    ractor_cache_bump_pointer_offset: usize,
    ractor_cache_obj_free_parallel_buf_offset: usize,
    ractor_cache_obj_free_parallel_count_offset: usize,
    bump_pointer_cursor_offset: usize,
    bump_pointer_limit_offset: usize,
    min_obj_align: usize,
    payload_size: usize,
    total_alloc_size: usize,
    allocation_semantics_default: u32,
    gc_stress_p_func: usize,
    newobj_tracing_p_func: usize,
    post_alloc_func: usize,
    obj_free_buf_capacity_minus_one: usize,
    value_size_shift: usize,
    flags: VALUE,
    klass: VALUE,
}

#[repr(C)]
union RbGcZjitFastpathData {
    default_gc: RbGcZjitDefaultNewObjFastpath,
    mmtk: RbGcZjitMmtkNewObjFastpath,
}

#[repr(C)]
struct RbGcZjitFastpath {
    kind: u32,
    data: RbGcZjitFastpathData,
}

unsafe extern "C" {
    fn rb_gc_zjit_new_obj_fastpath(
        alloc_size: usize,
        flags: VALUE,
        klass: VALUE,
        fastpath: *mut RbGcZjitFastpath,
    ) -> bool;
}

enum PreparedNewObjFastpath {
    Default(RbGcZjitDefaultNewObjFastpath),
    Mmtk(RbGcZjitMmtkNewObjFastpath),
}

pub(super) fn gc_fast_path_new_obj(
    jit: &mut JITState,
    asm: &mut Assembler,
    alloc_size: usize,
    flags: u64,
    klass: VALUE,
    slow_path: impl Fn(&mut Assembler) -> lir::Opnd,
) -> lir::Opnd {
    let Some(fastpath) = prepare_new_obj_fastpath(alloc_size, flags, klass) else {
        return slow_path(asm);
    };

    asm_comment!(asm, "GC inline allocation");

    let hir_block_id = asm.current_block().hir_block_id;
    let rpo_idx = asm.current_block().rpo_index;

    let result_block = asm.new_block(hir_block_id, false, rpo_idx);
    let miss_block = asm.new_block(hir_block_id, false, rpo_idx);

    let result_edge = |v: Opnd| Target::Block(Box::new(lir::BranchEdge { target: result_block, args: vec![v] }));

    let obj = emit_new_obj_fastpath(jit, asm, &fastpath, miss_block)
        .expect("validated GC fastpath must return an object");
    asm.jmp(result_edge(obj));

    asm.set_current_block(miss_block);
    let label = jit.get_label(asm, miss_block, hir_block_id);
    asm.write_label(label);
    let obj = slow_path(asm);
    asm.jmp(result_edge(obj));

    asm.set_current_block(result_block);
    let label = jit.get_label(asm, result_block, hir_block_id);
    asm.write_label(label);
    let param = asm.new_block_param(VALUE_BITS);
    asm.current_block().add_parameter(param);
    param
}

fn prepare_new_obj_fastpath(alloc_size: usize, flags: u64, klass: VALUE) -> Option<PreparedNewObjFastpath> {
    let mut fastpath: RbGcZjitFastpath = unsafe { std::mem::zeroed() };
    let has_fastpath = unsafe {
        rb_gc_zjit_new_obj_fastpath(alloc_size, VALUE(flags as usize), klass, &mut fastpath)
    };

    if !has_fastpath {
        return None;
    }

    match fastpath.kind {
        RB_GC_ZJIT_FASTPATH_DEFAULT => {
            let fastpath = unsafe { fastpath.data.default_gc };
            Some(PreparedNewObjFastpath::Default(fastpath))
        }
        RB_GC_ZJIT_FASTPATH_MMTK => {
            let fastpath = unsafe { fastpath.data.mmtk };
            if fastpath.objspace.is_null()
                || fastpath.gc_stress_p_func == 0
                || fastpath.newobj_tracing_p_func == 0
                || fastpath.post_alloc_func == 0
                || fastpath.min_obj_align == 0
                || !fastpath.min_obj_align.is_power_of_two()
            {
                return None;
            }

            Some(PreparedNewObjFastpath::Mmtk(fastpath))
        }
        _ => None,
    }
}

fn emit_new_obj_fastpath(
    jit: &mut JITState,
    asm: &mut Assembler,
    prepared: &PreparedNewObjFastpath,
    miss_block: lir::BlockId,
) -> Option<Opnd> {
    let miss = Target::Block(Box::new(lir::BranchEdge {
        target: miss_block,
        args: vec![],
    }));

    match prepared {
        PreparedNewObjFastpath::Default(fastpath) => {
            emit_default_new_obj_fastpath(jit, asm, fastpath, &miss)
        }
        PreparedNewObjFastpath::Mmtk(fastpath) => {
            emit_mmtk_new_obj_fastpath(jit, asm, fastpath, &miss)
        }
    }
}

/* This function implements the GC fast path for the default GC. It implements
 * the fast path defined in function ractor_cache_allocate_slot (but not the
 * medium path in ractor_cache_advance_region). It also implements newobj_init
 * to write the flags and klass in the object.  */
fn emit_default_new_obj_fastpath(
    jit: &mut JITState,
    asm: &mut Assembler,
    fastpath: &RbGcZjitDefaultNewObjFastpath,
    miss: &Target,
) -> Option<Opnd> {
    let cursor_offset: i32 = fastpath.cursor_offset.try_into().ok()?;
    let cursor_end_offset: i32 = fastpath.cursor_end_offset.try_into().ok()?;
    let slot_size: u64 = fastpath.slot_size.try_into().ok()?;

    let thread = asm.load(Opnd::mem(64, EC, RUBY_OFFSET_EC_THREAD_PTR as i32));
    let ractor = asm.load(Opnd::mem(64, thread, RUBY_OFFSET_THREAD_RACTOR as i32));
    let ractor_newobj_cache_offset: i32 = unsafe { rb_zjit_offset_ractor_newobj_cache() }
        .try_into()
        .expect("ractor newobj cache offset fits in i32");
    let gc_cache = asm.load(Opnd::mem(64, ractor, ractor_newobj_cache_offset));

    let cursor = asm.load(Opnd::mem(64, gc_cache, cursor_offset));
    let cursor_end = asm.load(Opnd::mem(64, gc_cache, cursor_end_offset));

    let new_cursor = asm.add(cursor, Opnd::UImm(slot_size));
    asm.cmp(cursor_end, new_cursor);
    asm.jl(jit, miss.clone());

    asm.store(Opnd::mem(64, gc_cache, cursor_offset), new_cursor);
    asm.store(
        Opnd::mem(VALUE_BITS, cursor, RUBY_OFFSET_RBASIC_FLAGS),
        fastpath.flags.as_u64().into(),
    );
    asm.store(
        Opnd::mem(VALUE_BITS, cursor, RUBY_OFFSET_RBASIC_KLASS),
        fastpath.klass.into(),
    );

    Some(cursor)
}

/* This function implements the GC fast path for MMTk. It implements the fast
 * path defined in function rb_mmtk_alloc_fast_path, as well as writing the
 * flags and klass into the object. */
fn emit_mmtk_new_obj_fastpath(
    jit: &mut JITState,
    asm: &mut Assembler,
    fastpath: &RbGcZjitMmtkNewObjFastpath,
    miss: &Target,
) -> Option<Opnd> {
    let objspace_total_allocated_objects_offset: i32 = fastpath
        .objspace_total_allocated_objects_offset
        .try_into()
        .ok()?;
    let ractor_cache_mutator_offset: i32 = fastpath.ractor_cache_mutator_offset.try_into().ok()?;
    let ractor_cache_bump_pointer_offset: i32 = fastpath
        .ractor_cache_bump_pointer_offset
        .try_into()
        .ok()?;
    let ractor_cache_obj_free_parallel_buf_offset: u64 = fastpath
        .ractor_cache_obj_free_parallel_buf_offset
        .try_into()
        .ok()?;
    let ractor_cache_obj_free_parallel_count_offset: i32 = fastpath
        .ractor_cache_obj_free_parallel_count_offset
        .try_into()
        .ok()?;
    let bump_pointer_cursor_offset: i32 = fastpath.bump_pointer_cursor_offset.try_into().ok()?;
    let bump_pointer_limit_offset: i32 = fastpath.bump_pointer_limit_offset.try_into().ok()?;
    let payload_size: u64 = fastpath.payload_size.try_into().ok()?;
    let total_alloc_size: u64 = fastpath.total_alloc_size.try_into().ok()?;
    let obj_free_buf_capacity_minus_one: u64 = fastpath
        .obj_free_buf_capacity_minus_one
        .try_into()
        .ok()?;
    let value_size_shift: u64 = fastpath.value_size_shift.try_into().ok()?;
    let newobj_tracing_p_func = (fastpath.newobj_tracing_p_func != 0)
        .then_some(fastpath.newobj_tracing_p_func as *const u8)?;
    let gc_stress_p_func = (fastpath.gc_stress_p_func != 0)
        .then_some(fastpath.gc_stress_p_func as *const u8)?;
    let post_alloc_func = (fastpath.post_alloc_func != 0)
        .then_some(fastpath.post_alloc_func as *const u8)?;

    let event_hook = asm.ccall(newobj_tracing_p_func, vec![]);
    asm.test(event_hook, event_hook);
    asm.jnz(jit, miss.clone());

    let objspace_const = Opnd::const_ptr(fastpath.objspace);
    let gc_stress = asm.ccall(gc_stress_p_func, vec![objspace_const]);
    asm.test(gc_stress, gc_stress);
    asm.jnz(jit, miss.clone());

    let objspace = asm.load(objspace_const);
    let thread = asm.load(Opnd::mem(64, EC, RUBY_OFFSET_EC_THREAD_PTR as i32));
    let ractor = asm.load(Opnd::mem(64, thread, RUBY_OFFSET_THREAD_RACTOR as i32));
    let ractor_newobj_cache_offset: i32 = unsafe { rb_zjit_offset_ractor_newobj_cache() }
        .try_into()
        .expect("ractor newobj cache offset fits in i32");
    let ractor_cache = asm.load(Opnd::mem(64, ractor, ractor_newobj_cache_offset));

    let bump_pointer = asm.load(Opnd::mem(
        64,
        ractor_cache,
        ractor_cache_bump_pointer_offset,
    ));
    asm.test(bump_pointer, bump_pointer);
    asm.jz(jit, miss.clone());

    let obj_free_count = asm.load(Opnd::mem(
        64,
        ractor_cache,
        ractor_cache_obj_free_parallel_count_offset,
    ));
    asm.cmp(obj_free_count, Opnd::UImm(obj_free_buf_capacity_minus_one));
    asm.jge(jit, miss.clone());

    let cursor = asm.load(Opnd::mem(
        64,
        bump_pointer,
        bump_pointer_cursor_offset,
    ));
    let align_mask: i64 = (fastpath.min_obj_align - 1).try_into().ok()?;
    let adjusted = asm.add(cursor, Opnd::UImm(align_mask as u64));
    let aligned = asm.and(adjusted, Opnd::Imm(!align_mask));
    let new_cursor = asm.add(aligned, Opnd::UImm(total_alloc_size));
    let limit = asm.load(Opnd::mem(
        64,
        bump_pointer,
        bump_pointer_limit_offset,
    ));
    asm.cmp(limit, new_cursor);
    asm.jl(jit, miss.clone());

    asm.store(
        Opnd::mem(
            64,
            bump_pointer,
            bump_pointer_cursor_offset,
        ),
        new_cursor,
    );

    let value_size: u64 = std::mem::size_of::<VALUE>().try_into().ok()?;
    let obj = asm.add(aligned, Opnd::UImm(value_size));
    asm.store(Opnd::mem(VALUE_BITS, aligned, 0), Opnd::UImm(payload_size));
    asm.store(
        Opnd::mem(VALUE_BITS, obj, RUBY_OFFSET_RBASIC_FLAGS),
        fastpath.flags.as_u64().into(),
    );
    asm.store(
        Opnd::mem(VALUE_BITS, obj, RUBY_OFFSET_RBASIC_KLASS),
        fastpath.klass.into(),
    );

    let mutator = asm.load(Opnd::mem(
        64,
        ractor_cache,
        ractor_cache_mutator_offset,
    ));
    asm.ccall(
        post_alloc_func,
        vec![
            mutator,
            obj,
            Opnd::UImm(total_alloc_size),
            Opnd::UImm(u64::from(fastpath.allocation_semantics_default)),
        ],
    );

    let obj_free_index = asm.lshift(obj_free_count, Opnd::UImm(value_size_shift));
    let obj_free_buf = asm.add(
        ractor_cache,
        Opnd::UImm(ractor_cache_obj_free_parallel_buf_offset),
    );
    let obj_free_slot = asm.add(obj_free_buf, obj_free_index);
    asm.store(Opnd::mem(64, obj_free_slot, 0), obj);
    let new_obj_free_count = asm.add(obj_free_count, Opnd::UImm(1));
    asm.store(
        Opnd::mem(
            64,
            ractor_cache,
            ractor_cache_obj_free_parallel_count_offset,
        ),
        new_obj_free_count,
    );

    let total_allocated_objects = asm.load(Opnd::mem(
        64,
        objspace,
        objspace_total_allocated_objects_offset,
    ));
    let new_total_allocated_objects = asm.add(total_allocated_objects, Opnd::UImm(1));
    asm.store(
        Opnd::mem(
            64,
            objspace,
            objspace_total_allocated_objects_offset,
        ),
        new_total_allocated_objects,
    );

    Some(obj)
}
