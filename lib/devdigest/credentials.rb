require 'netrc'

class Devdigest
  class Credentials
    attr_reader :netrc, :label

    def initialize(netrc, label)
      @netrc = netrc
      @label = label
    end

    def self.token netrc = Netrc.read, label = 'devdigest@api.github.com'
      new(netrc, label).token
    end

    def self.save login, token, netrc = Netrc.read, label = 'devdigest@api.github.com'
      new(netrc, label).save login, token
    end

    def token
      credentials.last
    end

    def save(login, token)
      return if login.nil? or login =~ /^\s*$/
      return if token.nil? or token =~ /^\s*$/
      netrc[label] = [ login, token ]
      netrc.save
    end

  private

    def credentials
      Array netrc[label]
    end
  end
end
