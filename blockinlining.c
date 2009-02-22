/**********************************************************************

  blockinlining.c -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#include "ruby/ruby.h"
#include "vm_core.h"

static VALUE
iseq_special_block(rb_iseq_t *iseq, void *builder)
{
#if OPT_BLOCKINLINING
    VALUE parent = Qfalse;
    VALUE iseqval;

    if (iseq->argc > 1 || iseq->arg_simple == 0) {
	/* argument check */
	return 0;
    }

    if (iseq->cached_special_block_builder) {
	if (iseq->cached_special_block_builder == builder) {
	    return iseq->cached_special_block;
	}
	else {
	    return 0;
	}
    }
    else {
	iseq->cached_special_block_builder = (void *)1;
    }

    if (iseq->parent_iseq) {
	parent = iseq->parent_iseq->self;
    }
    iseqval = rb_iseq_new_with_bopt(iseq->node, iseq->name, iseq->filename,
				      parent, iseq->type,
				      GC_GUARDED_PTR(builder));
    if (0) {
	printf("%s\n", RSTRING_PTR(rb_iseq_disasm(iseqval)));
    }
    iseq->cached_special_block = iseqval;
    iseq->cached_special_block_builder = builder;
    return iseqval;
#else
    return 0;
#endif
}

static NODE *
new_block(NODE * head, NODE * tail)
{
    head = NEW_BLOCK(head);
    tail = NEW_BLOCK(tail);
    head->nd_next = tail;
    return head;
}

static NODE *
new_ary(NODE * head, NODE * tail)
{
    head = NEW_ARRAY(head);
    head->nd_next = tail;
    return head;
}

static NODE *
new_assign(NODE * lnode, NODE * rhs)
{
    switch (nd_type(lnode)) {
      case NODE_LASGN:{
	  return NEW_NODE(NODE_LASGN, lnode->nd_vid, rhs, lnode->nd_cnt);
	  /* NEW_LASGN(lnode->nd_vid, rhs); */
      }
      case NODE_GASGN:{
	  return NEW_GASGN(lnode->nd_vid, rhs);
      }
      case NODE_DASGN:{
	  return NEW_DASGN(lnode->nd_vid, rhs);
      }
      case NODE_ATTRASGN:{
	  NODE *args = 0;
	  if (lnode->nd_args) {
	      args = NEW_ARRAY(lnode->nd_args->nd_head);
	      args->nd_next = NEW_ARRAY(rhs);
	      args->nd_alen = 2;
	  }
	  else {
	      args = NEW_ARRAY(rhs);
	  }

	  return NEW_ATTRASGN(lnode->nd_recv,
			      lnode->nd_mid,
			      args);
      }
      default:
	rb_bug("unimplemented (block inlining): %s", ruby_node_name(nd_type(lnode)));
    }
    return 0;
}

static NODE *
build_Integer_times_node(rb_iseq_t *iseq, NODE * node, NODE * lnode,
			 VALUE param_vars, VALUE local_vars)
{
    /* Special Block for Integer#times
       {|e, _self|
       _e = e
       while(e < _self)
       e = _e
       redo_point:
       BODY
       next_point:
       _e = _e.succ
       end
       }

       {|e, _self|
       while(e < _self)
       BODY
       next_point:
       e = e.succ
       end
       }
     */
    ID _self;
    CONST_ID(_self, "#_self");
    if (iseq->argc == 0) {
	ID e;
	CONST_ID(e, "#e");
	rb_ary_push(param_vars, ID2SYM(e));
	rb_ary_push(param_vars, ID2SYM(_self));
	iseq->argc += 2;

	node =
	    NEW_WHILE(NEW_CALL
		      (NEW_DVAR(e), idLT, new_ary(NEW_DVAR(_self), 0)),
		      new_block(NEW_OPTBLOCK(node),
				NEW_DASGN(e,
					  NEW_CALL(NEW_DVAR(e), idSucc, 0))),
		      Qundef);
    }
    else {
	ID _e;
	ID e = SYM2ID(rb_ary_entry(param_vars, 0));
	NODE *assign;

	CONST_ID(_e, "#_e");
	rb_ary_push(param_vars, ID2SYM(_self));
	rb_ary_push(local_vars, ID2SYM(_e));
	iseq->argc++;

	if (nd_type(lnode) == NODE_DASGN_CURR) {
	    assign = NEW_DASGN(e, NEW_DVAR(_e));
	}
	else {
	    assign = new_assign(lnode, NEW_DVAR(_e));
	}

	node =
	    new_block(NEW_DASGN(_e, NEW_DVAR(e)),
		      NEW_WHILE(NEW_CALL
				(NEW_DVAR(_e), idLT,
				 new_ary(NEW_DVAR(_self), 0)),
				new_block(assign,
					  new_block(NEW_OPTBLOCK(node),
						    NEW_DASGN(_e,
							      NEW_CALL
							      (NEW_DVAR(_e),
							       idSucc, 0)))),
				Qundef));
    }
    return node;
}

VALUE
invoke_Integer_times_special_block(VALUE num)
{
    rb_thread_t *th = GET_THREAD();
    rb_block_t *orig_block = GC_GUARDED_PTR_REF(th->cfp->lfp[0]);

    if (orig_block && BUILTIN_TYPE(orig_block->iseq) != T_NODE) {
	VALUE tsiseqval = iseq_special_block(orig_block->iseq,
					     build_Integer_times_node);
	rb_iseq_t *tsiseq;
	VALUE argv[2], val;

	if (tsiseqval) {
	    rb_block_t block = *orig_block;
	    GetISeqPtr(tsiseqval, tsiseq);
	    block.iseq = tsiseq;
	    th->cfp->lfp[0] = GC_GUARDED_PTR(&block);
	    argv[0] = INT2FIX(0);
	    argv[1] = num;
	    val = rb_yield_values(2, argv);
	    if (val == Qundef) {
		return num;
	    }
	    else {
		return val;
	    }
	}
    }
    return Qundef;
}

static NODE *
build_Range_each_node(rb_iseq_t *iseq, NODE * node, NODE * lnode,
		      VALUE param_vars, VALUE local_vars, ID mid)
{
    /* Special Block for Range#each
       {|e, _last|
       _e = e
       while _e < _last
       e = _e
       next_point:
       BODY
       redo_point:
       _e = _e.succ
       end
       }
       {|e, _last|
       while e < _last
       BODY
       redo_point:
       e = e.succ
       end
       }
     */
    ID _last;
    CONST_ID(_last, "#_last");
    if (iseq->argc == 0) {
	ID e;
	CONST_ID(e, "#e");
	rb_ary_push(param_vars, ID2SYM(e));
	rb_ary_push(param_vars, ID2SYM(_last));
	iseq->argc += 2;

	node =
	    NEW_WHILE(NEW_CALL(NEW_DVAR(e), mid, new_ary(NEW_DVAR(_last), 0)),
		      new_block(NEW_OPTBLOCK(node),
				NEW_DASGN(e,
					  NEW_CALL(NEW_DVAR(e), idSucc, 0))),
		      Qundef);
    }
    else {
	ID _e;
	ID e = SYM2ID(rb_ary_entry(param_vars, 0));
	NODE *assign;

	CONST_ID(_e, "#_e");
	rb_ary_push(param_vars, ID2SYM(_last));
	rb_ary_push(local_vars, ID2SYM(_e));
	iseq->argc++;

	if (nd_type(lnode) == NODE_DASGN_CURR) {
	    assign = NEW_DASGN(e, NEW_DVAR(_e));
	}
	else {
	    assign = new_assign(lnode, NEW_DVAR(_e));
	}

	node =
	    new_block(NEW_DASGN(_e, NEW_DVAR(e)),
		      NEW_WHILE(NEW_CALL
				(NEW_DVAR(_e), mid,
				 new_ary(NEW_DVAR(_last), 0)),
				new_block(assign,
					  new_block(NEW_OPTBLOCK(node),
						    NEW_DASGN(_e,
							      NEW_CALL
							      (NEW_DVAR(_e),
							       idSucc, 0)))),
				Qundef));
    }
    return node;
}

static NODE *
build_Range_each_node_LE(rb_iseq_t *iseq, NODE * node, NODE * lnode,
			 VALUE param_vars, VALUE local_vars)
{
    return build_Range_each_node(iseq, node, lnode,
				 param_vars, local_vars, idLE);
}

static NODE *
build_Range_each_node_LT(rb_iseq_t *iseq, NODE * node, NODE * lnode,
			 VALUE param_vars, VALUE local_vars)
{
    return build_Range_each_node(iseq, node, lnode,
				 param_vars, local_vars, idLT);
}

VALUE
invoke_Range_each_special_block(VALUE range,
				VALUE beg, VALUE end, int excl)
{
    rb_thread_t *th = GET_THREAD();
    rb_block_t *orig_block = GC_GUARDED_PTR_REF(th->cfp->lfp[0]);

    if (BUILTIN_TYPE(orig_block->iseq) != T_NODE) {
	void *builder =
	    excl ? build_Range_each_node_LT : build_Range_each_node_LE;
	VALUE tsiseqval = iseq_special_block(orig_block->iseq, builder);
	rb_iseq_t *tsiseq;
	VALUE argv[2];

	if (tsiseqval) {
	    VALUE val;
	    rb_block_t block = *orig_block;
	    GetISeqPtr(tsiseqval, tsiseq);
	    block.iseq = tsiseq;
	    th->cfp->lfp[0] = GC_GUARDED_PTR(&block);
	    argv[0] = beg;
	    argv[1] = end;
	    val = rb_yield_values(2, argv);
	    if (val == Qundef) {
		return range;
	    }
	    else {
		return val;
	    }
	}
    }
    return Qundef;
}


static NODE *
build_Array_each_node(rb_iseq_t *iseq, NODE * node, NODE * lnode,
		      VALUE param_vars, VALUE local_vars)
{
    /* Special block for Array#each
       ary.each{|e|
       BODY
       }
       =>
       {|e, _self|
       _i = 0
       while _i < _self.length
       e = _self[_i]
       redo_point:
       BODY
       next_point:
       _i = _i.succ
       end
       }

       ary.each{
       BODY
       }
       =>
       {|_i, _self|
       _i = 0
       while _i < _self.length
       redo_point:
       BODY
       next_point:
       _i = _i.succ
       end
       }
     */

    ID _self, _i;

    CONST_ID(_self, "#_self");
    CONST_ID(_i, "#_i");
    if (iseq->argc == 0) {
	ID _e;
	CONST_ID(_e, "#_e");
	rb_ary_push(param_vars, ID2SYM(_e));
	rb_ary_push(param_vars, ID2SYM(_self));
	iseq->argc += 2;
	rb_ary_push(local_vars, ID2SYM(_i));

	node =
	    new_block(NEW_DASGN(_i, NEW_LIT(INT2FIX(0))),
		      NEW_WHILE(NEW_CALL(NEW_DVAR(_i), idLT,
					 new_ary(NEW_CALL
						 (NEW_DVAR(_self), idLength,
						  0), 0)),
				new_block(NEW_OPTBLOCK(node),
					  NEW_DASGN(_i,
						    NEW_CALL(NEW_DVAR(_i),
							     idSucc, 0))),
				Qundef));
    }
    else {
	ID e = SYM2ID(rb_ary_entry(param_vars, 0));
	NODE *assign;

	rb_ary_push(param_vars, ID2SYM(_self));
	iseq->argc++;
	rb_ary_push(local_vars, ID2SYM(_i));

	if (nd_type(lnode) == NODE_DASGN_CURR) {
	    assign = NEW_DASGN(e,
			       NEW_CALL(NEW_DVAR(_self), idAREF,
					new_ary(NEW_DVAR(_i), 0)));
	}
	else {
	    assign = new_assign(lnode,
				NEW_CALL(NEW_DVAR(_self), idAREF,
					 new_ary(NEW_DVAR(_i), 0)));
	}

	node =
	    new_block(NEW_DASGN(_i, NEW_LIT(INT2FIX(0))),
		      NEW_WHILE(NEW_CALL(NEW_DVAR(_i), idLT,
					 new_ary(NEW_CALL
						 (NEW_DVAR(_self), idLength,
						  0), 0)), new_block(assign,
								     new_block
								     (NEW_OPTBLOCK
								      (node),
								      NEW_DASGN
								      (_i,
								       NEW_CALL
								       (NEW_DVAR
									(_i),
									idSucc,
									0)))),
				Qundef));
    }
    return node;
}

VALUE
invoke_Array_each_special_block(VALUE ary)
{
    rb_thread_t *th = GET_THREAD();
    rb_block_t *orig_block = GC_GUARDED_PTR_REF(th->cfp->lfp[0]);

    if (BUILTIN_TYPE(orig_block->iseq) != T_NODE) {
	VALUE tsiseqval = iseq_special_block(orig_block->iseq,
					     build_Array_each_node);
	rb_iseq_t *tsiseq;
	VALUE argv[2];

	if (tsiseqval) {
	    VALUE val;
	    rb_block_t block = *orig_block;
	    GetISeqPtr(tsiseqval, tsiseq);
	    block.iseq = tsiseq;
	    th->cfp->lfp[0] = GC_GUARDED_PTR(&block);
	    argv[0] = 0;
	    argv[1] = ary;
	    val = rb_yield_values(2, argv);
	    if (val == Qundef) {
		return ary;
	    }
	    else {
		return val;
	    }
	}
    }
    return Qundef;
}
