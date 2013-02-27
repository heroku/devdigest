class Devdigest
  def initialize(since)
    @since  = since
    @digest = ""
  end

  def run
    run_github_digest
    run_pagerduty_digest
    run_zendesk_digest
    @digest
  end

  def add(row)
    @digest << "#{row}\n"
  end

  def run_github_digest
    return unless %w{GITHUB_ORG GITHUB_REPOS GITHUB_TOKEN GITHUB_USERS}.all? {|key| ENV.has_key?(key)}
    add "# Github activity"

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
        break if Time.parse(event.created_at) < @since.utc
        next unless users.include?(event.actor.login)
        activity[event.actor.login] << [repo, event]
      end
    end

    important_events = {
      "PullRequestEvent" => lambda { |event|
        action = event.payload.action # opened/closed/reopened/synchronize
        title  = event.payload.pull_request.title
        url    = event.payload.pull_request.url
        "#{action} [pull #{title}](#{github_url(url)})"
      },
      "IssuesEvent" => lambda { |event|
        action = event.payload.action # opened/closed/reopened
        title  = event.payload.issue.title
        url    = event.payload.issue.url
        "#{action} [issue #{title}](#{github_url(url)})"
      },
      "PushEvent" => lambda { |event|
        commits  = event.payload.commits
        if commits.size == 1
          message = commits.first.message.split("\n").first
          url     = commits.first.url
          "pushed [#{message}](#{github_url(url)})"
        else
          message = commits.last.message.split("\n").first
          url     = commits.last.url
          "pushed #{commits.size} commits: [#{message}](#{github_url(url)})"
        end
      },
      "IssueCommentEvent" => lambda { |event|
        title  = event.payload.issue.title
        url    = event.payload.issue.url
        "commented on [#{title}](#{github_url(url)})"
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

      add "## #{info.name}"

      if events.empty?
        add "  - no tracked activity"
      else
        events[0, 6].each do |repo, event|
          summary = important_events[event.type].call(event)
          add "  - **#{repo}** #{summary}"
        end
      end

      add("")
    end
  end

  def run_pagerduty_digest
    return unless %w{PAGERDUTY_SERVICE PAGERDUTY_URL}.all? {|key| ENV.has_key?(key)}
    add "# On-call alerts"

    pagerduty = RestClient::Resource.new(ENV["PAGERDUTY_URL"])
    raw = pagerduty["api/v1/incidents?since=#{@since.iso8601}&until=#{Time.now.iso8601}&service=#{ENV["PAGERDUTY_SERVICE"]}"].get
    incidents = Yajl::Parser.parse(raw)["incidents"]
    if incidents.empty?
      add "  - No incidents"
    else
      incidents.each do |incident|
        description = if incident["trigger_summary_data"]
          incident["trigger_summary_data"]["description"]
        else
          "[no description]"
        end
        url = incident["html_url"]
        add "  - [#{description}](#{url})"
      end
    end

    add ""
  end

  def run_zendesk_digest
    return unless %w{ZENDESK_GROUP ZENDESK_PASSWORD ZENDESK_USER}.all? {|key| ENV.has_key?(key)}
    add "# Support"

    groups = %w( opened closed updated ).inject({}) { |h, status| h[status] = []; h }

    find_tickets.each do |ticket|
      break if Time.parse(ticket["updated_at"]) < @since.utc
      case ticket["status"]
      when "new"
        groups["opened"] << ticket
      when "open"
        groups["updated"] << ticket
      when "closed", "solved"
        groups["closed"] << ticket
      end
    end

    # get agents assigned to a ticket
    agents = find_agents
    groups.values.flatten.each do |ticket|
      agent = agents.detect { |agent| agent["id"] == ticket["assignee_id"] }
      ticket.merge!("agent" => agent) if agent
    end

    if groups["opened"].empty?
      add "  - No new tickets"
    else
      add "  - Opened tickets:"
      groups["opened"].each do |ticket|
        add "    - #{ticket_entry(ticket)}"
      end
    end

    unless groups["updated"].empty?
      add "  - Updated tickets:"
      groups["updated"].each do |ticket|
        add "    - #{ticket_entry(ticket)}"
      end
    end

    unless groups["closed"].empty?
      add "  - Closed tickets:"
      groups["closed"].each do |ticket|
        add "    - #{ticket_entry(ticket)}"
      end
    end

    add ""
  end

  def zendesk
    @zendesk ||= RestClient::Resource.new("https://heroku.zendesk.com/api/v2",
      :user => "#{ENV["ZENDESK_USER"]}/token", :password => ENV["ZENDESK_PASSWORD"])
  end

  def find_tickets
    raw = zendesk["/search.json"].get(:params => {
      :query      => "type:ticket group:#{ENV["ZENDESK_GROUP"]}",
      :sort_by    => "updated_at",
      :sort_order => "desc",
    })
    Yajl::Parser.parse(raw)["results"]
  end

  def find_agents
    raw = zendesk["/search.json"].get(:params => {
      :query => "type:user group:#{ENV["ZENDESK_GROUP"]}"
    })
    Yajl::Parser.parse(raw)["results"]
  end

  def ticket_entry(ticket)
    description = ticket["description"].split("\n")[0]
    short_description = description.split(/\s+/)[0, 12].join(" ") << "..."
    url = ticket_url(ticket)
    author_info = " by #{ticket["agent"]["name"]}" if ticket.has_key?("agent")
    "[#{short_description}](#{url})#{author_info}"
  end

  def ticket_url(ticket)
    "https://support.heroku.com/tickets/#{ticket["id"]}"
  end

  def github_url(api_url)
    api_url.sub("api.github.com/repos", "github.com").sub("/pulls/", "/pull/")
  end
end
