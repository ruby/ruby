# frozen_string_literal: false
#
# httpauth/htpasswd -- Apache compatible htpasswd file
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2003 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: htpasswd.rb,v 1.4 2003/07/22 19:20:45 gotoyuzo Exp $

require_relative 'userdb'
require_relative 'basicauth'
require 'tempfile'

module WEBrick
  module HTTPAuth

    ##
    # Htpasswd accesses apache-compatible password files.  Passwords are
    # matched to a realm where they are valid.  For security, the path for a
    # password database should be stored outside of the paths available to the
    # HTTP server.
    #
    # Htpasswd is intended for use with WEBrick::HTTPAuth::BasicAuth.
    #
    # To create an Htpasswd database with a single user:
    #
    #   htpasswd = WEBrick::HTTPAuth::Htpasswd.new 'my_password_file'
    #   htpasswd.set_passwd 'my realm', 'username', 'password'
    #   htpasswd.flush

    class Htpasswd
      include UserDB

      ##
      # Open a password database at +path+

      def initialize(path, password_hash: nil)
        @path = path
        @mtime = Time.at(0)
        @passwd = Hash.new
        @auth_type = BasicAuth
        @password_hash = password_hash

        case @password_hash
        when nil
          # begin
          #   require "string/crypt"
          # rescue LoadError
          #   warn("Unable to load string/crypt, proceeding with deprecated use of String#crypt, consider using password_hash: :bcrypt")
          # end
          @password_hash = :crypt
        when :crypt
          # require "string/crypt"
        when :bcrypt
          require "bcrypt"
        else
          raise ArgumentError, "only :crypt and :bcrypt are supported for password_hash keyword argument"
        end

        File.open(@path,"a").close unless File.exist?(@path)
        reload
      end

      ##
      # Reload passwords from the database

      def reload
        mtime = File::mtime(@path)
        if mtime > @mtime
          @passwd.clear
          File.open(@path){|io|
            while line = io.gets
              line.chomp!
              case line
              when %r!\A[^:]+:[a-zA-Z0-9./]{13}\z!
                if @password_hash == :bcrypt
                  raise StandardError, ".htpasswd file contains crypt password, only bcrypt passwords supported"
                end
                user, pass = line.split(":")
              when %r!\A[^:]+:\$2[aby]\$\d{2}\$.{53}\z!
                if @password_hash == :crypt
                  raise StandardError, ".htpasswd file contains bcrypt password, only crypt passwords supported"
                end
                user, pass = line.split(":")
              when /:\$/, /:{SHA}/
                raise NotImplementedError,
                      'MD5, SHA1 .htpasswd file not supported'
              else
                raise StandardError, 'bad .htpasswd file'
              end
              @passwd[user] = pass
            end
          }
          @mtime = mtime
        end
      end

      ##
      # Flush the password database.  If +output+ is given the database will
      # be written there instead of to the original path.

      def flush(output=nil)
        output ||= @path
        tmp = Tempfile.create("htpasswd", File::dirname(output))
        renamed = false
        begin
          each{|item| tmp.puts(item.join(":")) }
          tmp.close
          File::rename(tmp.path, output)
          renamed = true
        ensure
          tmp.close
          File.unlink(tmp.path) if !renamed
        end
      end

      ##
      # Retrieves a password from the database for +user+ in +realm+.  If
      # +reload_db+ is true the database will be reloaded first.

      def get_passwd(realm, user, reload_db)
        reload() if reload_db
        @passwd[user]
      end

      ##
      # Sets a password in the database for +user+ in +realm+ to +pass+.

      def set_passwd(realm, user, pass)
        if @password_hash == :bcrypt
          # Cost of 5 to match Apache default, and because the
          # bcrypt default of 10 will introduce significant delays
          # for every request.
          @passwd[user] = BCrypt::Password.create(pass, :cost=>5)
        else
          @passwd[user] = make_passwd(realm, user, pass)
        end
      end

      ##
      # Removes a password from the database for +user+ in +realm+.

      def delete_passwd(realm, user)
        @passwd.delete(user)
      end

      ##
      # Iterate passwords in the database.

      def each # :yields: [user, password]
        @passwd.keys.sort.each{|user|
          yield([user, @passwd[user]])
        }
      end
    end
  end
end
