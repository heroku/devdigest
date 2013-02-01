require 'rubygems'
require 'bundler'
require 'time'
Bundler.require

require './devdigest'

task :run do
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

  digest   = Devdigest.run(since)
  markdown = RDiscount.new(digest)
  subject  = "Team digest - #{Time.now.strftime("%A")}"

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