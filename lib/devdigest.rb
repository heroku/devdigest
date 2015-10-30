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
    run_tracker_digest
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

    require_relative "dd/gh"

    ENV['GITHUB_ORG'].split(',').sort.each { |org|
      gh_worker = Dd::Gh.new(ENV['GITHUB_TOKEN'], org, @since)
      gh_digest = gh_worker.run
      add(gh_digest)
    }

  rescue => e
    add e.to_s
    e.backtrace.each { |line| add('  ' + line) }
  end

  def run_pagerduty_digest
    return unless %w{PAGERDUTY_SERVICE PAGERDUTY_URL}.all? {|key| ENV.has_key?(key)}
    return if skip?("pagerduty")

    headers = if token = ENV['PAGERDUTY_TOKEN']
      {
        'Authorization' => "Token token=#{token}"
      }
    else
      {}
    end

    pagerduty = RestClient::Resource.new(ENV["PAGERDUTY_URL"], :headers => headers)

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

  def run_tracker_digest
    return unless %w{TRACKER_TOKEN TRACKER_PROJECTS}.all? {|key| ENV.has_key?(key)}
    return if skip?("tracker")
    add "## Tracker\n"

    token = ENV["TRACKER_TOKEN"]
    yesterday = (Time.now - 86400).iso8601

    ENV["TRACKER_PROJECTS"].split(",").each do |pid|
      activity = tracker(pid, yesterday)

      add "### Highlights for #{activity[0]["project"]["name"]}\n"

      activity.select { |a| a["kind"] == "story_create_activity" && a["highlight"] == "added" }.each do |act|
        add "  - #{format_tracker_activity act}"
      end

      activity.select { |a| a["kind"] == "story_update_activity" && a["highlight"] == "delivered" }.each do |act|
        add "  - #{format_tracker_activity act}"
      end

      activity.select { |a| a["kind"] == "story_update_activity" && a["highlight"] == "accepted" }.each do |act|
        add "  - #{format_tracker_activity act}"
      end

      activity.select { |a| a["kind"] == "story_update_activity" && a["highlight"] == "started" }.each do |act|
        add "  - #{format_tracker_activity act}"
      end
    end
  rescue => e
    add e.to_s
    e.backtrace.each { |line| add('  ' + line) }
  end

  def format_tracker_activity(act)
    name = act["performed_by"]["name"]
    highlight = act["highlight"]
    story_type = act["primary_resources"][0]["story_type"]
    desc = act["primary_resources"][0]["name"]
    "#{name} #{highlight} #{story_type} [#{desc}](#{tracker_url act})"
  end

  def tracker_url(act)
    "https://www.pivotaltracker.com/story/show/#{act["primary_resources"][0]["id"]}"
  end

  def tracker(project_id, since)
    url = "https://www.pivotaltracker.com/services/v5/projects/#{project_id}/activity?occurred_after=#{since.to_i}"
    @tracker ||= RestClient::Resource.new(url, :headers => { "X-TrackerToken" => ENV["TRACKER_TOKEN"] })
    raw = @tracker.get
    Yajl::Parser.parse(raw)
  end
end
