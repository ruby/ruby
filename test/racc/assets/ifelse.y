class C::Parser
token tSOMETHING
rule
  statement
    : tSOMETHING
    | 'if' statement 'then' statement
    | 'if' statement 'then' statement 'else' statement
    ;

  dummy
    : tSOMETHING '+' tSOMETHING
    | tSOMETHING '-' tSOMETHING
    ;

