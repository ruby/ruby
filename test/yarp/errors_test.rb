# frozen_string_literal: true

require "test_helper"

class ErrorsTest < Test::Unit::TestCase
  include YARP::DSL

  test "constant path with invalid token after" do
    assert_error_messages "A::$b", [
      "Expected identifier or constant after '::'",
      "Expected a newline or semicolon after statement."
    ]
  end

  test "module name recoverable" do
    expected = ModuleNode(
      ScopeNode([]),
      KEYWORD_MODULE("module"),
      ConstantReadNode(),
      StatementsNode(
        [ModuleNode(
           ScopeNode([]),
           KEYWORD_MODULE("module"),
           MissingNode(),
           nil,
           MISSING("")
         )]
      ),
      KEYWORD_END("end")
    )

    assert_errors expected, "module Parent module end", [
      "Expected to find a module name after `module`."
    ]
  end

  test "for loops index missing" do
    expected = ForNode(
      MissingNode(),
      expression("1..10"),
      StatementsNode([expression("i")]),
      Location(),
      Location(),
      nil,
      Location()
    )

    assert_errors expected, "for in 1..10\ni\nend", ["Expected index after for."]
  end

  test "for loops only end" do
    expected = ForNode(
      MissingNode(),
      MissingNode(),
      nil,
      Location(),
      Location(),
      nil,
      Location()
    )

    assert_errors expected, "for end", ["Expected index after for.", "Expected keyword in.", "Expected collection."]
  end

  test "pre execution missing {" do
    expected = PreExecutionNode(
      StatementsNode([expression("1")]),
      Location(),
      Location(),
      Location()
    )

    assert_errors expected, "BEGIN 1 }", ["Expected '{' after 'BEGIN'."]
  end

  test "pre execution context" do
    expected = PreExecutionNode(
      StatementsNode([
        CallNode(
          expression("1"),
          nil,
          PLUS("+"),
          nil,
          ArgumentsNode([MissingNode()]),
          nil,
          nil,
          "+"
        )
      ]),
      Location(),
      Location(),
      Location()
    )

    assert_errors expected, "BEGIN { 1 + }", ["Expected a value after the operator."]
  end

  test "unterminated embdoc" do
    assert_errors expression("1"), "1\n=begin\n", ["Unterminated embdoc"]
  end

  test "unterminated %i list" do
    assert_errors expression("%i["), "%i[", ["Expected a closing delimiter for a `%i` list."]
  end

  test "unterminated %w list" do
    assert_errors expression("%w["), "%w[", ["Expected a closing delimiter for a `%w` list."]
  end

  test "unterminated %W list" do
    assert_errors expression("%W["), "%W[", ["Expected a closing delimiter for a `%W` list."]
  end

  test "unterminated regular expression" do
    assert_errors expression("/hello"), "/hello", ["Expected a closing delimiter for a regular expression."]
  end

  test "unterminated xstring" do
    assert_errors expression("`hello"), "`hello", ["Expected a closing delimiter for an xstring."]
  end

  test "unterminated string" do
    assert_errors expression('"hello'), '"hello', ["Expected a closing delimiter for an interpolated string."]
  end

  test "unterminated %s symbol" do
    assert_errors expression("%s[abc"), "%s[abc", ["Expected a closing delimiter for a dynamic symbol."]
  end

  test "unterminated parenthesized expression" do
    assert_errors expression('(1 + 2'), '(1 + 2', ["Expected to be able to parse an expression.", "Expected a closing parenthesis."]
  end

  test "(1, 2, 3)" do
    assert_errors expression("(1, 2, 3)"), "(1, 2, 3)", [
      "Expected to be able to parse an expression.",
      "Expected a closing parenthesis.",
      "Expected a newline or semicolon after statement.",
      "Expected to be able to parse an expression.",
      "Expected a newline or semicolon after statement.",
      "Expected to be able to parse an expression.",
      "Expected a newline or semicolon after statement.",
      "Expected to be able to parse an expression."
    ]
  end

  test "return(1, 2, 3)" do
    assert_error_messages "return(1, 2, 3)", [
      "Expected to be able to parse an expression.",
      "Expected a closing parenthesis.",
      "Expected a newline or semicolon after statement.",
      "Expected to be able to parse an expression."
    ]
  end

  test "return 1,;" do
    assert_errors expression("return 1,;"), "return 1,;", ["Expected to be able to parse an argument."]
  end

  test "next(1, 2, 3)" do
    assert_errors expression("next(1, 2, 3)"), "next(1, 2, 3)", [
      "Expected to be able to parse an expression.",
      "Expected a closing parenthesis.",
      "Expected a newline or semicolon after statement.",
      "Expected to be able to parse an expression."
    ]
  end

  test "next 1,;" do
    assert_errors expression("next 1,;"), "next 1,;", ["Expected to be able to parse an argument."]
  end

  test "break(1, 2, 3)" do
    errors = [
      "Expected to be able to parse an expression.",
      "Expected a closing parenthesis.",
      "Expected a newline or semicolon after statement.",
      "Expected to be able to parse an expression."
    ]

    assert_errors expression("break(1, 2, 3)"), "break(1, 2, 3)", errors
  end

  test "break 1,;" do
    assert_errors expression("break 1,;"), "break 1,;", ["Expected to be able to parse an argument."]
  end

  test "argument forwarding when parent is not forwarding" do
    assert_errors expression('def a(x, y, z); b(...); end'), 'def a(x, y, z); b(...); end', ["unexpected ... when parent method is not forwarding."]
  end

  test "argument forwarding only effects its own internals" do
    assert_errors expression('def a(...); b(...); end; def c(x, y, z); b(...); end'), 'def a(...); b(...); end; def c(x, y, z); b(...); end', ["unexpected ... when parent method is not forwarding."]
  end

  test "top level constant with downcased identifier" do
    assert_error_messages "::foo", [
      "Expected a constant after ::.",
      "Expected a newline or semicolon after statement."
    ]
  end

  test "top level constant starting with downcased identifier" do
    assert_error_messages "::foo::A", [
      "Expected a constant after ::.",
      "Expected a newline or semicolon after statement."
    ]
  end

  test "aliasing global variable with non global variable" do
    assert_errors expression("alias $a b"), "alias $a b", ["Expected a global variable."]
  end

  test "aliasing non global variable with global variable" do
    assert_errors expression("alias a $b"), "alias a $b", ["Expected a bare word or symbol argument."]
  end

  test "aliasing global variable with global number variable" do
    assert_errors expression("alias $a $1"), "alias $a $1", ["Can't make alias for number variables."]
  end

  test "def with expression receiver and no identifier" do
    assert_errors expression("def (a); end"), "def (a); end", [
      "Expected '.' or '::' after receiver"
    ]
  end

  test "def with multiple statements receiver" do
    assert_errors expression("def (\na\nb\n).c; end"), "def (\na\nb\n).c; end", [
      "Expected closing ')' for receiver.",
      "Expected '.' or '::' after receiver",
      "Expected to be able to parse an expression.",
      "Expected to be able to parse an expression."
    ]
  end

  test "def with empty expression receiver" do
    assert_errors expression("def ().a; end"), "def ().a; end", ["Expected to be able to parse receiver."]
  end

  test "block beginning with '{' and ending with 'end'" do
    assert_error_messages "x.each { x end", [
      "Expected a newline or semicolon after statement.",
      "Expected to be able to parse an expression.",
      "Expected to be able to parse an expression.",
      "Expected block beginning with '{' to end with '}'."
    ]
  end

  test "double splat followed by splat argument" do
    expected = CallNode(
      nil,
      nil,
      IDENTIFIER("a"),
      PARENTHESIS_LEFT("("),
      ArgumentsNode(
        [HashNode(
           nil,
           [AssocSplatNode(
              CallNode(
                nil,
                nil,
                IDENTIFIER("kwargs"),
                nil,
                nil,
                nil,
                nil,
                "kwargs"
              ),
              Location()
            )],
           nil
         ),
         SplatNode(
           USTAR("*"),
           CallNode(nil, nil, IDENTIFIER("args"), nil, nil, nil, nil, "args")
         )]
      ),
      PARENTHESIS_RIGHT(")"),
      nil,
      "a"
    )

    assert_errors expected, "a(**kwargs, *args)", ["Unexpected splat argument after double splat."]
  end

  test "arguments after block" do
    expected = CallNode(
      nil,
      nil,
      IDENTIFIER("a"),
      PARENTHESIS_LEFT("("),
      ArgumentsNode([
        BlockArgumentNode(expression("block"), Location()),
        expression("foo")
      ]),
      PARENTHESIS_RIGHT(")"),
      nil,
      "a"
    )

    assert_errors expected, "a(&block, foo)", ["Unexpected argument after block argument."]
  end

  test "arguments binding power for and" do
    assert_error_messages "foo(*bar and baz)", [
      "Expected a ')' to close the argument list.",
      "Expected a newline or semicolon after statement.",
      "Expected to be able to parse an expression."
    ]
  end

  test "splat argument after keyword argument" do
    expected = CallNode(
      nil,
      nil,
      IDENTIFIER("a"),
      PARENTHESIS_LEFT("("),
      ArgumentsNode(
        [HashNode(
           nil,
           [AssocNode(
              SymbolNode(nil, LABEL("foo"), LABEL_END(":"), "foo"),
              CallNode(nil, nil, IDENTIFIER("bar"), nil, nil, nil, nil, "bar"),
              nil
            )],
           nil
         ),
         SplatNode(
           USTAR("*"),
           CallNode(nil, nil, IDENTIFIER("args"), nil, nil, nil, nil, "args")
         )]
      ),
      PARENTHESIS_RIGHT(")"),
      nil,
      "a"
    )

    assert_errors expected, "a(foo: bar, *args)", ["Unexpected splat argument after double splat."]
  end

  test "module definition in method body" do
    expected = DefNode(
      IDENTIFIER("foo"),
      nil,
      nil,
      StatementsNode(
        [ModuleNode(
           ScopeNode([]),
           KEYWORD_MODULE("module"),
           ConstantReadNode(),
           nil,
           KEYWORD_END("end")
         )]
      ),
      ScopeNode([]),
      Location(),
      nil,
      nil,
      nil,
      nil,
      Location()
    )

    assert_errors expected, "def foo;module A;end;end", ["Module definition in method body"]
  end

  test "module definition in method body within block" do
    expected = DefNode(
      IDENTIFIER("foo"),
      nil,
      nil,
      StatementsNode(
        [CallNode(
           nil,
           nil,
           IDENTIFIER("bar"),
           nil,
           nil,
           nil,
           BlockNode(
             ScopeNode([]),
             nil,
             StatementsNode(
               [ModuleNode(
                  ScopeNode([]),
                  KEYWORD_MODULE("module"),
                  ConstantReadNode(),
                  nil,
                  KEYWORD_END("end")
                )]
             ),
             Location(),
             Location()
           ),
           "bar"
         )]
      ),
      ScopeNode([]),
      Location(),
      nil,
      nil,
      nil,
      nil,
      Location()
    )

    assert_errors expected, "
      def foo
        bar do
          module Foo;end
        end
      end
    ", ["Module definition in method body"]
  end

  test "class definition in method body" do
    expected = DefNode(
      IDENTIFIER("foo"),
      nil,
      nil,
      StatementsNode(
        [ClassNode(
           ScopeNode([]),
           KEYWORD_CLASS("class"),
           ConstantReadNode(),
           nil,
           nil,
           nil,
           KEYWORD_END("end")
         )]
      ),
      ScopeNode([]),
      Location(),
      nil,
      nil,
      nil,
      nil,
      Location()
    )

    assert_errors expected, "def foo;class A;end;end", ["Class definition in method body"]
  end

  test "bad arguments" do
    expected = DefNode(
      IDENTIFIER("foo"),
      nil,
      ParametersNode([], [], [], nil, [], nil, nil),
      nil,
      ScopeNode([]),
      Location(),
      nil,
      Location(),
      Location(),
      nil,
      Location()
    )

    assert_errors expected, "def foo(A, @a, $A, @@a);end", [
      "Formal argument cannot be a constant",
      "Formal argument cannot be an instance variable",
      "Formal argument cannot be a global variable",
      "Formal argument cannot be a class variable",
    ]
  end

  test "cannot assign to a reserved numbered parameter" do
    expected = BeginNode(
      KEYWORD_BEGIN("begin"),
      StatementsNode(
        [LocalVariableWriteNode(
           Location(),
           SymbolNode(SYMBOL_BEGIN(":"), IDENTIFIER("a"), nil, "a"),
           Location(),
           0
         ),
         LocalVariableWriteNode(
           Location(),
           SymbolNode(SYMBOL_BEGIN(":"), IDENTIFIER("a"), nil, "a"),
           Location(),
           0
         ),
         LocalVariableWriteNode(
           Location(),
           SymbolNode(SYMBOL_BEGIN(":"), IDENTIFIER("a"), nil, "a"),
           Location(),
           0
         ),
         LocalVariableWriteNode(
           Location(),
           SymbolNode(SYMBOL_BEGIN(":"), IDENTIFIER("a"), nil, "a"),
           Location(),
           0
         ),
         LocalVariableWriteNode(
           Location(),
           SymbolNode(SYMBOL_BEGIN(":"), IDENTIFIER("a"), nil, "a"),
           Location(),
           0
         ),
         LocalVariableWriteNode(
           Location(),
           SymbolNode(SYMBOL_BEGIN(":"), IDENTIFIER("a"), nil, "a"),
           Location(),
           0
         ),
         LocalVariableWriteNode(
           Location(),
           SymbolNode(SYMBOL_BEGIN(":"), IDENTIFIER("a"), nil, "a"),
           Location(),
           0
         ),
         LocalVariableWriteNode(
           Location(),
           SymbolNode(SYMBOL_BEGIN(":"), IDENTIFIER("a"), nil, "a"),
           Location(),
           0
         ),
         LocalVariableWriteNode(
           Location(),
           SymbolNode(SYMBOL_BEGIN(":"), IDENTIFIER("a"), nil, "a"),
           Location(),
           0
         ),
         LocalVariableWriteNode(
           Location(),
           SymbolNode(SYMBOL_BEGIN(":"), IDENTIFIER("a"), nil, "a"),
           Location(),
           0
         )]
      ),
      nil,
      nil,
      nil,
      KEYWORD_END("end")
    )
    assert_errors expected, "
    begin
      _1=:a;_2=:a;_3=:a;_4=:a;_5=:a
      _6=:a;_7=:a;_8=:a;_9=:a;_10=:a
    end
    ", Array.new(9, "reserved for numbered parameter")
  end

  test "do not allow trailing commas in method parameters" do
    expected = DefNode(
      IDENTIFIER("foo"),
      nil,
      ParametersNode(
        [RequiredParameterNode(), RequiredParameterNode(), RequiredParameterNode()],
        [],
        [],
        nil,
        [],
        nil,
        nil
      ),
      nil,
      ScopeNode([IDENTIFIER("a"), IDENTIFIER("b"), IDENTIFIER("c")]),
      Location(),
      nil,
      Location(),
      Location(),
      nil,
      Location()
    )

    assert_errors expected, "def foo(a,b,c,);end", [
      "Unexpected ','."
    ]
  end

  test "do not allow trailing commas in lambda parameters" do
    expected = LambdaNode(
      ScopeNode([IDENTIFIER("a"), IDENTIFIER("b")]),
      MINUS_GREATER("->"),
      BlockParametersNode(
        ParametersNode([RequiredParameterNode(), RequiredParameterNode()], [], [], nil, [], nil, nil),
        [],
        Location(),
        Location()
      ),
      nil
    )
    assert_errors expected, "-> (a, b, ) {}", [
      "Unexpected ','."
    ]
  end

  test "do not allow multiple codepoints in a single character literal" do
    expected = StringNode(
      STRING_BEGIN("?"),
      STRING_CONTENT('\u{0001 0002}'),
      nil,
      "\u0001\u0002"
    )
    assert_errors expected, '?\u{0001 0002}', [
      "Multiple codepoints at single character literal"
    ]
  end

  test "do not allow more than 6 hexadecimal digits in \u{} Unicode character notation" do
    expected = StringNode(
      STRING_BEGIN('"'),
      STRING_CONTENT('\u{0000001}'),
      STRING_END('"'),
      "\u0001"
    )
    assert_errors expected, '"\u{0000001}"', [
      "invalid Unicode escape.",
      "invalid Unicode escape."
    ]
  end

  test "do not allow characters other than 0-9, a-f and A-F in \u{} Unicode character notation" do
    expected = StringNode(
      STRING_BEGIN('"'),
      STRING_CONTENT('\u{000z}'),
      STRING_END('"'),
      "\u0000z}"
    )
    assert_errors expected, '"\u{000z}"', [
      "unterminated Unicode escape",
      "unterminated Unicode escape"
    ]
  end

  test "method parameters after block" do
    expected = DefNode(
      IDENTIFIER("foo"),
      nil,
      ParametersNode(
        [],
        [],
        [RequiredParameterNode()],
        nil,
        [],
        nil,
        BlockParameterNode(IDENTIFIER("block"), Location())
      ),
      nil,
      ScopeNode([IDENTIFIER("block"), IDENTIFIER("a")]),
      Location(),
      nil,
      Location(),
      Location(),
      nil,
      Location()
    )
    assert_errors expected, "def foo(&block, a)\nend", ["Unexpected parameter order"]
  end

  test "method with arguments after anonamous block" do
    expected = DefNode(
      IDENTIFIER("foo"),
      nil,
      ParametersNode([], [], [RequiredParameterNode()], nil, [], nil, BlockParameterNode(nil, Location())),
      nil,
      ScopeNode([AMPERSAND("&"), IDENTIFIER("a")]),
      Location(),
      nil,
      Location(),
      Location(),
      nil,
      Location()
    )

    assert_errors expected, "def foo(&, a)\nend", ["Unexpected parameter order"]
  end

  test "method parameters after arguments forwarding" do
    expected = DefNode(
      IDENTIFIER("foo"),
      nil,
      ParametersNode(
        [],
        [],
        [RequiredParameterNode()],
        nil,
        [],
        ForwardingParameterNode(),
        nil
      ),
      nil,
      ScopeNode([UDOT_DOT_DOT("..."), IDENTIFIER("a")]),
      Location(),
      nil,
      Location(),
      Location(),
      nil,
      Location()
    )
    assert_errors expected, "def foo(..., a)\nend", ["Unexpected parameter order"]
  end

  test "keywords parameters before required parameters" do
    expected = DefNode(
      IDENTIFIER("foo"),
      nil,
      ParametersNode(
        [],
        [],
        [RequiredParameterNode()],
        nil,
        [KeywordParameterNode(LABEL("b:"), nil)],
        nil,
        nil
      ),
      nil,
      ScopeNode([LABEL("b"), IDENTIFIER("a")]),
      Location(),
      nil,
      Location(),
      Location(),
      nil,
      Location()
    )
    assert_errors expected, "def foo(b:, a)\nend", ["Unexpected parameter order"]
  end

  test "rest keywords parameters before required parameters" do
    expected = DefNode(
      IDENTIFIER("foo"),
      nil,
      ParametersNode(
        [],
        [],
        [],
        nil,
        [KeywordParameterNode(LABEL("b:"), nil)],
        KeywordRestParameterNode(
          USTAR_STAR("**"),
          IDENTIFIER("rest")
        ),
        nil
      ),
      nil,
      ScopeNode([IDENTIFIER("rest"), LABEL("b")]),
      Location(),
      nil,
      Location(),
      Location(),
      nil,
      Location()
    )
    assert_errors expected, "def foo(**rest, b:)\nend", ["Unexpected parameter order"]
  end

  test "double arguments forwarding" do
    expected = DefNode(
      IDENTIFIER("foo"),
      nil,
      ParametersNode([], [], [], nil, [], ForwardingParameterNode(), nil),
      nil,
      ScopeNode([UDOT_DOT_DOT("...")]),
      Location(),
      nil,
      Location(),
      Location(),
      nil,
      Location()
    )
    assert_errors expected, "def foo(..., ...)\nend", ["Unexpected parameter order"]
  end

  test "multiple error in parameters order" do
    expected = DefNode(
      IDENTIFIER("foo"),
      nil,
      ParametersNode(
        [],
        [],
        [RequiredParameterNode()],
        nil,
        [KeywordParameterNode(LABEL("b:"), nil)],
        KeywordRestParameterNode(
          USTAR_STAR("**"),
          IDENTIFIER("args")
        ),
        nil
      ),
      nil,
      ScopeNode(
        [IDENTIFIER("args"),
         IDENTIFIER("a"),
         LABEL("b")]
      ),
      Location(),
      nil,
      Location(),
      Location(),
      nil,
      Location()
    )
    assert_errors expected, "def foo(**args, a, b:)\nend", ["Unexpected parameter order", "Unexpected parameter order"]
  end

  test "switching to optional arguments twice" do
    expected = DefNode(
      IDENTIFIER("foo"),
      nil,
      ParametersNode(
        [],
        [],
        [RequiredParameterNode()],
        nil,
        [KeywordParameterNode(LABEL("b:"), nil)],
        KeywordRestParameterNode(
          USTAR_STAR("**"),
          IDENTIFIER("args")
        ),
        nil
      ),
      nil,
      ScopeNode(
        [IDENTIFIER("args"),
         IDENTIFIER("a"),
         LABEL("b")]
      ),
      Location(),
      nil,
      Location(),
      Location(),
      nil,
      Location(),
    )
    assert_errors expected, "def foo(**args, a, b:)\nend", ["Unexpected parameter order", "Unexpected parameter order"]
  end

  test "switching to named arguments twice" do
    expected = DefNode(
      IDENTIFIER("foo"),
      nil,
      ParametersNode(
        [],
        [],
        [RequiredParameterNode()],
        nil,
        [KeywordParameterNode(LABEL("b:"), nil)],
        KeywordRestParameterNode(
          USTAR_STAR("**"),
          IDENTIFIER("args")
        ),
        nil
      ),
      nil,
      ScopeNode(
        [IDENTIFIER("args"),
         IDENTIFIER("a"),
         LABEL("b")]
      ),
      Location(),
      nil,
      Location(),
      Location(),
      nil,
      Location(),
    )
    assert_errors expected, "def foo(**args, a, b:)\nend", ["Unexpected parameter order", "Unexpected parameter order"]
  end

  test "returning to optional parameters multiple times" do
    expected = DefNode(
      IDENTIFIER("foo"),
      nil,
      ParametersNode(
        [RequiredParameterNode()],
        [OptionalParameterNode(
           IDENTIFIER("b"),
           EQUAL("="),
           IntegerNode()
         ),
         OptionalParameterNode(
           IDENTIFIER("d"),
           EQUAL("="),
           IntegerNode()
         )],
        [RequiredParameterNode(),
         RequiredParameterNode()],
        nil,
        [],
        nil,
        nil
      ),
      nil,
      ScopeNode(
        [IDENTIFIER("a"),
         IDENTIFIER("b"),
         IDENTIFIER("c"),
         IDENTIFIER("d"),
         IDENTIFIER("e")]
      ),
      Location(),
      nil,
      Location(),
      Location(),
      nil,
      Location(),
    )
    assert_errors expected, "def foo(a, b = 1, c, d = 2, e)\nend", ["Unexpected parameter order"]
  end

  test "case without when clauses errors on else clause" do
    expected = CaseNode(
      SymbolNode(SYMBOL_BEGIN(":"), IDENTIFIER("a"), nil, "a"),
      [],
      ElseNode(KEYWORD_ELSE("else"), nil, KEYWORD_END("end")),
      Location(),
      Location()
    )

    assert_errors expected, "case :a\nelse\nend", ["Unexpected else without no when clauses in case statement."]
  end

  test "setter method cannot be defined in an endless method definition"  do
    expected = DefNode(
      IDENTIFIER("a="),
      nil,
      nil,
      StatementsNode([IntegerNode()]),
      ScopeNode([]),
      Location(),
      nil,
      Location(),
      Location(),
      Location(),
      nil
    )

    assert_errors expected, "def a=() = 42", ["Setter method cannot be defined in an endless method definition"]
  end

  test "do not allow forward arguments in lambda literals" do
    expected = LambdaNode(
      ScopeNode([UDOT_DOT_DOT("...")]),
      MINUS_GREATER("->"),
      BlockParametersNode(ParametersNode([], [], [], nil, [], ForwardingParameterNode(), nil), [], Location(), Location()),
      nil
    )

    assert_errors expected, "->(...) {}", ["Unexpected ..."]
  end

  test "do not allow forward arguments in blocks" do
    expected = CallNode(
      nil,
      nil,
      IDENTIFIER("a"),
      nil,
      nil,
      nil,
      BlockNode(
        ScopeNode([UDOT_DOT_DOT("...")]),
        BlockParametersNode(ParametersNode([], [], [], nil, [], ForwardingParameterNode(), nil), [], Location(), Location()),
        nil,
        Location(),
        Location()
      ),
      "a"
    )

    assert_errors expected, "a {|...|}", ["Unexpected ..."]
  end

  test "don't allow return inside class body" do
    expected = ClassNode(
      ScopeNode([]),
      KEYWORD_CLASS("class"),
      ConstantReadNode(),
      nil,
      nil,
      StatementsNode([ReturnNode(KEYWORD_RETURN("return"), nil)]),
      KEYWORD_END("end")
    )

    assert_errors expected, "class A; return; end", ["Invalid return in class/module body"]
  end

  test "don't allow return inside module body" do
    expected = ModuleNode(
      ScopeNode([]),
      KEYWORD_MODULE("module"),
      ConstantReadNode(),
      StatementsNode([ReturnNode(KEYWORD_RETURN("return"), nil)]),
      KEYWORD_END("end")
    )

    assert_errors expected, "module A; return; end", ["Invalid return in class/module body"]
  end

  private

  def assert_errors(expected, source, errors)
    assert_nil Ripper.sexp_raw(source)

    result = YARP.parse_dup(source)
    result => YARP::ParseResult[value: YARP::ProgramNode[statements: YARP::StatementsNode[body: [*, node]]]]

    assert_equal_nodes(expected, node, compare_location: false)
    assert_equal(errors, result.errors.map(&:message))
  end

  def assert_error_messages(source, errors)
    assert_nil Ripper.sexp_raw(source)
    result = YARP.parse_dup(source)
    assert_equal(errors, result.errors.map(&:message))
  end

  def expression(source)
    YARP.parse_dup(source) => YARP::ParseResult[value: YARP::ProgramNode[statements: YARP::StatementsNode[body: [*, node]]]]
    node
  end
end
