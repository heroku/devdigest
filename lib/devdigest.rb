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

  def run_github_digest
    return unless %w{GITHUB_ORG GITHUB_TOKEN}.all? {|key| ENV.has_key?(key)}
    return if skip?("github")
    add "## Github activity"
    add ""

    github = Github.new oauth_token: ENV["GITHUB_TOKEN"]
    org   = ENV["GITHUB_ORG"]

    repos = []
    users = []

    repos = ENV["GITHUB_REPOS"].split(",").sort if ENV["GITHUB_REPOS"]
    users = ENV["GITHUB_USERS"].split(",").sort if ENV["GITHUB_USERS"]

    github.repos.list(:org => org) { |repo|
      repos << repo.name
    } if repos.empty?

    github.orgs.members.list(org) { |member|
      users << member.login
    } if users.empty?

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
      res = github.activity.events.repository(repo_org, repo)
      collected_all = false
      res.each_page do |page|
        page.each do |event|
          if Time.parse(event.created_at) < @since.utc
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

    activity.keys.sort.each do |user|
      info = github.users.get user: user

      add "- **#{info.name}**"

      if activity[user].values.all? {|repo| repo.empty?}
        add "  - no tracked activity"
      else
        activity[user].each do |repo, events|
          next if events.empty?

          add "  - #{repo}"
          events.each do |title, links|
            add "    - #{title} #{links.join(', ')}"
          end

        end
      end

    end

    add ""

  rescue => e
    add e.to_s
    e.backtrace.each { |line| add('  ' + line) }
  end

  def run_pagerduty_digest
    return unless %w{PAGERDUTY_SERVICE PAGERDUTY_URL}.all? {|key| ENV.has_key?(key)}
    return if skip?("pagerduty")

    pagerduty = RestClient::Resource.new(ENV["PAGERDUTY_URL"])

    add "## On-call Schedule"
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
      add "- **#{schedule['name']}**: #{users.join(' > ')}"
    end
    add ""

    add "## On-call alerts"
    raw = pagerduty["api/v1/incidents?since=#{@since.iso8601}&until=#{Time.now.iso8601}&service=#{ENV["PAGERDUTY_SERVICE"]}"].get
    incidents = Yajl::Parser.parse(raw)["incidents"]
    if incidents.empty?
      add "- No incidents"
    else
      incidents.each do |incident|
        if incident["trigger_summary_data"]
          description = incident["trigger_summary_data"]["description"]
          description ||= incident["trigger_summary_data"]["subject"]
        end
        description ||= "(no description)"
        url = incident["html_url"]
        add "- #{incident["created_on"]} [#{description}](#{url})"
      end
    end

    add ""

  rescue => e
    add e.to_s
    e.backtrace.each { |line| add('  ' + line) }
  end

  def run_zendesk_digest
    return unless %w{ZENDESK_GROUP ZENDESK_PASSWORD ZENDESK_USER}.all? {|key| ENV.has_key?(key)}
    return if skip?("zendesk")
    add "## Support"

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
      agent = agents.detect { |a| a["id"] == ticket["assignee_id"] }
      ticket.merge!("agent" => agent) if agent
    end

    if groups["opened"].empty?
      add "- **No opened tickets**"
    else
      add "- **Opened tickets**:"
      groups["opened"].each do |ticket|
        add "  - #{ticket_entry(ticket)}"
      end
    end

    if groups["updated"].empty?
      add "- **No updated tickets**"
    else
      add "- **Updated tickets**:"
      groups["updated"].each do |ticket|
        add "  - #{ticket_entry(ticket)}"
      end
    end

    if groups["closed"].empty?
      add "- **No closed tickets**"
    else
      add "- **Closed tickets**:"
      groups["closed"].each do |ticket|
        add "  - #{ticket_entry(ticket)}"
      end
    end

    add ""

  rescue => e
    add e.to_s
    e.backtrace.each { |line| add('  ' + line) }
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
end
