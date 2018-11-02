# frozen_string_literal: false
#
# httpservlet.rb -- HTTPServlet Utility File
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2000, 2001 TAKAHASHI Masayoshi, GOTOU Yuuzou
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: httpservlet.rb,v 1.21 2003/02/23 12:24:46 gotoyuzo Exp $

require_relative 'httpservlet/abstract'
require_relative 'httpservlet/filehandler'
require_relative 'httpservlet/cgihandler'
require_relative 'httpservlet/erbhandler'
require_relative 'httpservlet/prochandler'

module WEBrick
  module HTTPServlet
    FileHandler.add_handler("cgi", CGIHandler)
    FileHandler.add_handler("rhtml", ERBHandler)
  end
end
