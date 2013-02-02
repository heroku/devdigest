require 'github_api'

class Devdigest
  VERSION = '1.0.0.beta.1'

  def self.defaults
    { since: Time.now - 24*60*60,
      org:   ENV['GITHUB_ORG'],
      repos: ENV['GITHUB_REPOS'].split(','),
      users: ENV['GITHUB_USERS'].split(','),
      token: ENV['GITHUB_TOKEN'] }
  end

  def self.run(options = {})
    options = defaults.merge(options)
    new(defaults.merge(options)).run
  end

  attr_accessor :since, :org, :repos, :users, :github
  def initialize(options)
    @since  = options.fetch(:since)
    @org    = options.fetch(:org)
    @repos  = options.fetch(:repos)
    @users  = options.fetch(:users)
    @github = Github.new(oauth_token: options.fetch(:token))
  end

  def run
    digest = ''

    # create a hash user -> array of activity
    activity = users.inject({}) do |activity, user|
      activity[user] = []
      activity
    end

    # collect activities
    repos.each do |repo|
      github.activity.events.repository(org, repo) do |event|
        break if Time.parse(event.created_at) < since
        next unless users.include?(event.actor.login)
        activity[event.actor.login] << [repo, event]
      end
    end

    important_events = {
      "PullRequestEvent" => lambda { |event|
        action = event.payload.action # opened/closed/reopened/synchronize
        title  = event.payload.pull_request.title
        url    = event.payload.pull_request.url
        "[#{action} pull #{title}](#{url})"
      },
      "IssuesEvent" => lambda { |event|
        action = event.payload.action # opened/closed/reopened
        title  = event.payload.issue.title
        url    = event.payload.issue.url
        "[#{action} issue #{title}](#{url})"
      },
      "PushEvent" => lambda { |event|
        commits  = event.payload.commits
        messages = commits.map { |commit| commit.message.split("\n").first }
        if messages.size == 1
          "pushed #{messages.first}"
        else
          "pushed #{messages.size} commits: #{messages.last}"
        end
      },
      "IssueCommentEvent" => lambda { |event|
        title  = event.payload.issue.title
        url    = event.payload.issue.title
        "[commented on #{title}](#{url})"
      },
    }

    # the events above are in order of priority
    order = important_events.keys

    activity.keys.each do |user|
      info = github.users.get user: user
      events = activity[user].select do |repo, event|
        important_events.has_key?(event.type)
      end

      # voodoo magic I don't want to bother making readable without classes
      events.sort_by! do |repo, event|
        "#{order.index(event.type) || 999} #{event.created_at}"
      end

      digest << "## #{info.name}\n"

      if events.empty?
        digest << "  - no tracked activity\n"
      else
        events[0, 6].each do |repo, event|
          summary = important_events[event.type].call(event)
          digest << "  - **#{repo}** #{summary}\n"
        end
      end

      digest << "\n"
    end

    digest
  end
end
