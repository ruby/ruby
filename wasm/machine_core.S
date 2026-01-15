	# extern int __stack_pointer;
	.globaltype __stack_pointer, i32

	# NOTE: Implement this in raw assembly to avoid stack pointer
	#       operations in C-prologue and epilogue.

	# void *rb_wasm_get_stack_pointer(void);
	.section	.text.rb_wasm_get_stack_pointer,"",@
	.globl	rb_wasm_get_stack_pointer
	.type	rb_wasm_get_stack_pointer,@function
rb_wasm_get_stack_pointer:
	.functype	rb_wasm_get_stack_pointer () -> (i32)
	global.get	__stack_pointer
	end_function

	# void rb_wasm_set_stack_pointer(void *sp);
	.section	.text.rb_wasm_set_stack_pointer,"",@
	.globl	rb_wasm_set_stack_pointer
	.type	rb_wasm_set_stack_pointer,@function
rb_wasm_set_stack_pointer:
	.functype	rb_wasm_set_stack_pointer (i32) -> ()
	local.get	0
	global.set	__stack_pointer
	end_function

