from lldb_rb.lldb_interface import LLDBInterface
from lldb_rb.rb_heap_structs import HeapPage, RbObject
from lldb_rb.constants import *

class RbInspector(LLDBInterface):
    def __init__(self, debugger, result, ruby_globals):
        self.build_environment(debugger)
        self.result = result
        self.ruby_globals = ruby_globals

    def _append_command_output(self, command):
        output1 = self.result.GetOutput()
        self.debugger.GetCommandInterpreter().HandleCommand(command, self.result)
        output2 = self.result.GetOutput()
        self.result.Clear()
        self.result.write(output1)
        self.result.write(output2)

    def _append_expression(self, expression):
        self._append_command_output("expression " + expression)

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

            elif rval.is_type("RUBY_T_NODE"):
                tRNode = self.target.FindFirstType("struct RNode").GetPointerType()
                rbNodeTypeMask = self.ruby_globals["RUBY_NODE_TYPEMASK"]
                rbNodeTypeShift = self.ruby_globals["RUBY_NODE_TYPESHIFT"]

                nd_type = (rval.flags & rbNodeTypeMask) >> rbNodeTypeShift
                val = val.Cast(tRNode)

                self._append_expression("(node_type) %d" % nd_type)

                if nd_type == self.ruby_globals["NODE_SCOPE"]:
                    self._append_expression("*(struct RNode_SCOPE *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_BLOCK"]:
                    self._append_expression("*(struct RNode_BLOCK *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_IF"]:
                    self._append_expression("*(struct RNode_IF *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_UNLESS"]:
                    self._append_expression("*(struct RNode_UNLESS *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_CASE"]:
                    self._append_expression("*(struct RNode_CASE *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_CASE2"]:
                    self._append_expression("*(struct RNode_CASE2 *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_CASE3"]:
                    self._append_expression("*(struct RNode_CASE3 *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_WHEN"]:
                    self._append_expression("*(struct RNode_WHEN *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_IN"]:
                    self._append_expression("*(struct RNode_IN *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_WHILE"]:
                    self._append_expression("*(struct RNode_WHILE *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_UNTIL"]:
                    self._append_expression("*(struct RNode_UNTIL *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_ITER"]:
                    self._append_expression("*(struct RNode_ITER *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_FOR"]:
                    self._append_expression("*(struct RNode_FOR *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_FOR_MASGN"]:
                    self._append_expression("*(struct RNode_FOR_MASGN *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_BREAK"]:
                    self._append_expression("*(struct RNode_BREAK *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_NEXT"]:
                    self._append_expression("*(struct RNode_NEXT *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_REDO"]:
                    self._append_expression("*(struct RNode_REDO *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_RETRY"]:
                    self._append_expression("*(struct RNode_RETRY *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_BEGIN"]:
                    self._append_expression("*(struct RNode_BEGIN *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_RESCUE"]:
                    self._append_expression("*(struct RNode_RESCUE *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_RESBODY"]:
                    self._append_expression("*(struct RNode_RESBODY *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_ENSURE"]:
                    self._append_expression("*(struct RNode_ENSURE *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_AND"]:
                    self._append_expression("*(struct RNode_AND *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_OR"]:
                    self._append_expression("*(struct RNode_OR *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_MASGN"]:
                    self._append_expression("*(struct RNode_MASGN *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_LASGN"]:
                    self._append_expression("*(struct RNode_LASGN *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_DASGN"]:
                    self._append_expression("*(struct RNode_DASGN *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_GASGN"]:
                    self._append_expression("*(struct RNode_GASGN *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_IASGN"]:
                    self._append_expression("*(struct RNode_IASGN *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_CDECL"]:
                    self._append_expression("*(struct RNode_CDECL *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_CVASGN"]:
                    self._append_expression("*(struct RNode_CVASGN *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_OP_ASGN1"]:
                    self._append_expression("*(struct RNode_OP_ASGN1 *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_OP_ASGN2"]:
                    self._append_expression("*(struct RNode_OP_ASGN2 *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_OP_ASGN_AND"]:
                    self._append_expression("*(struct RNode_OP_ASGN_AND *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_OP_ASGN_OR"]:
                    self._append_expression("*(struct RNode_OP_ASGN_OR *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_OP_CDECL"]:
                    self._append_expression("*(struct RNode_OP_CDECL *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_CALL"]:
                    self._append_expression("*(struct RNode_CALL *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_OPCALL"]:
                    self._append_expression("*(struct RNode_OPCALL *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_FCALL"]:
                    self._append_expression("*(struct RNode_FCALL *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_VCALL"]:
                    self._append_expression("*(struct RNode_VCALL *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_QCALL"]:
                    self._append_expression("*(struct RNode_QCALL *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_SUPER"]:
                    self._append_expression("*(struct RNode_SUPER *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_ZSUPER"]:
                    self._append_expression("*(struct RNode_ZSUPER *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_LIST"]:
                    self._append_expression("*(struct RNode_LIST *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_ZLIST"]:
                    self._append_expression("*(struct RNode_ZLIST *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_HASH"]:
                    self._append_expression("*(struct RNode_HASH *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_RETURN"]:
                    self._append_expression("*(struct RNode_RETURN *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_YIELD"]:
                    self._append_expression("*(struct RNode_YIELD *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_LVAR"]:
                    self._append_expression("*(struct RNode_LVAR *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_DVAR"]:
                    self._append_expression("*(struct RNode_DVAR *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_GVAR"]:
                    self._append_expression("*(struct RNode_GVAR *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_CONST"]:
                    self._append_expression("*(struct RNode_CONST *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_CVAR"]:
                    self._append_expression("*(struct RNode_CVAR *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_NTH_REF"]:
                    self._append_expression("*(struct RNode_NTH_REF *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_BACK_REF"]:
                    self._append_expression("*(struct RNode_BACK_REF *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_MATCH"]:
                    self._append_expression("*(struct RNode_MATCH *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_MATCH2"]:
                    self._append_expression("*(struct RNode_MATCH2 *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_MATCH3"]:
                    self._append_expression("*(struct RNode_MATCH3 *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_LIT"]:
                    self._append_expression("*(struct RNode_LIT *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_STR"]:
                    self._append_expression("*(struct RNode_STR *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_DSTR"]:
                    self._append_expression("*(struct RNode_DSTR *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_XSTR"]:
                    self._append_expression("*(struct RNode_XSTR *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_DXSTR"]:
                    self._append_expression("*(struct RNode_DXSTR *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_EVSTR"]:
                    self._append_expression("*(struct RNode_EVSTR *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_REGX"]:
                    self._append_expression("*(struct RNode_REGX *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_DREGX"]:
                    self._append_expression("*(struct RNode_DREGX *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_ONCE"]:
                    self._append_expression("*(struct RNode_ONCE *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_ARGS"]:
                    self._append_expression("*(struct RNode_ARGS *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_ARGS_AUX"]:
                    self._append_expression("*(struct RNode_ARGS_AUX *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_OPT_ARG"]:
                    self._append_expression("*(struct RNode_OPT_ARG *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_KW_ARG"]:
                    self._append_expression("*(struct RNode_KW_ARG *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_POSTARG"]:
                    self._append_expression("*(struct RNode_POSTARG *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_ARGSCAT"]:
                    self._append_expression("*(struct RNode_ARGSCAT *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_ARGSPUSH"]:
                    self._append_expression("*(struct RNode_ARGSPUSH *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_SPLAT"]:
                    self._append_expression("*(struct RNode_SPLAT *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_DEFN"]:
                    self._append_expression("*(struct RNode_DEFN *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_DEFS"]:
                    self._append_expression("*(struct RNode_DEFS *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_ALIAS"]:
                    self._append_expression("*(struct RNode_ALIAS *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_VALIAS"]:
                    self._append_expression("*(struct RNode_VALIAS *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_UNDEF"]:
                    self._append_expression("*(struct RNode_UNDEF *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_CLASS"]:
                    self._append_expression("*(struct RNode_CLASS *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_MODULE"]:
                    self._append_expression("*(struct RNode_MODULE *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_SCLASS"]:
                    self._append_expression("*(struct RNode_SCLASS *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_COLON2"]:
                    self._append_expression("*(struct RNode_COLON2 *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_COLON3"]:
                    self._append_expression("*(struct RNode_COLON3 *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_DOT2"]:
                    self._append_expression("*(struct RNode_DOT2 *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_DOT3"]:
                    self._append_expression("*(struct RNode_DOT3 *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_FLIP2"]:
                    self._append_expression("*(struct RNode_FLIP2 *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_FLIP3"]:
                    self._append_expression("*(struct RNode_FLIP3 *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_SELF"]:
                    self._append_expression("*(struct RNode_SELF *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_NIL"]:
                    self._append_expression("*(struct RNode_NIL *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_TRUE"]:
                    self._append_expression("*(struct RNode_TRUE *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_FALSE"]:
                    self._append_expression("*(struct RNode_FALSE *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_ERRINFO"]:
                    self._append_expression("*(struct RNode_ERRINFO *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_DEFINED"]:
                    self._append_expression("*(struct RNode_DEFINED *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_POSTEXE"]:
                    self._append_expression("*(struct RNode_POSTEXE *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_DSYM"]:
                    self._append_expression("*(struct RNode_DSYM *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_ATTRASGN"]:
                    self._append_expression("*(struct RNode_ATTRASGN *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_LAMBDA"]:
                    self._append_expression("*(struct RNode_LAMBDA *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_ARYPTN"]:
                    self._append_expression("*(struct RNode_ARYPTN *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_HSHPTN"]:
                    self._append_expression("*(struct RNode_HSHPTN *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_FNDPTN"]:
                    self._append_expression("*(struct RNode_FNDPTN *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_ERROR"]:
                    self._append_expression("*(struct RNode_ERROR *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_LINE"]:
                    self._append_expression("*(struct RNode_LINE *) %0#x" % val.GetValueAsUnsigned())
                elif nd_type == self.ruby_globals["NODE_FILE"]:
                    self._append_expression("*(struct RNode_FILE *) %0#x" % val.GetValueAsUnsigned())
                else:
                    self._append_expression("*(struct RNode *) %0#x" % val.GetValueAsUnsigned())

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
