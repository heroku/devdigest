require 'rubygems'
require 'bundler'
require 'time'
Bundler.require

require './lib/devdigest'

desc "Run the digest and print to stdout"
task :digest do
  since = Time.now-24*60*60
  puts Devdigest.new(since).run
end

desc "Run weekly ops and print to stdout"
task :ops_digest do
  since = Time.now-7*24*60*60
  puts Devdigest.new(since, :only => %w( pagerduty zendesk )).run
end

desc "Email daily digest"
task :daily_email do
  case Time.now.wday
  when 0, 6
    puts "Skipping weekend"
    next
  when 1 # monday
    since = Time.now-3*24*60*60
    puts "Monday - fetching activity since #{since}"
  else   # regular weekday
    since = Time.now-24*60*60
    puts "Weekday - fetching activity since #{since}"
  end

  digest    = Devdigest.new(since).run
  markdown  = RDiscount.new(digest)
  team      = ENV["ZENDESK_GROUP"] || "Team"
  subject   = "#{team} digest - #{Time.now.strftime("%A")}"

  Pony.mail({
    :to      => ENV["EMAIL_TO"],
    :from    => ENV["EMAIL_FROM"],
    :subject => subject,
    :headers => { "Content-Type" => "text/html" },
    :body    => markdown.to_html,

    :via => :smtp,
    :via_options => {
      :address        => ENV["MAILGUN_SMTP_SERVER"],
      :port           => ENV["MAILGUN_SMTP_PORT"],
      :user_name      => ENV["MAILGUN_SMTP_LOGIN"],
      :password       => ENV["MAILGUN_SMTP_PASSWORD"],
      :authentication => :plain,
      :domain         => "heroku.com"
    }
  })

  puts "Emailed #{ENV["EMAIL_TO"]}."
end

desc "Email weekly operational digest"
task :weekly_ops_email do
  if !ENV["WEEKLY_OPS_EMAIL_DAY"]
    abort("set WEEKLY_OPS_EMAIL_DAY to the weekday you want it sent (sunday=0)")
  end

  if Time.now.wday != ENV["WEEKLY_OPS_EMAIL_DAY"].to_i
    puts "Not doing the ops hand-off today, skipping"
    exit 0
  end

  since = Time.now-7*24*60*60
  puts "Fetching activity since #{since}"

  digest   = Devdigest.new(since, :only => %w( pagerduty zendesk )).run
  markdown = RDiscount.new(digest)
  subject  = "Ops digest - #{Time.now.strftime("%A")}"

  Pony.mail({
    :to      => ENV["EMAIL_TO"],
    :from    => ENV["EMAIL_FROM"],
    :subject => subject,
    :headers => { "Content-Type" => "text/html" },
    :body    => markdown.to_html,

    :via => :smtp,
    :via_options => {
      :address        => ENV["MAILGUN_SMTP_SERVER"],
      :port           => ENV["MAILGUN_SMTP_PORT"],
      :user_name      => ENV["MAILGUN_SMTP_LOGIN"],
      :password       => ENV["MAILGUN_SMTP_PASSWORD"],
      :authentication => :plain,
      :domain         => "heroku.com"
    }
  })

  puts "Emailed #{ENV["EMAIL_TO"]}."
end
