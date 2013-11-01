class Devdigest
  def initialize(since, options={})
    @since  = since
    @digest = ""
    @only   = options[:only]
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

  def skip?(section)
    @only && !@only.include?(section)
  end

  def parse_event(event)
    case event.type
    when "PullRequestEvent"
      action = event.payload.action # opened/closed/reopened/synchronize
      title  = event.payload.pull_request.title
      url    = event.payload.pull_request.url
      [title, "[#{action} pull](#{github_url(url)})"]
    when "IssuesEvent"
      action = event.payload.action # opened/closed/reopened
      title  = event.payload.issue.title
      url    = event.payload.issue.url
      [title, "[#{action} issue](#{github_url(url)})"]
    when "PushEvent"
      commits  = event.payload.commits
      message = commits.first.message.split("\n").first rescue ""
      if commits.size == 1
        url     = commits.first.url
        [message,"[pushed](#{github_url(url)})"]
      elsif commits.size > 1
        url     = commits.last.url
        [message,"[pushed #{commits.size} commits](#{github_url(url)})"]
      end
    when "IssueCommentEvent"
      title  = event.payload.issue.title
      url    = event.payload.issue.url
      [title,"[commented](#{github_url(url)})"]
    end
  end

  def run_github_digest
    return unless %w{GITHUB_ORG GITHUB_REPOS GITHUB_TOKEN GITHUB_USERS}.all? {|key| ENV.has_key?(key)}
    return if skip?("github")
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

    repo_activity = {}

    # collect activities
    repos.each do |repo|
      res = github.activity.events.repository(org, repo)
      collected_all = false
      res.each_page do |page|
        page.each do |event|
          if Time.parse(event.created_at) < @since.utc
            collected_all = true
            break
          end

          next unless users.include?(event.actor.login)

          title, action = parse_event(event)
          if (title && action)
            repo_activity[event.actor.login] ||= {}
            repo_activity[event.actor.login][repo] ||= {}
            repo_activity[event.actor.login][repo][title] ||= []
            repo_activity[event.actor.login][repo][title] << action
          end
        end
        break if collected_all
      end
    end

    users.each do |user|
      info = github.users.get user: user
      add "## #{info.name}"

      if repo_activity[user].nil?
        add "  * no tracked activity"
      else
        repo_activity[user].keys.each do |repo|
          add "* **#{repo}**"
          repo_activity[user][repo].keys.each do |title|
            add "  * #{title} - #{repo_activity[user][repo][title].reverse.join(', ')}"
          end
        end
      end
      add("")
    end
  end

  def run_pagerduty_digest
    return unless %w{PAGERDUTY_SERVICE PAGERDUTY_URL}.all? {|key| ENV.has_key?(key)}
    return if skip?("pagerduty")

    pagerduty = RestClient::Resource.new(ENV["PAGERDUTY_URL"])

    add "# On-call Schedule"
    ENV['PAGERDUTY_SCHEDULE'].split(',').each do |schedule_id|
      users = []
      raw = pagerduty["api/v1/schedules/#{schedule_id}"].get
      schedule = Yajl::Parser.parse(raw)['schedule']
      yesterday, tomorrow = (Time.now - 86400).iso8601, (Time.now + 86400).iso8601
      raw = pagerduty["api/v1/schedules/#{schedule_id}/entries?overflow=true&since=#{yesterday}&until=#{tomorrow}"].get
      entries = Yajl::Parser.parse(raw)['entries']
      entries.sort_by {|entry| entry['end']}.each do |entry|
        users << entry['user']['name']
      end
      add "  - #{schedule['name']}: #{users.join(' > ')}"
    end
    add ""

    add "# On-call alerts"
    raw = pagerduty["api/v1/incidents?since=#{@since.iso8601}&until=#{Time.now.iso8601}&service=#{ENV["PAGERDUTY_SERVICE"]}"].get
    incidents = Yajl::Parser.parse(raw)["incidents"]
    if incidents.empty?
      add "  - No incidents"
    else
      incidents.each do |incident|
        if incident["trigger_summary_data"]
          description = incident["trigger_summary_data"]["description"]
          description ||= incident["trigger_summary_data"]["subject"]
        end
        description ||= "(no description)"
        url = incident["html_url"]
        add "  - [#{description}](#{url})"
      end
    end

    add ""
  end

  def run_zendesk_digest
    return unless %w{ZENDESK_GROUP ZENDESK_PASSWORD ZENDESK_USER}.all? {|key| ENV.has_key?(key)}
    return if skip?("zendesk")
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
