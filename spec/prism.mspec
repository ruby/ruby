# frozen_string_literal: true

## Language
MSpec.register(:exclude, "Hash literal raises a SyntaxError at parse time when Symbol key with invalid bytes")
MSpec.register(:exclude, "Hash literal raises a SyntaxError at parse time when Symbol key with invalid bytes and 'key: value' syntax used")
MSpec.register(:exclude, "A Symbol literal raises an SyntaxError at parse time when Symbol with invalid bytes")

## Core
MSpec.register(:exclude, "TracePoint#path equals \"(eval at __FILE__:__LINE__)\" inside an eval for :end event")

## Library
MSpec.register(:exclude, "Coverage.result returns the correct results when eval coverage is disabled")
MSpec.register(:exclude, "Socket.gethostbyaddr using an IPv6 address with an explicit address family raises SocketError when the address is not supported by the family")
