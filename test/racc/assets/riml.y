# Copyright (c) 2012-2014 by Luke Gruber
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Riml::Parser

token IF ELSE ELSEIF THEN UNLESS END
token WHILE UNTIL BREAK CONTINUE
token TRY CATCH FINALLY
token FOR IN
token DEF DEF_BANG SPLAT_PARAM SPLAT_ARG CALL BUILTIN_COMMAND # such as echo "hi"
token CLASS NEW DEFM DEFM_BANG SUPER
token RIML_FILE_COMMAND RIML_CLASS_COMMAND
token RETURN
token NEWLINE
token NUMBER
token STRING_D STRING_S # single- and double-quoted
token EX_LITERAL
token REGEXP
token TRUE FALSE
token LET UNLET UNLET_BANG IDENTIFIER
token DICT_VAL # like dict.key, 'key' is a DICT_VAL
token SCOPE_MODIFIER SCOPE_MODIFIER_LITERAL SPECIAL_VAR_PREFIX
token FINISH

prechigh
  right '!'
  left '*' '/' '%'
  left '+' '-' '.'
  left '>' '>#' '>?' '<' '<#' '<?' '>=' '>=#' '>=?'  '<=' '<=#' '<=?'
  left '==' '==?' '==#' '=~' '=~?' '=~#' '!~' '!~?' '!~#' '!=' '!=?' '!=#'
  left IS ISNOT
  left '&&'
  left '||'
  right '?'
  right '=' '+=' '-=' '.='
  left ','
  left IF UNLESS
preclow

# All rules
rule

  Root:
    /* nothing */                        { result = make_node(val) { |_| Riml::Nodes.new([]) } }
  | Terminator                           { result = make_node(val) { |_| Riml::Nodes.new([]) } }
  | Statements                           { result = val[0] }
  ;

  # any list of expressions
  Statements:
    Statement                            { result = make_node(val) { |v| Riml::Nodes.new([ v[0] ]) } }
  | Statements Terminator Statement      { result = val[0] << val[2] }
  | Statements Terminator                { result = val[0] }
  | Terminator Statements                { result = make_node(val) { |v| Riml::Nodes.new(v[1]) } }
  ;

  # All types of expressions in Riml
  Statement:
    ExplicitCall                          { result = val[0] }
  | Def                                   { result = val[0] }
  | Return                                { result = val[0] }
  | UnletVariable                         { result = val[0] }
  | ExLiteral                             { result = val[0] }
  | For                                   { result = val[0] }
  | While                                 { result = val[0] }
  | Until                                 { result = val[0] }
  | Try                                   { result = val[0] }
  | ClassDefinition                       { result = val[0] }
  | LoopKeyword                           { result = val[0] }
  | EndScript                             { result = val[0] }
  | RimlFileCommand                       { result = val[0] }
  | RimlClassCommand                      { result = val[0] }
  | MultiAssign                           { result = val[0] }
  | If                                    { result = val[0] }
  | Unless                                { result = val[0] }
  | Expression                            { result = val[0] }
  ;

  Expression:
    ExpressionWithoutDictLiteral          { result = val[0] }
  | Dictionary                            { result = val[0] }
  | Dictionary DictGetWithDotLiteral      { result = make_node(val) { |v| Riml::DictGetDotNode.new(v[0], v[1]) } }
  | BinaryOperator                        { result = val[0] }
  | Ternary                               { result = val[0] }
  | Assign                                { result = val[0] }
  | Super                                 { result = val[0] }
  | '(' Expression ')'                    { result = make_node(val) { |v| Riml::WrapInParensNode.new(v[1]) } }
  ;

  ExpressionWithoutDictLiteral:
    UnaryOperator                         { result = val[0] }
  | DictGet                               { result = val[0] }
  | ListOrDictGet                         { result = val[0] }
  | AllVariableRetrieval                  { result = val[0] }
  | LiteralWithoutDictLiteral             { result = val[0] }
  | Call                                  { result = val[0] }
  | ObjectInstantiation                   { result = val[0] }
  | '(' ExpressionWithoutDictLiteral ')'  { result = make_node(val) { |v| Riml::WrapInParensNode.new(v[1]) } }
  ;

  # for inside curly-brace variable names
  PossibleStringValue:
    String                                { result = val[0] }
  | DictGet                               { result = val[0] }
  | ListOrDictGet                         { result = val[0] }
  | AllVariableRetrieval                  { result = val[0] }
  | BinaryOperator                        { result = val[0] }
  | Ternary                               { result = val[0] }
  | Call                                  { result = val[0] }
  ;

  Terminator:
    NEWLINE                               { result = nil }
  | ';'                                   { result = nil }
  ;

  LiteralWithoutDictLiteral:
    Number                                { result = val[0] }
  | String                                { result = val[0] }
  | Regexp                                { result = val[0] }
  | List                                  { result = val[0] }
  | ScopeModifierLiteral                  { result = val[0] }
  | TRUE                                  { result = make_node(val) { |_| Riml::TrueNode.new } }
  | FALSE                                 { result = make_node(val) { |_| Riml::FalseNode.new } }
  ;

  Number:
    NUMBER                                { result = make_node(val) { |v| Riml::NumberNode.new(v[0]) } }
  ;

  String:
    STRING_S                              { result = make_node(val) { |v| Riml::StringNode.new(v[0], :s) } }
  | STRING_D                              { result = make_node(val) { |v| Riml::StringNode.new(v[0], :d) } }
  | String STRING_S                       { result = make_node(val) { |v| Riml::StringLiteralConcatNode.new(v[0], Riml::StringNode.new(v[1], :s)) } }
  | String STRING_D                       { result = make_node(val) { |v| Riml::StringLiteralConcatNode.new(v[0], Riml::StringNode.new(v[1], :d)) } }
  ;

  Regexp:
    REGEXP                                { result = make_node(val) { |v| Riml::RegexpNode.new(v[0]) } }
  ;

  ScopeModifierLiteral:
    SCOPE_MODIFIER_LITERAL                { result = make_node(val) { |v| Riml::ScopeModifierLiteralNode.new(v[0]) } }
  ;

  List:
    ListLiteral                           { result = make_node(val) { |v| Riml::ListNode.new(v[0]) } }
  ;

  ListUnpack:
    '[' ListItems ';' Expression ']'      { result = make_node(val) { |v| Riml::ListUnpackNode.new(v[1] << v[3]) } }
  ;

  ListLiteral:
    '[' ListItems ']'                     { result = val[1] }
  | '[' ListItems ',' ']'                 { result = val[1] }
  ;

  ListItems:
    /* nothing */                         { result = [] }
  | Expression                            { result = [val[0]] }
  | ListItems ',' Expression              { result = val[0] << val[2] }
  ;

  Dictionary:
    DictionaryLiteral                     { result = make_node(val) { |v| Riml::DictionaryNode.new(v[0]) } }
  ;

  # {'key': 'value', 'key2': 'value2'}
  # Save as [['key', 'value'], ['key2', 'value2']] because ruby-1.8.7 offers
  # no guarantee for key-value pair ordering.
  DictionaryLiteral:
    '{' DictItems '}'                     { result = val[1] }
  | '{' DictItems ',' '}'                 { result = val[1] }
  ;

  # [[key, value], [key, value]]
  DictItems:
    /* nothing */                         { result = [] }
  | DictItem                              { result = val }
  | DictItems ',' DictItem                { result = val[0] << val[2] }
  ;

  # [key, value]
  DictItem:
    Expression ':' Expression                   { result = [val[0], val[2]] }
  ;

  DictGet:
    AllVariableRetrieval DictGetWithDot          { result = make_node(val) { |v| Riml::DictGetDotNode.new(v[0], v[1]) } }
  | ListOrDictGet DictGetWithDot                 { result = make_node(val) { |v| Riml::DictGetDotNode.new(v[0], v[1]) } }
  | Call DictGetWithDot                          { result = make_node(val) { |v| Riml::DictGetDotNode.new(v[0], v[1]) } }
  | '(' Expression ')' DictGetWithDot            { result = make_node(val) { |v| Riml::DictGetDotNode.new(Riml::WrapInParensNode.new(v[1]), v[3]) } }
  ;

  ListOrDictGet:
    ExpressionWithoutDictLiteral ListOrDictGetWithBrackets  { result = make_node(val) { |v| Riml::ListOrDictGetNode.new(v[0], v[1]) } }
  | '(' Expression ')' ListOrDictGetWithBrackets            { result = make_node(val) { |v| Riml::ListOrDictGetNode.new(Riml::WrapInParensNode.new(v[1]), v[3]) } }
  ;

  ListOrDictGetAssign:
    ExpressionWithoutDictLiteral ListOrDictGetWithBrackets  { result = make_node(val) { |v| Riml::ListOrDictGetNode.new(v[0], v[1]) } }
  ;

  ListOrDictGetWithBrackets:
    '['  Expression ']'                           { result = [val[1]] }
  | '['  SubList    ']'                           { result = [val[1]] }
  | ListOrDictGetWithBrackets '[' Expression ']'  { result = val[0] << val[2] }
  | ListOrDictGetWithBrackets '[' SubList    ']'  { result = val[0] << val[2] }
  ;

  SubList:
    Expression ':' Expression          { result = make_node(val) { |v| Riml::SublistNode.new([v[0], Riml::LiteralNode.new(' : '), v[2]]) } }
  | Expression ':'                     { result = make_node(val) { |v| Riml::SublistNode.new([v[0], Riml::LiteralNode.new(' :')]) } }
  | ':' Expression                     { result = make_node(val) { |v| Riml::SublistNode.new([Riml::LiteralNode.new(': '), v[1]]) } }
  | ':'                                { result = make_node(val) { |_| Riml::SublistNode.new([Riml::LiteralNode.new(':')]) } }
  ;

  DictGetWithDot:
    DICT_VAL                        { result = [val[0]] }
  | DictGetWithDot DICT_VAL         { result = val[0] << val[1] }
  ;

  DictGetWithDotLiteral:
    '.' IDENTIFIER                  { result = [val[1]] }
  | DictGetWithDotLiteral DICT_VAL  { result = val[0] << val[1] }
  ;

  Call:
    Scope DefCallIdentifier '(' ArgList ')'       { result = make_node(val) { |v| Riml::CallNode.new(v[0], v[1], v[3]) } }
  | DictGet '(' ArgList ')'                       { result = make_node(val) { |v| Riml::CallNode.new(nil, v[0], v[2]) } }
  | BUILTIN_COMMAND '(' ArgList ')'               { result = make_node(val) { |v| Riml::CallNode.new(nil, v[0], v[2]) } }
  | BUILTIN_COMMAND ArgListWithoutNothing         { result = make_node(val) { |v| Riml::CallNode.new(nil, v[0], v[1]) } }
  | BUILTIN_COMMAND NEWLINE                       { result = make_node(val) { |v| Riml::CallNode.new(nil, v[0], []) } }
  | CALL '(' ArgList ')'                          { result = make_node(val) { |v| Riml::ExplicitCallNode.new(nil, nil, v[2]) } }
  ;

  ObjectInstantiationCall:
    Scope DefCallIdentifier '(' ArgList ')'       { result = make_node(val) { |v| Riml::CallNode.new(v[0], v[1], v[3]) } }
  | Scope DefCallIdentifier                       { result = make_node(val) { |v| Riml::CallNode.new(v[0], v[1], []) } }
  ;

  RimlFileCommand:
    RIML_FILE_COMMAND '(' ArgList ')'             { result = make_node(val) { |v| Riml::RimlFileCommandNode.new(nil, v[0], v[2]) } }
  | RIML_FILE_COMMAND ArgList                     { result = make_node(val) { |v| Riml::RimlFileCommandNode.new(nil, v[0], v[1]) } }
  ;

  RimlClassCommand:
    RIML_CLASS_COMMAND '(' ClassArgList ')'       { result = make_node(val) { |v| Riml::RimlClassCommandNode.new(nil, v[0], v[2]) } }
  | RIML_CLASS_COMMAND ClassArgList               { result = make_node(val) { |v| Riml::RimlClassCommandNode.new(nil, v[0], v[1]) } }
  ;

  ClassArgList:
    Scope IDENTIFIER                              { result = ["#{val[0]}#{val[1]}"] }
  | String                                        { result = val }
  | ClassArgList ',' Scope IDENTIFIER             { result = val[0].concat ["#{val[2]}#{val[3]}"] }
  ;

  ExplicitCall:
    CALL Scope DefCallIdentifier '(' ArgList ')'  { result = make_node(val) { |v| Riml::ExplicitCallNode.new(v[1], v[2], v[4]) } }
  | CALL DictGet '(' ArgList ')'                  { result = make_node(val) { |v| Riml::ExplicitCallNode.new(nil, v[1], v[3]) } }
  ;

  Scope:
    SCOPE_MODIFIER         { result = val[0] }
  | /* nothing */          { result = nil }
  ;

  # [SID, scope_modifier]
  SIDAndScope:
    Scope                       { result = [ nil, val[0] ] }
  | '<' IDENTIFIER '>' Scope    { result = [ make_node(val) { |v| Riml::SIDNode.new(v[1]) }, val[3] ] }
  ;

  ArgList:
    /* nothing */                                  { result = [] }
  | ArgListWithoutNothingWithSplat                 { result = val[0] }
  ;

  ArgListWithSplat:
    /* nothing */                         { result = [] }
  | ArgListWithoutNothingWithSplat        { result = val[0] }
  ;

  ArgListWithoutNothingWithSplat:
    Expression                                                   { result = val }
  | SPLAT_ARG Expression                                         { result = [ make_node(val) { |v| Riml::SplatNode.new(v[1]) } ] }
  | ArgListWithoutNothingWithSplat "," Expression                { result = val[0] << val[2] }
  | ArgListWithoutNothingWithSplat "," SPLAT_ARG Expression      { result = val[0] << make_node(val) { |v| Riml::SplatNode.new(v[3]) } }
  ;

  ArgListWithoutNothing:
    Expression                               { result = val }
  | ArgListWithoutNothing "," Expression     { result = val[0] << val[2] }
  ;

  BinaryOperator:
    Expression '||' Expression            { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '&&' Expression            { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }

  | Expression '==' Expression            { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '==#' Expression           { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '==?' Expression           { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }

  # added by riml
  | Expression '===' Expression           { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }

  | Expression '!=' Expression            { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '!=#' Expression           { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '!=?' Expression           { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }

  | Expression '=~' Expression            { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '=~#' Expression           { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '=~?' Expression           { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }

  | Expression '!~' Expression            { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '!~#' Expression           { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '!~?' Expression           { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }

  | Expression '>' Expression             { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '>#' Expression            { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '>?' Expression            { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }

  | Expression '>=' Expression            { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '>=#' Expression           { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '>=?' Expression           { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }

  | Expression '<' Expression             { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '<#' Expression            { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '<?' Expression            { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }

  | Expression '<=' Expression            { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '<=#' Expression           { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '<=?' Expression           { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }

  | Expression '+' Expression             { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '-' Expression             { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '*' Expression             { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '/' Expression             { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '.' Expression             { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression '%' Expression             { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }

  | Expression IS    Expression           { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  | Expression ISNOT Expression           { result = make_node(val) { |v| Riml::BinaryOperatorNode.new(v[1], [v[0], v[2]]) } }
  ;

  UnaryOperator:
    '!' Expression                        { result = make_node(val) { |v| Riml::UnaryOperatorNode.new(val[0], [val[1]]) } }
  | '+' Expression                        { result = make_node(val) { |v| Riml::UnaryOperatorNode.new(val[0], [val[1]]) } }
  | '-' Expression                        { result = make_node(val) { |v| Riml::UnaryOperatorNode.new(val[0], [val[1]]) } }
  ;

  # ['=', LHS, RHS]
  Assign:
    LET AssignExpression                  { result = make_node(val) { |v| Riml::AssignNode.new(v[1][0], v[1][1], v[1][2]) } }
  | AssignExpression                      { result = make_node(val) { |v| Riml::AssignNode.new(v[0][0], v[0][1], v[0][2]) } }
  ;

  MultiAssign:
    Assign ',' Assign                     { result = make_node(val) { |v| Riml::MultiAssignNode.new([v[0], v[2]]) } }
  | MultiAssign ',' Assign                { val[0].assigns << val[2]; result = val[0] }
  ;

  # ['=', AssignLHS, Expression]
  AssignExpression:
    AssignLHS '='  Expression             { result = [val[1], val[0], val[2]] }
  | AssignLHS '+=' Expression             { result = [val[1], val[0], val[2]] }
  | AssignLHS '-=' Expression             { result = [val[1], val[0], val[2]] }
  | AssignLHS '.=' Expression             { result = [val[1], val[0], val[2]] }
  ;

  AssignLHS:
    AllVariableRetrieval                  { result = val[0] }
  | List                                  { result = val[0] }
  | ListUnpack                            { result = val[0] }
  | DictGet                               { result = val[0] }
  | ListOrDictGetAssign                   { result = val[0] }
  ;

  # retrieving the value of a variable
  VariableRetrieval:
    SimpleVariableRetrieval                        { result = val[0] }
  | SPECIAL_VAR_PREFIX IDENTIFIER                  { result = make_node(val) { |v| Riml::GetSpecialVariableNode.new(v[0], v[1]) } }
  | ScopeModifierLiteral ListOrDictGetWithBrackets { result = make_node(val) { |v| Riml::GetVariableByScopeAndDictNameNode.new(v[0], v[1]) } }
  ;

  SimpleVariableRetrieval:
    Scope IDENTIFIER                               { result = make_node(val) { |v| Riml::GetVariableNode.new(v[0], v[1]) } }
  ;

  AllVariableRetrieval:
    VariableRetrieval                          { result = val[0] }
  | Scope CurlyBraceName                       { result = make_node(val) { |v| Riml::GetCurlyBraceNameNode.new(v[0], v[1]) } }
  ;

  UnletVariable:
    UNLET VariableRetrieval                    { result = make_node(val) { |v| Riml::UnletVariableNode.new('!', [ v[1] ]) } }
  | UNLET_BANG VariableRetrieval               { result = make_node(val) { |v| Riml::UnletVariableNode.new('!', [ v[1] ]) } }
  | UnletVariable VariableRetrieval            { result = val[0] << val[1] }
  ;

  CurlyBraceName:
    CurlyBraceVarPart                          { result = make_node(val) { |v| Riml::CurlyBraceVariable.new([ v[0] ]) } }
  | IDENTIFIER CurlyBraceName                  { result = make_node(val) { |v| Riml::CurlyBraceVariable.new([ Riml::CurlyBracePart.new(v[0]), v[1] ]) } }
  | CurlyBraceName IDENTIFIER                  { result = val[0] << make_node(val) { |v| Riml::CurlyBracePart.new(v[1]) } }
  | CurlyBraceName CurlyBraceVarPart           { result = val[0] << val[1] }
  ;

  CurlyBraceVarPart:
    '{' PossibleStringValue '}'                     { result = make_node(val) { |v| Riml::CurlyBracePart.new(v[1]) } }
  | '{' PossibleStringValue CurlyBraceVarPart '}'   { result = make_node(val) { |v| Riml::CurlyBracePart.new([v[1], v[2]]) } }
  | '{' CurlyBraceVarPart PossibleStringValue '}'   { result = make_node(val) { |v| Riml::CurlyBracePart.new([v[1], v[2]]) } }
  ;

  # Method definition
  # [SID, scope_modifier, name, parameters, keyword, expressions]
  Def:
    FunctionType SIDAndScope DefCallIdentifier DefKeywords Block END                                     { result = make_node(val) { |v| Riml.const_get(val[0]).new('!', v[1][0], v[1][1], v[2], [], v[3], v[4]) } }
  | FunctionType SIDAndScope DefCallIdentifier '(' ParamList ')' DefKeywords Block END                   { result = make_node(val) { |v| Riml.const_get(val[0]).new('!', v[1][0], v[1][1], v[2], v[4], v[6], v[7]) } }
  | FunctionType SIDAndScope DefCallIdentifier '(' SPLAT_PARAM     ')' DefKeywords Block END             { result = make_node(val) { |v| Riml.const_get(val[0]).new('!', v[1][0], v[1][1], v[2], [v[4]], v[6], v[7]) } }
  | FunctionType SIDAndScope DefCallIdentifier '(' ParamList ',' SPLAT_PARAM ')' DefKeywords Block END   { result = make_node(val) { |v| Riml.const_get(val[0]).new('!', v[1][0], v[1][1], v[2], v[4] << v[6], v[8], v[9]) } }
  ;

  FunctionType:
    DEF           { result = "DefNode" }
  | DEF_BANG      { result = "DefNode" }
  | DEFM          { result = "DefMethodNode" }
  ;

  DefCallIdentifier:
    # use '' for first argument instead of nil in order to avoid a double scope-modifier
    CurlyBraceName          { result = make_node(val) { |v| Riml::GetCurlyBraceNameNode.new('', v[0]) } }
  | IDENTIFIER              { result = val[0] }
  ;

  # Example: 'range', 'dict' or 'abort' after function definition
  DefKeywords:
    IDENTIFIER             { result = [val[0]] }
  | DefKeywords IDENTIFIER { result = val[0] << val[1] }
  | /* nothing */          { result = nil }
  ;

  ParamList:
    /* nothing */                         { result = [] }
  | IDENTIFIER                            { result = val }
  | DefaultParam                          { result = val }
  | ParamList ',' IDENTIFIER              { result = val[0] << val[2] }
  | ParamList ',' DefaultParam            { result = val[0] << val[2] }
  ;

  DefaultParam:
    IDENTIFIER '=' Expression                { result = make_node(val) { |v| Riml::DefaultParamNode.new(v[0], v[2]) } }
  ;

  Return:
    RETURN Returnable                        { result = make_node(val) { |v| Riml::ReturnNode.new(v[1]) } }
  | RETURN Returnable IF Expression          { result = make_node(val) { |v| Riml::IfNode.new(v[3], Nodes.new([ReturnNode.new(v[1])])) } }
  | RETURN Returnable UNLESS Expression      { result = make_node(val) { |v| Riml::UnlessNode.new(v[3], Nodes.new([ReturnNode.new(v[1])])) } }
  ;

  Returnable:
    /* nothing */     { result = nil }
  | Expression        { result = val[0] }
  ;

  EndScript:
    FINISH                                  { result = make_node(val) { |_| Riml::FinishNode.new } }
  ;

  # [expression, expressions]
  If:
    IF Expression IfBlock END               { result = make_node(val) { |v| Riml::IfNode.new(v[1], v[2]) } }
  | IF Expression THEN Expression END       { result = make_node(val) { |v| Riml::IfNode.new(v[1], Riml::Nodes.new([v[3]])) } }
  | Expression IF Expression                { result = make_node(val) { |v| Riml::IfNode.new(v[2], Riml::Nodes.new([v[0]])) } }
  ;

  Unless:
    UNLESS Expression IfBlock END           { result = make_node(val) { |v| Riml::UnlessNode.new(v[1], v[2]) } }
  | UNLESS Expression THEN Expression END   { result = make_node(val) { |v| Riml::UnlessNode.new(v[1], Riml::Nodes.new([v[3]])) } }
  | Expression UNLESS Expression            { result = make_node(val) { |v| Riml::UnlessNode.new(v[2], Riml::Nodes.new([v[0]])) } }
  ;

  Ternary:
    Expression '?' Expression ':' Expression   { result = make_node(val) { |v| Riml::TernaryOperatorNode.new([v[0], v[2], v[4]]) } }
  ;

  While:
    WHILE Expression Block END                 { result = make_node(val) { |v| Riml::WhileNode.new(v[1], v[2]) } }
  ;

  LoopKeyword:
    BREAK                                      { result = make_node(val) { |_| Riml::BreakNode.new } }
  | CONTINUE                                   { result = make_node(val) { |_| Riml::ContinueNode.new } }
  ;

  Until:
    UNTIL Expression Block END                 { result = make_node(val) { |v| Riml::UntilNode.new(v[1], v[2]) } }
  ;

  For:
    FOR SimpleVariableRetrieval IN Expression Block END     { result = make_node(val) { |v| Riml::ForNode.new(v[1], v[3], v[4]) } }
  | FOR List IN Expression Block END                        { result = make_node(val) { |v| Riml::ForNode.new(v[1], v[3], v[4]) } }
  | FOR ListUnpack IN Expression Block END                  { result = make_node(val) { |v| Riml::ForNode.new(v[1], v[3], v[4]) } }
  ;

  Try:
    TRY Block END                              { result = make_node(val) { |v| Riml::TryNode.new(v[1], nil, nil) } }
  | TRY Block Catch END                        { result = make_node(val) { |v| Riml::TryNode.new(v[1], v[2], nil) } }
  | TRY Block Catch FINALLY Block END          { result = make_node(val) { |v| Riml::TryNode.new(v[1], v[2], v[4]) } }
  ;

  Catch:
    /* nothing */                              { result = nil }
  | CATCH Block                                { result = [ make_node(val) { |v| Riml::CatchNode.new(nil, v[1]) } ] }
  | CATCH Catchable Block                      { result = [ make_node(val) { |v| Riml::CatchNode.new(v[1], v[2]) } ] }
  | Catch CATCH Block                          { result = val[0] << make_node(val) { |v| Riml::CatchNode.new(nil, v[2]) } }
  | Catch CATCH Catchable Block                { result = val[0] << make_node(val) { |v| Riml::CatchNode.new(v[2], v[3]) } }
  ;

  Catchable:
    Regexp                                      { result = val[0] }
  | String                                      { result = val[0] }
  ;

  # [expressions]
  # expressions list could contain an ElseNode, which contains expressions
  # itself
  Block:
    NEWLINE Statements                        { result = val[1] }
  | NEWLINE                                   { result = make_node(val) { |_| Riml::Nodes.new([]) } }
  ;

  IfBlock:
    Block                                     { result = val[0] }
  | NEWLINE Statements ElseBlock              { result = val[1] << val[2] }
  | NEWLINE Statements ElseifBlock            { result = val[1] << val[2] }
  | NEWLINE Statements ElseifBlock ElseBlock  { result = val[1] << val[2] << val[3] }
  ;

  ElseBlock:
    ELSE NEWLINE Statements                   { result = make_node(val) { |v| Riml::ElseNode.new(v[2]) } }
  ;

  ElseifBlock:
    ELSEIF Expression NEWLINE Statements                   { result = make_node(val) { |v| Riml::Nodes.new([Riml::ElseifNode.new(v[1], v[3])]) } }
  | ElseifBlock ELSEIF Expression NEWLINE Statements       { result = val[0] << make_node(val) { |v| Riml::ElseifNode.new(v[2], v[4]) } }
  ;

  ClassDefinition:
    CLASS Scope IDENTIFIER Block END                         { result = make_node(val) { |v| Riml::ClassDefinitionNode.new(v[1], v[2], nil, v[3]) } }
  | CLASS Scope IDENTIFIER '<' Scope IDENTIFIER Block END    { result = make_node(val) { |v| Riml::ClassDefinitionNode.new(v[1], v[2], (v[4] || ClassDefinitionNode::DEFAULT_SCOPE_MODIFIER) + v[5], v[6]) } }
  ;

  ObjectInstantiation:
    NEW ObjectInstantiationCall                              { result = make_node(val) { |v| Riml::ObjectInstantiationNode.new(v[1]) } }
  ;

  Super:
    SUPER '(' ArgListWithSplat ')'     { result = make_node(val) { |v| Riml::SuperNode.new(v[2], true) } }
  | SUPER                              { result = make_node(val) { |_| Riml::SuperNode.new([], false) } }
  ;

  ExLiteral:
    EX_LITERAL                { result = make_node(val) { |v| Riml::ExLiteralNode.new(v[0]) } }
  ;
end

---- header
  require File.expand_path("../lexer", __FILE__)
  require File.expand_path("../nodes", __FILE__)
  require File.expand_path("../errors", __FILE__)
  require File.expand_path("../ast_rewriter", __FILE__)
---- inner
  # This code will be put as-is in the parser class

  attr_accessor :ast_rewriter
  attr_writer :options

  # The Parser and AST_Rewriter share this same hash of options
  def options
    @options ||= {}
  end

  def self.ast_cache
    @ast_cache
  end
  @ast_cache = {}

  # parses tokens or code into output nodes
  def parse(object, ast_rewriter = Riml::AST_Rewriter.new, filename = nil, included = false)
    if (ast = self.class.ast_cache[filename])
    else
      if tokens?(object)
        @tokens = object
      elsif code?(object)
        @lexer = Riml::Lexer.new(object, filename, true)
      end

      begin
        ast = do_parse
      rescue Racc::ParseError => e
        raise unless @lexer
        if (invalid_token = @lexer.prev_token_is_keyword?)
          warning = "#{invalid_token.inspect} is a keyword, and cannot " \
            "be used as a variable name"
        end
        error_msg = e.message
        error_msg << "\nWARNING: #{warning}" if warning
        error = Riml::ParseError.new(error_msg, @lexer.filename, @lexer.lineno)
        raise error
      end
      self.class.ast_cache[filename] = ast if filename
    end
    @ast_rewriter ||= ast_rewriter
    return ast unless @ast_rewriter
    @ast_rewriter.ast = ast.dup
    @ast_rewriter.options ||= options
    @ast_rewriter.rewrite(filename, included)
    @ast_rewriter.ast
  end

  # get the next token from either the list of tokens provided, or
  # the lexer getting the next token
  def next_token
    return @tokens.shift unless @lexer
    token = @lexer.next_token
    if token && @lexer.parser_info
      @current_parser_info = token.pop
    end
    token
  end

  private

  def tokens?(object)
    Array === object
  end

  def code?(object)
    String === object
  end

  def make_node(racc_val)
    node = yield racc_val
    node.parser_info = @current_parser_info
    node
  end
