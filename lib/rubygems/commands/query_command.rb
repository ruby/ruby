# frozen_string_literal: true
require 'rubygems/command'
require 'rubygems/query_utils'
require 'rubygems/deprecate'

class Gem::Commands::QueryCommand < Gem::Command
  extend Gem::Deprecate
  rubygems_deprecate_command

  include Gem::QueryUtils

  def initialize(name = 'query',
                 summary = 'Query gem information in local or remote repositories')
    super name, summary,
         :name => //, :domain => :local, :details => false, :versions => true,
         :installed => nil, :version => Gem::Requirement.default

    add_option('-n', '--name-matches REGEXP',
               'Name of gem(s) to query on matches the',
               'provided REGEXP') do |value, options|
      options[:name] = /#{value}/i
    end

    add_query_options
  end
end
