class Authmgr
  def initialize
    @users = {
      'NaHi' => 'passwd',
      'HiNa' => 'wspass'
    }
    @sessions = {}
  end

  def login(userid, passwd)
    userid and passwd and @users[userid] == passwd
  end

  # returns userid
  def auth(sessionid)
    @sessions[sessionid]
  end

  def create_session(userid)
    while true
      key = create_sessionkey
      break unless @sessions[key]
    end
    @sessions[key] = userid
    key
  end

  def get_session(userid)
    @sessions.index(userid)
  end

  def destroy_session(sessionkey)
    @sessions.delete(sessionkey)
  end

private

  def create_sessionkey
    Time.now.usec.to_s
  end
end
