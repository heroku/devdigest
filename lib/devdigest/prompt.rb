# Lovingly borrowed from the heroku gem:
#   https://github.com/heroku/heroku/blob/master/lib/heroku/auth.rb
class Devdigest
  class Prompt
    attr_accessor :stdin, :stderr

    def initialize(stdin, stderr)
      @stdin  = stdin
      @stderr = stderr
    end

    def self.ask_for_credentials(stdin = $stdin, stderr = $stderr)
      new(stdin, stderr).ask_for_credentials
    end

    def ask_for_credentials
      stderr.puts "Sign into your GitHub account."
      stderr.print "Username: "
      email = ask

      stderr.print "Password (typing will be hidden): "
      password = ask_for_password

      [ email, password ]
    end

    def ask
      stdin.gets.to_s.strip
    end

    def ask_for_password
      echo_off
      password = ask
      stderr.puts
      echo_on
      password
    end

    NULL = defined?(File::NULL) ? File::NULL :
             File.exist?('/dev/null') ? '/dev/null' : 'NUL'

    def echo_on()  with_tty { system "stty echo 2>#{NULL}"  } end
    def echo_off() with_tty { system "stty -echo 2>#{NULL}" } end
    def with_tty(&block)
      return unless stdin.isatty
      yield
    rescue
      # fails on windows
    end
  end
end
