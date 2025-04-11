from lldb_rb.lldb_interface import LLDBInterface
from lldb_rb.rb_heap_structs import HeapPage, RbObject
from lldb_rb.constants import *

class RbInspector(LLDBInterface):
    def __init__(self, debugger, result, ruby_globals):
        self.build_environment(debugger)
        self.result = result
        self.ruby_globals = ruby_globals

    def string2cstr(self, rstring):
        """Returns the pointer to the C-string in the given String object"""
        if rstring.TypeIsPointerType():
            rstring = rstring.Dereference()

        flags = rstring.GetValueForExpressionPath(".basic->flags").unsigned
        clen = int(rstring.GetValueForExpressionPath(".len").value, 0)
        if flags & self.ruby_globals["RUBY_FL_USER1"]:
            cptr = int(rstring.GetValueForExpressionPath(".as.heap.ptr").value, 0)
        else:
            cptr = int(rstring.GetValueForExpressionPath(".as.embed.ary").location, 0)

        return cptr, clen

    def output_string(self, rstring):
        cptr, clen = self.string2cstr(rstring)
        self._append_expression("*(const char (*)[%d])%0#x" % (clen, cptr))

    def fixnum_p(self, x):
        return x & self.ruby_globals["RUBY_FIXNUM_FLAG"] != 0

    def flonum_p(self, x):
        return (x & self.ruby_globals["RUBY_FLONUM_MASK"]) == self.ruby_globals["RUBY_FLONUM_FLAG"]

    def static_sym_p(self, x):
        special_shift = self.ruby_globals["RUBY_SPECIAL_SHIFT"]
        symbol_flag = self.ruby_globals["RUBY_SYMBOL_FLAG"]
        return (x & ~(~0 << special_shift)) == symbol_flag

    def generic_inspect(self, val, rtype):
        tRType = self.target.FindFirstType("struct %s" % rtype).GetPointerType()
        val = val.Cast(tRType)
        self._append_expression("*(struct %s *) %0#x" % (rtype, val.GetValueAsUnsigned()))

    def inspect(self, val):
        rbTrue  = self.ruby_globals["RUBY_Qtrue"]
        rbFalse = self.ruby_globals["RUBY_Qfalse"]
        rbNil   = self.ruby_globals["RUBY_Qnil"]
        rbUndef = self.ruby_globals["RUBY_Qundef"]
        rbImmediateMask = self.ruby_globals["RUBY_IMMEDIATE_MASK"]

        if self.inspect_node(val):
            return

        num = val.GetValueAsSigned()
        if num == rbFalse:
            print('false', file=self.result)
        elif num == rbTrue:
            print('true', file=self.result)
        elif num == rbNil:
            print('nil', file=self.result)
        elif num == rbUndef:
            print('undef', file=self.result)
        elif self.fixnum_p(num):
            print(num >> 1, file=self.result)
        elif self.flonum_p(num):
            self._append_expression("rb_float_value(%0#x)" % val.GetValueAsUnsigned())
        elif self.static_sym_p(num):
            if num < 128:
                print("T_SYMBOL: %c" % num, file=self.result)
            else:
                print("T_SYMBOL: (%x)" % num, file=self.result)
                self._append_expression("rb_id2name(%0#x)" % (num >> 8))

        elif num & rbImmediateMask:
            print('immediate(%x)' % num, file=self.result)
        else:
            rval = RbObject(val, self.debugger, self.ruby_globals)
            rval.dump_bits(self.result)

            flaginfo = ""
            if rval.promoted_p():
                flaginfo += "[PROMOTED] "
            if rval.frozen_p():
                flaginfo += "[FROZEN] "

            if rval.is_type("RUBY_T_NONE"):
                print('T_NONE: %s%s' % (flaginfo, val.Dereference()), file=self.result)

            elif rval.is_type("RUBY_T_NIL"):
                print('T_NIL: %s%s' % (flaginfo, val.Dereference()), file=self.result)

            elif rval.is_type("RUBY_T_OBJECT"):
                self.result.write('T_OBJECT: %s' % flaginfo)
                self._append_expression("*(struct RObject*)%0#x" % val.GetValueAsUnsigned())

            elif (rval.is_type("RUBY_T_CLASS") or
                  rval.is_type("RUBY_T_MODULE") or
                  rval.is_type("RUBY_T_ICLASS")):
                self.result.write('T_%s: %s' % (rval.type_name.split('_')[-1], flaginfo))
                tRClass = self.target.FindFirstType("struct RClass")

                self._append_expression("*(struct RClass*)%0#x" % val.GetValueAsUnsigned())
                if not val.Cast(tRClass).GetChildMemberWithName("ptr").IsValid():
                    self._append_expression(
                        "*(struct rb_classext_struct*)%0#x" %
                        (val.GetValueAsUnsigned() + tRClass.GetByteSize())
                    )

            elif rval.is_type("RUBY_T_STRING"):
                self.result.write('T_STRING: %s' % flaginfo)
                tRString = self.target.FindFirstType("struct RString").GetPointerType()

                chilled = self.ruby_globals["RUBY_FL_USER3"]
                if (rval.flags & chilled) != 0:
                    self.result.write("[CHILLED] ")

                rb_enc_mask = self.ruby_globals["RUBY_ENCODING_MASK"]
                rb_enc_shift = self.ruby_globals["RUBY_ENCODING_SHIFT"]
                encidx = ((rval.flags & rb_enc_mask) >> rb_enc_shift)
                encname = self.target.FindFirstType("enum ruby_preserved_encindex") \
                        .GetEnumMembers().GetTypeEnumMemberAtIndex(encidx) \
                        .GetName()

                if encname is not None:
                    self.result.write('[%s] ' % encname[14:])
                else:
                    self.result.write('[enc=%d] ' % encidx)

                coderange = rval.flags & self.ruby_globals["RUBY_ENC_CODERANGE_MASK"]
                if coderange == self.ruby_globals["RUBY_ENC_CODERANGE_7BIT"]:
                    self.result.write('[7BIT] ')
                elif coderange == self.ruby_globals["RUBY_ENC_CODERANGE_VALID"]:
                    self.result.write('[VALID] ')
                elif coderange == self.ruby_globals["RUBY_ENC_CODERANGE_BROKEN"]:
                    self.result.write('[BROKEN] ')
                else:
                    self.result.write('[UNKNOWN] ')

                ptr, len = self.string2cstr(val.Cast(tRString))
                if len == 0:
                    self.result.write("(empty)\n")
                else:
                    self._append_expression("*(const char (*)[%d])%0#x" % (len, ptr))

            elif rval.is_type("RUBY_T_SYMBOL"):
                self.result.write('T_SYMBOL: %s' % flaginfo)
                tRSymbol = self.target.FindFirstType("struct RSymbol").GetPointerType()
                tRString = self.target.FindFirstType("struct RString").GetPointerType()

                val = val.Cast(tRSymbol)
                self._append_expression('(ID)%0#x ' % val.GetValueForExpressionPath("->id").GetValueAsUnsigned())
                self.output_string(val.GetValueForExpressionPath("->fstr").Cast(tRString))

            elif rval.is_type("RUBY_T_ARRAY"):
                len = rval.ary_len()
                ptr = rval.ary_ptr()

                self.result.write("T_ARRAY: %slen=%d" % (flaginfo, len))

                if rval.flags & self.ruby_globals["RUBY_FL_USER1"]:
                    self.result.write(" (embed)")
                elif rval.flags & self.ruby_globals["RUBY_FL_USER2"]:
                    shared = val.GetValueForExpressionPath("->as.heap.aux.shared").GetValueAsUnsigned()
                    self.result.write(" (shared) shared=%016x" % shared)
                else:
                    capa = val.GetValueForExpressionPath("->as.heap.aux.capa").GetValueAsSigned()
                    self.result.write(" (ownership) capa=%d" % capa)
                if len == 0:
                    self.result.write(" {(empty)}\n")
                else:
                    self.result.write("\n")
                    if ptr.GetValueAsSigned() == 0:
                        self._append_expression("-fx -- ((struct RArray*)%0#x)->as.ary" % val.GetValueAsUnsigned())
                    else:
                        self._append_expression("-Z %d -fx -- (const VALUE*)%0#x" % (len, ptr.GetValueAsUnsigned()))

            elif rval.is_type("RUBY_T_HASH"):
                self.result.write("T_HASH: %s" % flaginfo)
                ptr = val.GetValueAsUnsigned()
                self._append_expression("*(struct RHash *) %0#x" % ptr)
                if rval.flags & self.ruby_globals["RUBY_FL_USER3"]:
                    self._append_expression("*(struct st_table *) (%0#x + sizeof(struct RHash))" % ptr)
                else:
                    self._append_expression("*(struct ar_table *) (%0#x + sizeof(struct RHash))" % ptr)

            elif rval.is_type("RUBY_T_BIGNUM"):
                sign = '-'
                if (rval.flags & self.ruby_globals["RUBY_FL_USER1"]) != 0:
                    sign = '+'
                len = rval.bignum_len()

                if rval.flags & self.ruby_globals["RUBY_FL_USER2"]:
                    print("T_BIGNUM: sign=%s len=%d (embed)" % (sign, len), file=self.result)
                    self._append_expression("((struct RBignum *) %0#x)->as.ary"
                                                % val.GetValueAsUnsigned())
                else:
                    print("T_BIGNUM: sign=%s len=%d" % (sign, len), file=self.result)
                    print(rval.as_type("bignum"), file=self.result)
                    self._append_expression("-Z %d -fx -- ((struct RBignum*)%d)->as.heap.digits" %
                                            (len, val.GetValueAsUnsigned()))

            elif rval.is_type("RUBY_T_FLOAT"):
                self._append_expression("((struct RFloat *)%d)->float_value"
                                            % val.GetValueAsUnsigned())

            elif rval.is_type("RUBY_T_RATIONAL"):
                tRRational = self.target.FindFirstType("struct RRational").GetPointerType()
                val = val.Cast(tRRational)
                self.inspect(val.GetValueForExpressionPath("->num"))
                output = self.result.GetOutput()
                self.result.Clear()
                self.result.write("(Rational) " + output.rstrip() + " / ")
                self.inspect(val.GetValueForExpressionPath("->den"))

            elif rval.is_type("RUBY_T_COMPLEX"):
                tRComplex = self.target.FindFirstType("struct RComplex").GetPointerType()
                val = val.Cast(tRComplex)
                self.inspect(val.GetValueForExpressionPath("->real"))
                real = self.result.GetOutput().rstrip()
                self.result.Clear()
                self.inspect(val.GetValueForExpressionPath("->imag"))
                imag = self.result.GetOutput().rstrip()
                self.result.Clear()
                if not imag.startswith("-"):
                    imag = "+" + imag
                print("(Complex) " + real + imag + "i", file=self.result)

            elif rval.is_type("RUBY_T_REGEXP"):
                tRRegex = self.target.FindFirstType("struct RRegexp").GetPointerType()
                val = val.Cast(tRRegex)
                print("(Regex) ->src {", file=self.result)
                self.inspect(val.GetValueForExpressionPath("->src"))
                print("}", file=self.result)

            elif rval.is_type("RUBY_T_DATA"):
                tRTypedData = self.target.FindFirstType("struct RTypedData").GetPointerType()
                val = val.Cast(tRTypedData)
                flag = val.GetValueForExpressionPath("->typed_flag")

                if flag.GetValueAsUnsigned() == 1:
                    print("T_DATA: %s" %
                          val.GetValueForExpressionPath("->type->wrap_struct_name"),
                          file=self.result)
                    self._append_expression("*(struct RTypedData *) %0#x" % val.GetValueAsUnsigned())
                else:
                    print("T_DATA:", file=self.result)
                    self._append_expression("*(struct RData *) %0#x" % val.GetValueAsUnsigned())

            elif rval.is_type("RUBY_T_IMEMO"):
                imemo_type = ((rval.flags >> self.ruby_globals["RUBY_FL_USHIFT"])
                              & IMEMO_MASK)
                print("T_IMEMO: ", file=self.result)

                self._append_expression("(enum imemo_type) %d" % imemo_type)
                self._append_expression("*(struct MEMO *) %0#x" % val.GetValueAsUnsigned())

            elif rval.is_type("RUBY_T_FILE"):
                self.generic_inspect(val, "RFile")

            elif rval.is_type("RUBY_T_MOVED"):
                self.generic_inspect(val, "RMoved")

            elif rval.is_type("RUBY_T_MATCH"):
                self.generic_inspect(val, "RMatch")

            elif rval.is_type("RUBY_T_STRUCT"):
                self.generic_inspect(val, "RStruct")

            elif rval.is_type("RUBY_T_ZOMBIE"):
                self.generic_inspect(val, "RZombie")

            else:
                print("Not-handled type %0#x" % rval.type, file=self.result)
                print(val, file=self.result)

    def inspect_node(self, val):
        tRNode = self.target.FindFirstType("struct RNode").GetPointerType()

        # if val.GetType() != tRNode: does not work for unknown reason

        if val.GetType().GetPointeeType().name != "NODE":
            return False

        rbNodeTypeMask = self.ruby_globals["RUBY_NODE_TYPEMASK"]
        rbNodeTypeShift = self.ruby_globals["RUBY_NODE_TYPESHIFT"]
        flags = val.Cast(tRNode).GetChildMemberWithName("flags").GetValueAsUnsigned()
        nd_type = (flags & rbNodeTypeMask) >> rbNodeTypeShift

        self._append_expression("(node_type) %d" % nd_type)

        if nd_type == self.ruby_globals["NODE_SCOPE"]:
            self._append_expression("*(rb_node_scope_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_BLOCK"]:
            self._append_expression("*(rb_node_block_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_IF"]:
            self._append_expression("*(rb_node_if_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_UNLESS"]:
            self._append_expression("*(rb_node_unless_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_CASE"]:
            self._append_expression("*(rb_node_case_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_CASE2"]:
            self._append_expression("*(rb_node_case2_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_CASE3"]:
            self._append_expression("*(rb_node_case3_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_WHEN"]:
            self._append_expression("*(rb_node_when_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_IN"]:
            self._append_expression("*(rb_node_in_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_WHILE"]:
            self._append_expression("*(rb_node_while_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_UNTIL"]:
            self._append_expression("*(rb_node_until_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_ITER"]:
            self._append_expression("*(rb_node_iter_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_FOR"]:
            self._append_expression("*(rb_node_for_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_FOR_MASGN"]:
            self._append_expression("*(rb_node_for_masgn_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_BREAK"]:
            self._append_expression("*(rb_node_break_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_NEXT"]:
            self._append_expression("*(rb_node_next_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_REDO"]:
            self._append_expression("*(rb_node_redo_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_RETRY"]:
            self._append_expression("*(rb_node_retry_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_BEGIN"]:
            self._append_expression("*(rb_node_begin_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_RESCUE"]:
            self._append_expression("*(rb_node_rescue_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_RESBODY"]:
            self._append_expression("*(rb_node_resbody_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_ENSURE"]:
            self._append_expression("*(rb_node_ensure_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_AND"]:
            self._append_expression("*(rb_node_and_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_OR"]:
            self._append_expression("*(rb_node_or_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_MASGN"]:
            self._append_expression("*(rb_node_masgn_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_LASGN"]:
            self._append_expression("*(rb_node_lasgn_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_DASGN"]:
            self._append_expression("*(rb_node_dasgn_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_GASGN"]:
            self._append_expression("*(rb_node_gasgn_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_IASGN"]:
            self._append_expression("*(rb_node_iasgn_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_CDECL"]:
            self._append_expression("*(rb_node_cdecl_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_CVASGN"]:
            self._append_expression("*(rb_node_cvasgn_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_OP_ASGN1"]:
            self._append_expression("*(rb_node_op_asgn1_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_OP_ASGN2"]:
            self._append_expression("*(rb_node_op_asgn2_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_OP_ASGN_AND"]:
            self._append_expression("*(rb_node_op_asgn_and_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_OP_ASGN_OR"]:
            self._append_expression("*(rb_node_op_asgn_or_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_OP_CDECL"]:
            self._append_expression("*(rb_node_op_cdecl_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_CALL"]:
            self._append_expression("*(rb_node_call_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_OPCALL"]:
            self._append_expression("*(rb_node_opcall_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_FCALL"]:
            self._append_expression("*(rb_node_fcall_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_VCALL"]:
            self._append_expression("*(rb_node_vcall_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_QCALL"]:
            self._append_expression("*(rb_node_qcall_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_SUPER"]:
            self._append_expression("*(rb_node_super_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_ZSUPER"]:
            self._append_expression("*(rb_node_zsuper_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_LIST"]:
            self._append_expression("*(rb_node_list_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_ZLIST"]:
            self._append_expression("*(rb_node_zlist_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_HASH"]:
            self._append_expression("*(rb_node_hash_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_RETURN"]:
            self._append_expression("*(rb_node_return_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_YIELD"]:
            self._append_expression("*(rb_node_yield_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_LVAR"]:
            self._append_expression("*(rb_node_lvar_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_DVAR"]:
            self._append_expression("*(rb_node_dvar_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_GVAR"]:
            self._append_expression("*(rb_node_gvar_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_CONST"]:
            self._append_expression("*(rb_node_const_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_CVAR"]:
            self._append_expression("*(rb_node_cvar_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_NTH_REF"]:
            self._append_expression("*(rb_node_nth_ref_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_BACK_REF"]:
            self._append_expression("*(rb_node_back_ref_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_MATCH"]:
            self._append_expression("*(rb_node_match_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_MATCH2"]:
            self._append_expression("*(rb_node_match2_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_MATCH3"]:
            self._append_expression("*(rb_node_match3_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_STR"]:
            self._append_expression("*(rb_node_str_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_DSTR"]:
            self._append_expression("*(rb_node_dstr_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_XSTR"]:
            self._append_expression("*(rb_node_xstr_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_DXSTR"]:
            self._append_expression("*(rb_node_dxstr_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_EVSTR"]:
            self._append_expression("*(rb_node_evstr_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_REGX"]:
            self._append_expression("*(rb_node_regx_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_DREGX"]:
            self._append_expression("*(rb_node_dregx_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_ONCE"]:
            self._append_expression("*(rb_node_once_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_ARGS"]:
            self._append_expression("*(rb_node_args_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_ARGS_AUX"]:
            self._append_expression("*(rb_node_args_aux_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_OPT_ARG"]:
            self._append_expression("*(rb_node_opt_arg_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_KW_ARG"]:
            self._append_expression("*(rb_node_kw_arg_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_POSTARG"]:
            self._append_expression("*(rb_node_postarg_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_ARGSCAT"]:
            self._append_expression("*(rb_node_argscat_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_ARGSPUSH"]:
            self._append_expression("*(rb_node_argspush_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_SPLAT"]:
            self._append_expression("*(rb_node_splat_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_DEFN"]:
            self._append_expression("*(rb_node_defn_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_DEFS"]:
            self._append_expression("*(rb_node_defs_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_ALIAS"]:
            self._append_expression("*(rb_node_alias_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_VALIAS"]:
            self._append_expression("*(rb_node_valias_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_UNDEF"]:
            self._append_expression("*(rb_node_undef_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_CLASS"]:
            self._append_expression("*(rb_node_class_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_MODULE"]:
            self._append_expression("*(rb_node_module_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_SCLASS"]:
            self._append_expression("*(rb_node_sclass_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_COLON2"]:
            self._append_expression("*(rb_node_colon2_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_COLON3"]:
            self._append_expression("*(rb_node_colon3_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_DOT2"]:
            self._append_expression("*(rb_node_dot2_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_DOT3"]:
            self._append_expression("*(rb_node_dot3_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_FLIP2"]:
            self._append_expression("*(rb_node_flip2_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_FLIP3"]:
            self._append_expression("*(rb_node_flip3_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_SELF"]:
            self._append_expression("*(rb_node_self_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_NIL"]:
            self._append_expression("*(rb_node_nil_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_TRUE"]:
            self._append_expression("*(rb_node_true_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_FALSE"]:
            self._append_expression("*(rb_node_false_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_ERRINFO"]:
            self._append_expression("*(rb_node_errinfo_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_DEFINED"]:
            self._append_expression("*(rb_node_defined_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_POSTEXE"]:
            self._append_expression("*(rb_node_postexe_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_DSYM"]:
            self._append_expression("*(rb_node_dsym_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_ATTRASGN"]:
            self._append_expression("*(rb_node_attrasgn_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_LAMBDA"]:
            self._append_expression("*(rb_node_lambda_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_ARYPTN"]:
            self._append_expression("*(rb_node_aryptn_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_HSHPTN"]:
            self._append_expression("*(rb_node_hshptn_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_FNDPTN"]:
            self._append_expression("*(rb_node_fndptn_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_ERROR"]:
            self._append_expression("*(rb_node_error_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_LINE"]:
            self._append_expression("*(rb_node_line_t *) %0#x" % val.GetValueAsUnsigned())
        elif nd_type == self.ruby_globals["NODE_FILE"]:
            self._append_expression("*(rb_node_file_t *) %0#x" % val.GetValueAsUnsigned())
        else:
            self._append_expression("*(NODE *) %0#x" % val.GetValueAsUnsigned())
        return True
