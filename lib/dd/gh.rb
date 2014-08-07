module Dd
  class Gh
    def initialize(token, org, since)

      @org = org

      @github = Github.new oauth_token: token

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
      users = get_users(ENV['GITHUB_USERS'], org)

      activity = {}

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

        # collect activities
        res = @github.activity.events.repository(repo_org, repo)
        collected_all = false
        res.each_page do |page|
          page.each do |event|
            if Time.parse(event.created_at) < @since.utc
              puts "We're done: #{Time.parse(event.created_at)} (#{@since.utc} in #{repo_org}/#{repo})"
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
      end
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