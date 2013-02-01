require 'rubygems'
require 'bundler'
require 'time'

Bundler.require

since = Time.now-24*60*60

github = Github.new oauth_token: ENV["GITHUB_TOKEN"]

org   = ENV["GITHUB_ORG"]
repos = ENV["GITHUB_REPOS"].split(",").sort
users = ENV["GITHUB_USERS"].split(",").sort

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

  puts "## #{info.name}"

  if events.empty?
    puts "  - no tracked activity"
  else
    events[0, 6].each do |repo, event|
      summary = important_events[event.type].call(event)
      puts "  - **#{repo}** #{summary}"
    end
  end

  puts "\n"
end
