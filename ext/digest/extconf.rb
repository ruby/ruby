# frozen_string_literal: false
# $RoughId: extconf.rb,v 1.6 2001/07/13 15:38:27 knu Exp $
# $Id$

require "mkmf"

$INSTALLFILES = {
  "digest.h" => "$(HDRDIR)"
} if $extmk

create_makefile("digest")
