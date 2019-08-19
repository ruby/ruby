# s/r 5, r/r 10
class A
rule

  content: RecvH         received
    ;

  datetime: day
    ;

  msgid: '<' spec '>';

  day:
    | ATOM ','
    ;

  received: recvitem_list recvdatetime
    ;

  recvitem_list:
    | recvitem_list recvitem
    ;

  recvitem: by | via | with | for ;

  by:
    | BY domain
    ;

  via:
    | VIA ATOM
    ;

  with: WITH ATOM
    ;

  for:
    | FOR addr
    ;

  recvdatetime:
    | ';' datetime
    ;

  addr: mbox | group ;

  mboxes: mbox
    | mboxes ',' mbox
    ;

  mbox: spec
    | routeaddr
    | phrase routeaddr
    ;

  group: phrase ':' mboxes ';'
    ;

  routeaddr: '<' route spec '>'
    | '<' spec '>'
    ;

  route: at_domains ':' ;

  at_domains: '@' domain
    | at_domains ',' '@' domain
    ;

  spec: local '@' domain
    | local
    ;

  local: word
    | local '.' word
    ;

  domain: domword
    | domain '.' domword
    ;

  domword: atom
    | DOMLIT
    | DIGIT
    ;

  phrase: word
    | phrase word
    ;

  word: atom
    | QUOTED
    | DIGIT
    ;

  atom: ATOM | FROM | BY | VIA | WITH | ID | FOR ;

end
