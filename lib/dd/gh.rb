module Dd
  class Gh
    def initialize(token, org, since)

      @org = org

      @github = Github.new oauth_token: token, auto_pagination: true

      @digest = ""
      @since = since
    end

    def run
      collect(@org)
      @digest
    end

    private
    def add(row)
      @digest << "#{row}\n"
    end

    def collect(org)
      add "## Github activity in #{org}"
      add ""

      repos = get_repos(ENV['GITHUB_REPOS'], org)
      pull_request_repos = get_repos(ENV['GITHUB_PULL_REQUEST_REPOS'], org)
      users = get_users(ENV['GITHUB_USERS'], org)

      activity = {}
      pull_requests = []

      important_events = {
        "PullRequestEvent" => lambda { |event|
          action        = event.payload.action # opened/closed/reopened/synchronize
          pull_request  = event.payload.pull_request
          link          = "[#{action} pull](#{pull_request.html_url})"
          [ pull_request.title, link ]
        },
        "IssuesEvent" => lambda { |event|
          action = event.payload.action # opened/closed/reopened
          issue = event.payload.issue
          link = "[#{action} issue](#{issue.html_url})"
          [ issue.title, link ]
        },
        "PushEvent" => lambda { |event|
          commits  = event.payload.commits
          if commits.empty?
            ['empty','pushed']
          else
            [
              commits.first.message.split("\n").first,
              "[pushed #{commits.size}](#{commits.last.url.sub!("api.github.com/repos", "github.com").sub!("commits", "commit")})"
            ]
          end
        },
        "IssueCommentEvent" => lambda { |event|
          link = "[commented](#{event.payload.comment.html_url})"
          [ event.payload.issue.title, link ]
        },
      }

      repos.each do |repo_and_org|
        # repo can contain an override org
        repo, repo_org = repo_and_org.split("@").push(org)

        puts "Crawling #{repo_org} / #{repo}"

        # collect activities
        res = @github.activity.events.repository(repo_org, repo)
        collected_all = false
        res.each_page do |page|
          page.each do |event|
            # Repos that are permamently moved actually produce an array
            # instead of event object. Thanks, github_api
            next if Array === event

            if Time.parse(event.created_at) < @since.utc
              puts "We're done: #{Time.parse(event.created_at)} (#{@since.utc})"
              collected_all = true
              break
            end

            next unless users.include?(event.actor.login) && important_events.has_key?(event.type)

            activity[event.actor.login] ||= {}
            activity[event.actor.login][repo] ||= {}
            title, link = important_events[event.type].call(event)
            activity[event.actor.login][repo][title] ||= []
            activity[event.actor.login][repo][title] << link
          end
          break if collected_all
        end

        @github.pull_requests.list(repo_org, repo).each_page do |page|
          next unless pull_request_repos.include?(repo_and_org)
          page.each do |pull_request|
            author = pull_request.user && pull_request.user.login || 'null'
            next if pull_request.assignee # ignore assigned
            # work around possible time drift between server/client, all were 0 seconds or more ago
            seconds_ago = [(Time.now.utc - Time.parse(pull_request.updated_at)).round, 0].max
            days_ago = seconds_ago / (24 * 60 * 60)
            hours_ago = (seconds_ago / (60 * 60)) % 24
            minutes_ago = (seconds_ago / 60) % 60

            time_ago = ""
            time_ago << "#{days_ago} days " unless days_ago == 0
            time_ago << "#{hours_ago} hours " unless hours_ago == 0
            time_ago << "#{minutes_ago} minutes " unless minutes_ago == 0
            time_ago << "ago"
            pull_requests << [
              "#{days_ago.to_s.rjust(2,'0')}.#{hours_ago.to_s.rjust(2,'0')}.#{minutes_ago.to_s.rjust(2,'0')}",
              "  - **#{repo}** [#{pull_request.title}](#{pull_request.html_url}) *updated #{time_ago}*"
            ]
          end
        end
      end

      if pull_requests.empty?
        add("## No Pull Requests!")
        add("")
      else
        add("## Pull Requests")
        pull_requests.sort_by {|pr| pr[0]}.reverse.each {|pr| add(pr[1])}
        add("")
      end

      activity.keys.sort.each do |user|
        info = @github.users.get user: user

        if info.has_key?('name') && info.name != nil && !info.name.empty?
          add " - **#{info.name}**"
        else
          add " - **#{info.login}**"
        end

        if activity[user].values.all? {|repo| repo.empty?}
          add " - no tracked activity"
        else
          activity[user].each do |repo, events|
            next if events.empty?
            add "   - #{repo}"
            events.each do |title, links|
              add "     - #{title} #{links.join(', ')}"
            end
          end
        end
      end

      add ""
      rescue => e
        add e.to_s
        e.backtrace.each { |line| add(' ' + line) }
    end

    def get_repos(repos, org)
      if repos
        repos = repos.split(",")
      else
        repos = []
        @github.repos.list(:org => org) { |repo|
          repos << repo.name
        }
      end
      repos.sort
      repos
    end

    def get_users(users, org)
      if users
        users = users.split(",")
      else
        users = []
        @github.orgs.members.list(org) { |member|
          users << member.login
        }
      end
      users.sort
      users
    end

  end
end
