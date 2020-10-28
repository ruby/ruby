# Copyright (c) 2013 Peter Zotov  <whitequark@whitequark.org>
#
# Parts of the source are derived from ruby_parser:
# Copyright (c) Ryan Davis, seattle.rb
#
# MIT License
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Parser::Ruby18

token kCLASS kMODULE kDEF kUNDEF kBEGIN kRESCUE kENSURE kEND kIF kUNLESS
      kTHEN kELSIF kELSE kCASE kWHEN kWHILE kUNTIL kFOR kBREAK kNEXT
      kREDO kRETRY kIN kDO kDO_COND kDO_BLOCK kRETURN kYIELD kSUPER
      kSELF kNIL kTRUE kFALSE kAND kOR kNOT kIF_MOD kUNLESS_MOD kWHILE_MOD
      kUNTIL_MOD kRESCUE_MOD kALIAS kDEFINED klBEGIN klEND k__LINE__
      k__FILE__ tIDENTIFIER tFID tGVAR tIVAR tCONSTANT tCVAR tNTH_REF
      tBACK_REF tSTRING_CONTENT tINTEGER tFLOAT tREGEXP_END tUPLUS
      tUMINUS tUMINUS_NUM tPOW tCMP tEQ tEQQ tNEQ tGEQ tLEQ tANDOP
      tOROP tMATCH tNMATCH tDOT tDOT2 tDOT3 tAREF tASET tLSHFT tRSHFT
      tCOLON2 tCOLON3 tOP_ASGN tASSOC tLPAREN tLPAREN2 tRPAREN tLPAREN_ARG
      tLBRACK tLBRACK2 tRBRACK tLBRACE tLBRACE_ARG tSTAR tSTAR2 tAMPER tAMPER2
      tTILDE tPERCENT tDIVIDE tPLUS tMINUS tLT tGT tPIPE tBANG tCARET
      tLCURLY tRCURLY tBACK_REF2 tSYMBEG tSTRING_BEG tXSTRING_BEG tREGEXP_BEG
      tWORDS_BEG tQWORDS_BEG tSTRING_DBEG tSTRING_DVAR tSTRING_END tSTRING
      tSYMBOL tREGEXP_OPT tNL tEH tCOLON tCOMMA tSPACE tSEMI

prechigh
  right    tBANG tTILDE tUPLUS
  right    tPOW
  right    tUMINUS_NUM tUMINUS
  left     tSTAR2 tDIVIDE tPERCENT
  left     tPLUS tMINUS
  left     tLSHFT tRSHFT
  left     tAMPER2
  left     tPIPE tCARET
  left     tGT tGEQ tLT tLEQ
  nonassoc tCMP tEQ tEQQ tNEQ tMATCH tNMATCH
  left     tANDOP
  left     tOROP
  nonassoc tDOT2 tDOT3
  right    tEH tCOLON
  left     kRESCUE_MOD
  right    tEQL tOP_ASGN
  nonassoc kDEFINED
  right    kNOT
  left     kOR kAND
  nonassoc kIF_MOD kUNLESS_MOD kWHILE_MOD kUNTIL_MOD
  nonassoc tLBRACE_ARG
  nonassoc tLOWEST
preclow

rule

         program: compstmt
                    {
                      result = val[0]
                    }

        bodystmt: compstmt opt_rescue opt_else opt_ensure
                    {
                      rescue_bodies     = val[1]
                      else_t,   else_   = val[2]
                      ensure_t, ensure_ = val[3]

                      if rescue_bodies.empty? && !else_.nil?
                        diagnostic :warning, :useless_else, nil, else_t
                      end

                      result = @builder.begin_body(val[0],
                                  rescue_bodies,
                                  else_t,   else_,
                                  ensure_t, ensure_)
                    }

        compstmt: stmts opt_terms
                    {
                      result = @builder.compstmt(val[0])
                    }

           stmts: # nothing
                    {
                      result = []
                    }
                | stmt
                    {
                      result = [ val[0] ]
                    }
                | error stmt
                    {
                      result = [ val[1] ]
                    }
                | stmts terms stmt
                    {
                      result = val[0] << val[2]
                    }

            stmt: kALIAS fitem
                    {
                      @lexer.state = :expr_fname
                    }
                    fitem
                    {
                      result = @builder.alias(val[0], val[1], val[3])
                    }
                | kALIAS tGVAR tGVAR
                    {
                      result = @builder.alias(val[0],
                                  @builder.gvar(val[1]),
                                  @builder.gvar(val[2]))
                    }
                | kALIAS tGVAR tBACK_REF
                    {
                      result = @builder.alias(val[0],
                                  @builder.gvar(val[1]),
                                  @builder.back_ref(val[2]))
                    }
                | kALIAS tGVAR tNTH_REF
                    {
                      diagnostic :error, :nth_ref_alias, nil, val[2]
                    }
                | kUNDEF undef_list
                    {
                      result = @builder.undef_method(val[0], val[1])
                    }
                | stmt kIF_MOD expr_value
                    {
                      result = @builder.condition_mod(val[0], nil,
                                                      val[1], val[2])
                    }
                | stmt kUNLESS_MOD expr_value
                    {
                      result = @builder.condition_mod(nil, val[0],
                                                      val[1], val[2])
                    }
                | stmt kWHILE_MOD expr_value
                    {
                      result = @builder.loop_mod(:while, val[0], val[1], val[2])
                    }
                | stmt kUNTIL_MOD expr_value
                    {
                      result = @builder.loop_mod(:until, val[0], val[1], val[2])
                    }
                | stmt kRESCUE_MOD stmt
                    {
                      rescue_body = @builder.rescue_body(val[1],
                                        nil, nil, nil,
                                        nil, val[2])

                      result = @builder.begin_body(val[0], [ rescue_body ])
                    }
                | klBEGIN tLCURLY compstmt tRCURLY
                    {
                      if in_def?
                        diagnostic :error, :begin_in_method, nil, val[0]
                      end

                      result = @builder.preexe(val[0], val[1], val[2], val[3])
                    }
                | klEND tLCURLY compstmt tRCURLY
                    {
                      result = @builder.postexe(val[0], val[1], val[2], val[3])
                    }
                | lhs tEQL command_call
                    {
                      result = @builder.assign(val[0], val[1], val[2])
                    }
                | mlhs tEQL command_call
                    {
                      result = @builder.multi_assign(val[0], val[1], val[2])
                    }
                | var_lhs tOP_ASGN command_call
                    {
                      result = @builder.op_assign(val[0], val[1], val[2])
                    }
                | primary_value tLBRACK2 aref_args tRBRACK tOP_ASGN command_call
                    {
                      result = @builder.op_assign(
                                  @builder.index(
                                    val[0], val[1], val[2], val[3]),
                                  val[4], val[5])
                    }
                | primary_value tDOT tIDENTIFIER tOP_ASGN command_call
                    {
                      result = @builder.op_assign(
                                  @builder.call_method(
                                    val[0], val[1], val[2]),
                                  val[3], val[4])
                    }
                | primary_value tDOT tCONSTANT tOP_ASGN command_call
                    {
                      result = @builder.op_assign(
                                  @builder.call_method(
                                    val[0], val[1], val[2]),
                                  val[3], val[4])
                    }
                | primary_value tCOLON2 tIDENTIFIER tOP_ASGN command_call
                    {
                      result = @builder.op_assign(
                                  @builder.call_method(
                                    val[0], val[1], val[2]),
                                  val[3], val[4])
                    }
                | backref tOP_ASGN command_call
                    {
                      @builder.op_assign(val[0], val[1], val[2])
                    }
                | lhs tEQL mrhs
                    {
                      result = @builder.assign(val[0], val[1],
                                  @builder.array(nil, val[2], nil))
                    }
                | mlhs tEQL arg_value
                    {
                      result = @builder.multi_assign(val[0], val[1], val[2])
                    }
                | mlhs tEQL mrhs
                    {
                      result = @builder.multi_assign(val[0], val[1],
                                  @builder.array(nil, val[2], nil))
                    }
                | expr

            expr: command_call
                | expr kAND expr
                    {
                      result = @builder.logical_op(:and, val[0], val[1], val[2])
                    }
                | expr kOR expr
                    {
                      result = @builder.logical_op(:or, val[0], val[1], val[2])
                    }
                | kNOT expr
                    {
                      result = @builder.not_op(val[0], nil, val[1], nil)
                    }
                | tBANG command_call
                    {
                      result = @builder.not_op(val[0], nil, val[1], nil)
                    }
                | arg

      expr_value: expr

    command_call: command
                | block_command
                | kRETURN call_args
                    {
                      result = @builder.keyword_cmd(:return, val[0],
                                  nil, val[1], nil)
                    }
                | kBREAK call_args
                    {
                      result = @builder.keyword_cmd(:break, val[0],
                                  nil, val[1], nil)
                    }
                | kNEXT call_args
                    {
                      result = @builder.keyword_cmd(:next, val[0],
                                  nil, val[1], nil)
                    }

   block_command: block_call
                | block_call tDOT operation2 command_args
                    {
                      lparen_t, args, rparen_t = val[3]
                      result = @builder.call_method(val[0], val[1], val[2],
                                  lparen_t, args, rparen_t)
                    }
                | block_call tCOLON2 operation2 command_args
                    {
                      lparen_t, args, rparen_t = val[3]
                      result = @builder.call_method(val[0], val[1], val[2],
                                  lparen_t, args, rparen_t)
                    }

 cmd_brace_block: tLBRACE_ARG
                    {
                      @static_env.extend_dynamic
                    }
                    opt_block_var compstmt tRCURLY
                    {
                      result = [ val[0], val[2], val[3], val[4] ]

                      @static_env.unextend
                    }

         command: operation command_args =tLOWEST
                    {
                      lparen_t, args, rparen_t = val[1]
                      result = @builder.call_method(nil, nil, val[0],
                                  lparen_t, args, rparen_t)
                    }
                | operation command_args cmd_brace_block
                    {
                      lparen_t, args, rparen_t = val[1]
                      method_call = @builder.call_method(nil, nil, val[0],
                                      lparen_t, args, rparen_t)

                      begin_t, block_args, body, end_t = val[2]
                      result      = @builder.block(method_call,
                                      begin_t, block_args, body, end_t)
                    }
                | primary_value tDOT operation2 command_args =tLOWEST
                    {
                      lparen_t, args, rparen_t = val[3]
                      result = @builder.call_method(val[0], val[1], val[2],
                                  lparen_t, args, rparen_t)

                    }
                | primary_value tDOT operation2 command_args cmd_brace_block
                    {
                      lparen_t, args, rparen_t = val[3]
                      method_call = @builder.call_method(val[0], val[1], val[2],
                                      lparen_t, args, rparen_t)

                      begin_t, block_args, body, end_t = val[4]
                      result      = @builder.block(method_call,
                                      begin_t, block_args, body, end_t)
                    }
                | primary_value tCOLON2 operation2 command_args =tLOWEST
                    {
                      lparen_t, args, rparen_t = val[3]
                      result = @builder.call_method(val[0], val[1], val[2],
                                  lparen_t, args, rparen_t)
                    }
                | primary_value tCOLON2 operation2 command_args cmd_brace_block
                    {
                      lparen_t, args, rparen_t = val[3]
                      method_call = @builder.call_method(val[0], val[1], val[2],
                                      lparen_t, args, rparen_t)

                      begin_t, block_args, body, end_t = val[4]
                      result      = @builder.block(method_call,
                                      begin_t, block_args, body, end_t)
                    }
                | kSUPER command_args
                    {
                      lparen_t, args, rparen_t = val[1]
                      result = @builder.keyword_cmd(:super, val[0],
                                  lparen_t, args, rparen_t)
                    }
                | kYIELD command_args
                    {
                      lparen_t, args, rparen_t = val[1]
                      result = @builder.keyword_cmd(:yield, val[0],
                                  lparen_t, args, rparen_t)
                    }

            mlhs: mlhs_basic
                    {
                      result = @builder.multi_lhs(nil, val[0], nil)
                    }
                | tLPAREN mlhs_entry tRPAREN
                    {
                      result = @builder.begin(val[0], val[1], val[2])
                    }

      mlhs_entry: mlhs_basic
                    {
                      result = @builder.multi_lhs(nil, val[0], nil)
                    }
                | tLPAREN mlhs_entry tRPAREN
                    {
                      result = @builder.multi_lhs(val[0], val[1], val[2])
                    }

      mlhs_basic: mlhs_head
                    {
                      result = val[0]
                    }
                | mlhs_head mlhs_item
                    {
                      result = val[0] << val[1]
                    }
                | mlhs_head tSTAR mlhs_node
                    {
                      result = val[0] << @builder.splat(val[1], val[2])
                    }
                | mlhs_head tSTAR
                    {
                      result = val[0] << @builder.splat(val[1])
                    }
                | tSTAR mlhs_node
                    {
                      result = [ @builder.splat(val[0], val[1]) ]
                    }
                | tSTAR
                    {
                      result = [ @builder.splat(val[0]) ]
                    }

       mlhs_item: mlhs_node
                | tLPAREN mlhs_entry tRPAREN
                    {
                      result = @builder.begin(val[0], val[1], val[2])
                    }

       mlhs_head: mlhs_item tCOMMA
                    {
                      result = [ val[0] ]
                    }
                | mlhs_head mlhs_item tCOMMA
                    {
                      result = val[0] << val[1]
                    }

       mlhs_node: variable
                    {
                      result = @builder.assignable(val[0])
                    }
                | primary_value tLBRACK2 aref_args tRBRACK
                    {
                      result = @builder.index_asgn(val[0], val[1], val[2], val[3])
                    }
                | primary_value tDOT tIDENTIFIER
                    {
                      result = @builder.attr_asgn(val[0], val[1], val[2])
                    }
                | primary_value tCOLON2 tIDENTIFIER
                    {
                      result = @builder.attr_asgn(val[0], val[1], val[2])
                    }
                | primary_value tDOT tCONSTANT
                    {
                      result = @builder.attr_asgn(val[0], val[1], val[2])
                    }
                | primary_value tCOLON2 tCONSTANT
                    {
                      result = @builder.assignable(
                                  @builder.const_fetch(val[0], val[1], val[2]))
                    }
                | tCOLON3 tCONSTANT
                    {
                      result = @builder.assignable(
                                  @builder.const_global(val[0], val[1]))
                    }
                | backref
                    {
                      result = @builder.assignable(val[0])
                    }

             lhs: variable
                    {
                      result = @builder.assignable(val[0])
                    }
                | primary_value tLBRACK2 aref_args tRBRACK
                    {
                      result = @builder.index_asgn(val[0], val[1], val[2], val[3])
                    }
                | primary_value tDOT tIDENTIFIER
                    {
                      result = @builder.attr_asgn(val[0], val[1], val[2])
                    }
                | primary_value tCOLON2 tIDENTIFIER
                    {
                      result = @builder.attr_asgn(val[0], val[1], val[2])
                    }
                | primary_value tDOT tCONSTANT
                    {
                      result = @builder.attr_asgn(val[0], val[1], val[2])
                    }
                | primary_value tCOLON2 tCONSTANT
                    {
                      result = @builder.assignable(
                                  @builder.const_fetch(val[0], val[1], val[2]))
                    }
                | tCOLON3 tCONSTANT
                    {
                      result = @builder.assignable(
                                  @builder.const_global(val[0], val[1]))
                    }
                | backref
                    {
                      result = @builder.assignable(val[0])
                    }

           cname: tIDENTIFIER
                    {
                      diagnostic :error, :module_name_const, nil, val[0]
                    }
                | tCONSTANT

           cpath: tCOLON3 cname
                    {
                      result = @builder.const_global(val[0], val[1])
                    }
                | cname
                    {
                      result = @builder.const(val[0])
                    }
                | primary_value tCOLON2 cname
                    {
                      result = @builder.const_fetch(val[0], val[1], val[2])
                    }

           fname: tIDENTIFIER | tCONSTANT | tFID
                | op
                | reswords

            fsym: fname
                    {
                      result = @builder.symbol(val[0])
                    }
                | symbol

           fitem: fsym
                | dsym

      undef_list: fitem
                    {
                      result = [ val[0] ]
                    }
                | undef_list tCOMMA
                    {
                      @lexer.state = :expr_fname
                    }
                    fitem
                    {
                      result = val[0] << val[3]
                    }

              op: tPIPE    | tCARET     | tAMPER2 | tCMP   | tEQ     | tEQQ
                | tMATCH   | tGT        | tGEQ    | tLT    | tLEQ    | tLSHFT
                | tRSHFT   | tPLUS      | tMINUS  | tSTAR2 | tSTAR   | tDIVIDE
                | tPERCENT | tPOW       | tTILDE  | tUPLUS | tUMINUS | tAREF
                | tASET    | tBACK_REF2

        reswords: k__LINE__ | k__FILE__   | klBEGIN | klEND  | kALIAS  | kAND
                | kBEGIN    | kBREAK      | kCASE   | kCLASS | kDEF    | kDEFINED
                | kDO       | kELSE       | kELSIF  | kEND   | kENSURE | kFALSE
                | kFOR      | kIN         | kMODULE | kNEXT  | kNIL    | kNOT
                | kOR       | kREDO       | kRESCUE | kRETRY | kRETURN | kSELF
                | kSUPER    | kTHEN       | kTRUE   | kUNDEF | kWHEN   | kYIELD
                | kIF       | kUNLESS     | kWHILE  | kUNTIL

             arg: lhs tEQL arg
                    {
                      result = @builder.assign(val[0], val[1], val[2])
                    }
                | lhs tEQL arg kRESCUE_MOD arg
                    {
                      rescue_body = @builder.rescue_body(val[3],
                                        nil, nil, nil,
                                        nil, val[4])

                      rescue_ = @builder.begin_body(val[2], [ rescue_body ])

                      result  = @builder.assign(val[0], val[1], rescue_)
                    }
                | var_lhs tOP_ASGN arg
                    {
                      result = @builder.op_assign(val[0], val[1], val[2])
                    }
                | primary_value tLBRACK2 aref_args tRBRACK tOP_ASGN arg
                    {
                      result = @builder.op_assign(
                                  @builder.index(
                                    val[0], val[1], val[2], val[3]),
                                  val[4], val[5])
                    }
                | primary_value tDOT tIDENTIFIER tOP_ASGN arg
                    {
                      result = @builder.op_assign(
                                  @builder.call_method(
                                    val[0], val[1], val[2]),
                                  val[3], val[4])
                    }
                | primary_value tDOT tCONSTANT tOP_ASGN arg
                    {
                      result = @builder.op_assign(
                                  @builder.call_method(
                                    val[0], val[1], val[2]),
                                  val[3], val[4])
                    }
                | primary_value tCOLON2 tIDENTIFIER tOP_ASGN arg
                    {
                      result = @builder.op_assign(
                                  @builder.call_method(
                                    val[0], val[1], val[2]),
                                  val[3], val[4])
                    }
                | primary_value tCOLON2 tCONSTANT tOP_ASGN arg
                    {
                      diagnostic :error, :dynamic_const, nil, val[2], [ val[3] ]
                    }
                | tCOLON3 tCONSTANT tOP_ASGN arg
                    {
                      diagnostic :error, :dynamic_const, nil, val[1], [ val[2] ]
                    }
                | backref tOP_ASGN arg
                    {
                      result = @builder.op_assign(val[0], val[1], val[2])
                    }
                | arg tDOT2 arg
                    {
                      result = @builder.range_inclusive(val[0], val[1], val[2])
                    }
                | arg tDOT3 arg
                    {
                      result = @builder.range_exclusive(val[0], val[1], val[2])
                    }
                | arg tPLUS arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tMINUS arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tSTAR2 arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tDIVIDE arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tPERCENT arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tPOW arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | tUMINUS_NUM tINTEGER tPOW arg
                    {
                      result = @builder.unary_op(val[0],
                                  @builder.binary_op(
                                    @builder.integer(val[1]),
                                      val[2], val[3]))
                    }
                | tUMINUS_NUM tFLOAT tPOW arg
                    {
                      result = @builder.unary_op(val[0],
                                  @builder.binary_op(
                                    @builder.float(val[1]),
                                      val[2], val[3]))
                    }
                | tUPLUS arg
                    {
                      result = @builder.unary_op(val[0], val[1])
                    }
                | tUMINUS arg
                    {
                      result = @builder.unary_op(val[0], val[1])
                    }
                | arg tPIPE arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tCARET arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tAMPER2 arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tCMP arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tGT arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tGEQ arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tLT arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tLEQ arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tEQ arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tEQQ arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tNEQ arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tMATCH arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tNMATCH arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | tBANG arg
                    {
                      result = @builder.not_op(val[0], nil, val[1], nil)
                    }
                | tTILDE arg
                    {
                      result = @builder.unary_op(val[0], val[1])
                    }
                | arg tLSHFT arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tRSHFT arg
                    {
                      result = @builder.binary_op(val[0], val[1], val[2])
                    }
                | arg tANDOP arg
                    {
                      result = @builder.logical_op(:and, val[0], val[1], val[2])
                    }
                | arg tOROP arg
                    {
                      result = @builder.logical_op(:or, val[0], val[1], val[2])
                    }
                | kDEFINED opt_nl arg
                    {
                      result = @builder.keyword_cmd(:defined?, val[0], nil, [ val[2] ], nil)
                    }
                | arg tEH arg tCOLON arg
                    {
                      result = @builder.ternary(val[0], val[1],
                                                val[2], val[3], val[4])
                    }
                | primary

       arg_value: arg

       aref_args: none
                | command opt_nl
                    {
                      result = [ val[0] ]
                    }
                | args trailer
                    {
                      result = val[0]
                    }
                | args tCOMMA tSTAR arg opt_nl
                    {
                      result = val[0] << @builder.splat(val[2], val[3])
                    }
                | assocs trailer
                    {
                      result = [ @builder.associate(nil, val[0], nil) ]
                    }
                | tSTAR arg opt_nl
                    {
                      result = [ @builder.splat(val[0], val[1]) ]
                    }

      paren_args: tLPAREN2 none tRPAREN
                    {
                      result = [ val[0], [], val[2] ]
                    }
                | tLPAREN2 call_args opt_nl tRPAREN
                    {
                      result = [ val[0], val[1], val[3] ]
                    }
                | tLPAREN2 block_call opt_nl tRPAREN
                    {
                      result = [ val[0], [ val[1] ], val[3] ]
                    }
                | tLPAREN2 args tCOMMA block_call opt_nl tRPAREN
                    {
                      result = [ val[0], val[1] << val[3], val[5] ]
                    }

  opt_paren_args: # nothing
                    {
                      result = [ nil, [], nil ]
                    }
                | paren_args

       call_args: command
                    {
                      result = [ val[0] ]
                    }
                | args opt_block_arg
                    {
                      result = val[0].concat(val[1])
                    }
                | args tCOMMA tSTAR arg_value opt_block_arg
                    {
                      result = val[0].concat(
                                [ @builder.splat(val[2], val[3]),
                                   *val[4] ])
                    }
                | assocs opt_block_arg
                    {
                      result =  [ @builder.associate(nil, val[0], nil),
                                  *val[1] ]
                    }
                | assocs tCOMMA tSTAR arg_value opt_block_arg
                    {
                      result =  [ @builder.associate(nil, val[0], nil),
                                  @builder.splat(val[2], val[3]),
                                  *val[4] ]
                    }
                | args tCOMMA assocs opt_block_arg
                    {
                      result = val[0].concat(
                                [ @builder.associate(nil, val[2], nil),
                                  *val[3] ])
                    }
                | args tCOMMA assocs tCOMMA tSTAR arg opt_block_arg
                    {
                      result = val[0].concat(
                                [ @builder.associate(nil, val[2], nil),
                                  @builder.splat(val[4], val[5]),
                                  *val[6] ])
                    }
                | tSTAR arg_value opt_block_arg
                    {
                      result =  [ @builder.splat(val[0], val[1]),
                                  *val[2] ]
                    }
                | block_arg
                    {
                      result =  [ val[0] ]
                    }

      call_args2: arg_value tCOMMA args opt_block_arg
                    {
                      result = [ val[0], *val[2].concat(val[3]) ]
                    }
                | arg_value tCOMMA block_arg
                    {
                      result = [ val[0], val[2] ]
                    }
                | arg_value tCOMMA tSTAR arg_value opt_block_arg
                    {
                      result =  [ val[0],
                                  @builder.splat(val[2], val[3]),
                                  *val[4] ]
                    }
                | arg_value tCOMMA args tCOMMA tSTAR arg_value opt_block_arg
                    {
                      result =  [ val[0],
                                  *val[2].
                                    push(@builder.splat(val[4], val[5])).
                                    concat(val[6]) ]
                    }
                | assocs opt_block_arg
                    {
                      result =  [ @builder.associate(nil, val[0], nil),
                                  *val[1] ]
                    }
                | assocs tCOMMA tSTAR arg_value opt_block_arg
                    {
                      result =  [ @builder.associate(nil, val[0], nil),
                                  @builder.splat(val[2], val[3]),
                                  *val[4] ]
                    }
                | arg_value tCOMMA assocs opt_block_arg
                    {
                      result =  [ val[0],
                                  @builder.associate(nil, val[2], nil),
                                  *val[3] ]
                    }
                | arg_value tCOMMA args tCOMMA assocs opt_block_arg
                    {
                      result =  [ val[0],
                                  *val[2].
                                    push(@builder.associate(nil, val[4], nil)).
                                    concat(val[5]) ]
                    }
                | arg_value tCOMMA assocs tCOMMA tSTAR arg_value opt_block_arg
                    {
                      result =  [ val[0],
                                  @builder.associate(nil, val[2], nil),
                                  @builder.splat(val[4], val[5]),
                                  *val[6] ]
                    }
                | arg_value tCOMMA args tCOMMA assocs tCOMMA tSTAR arg_value opt_block_arg
                    {
                      result =  [ val[0],
                                  *val[2].
                                    push(@builder.associate(nil, val[4], nil)).
                                    push(@builder.splat(val[6], val[7])).
                                    concat(val[8]) ]
                    }
                | tSTAR arg_value opt_block_arg
                    {
                      result =  [ @builder.splat(val[0], val[1]),
                                  *val[2] ]
                    }
                | block_arg
                    {
                      result =  [ val[0] ]
                    }

    command_args:   {
                      result = @lexer.cmdarg.dup
                      @lexer.cmdarg.push(true)
                    }
                    open_args
                    {
                      @lexer.cmdarg = val[0]

                      result = val[1]
                    }

       open_args: call_args
                    {
                      result = [ nil, val[0], nil ]
                    }
                | tLPAREN_ARG
                    {
                      @lexer.state = :expr_endarg
                    }
                    tRPAREN
                    {
                      result = [ val[0], [], val[2] ]
                    }
                | tLPAREN_ARG call_args2
                    {
                      @lexer.state = :expr_endarg
                    }
                    tRPAREN
                    {
                      result = [ val[0], val[1], val[3] ]
                    }

       block_arg: tAMPER arg_value
                    {
                      result = @builder.block_pass(val[0], val[1])
                    }

   opt_block_arg: tCOMMA block_arg
                    {
                      result = [ val[1] ]
                    }
                | # nothing
                    {
                      result = []
                    }

            args: arg_value
                    {
                      result = [ val[0] ]
                    }
                | args tCOMMA arg_value
                    {
                      result = val[0] << val[2]
                    }

            mrhs: args tCOMMA arg_value
                    {
                      result = val[0] << val[2]
                    }
                | args tCOMMA tSTAR arg_value
                    {
                      result = val[0] << @builder.splat(val[2], val[3])
                    }
                | tSTAR arg_value
                    {
                      result = [ @builder.splat(val[0], val[1]) ]
                    }

         primary: literal
                | strings
                | xstring
                | regexp
                | words
                | qwords
                | var_ref
                | backref
                | tFID
                    {
                      result = @builder.call_method(nil, nil, val[0])
                    }
                | kBEGIN bodystmt kEND
                    {
                      result = @builder.begin_keyword(val[0], val[1], val[2])
                    }
                | tLPAREN_ARG expr
                    {
                      @lexer.state = :expr_endarg
                    }
                    opt_nl tRPAREN
                    {
                      result = @builder.begin(val[0], val[1], val[4])
                    }
                | tLPAREN compstmt tRPAREN
                    {
                      result = @builder.begin(val[0], val[1], val[2])
                    }
                | primary_value tCOLON2 tCONSTANT
                    {
                      result = @builder.const_fetch(val[0], val[1], val[2])
                    }
                | tCOLON3 tCONSTANT
                    {
                      result = @builder.const_global(val[0], val[1])
                    }
                | primary_value tLBRACK2 aref_args tRBRACK
                    {
                      result = @builder.index(val[0], val[1], val[2], val[3])
                    }
                | tLBRACK aref_args tRBRACK
                    {
                      result = @builder.array(val[0], val[1], val[2])
                    }
                | tLBRACE assoc_list tRCURLY
                    {
                      result = @builder.associate(val[0], val[1], val[2])
                    }
                | kRETURN
                    {
                      result = @builder.keyword_cmd(:return, val[0])
                    }
                | kYIELD tLPAREN2 call_args tRPAREN
                    {
                      result = @builder.keyword_cmd(:yield, val[0], val[1], val[2], val[3])
                    }
                | kYIELD tLPAREN2 tRPAREN
                    {
                      result = @builder.keyword_cmd(:yield, val[0], val[1], [], val[2])
                    }
                | kYIELD
                    {
                      result = @builder.keyword_cmd(:yield, val[0])
                    }
                | kDEFINED opt_nl tLPAREN2 expr tRPAREN
                    {
                      result = @builder.keyword_cmd(:defined?, val[0],
                                                    val[2], [ val[3] ], val[4])
                    }
                | operation brace_block
                    {
                      method_call = @builder.call_method(nil, nil, val[0])

                      begin_t, args, body, end_t = val[1]
                      result      = @builder.block(method_call,
                                      begin_t, args, body, end_t)
                    }
                | method_call
                | method_call brace_block
                    {
                      begin_t, args, body, end_t = val[1]
                      result      = @builder.block(val[0],
                                      begin_t, args, body, end_t)
                    }
                | kIF expr_value then compstmt if_tail kEND
                    {
                      else_t, else_ = val[4]
                      result = @builder.condition(val[0], val[1], val[2],
                                                  val[3], else_t,
                                                  else_,  val[5])
                    }
                | kUNLESS expr_value then compstmt opt_else kEND
                    {
                      else_t, else_ = val[4]
                      result = @builder.condition(val[0], val[1], val[2],
                                                  else_,  else_t,
                                                  val[3], val[5])
                    }
                | kWHILE
                    {
                      @lexer.cond.push(true)
                    }
                    expr_value do
                    {
                      @lexer.cond.pop
                    }
                    compstmt kEND
                    {
                      result = @builder.loop(:while, val[0], val[2], val[3],
                                             val[5], val[6])
                    }
                | kUNTIL
                    {
                      @lexer.cond.push(true)
                    }
                    expr_value do
                    {
                      @lexer.cond.pop
                    }
                    compstmt kEND
                    {
                      result = @builder.loop(:until, val[0], val[2], val[3],
                                             val[5], val[6])
                    }
                | kCASE expr_value opt_terms case_body kEND
                    {
                      when_bodies       = val[3][0..-2]
                      else_t, else_body = val[3][-1]

                      result = @builder.case(val[0], val[1],
                                             when_bodies, else_t, else_body,
                                             val[4])
                    }
                | kCASE            opt_terms case_body kEND
                    {
                      when_bodies       = val[2][0..-2]
                      else_t, else_body = val[2][-1]

                      result = @builder.case(val[0], nil,
                                             when_bodies, else_t, else_body,
                                             val[3])
                    }
                | kCASE opt_terms kELSE compstmt kEND
                    {
                      result = @builder.case(val[0], nil,
                                             [], val[2], val[3],
                                             val[4])
                    }
                | kFOR for_var kIN
                    {
                      @lexer.cond.push(true)
                    }
                    expr_value do
                    {
                      @lexer.cond.pop
                    }
                    compstmt kEND
                    {
                      result = @builder.for(val[0], val[1],
                                            val[2], val[4],
                                            val[5], val[7], val[8])
                    }
                | kCLASS cpath superclass
                    {
                      @static_env.extend_static
                    }
                    bodystmt kEND
                    {
                      if in_def?
                        diagnostic :error, :class_in_def, nil, val[0]
                      end

                      lt_t, superclass = val[2]
                      result = @builder.def_class(val[0], val[1],
                                                  lt_t, superclass,
                                                  val[4], val[5])

                      @static_env.unextend
                    }
                | kCLASS tLSHFT expr term
                    {
                      result = @def_level
                      @def_level = 0

                      @static_env.extend_static
                    }
                    bodystmt kEND
                    {
                      result = @builder.def_sclass(val[0], val[1], val[2],
                                                   val[5], val[6])

                      @static_env.unextend

                      @def_level = val[4]
                    }
                | kMODULE cpath
                    {
                      @static_env.extend_static
                    }
                    bodystmt kEND
                    {
                      if in_def?
                        diagnostic :error, :module_in_def, nil, val[0]
                      end

                      result = @builder.def_module(val[0], val[1],
                                                   val[3], val[4])

                      @static_env.unextend
                    }
                | kDEF fname
                    {
                      @def_level += 1
                      @static_env.extend_static
                    }
                    f_arglist bodystmt kEND
                    {
                      result = @builder.def_method(val[0], val[1],
                                  val[3], val[4], val[5])

                      @static_env.unextend
                      @def_level -= 1
                    }
                | kDEF singleton dot_or_colon
                    {
                      @lexer.state = :expr_fname
                    }
                    fname
                    {
                      @def_level += 1
                      @static_env.extend_static
                    }
                    f_arglist bodystmt kEND
                    {
                      result = @builder.def_singleton(val[0], val[1], val[2],
                                  val[4], val[6], val[7], val[8])

                      @static_env.unextend
                      @def_level -= 1
                    }
                | kBREAK
                    {
                      result = @builder.keyword_cmd(:break, val[0])
                    }
                | kNEXT
                    {
                      result = @builder.keyword_cmd(:next, val[0])
                    }
                | kREDO
                    {
                      result = @builder.keyword_cmd(:redo, val[0])
                    }
                | kRETRY
                    {
                      result = @builder.keyword_cmd(:retry, val[0])
                    }

   primary_value: primary

            then: term
                | tCOLON
                | kTHEN
                | term kTHEN
                    {
                      result = val[1]
                    }

              do: term
                | tCOLON
                | kDO_COND

         if_tail: opt_else
                | kELSIF expr_value then compstmt if_tail
                    {
                      else_t, else_ = val[4]
                      result = [ val[0],
                                 @builder.condition(val[0], val[1], val[2],
                                                    val[3], else_t,
                                                    else_,  nil),
                               ]
                    }

        opt_else: none
                | kELSE compstmt
                    {
                      result = val
                    }

         for_var: lhs
                | mlhs

       block_par: mlhs_item
                    {
                      result = [ @builder.arg_expr(val[0]) ]
                    }
                | block_par tCOMMA mlhs_item
                    {
                      result = val[0] << @builder.arg_expr(val[2])
                    }

       block_var: block_par
                | block_par tCOMMA
                | block_par tCOMMA tAMPER lhs
                    {
                      result =  val[0].
                                  push(@builder.blockarg_expr(val[2], val[3]))
                    }
                | block_par tCOMMA tSTAR lhs tCOMMA tAMPER lhs
                    {
                      result =  val[0].
                                  push(@builder.restarg_expr(val[2], val[3])).
                                  push(@builder.blockarg_expr(val[5], val[6]))
                    }
                | block_par tCOMMA tSTAR tCOMMA tAMPER lhs
                    {
                      result =  val[0].
                                  push(@builder.restarg_expr(val[2])).
                                  push(@builder.blockarg_expr(val[4], val[5]))
                    }
                | block_par tCOMMA tSTAR lhs
                    {
                      result =  val[0].
                                  push(@builder.restarg_expr(val[2], val[3]))
                    }
                | block_par tCOMMA tSTAR
                    {
                      result =  val[0].
                                  push(@builder.restarg_expr(val[2]))
                    }
                | tSTAR lhs tCOMMA tAMPER lhs
                    {
                      result =  [ @builder.restarg_expr(val[0], val[1]),
                                  @builder.blockarg_expr(val[3], val[4]) ]
                    }
                | tSTAR tCOMMA tAMPER lhs
                    {
                      result =  [ @builder.restarg_expr(val[0]),
                                  @builder.blockarg_expr(val[2], val[3]) ]
                    }
                | tSTAR lhs
                    {
                      result =  [ @builder.restarg_expr(val[0], val[1]) ]
                    }
                | tSTAR
                    {
                      result =  [ @builder.restarg_expr(val[0]) ]
                    }
                | tAMPER lhs
                    {
                      result =  [ @builder.blockarg_expr(val[0], val[1]) ]
                    }
                ;

   opt_block_var: # nothing
                    {
                      result = @builder.args(nil, [], nil)
                    }
                | tPIPE tPIPE
                    {
                      result = @builder.args(val[0], [], val[1])
                    }
                | tOROP
                    {
                      result = @builder.args(val[0], [], val[0])
                    }
                | tPIPE block_var tPIPE
                    {
                      result = @builder.args(val[0], val[1], val[2], false)
                    }

        do_block: kDO_BLOCK
                    {
                      @static_env.extend_dynamic
                    }
                    opt_block_var compstmt kEND
                    {
                      result = [ val[0], val[2], val[3], val[4] ]

                      @static_env.unextend
                    }

      block_call: command do_block
                    {
                      begin_t, block_args, body, end_t = val[1]
                      result      = @builder.block(val[0],
                                      begin_t, block_args, body, end_t)
                    }
                | block_call tDOT operation2 opt_paren_args
                    {
                      lparen_t, args, rparen_t = val[3]
                      result = @builder.call_method(val[0], val[1], val[2],
                                  lparen_t, args, rparen_t)
                    }
                | block_call tCOLON2 operation2 opt_paren_args
                    {
                      lparen_t, args, rparen_t = val[3]
                      result = @builder.call_method(val[0], val[1], val[2],
                                  lparen_t, args, rparen_t)
                    }

     method_call: operation paren_args
                    {
                      lparen_t, args, rparen_t = val[1]
                      result = @builder.call_method(nil, nil, val[0],
                                  lparen_t, args, rparen_t)
                    }
                | primary_value tDOT operation2 opt_paren_args
                    {
                      lparen_t, args, rparen_t = val[3]
                      result = @builder.call_method(val[0], val[1], val[2],
                                  lparen_t, args, rparen_t)
                    }
                | primary_value tCOLON2 operation2 paren_args
                    {
                      lparen_t, args, rparen_t = val[3]
                      result = @builder.call_method(val[0], val[1], val[2],
                                  lparen_t, args, rparen_t)
                    }
                | primary_value tCOLON2 operation3
                    {
                      result = @builder.call_method(val[0], val[1], val[2])
                    }
                | kSUPER paren_args
                    {
                      lparen_t, args, rparen_t = val[1]
                      result = @builder.keyword_cmd(:super, val[0],
                                  lparen_t, args, rparen_t)
                    }
                | kSUPER
                    {
                      result = @builder.keyword_cmd(:zsuper, val[0])
                    }

     brace_block: tLCURLY
                    {
                      @static_env.extend_dynamic
                    }
                    opt_block_var compstmt tRCURLY
                    {
                      result = [ val[0], val[2], val[3], val[4] ]

                      @static_env.unextend
                    }
                | kDO
                    {
                      @static_env.extend_dynamic
                    }
                    opt_block_var compstmt kEND
                    {
                      result = [ val[0], val[2], val[3], val[4] ]

                      @static_env.unextend
                    }

       case_body: kWHEN when_args then compstmt cases
                    {
                      result = [ @builder.when(val[0], val[1], val[2], val[3]),
                                 *val[4] ]
                    }

       when_args: args
                | args tCOMMA tSTAR arg_value
                    {
                      result = val[0] << @builder.splat(val[2], val[3])
                    }
                | tSTAR arg_value
                    {
                      result = [ @builder.splat(val[0], val[1]) ]
                    }

           cases: opt_else
                    {
                      result = [ val[0] ]
                    }
                | case_body

      opt_rescue: kRESCUE exc_list exc_var then compstmt opt_rescue
                    {
                      assoc_t, exc_var = val[2]

                      if val[1]
                        exc_list = @builder.array(nil, val[1], nil)
                      end

                      result = [ @builder.rescue_body(val[0],
                                      exc_list, assoc_t, exc_var,
                                      val[3], val[4]),
                                 *val[5] ]
                    }
                | # nothing
                    {
                      result = []
                    }

        exc_list: arg_value
                    {
                      result = [ val[0] ]
                    }
                | mrhs
                | none

         exc_var: tASSOC lhs
                    {
                      result = [ val[0], val[1] ]
                    }
                | none

      opt_ensure: kENSURE compstmt
                    {
                      result = [ val[0], val[1] ]
                    }
                | none

         literal: numeric
                | symbol
                | dsym

         strings: string
                    {
                      result = @builder.string_compose(nil, val[0], nil)
                    }

          string: string1
                    {
                      result = [ val[0] ]
                    }
                | string string1
                    {
                      result = val[0] << val[1]
                    }

         string1: tSTRING_BEG string_contents tSTRING_END
                    {
                      result = @builder.string_compose(val[0], val[1], val[2])
                    }
                | tSTRING
                    {
                      result = @builder.string(val[0])
                    }

         xstring: tXSTRING_BEG xstring_contents tSTRING_END
                    {
                      result = @builder.xstring_compose(val[0], val[1], val[2])
                    }

          regexp: tREGEXP_BEG xstring_contents tSTRING_END tREGEXP_OPT
                    {
                      opts   = @builder.regexp_options(val[3])
                      result = @builder.regexp_compose(val[0], val[1], val[2], opts)
                    }

           words: tWORDS_BEG word_list tSTRING_END
                    {
                      result = @builder.words_compose(val[0], val[1], val[2])
                    }

       word_list: # nothing
                    {
                      result = []
                    }
                | word_list word tSPACE
                    {
                      result = val[0] << @builder.word(val[1])
                    }

            word: string_content
                    {
                      result = [ val[0] ]
                    }
                | word string_content
                    {
                      result = val[0] << val[1]
                    }

          qwords: tQWORDS_BEG qword_list tSTRING_END
                    {
                      result = @builder.words_compose(val[0], val[1], val[2])
                    }

      qword_list: # nothing
                    {
                      result = []
                    }
                | qword_list tSTRING_CONTENT tSPACE
                    {
                      result = val[0] << @builder.string_internal(val[1])
                    }

 string_contents: # nothing
                    {
                      result = []
                    }
                | string_contents string_content
                    {
                      result = val[0] << val[1]
                    }

xstring_contents: # nothing
                    {
                      result = []
                    }
                | xstring_contents string_content
                    {
                      result = val[0] << val[1]
                    }

  string_content: tSTRING_CONTENT
                    {
                      result = @builder.string_internal(val[0])
                    }
                | tSTRING_DVAR string_dvar
                    {
                      result = val[1]
                    }
                | tSTRING_DBEG
                    {
                      @lexer.cond.push(false)
                      @lexer.cmdarg.push(false)
                    }
                    compstmt tRCURLY
                    {
                      @lexer.cond.lexpop
                      @lexer.cmdarg.lexpop

                      result = @builder.begin(val[0], val[2], val[3])
                    }

     string_dvar: tGVAR
                    {
                      result = @builder.gvar(val[0])
                    }
                | tIVAR
                    {
                      result = @builder.ivar(val[0])
                    }
                | tCVAR
                    {
                      result = @builder.cvar(val[0])
                    }
                | backref


          symbol: tSYMBOL
                    {
                      result = @builder.symbol(val[0])
                    }

            dsym: tSYMBEG xstring_contents tSTRING_END
                    {
                      result = @builder.symbol_compose(val[0], val[1], val[2])
                    }

         numeric: tINTEGER
                    {
                      result = @builder.integer(val[0])
                    }
                | tFLOAT
                    {
                      result = @builder.float(val[0])
                    }
                | tUMINUS_NUM tINTEGER =tLOWEST
                    {
                      result = @builder.negate(val[0],
                                  @builder.integer(val[1]))
                    }
                | tUMINUS_NUM tFLOAT   =tLOWEST
                    {
                      result = @builder.negate(val[0],
                                  @builder.float(val[1]))
                    }

        variable: tIDENTIFIER
                    {
                      result = @builder.ident(val[0])
                    }
                | tIVAR
                    {
                      result = @builder.ivar(val[0])
                    }
                | tGVAR
                    {
                      result = @builder.gvar(val[0])
                    }
                | tCVAR
                    {
                      result = @builder.cvar(val[0])
                    }
                | tCONSTANT
                    {
                      result = @builder.const(val[0])
                    }
                | kNIL
                    {
                      result = @builder.nil(val[0])
                    }
                | kSELF
                    {
                      result = @builder.self(val[0])
                    }
                | kTRUE
                    {
                      result = @builder.true(val[0])
                    }
                | kFALSE
                    {
                      result = @builder.false(val[0])
                    }
                | k__FILE__
                    {
                      result = @builder.__FILE__(val[0])
                    }
                | k__LINE__
                    {
                      result = @builder.__LINE__(val[0])
                    }

         var_ref: variable
                    {
                      result = @builder.accessible(val[0])
                    }

         var_lhs: variable
                    {
                      result = @builder.assignable(val[0])
                    }

         backref: tNTH_REF
                    {
                      result = @builder.nth_ref(val[0])
                    }
                | tBACK_REF
                    {
                      result = @builder.back_ref(val[0])
                    }

      superclass: term
                    {
                      result = nil
                    }
                | tLT expr_value term
                    {
                      result = [ val[0], val[1] ]
                    }
                | error term
                    {
                      yyerrok
                      result = nil
                    }

       f_arglist: tLPAREN2 f_args opt_nl tRPAREN
                    {
                      result = @builder.args(val[0], val[1], val[3])

                      @lexer.state = :expr_beg
                    }
                | f_args term
                    {
                      result = @builder.args(nil, val[0], nil)
                    }

          f_args: f_arg tCOMMA f_optarg tCOMMA f_rest_arg opt_f_block_arg
                    {
                      result = val[0].
                                  concat(val[2]).
                                  concat(val[4]).
                                  concat(val[5])
                    }
                | f_arg tCOMMA f_optarg                   opt_f_block_arg
                    {
                      result = val[0].
                                  concat(val[2]).
                                  concat(val[3])
                    }
                | f_arg tCOMMA                 f_rest_arg opt_f_block_arg
                    {
                      result = val[0].
                                  concat(val[2]).
                                  concat(val[3])
                    }
                | f_arg                                   opt_f_block_arg
                    {
                      result = val[0].
                                  concat(val[1])
                    }
                |              f_optarg tCOMMA f_rest_arg opt_f_block_arg
                    {
                      result = val[0].
                                  concat(val[2]).
                                  concat(val[3])
                    }
                |              f_optarg                   opt_f_block_arg
                    {
                      result = val[0].
                                  concat(val[1])
                    }
                |                              f_rest_arg opt_f_block_arg
                    {
                      result = val[0].
                                  concat(val[1])
                    }
                |                                             f_block_arg
                    {
                      result = [ val[0] ]
                    }
                | # nothing
                    {
                      result = []
                    }

      f_norm_arg: tCONSTANT
                    {
                      diagnostic :error, :argument_const, nil, val[0]
                    }
                | tIVAR
                    {
                      diagnostic :error, :argument_ivar, nil, val[0]
                    }
                | tGVAR
                    {
                      diagnostic :error, :argument_gvar, nil, val[0]
                    }
                | tCVAR
                    {
                      diagnostic :error, :argument_cvar, nil, val[0]
                    }
                | tIDENTIFIER
                    {
                      @static_env.declare val[0][0]

                      result = @builder.arg(val[0])
                    }

           f_arg: f_norm_arg
                    {
                      result = [ val[0] ]
                    }
                | f_arg tCOMMA f_norm_arg
                    {
                      result = val[0] << val[2]
                    }

           f_opt: tIDENTIFIER tEQL arg_value
                    {
                      @static_env.declare val[0][0]

                      result = @builder.optarg(val[0], val[1], val[2])
                    }

        f_optarg: f_opt
                    {
                      result = [ val[0] ]
                    }
                | f_optarg tCOMMA f_opt
                    {
                      result = val[0] << val[2]
                    }

    restarg_mark: tSTAR2 | tSTAR

      f_rest_arg: restarg_mark tIDENTIFIER
                    {
                      @static_env.declare val[1][0]

                      result = [ @builder.restarg(val[0], val[1]) ]
                    }
                | restarg_mark
                    {
                      result = [ @builder.restarg(val[0]) ]
                    }

     blkarg_mark: tAMPER2 | tAMPER

     f_block_arg: blkarg_mark tIDENTIFIER
                    {
                      @static_env.declare val[1][0]

                      result = @builder.blockarg(val[0], val[1])
                    }

 opt_f_block_arg: tCOMMA f_block_arg
                    {
                      result = [ val[1] ]
                    }
                | # nothing
                    {
                      result = []
                    }

       singleton: var_ref
                | tLPAREN2 expr opt_nl tRPAREN
                    {
                      result = val[1]
                    }

      assoc_list: # nothing
                    {
                      result = []
                    }
                | assocs trailer
                    {
                      result = val[0]
                    }
                | args trailer
                    {
                      result = @builder.pair_list_18(val[0])
                    }

          assocs: assoc
                    {
                      result = [ val[0] ]
                    }
                | assocs tCOMMA assoc
                    {
                      result = val[0] << val[2]
                    }

           assoc: arg_value tASSOC arg_value
                    {
                      result = @builder.pair(val[0], val[1], val[2])
                    }

       operation: tIDENTIFIER | tCONSTANT | tFID
      operation2: tIDENTIFIER | tCONSTANT | tFID | op
      operation3: tIDENTIFIER | tFID | op
    dot_or_colon: tDOT | tCOLON2
       opt_terms:  | terms
          opt_nl:  | tNL
         trailer:  | tNL | tCOMMA

            term: tSEMI
                    {
                      yyerrok
                    }
                | tNL

           terms: term
                | terms tSEMI

            none: # nothing
                    {
                      result = nil
                    }

end

---- header

require 'parser'

---- inner

  def version
    18
  end

  def default_encoding
    Encoding::BINARY if defined? Encoding
  end
