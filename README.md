# Devdigest

A script to collect activity from Github and (attempt to) compose a daily digest of what happened in your team.


## Terms of use

DO NOT USE THIS TO MEASURE PERFORMANCE.

ALSO, DO NOT USE THIS TO MEASURE PERFORMANCE.

FINALLY, DO NOT USE THIS TO MEASURE PERFORMANCE.


## Usage

You'll need a [Github OAuth token](https://help.github.com/articles/creating-an-oauth-token-for-command-line-use).

    cp .env.sample .env
    vim .env # fill in with the token and your team details
    foreman run bundle exec rake digest

**Note**

If you don't provide GitHub repositories and members, all repositories
and members of the organization will be included in the daily report.

## Deployment

Sorry, this is not yet a service! For now:

  - Push to a Heroku app
  - Add config vars
  - Install the addons `mailgun` and `scheduler`
  - Configure scheduler to run daily, running `bundle exec rake daily_email`


## Sample

    ## Brandur
      - **api** [closed pull Some Pull Request](https://api.github.com/repos/heroku/api/pulls/123)
      - **api** pushed 8 commits: Fix something

    ## Wesley Beary
      - **api-doc** pushed update domain serialization docs
      - **api** pushed update something

    ## Mark Fine
      - **api** [closed pull something](https://api.github.com/repos/heroku/api/pulls/456)
      - **core** [closed pull Pricing legacy intro](https://api.github.com/repos/heroku/core/pulls/123)

    ## Pedro Belo
      - **api** [opened pull Account endpoints](https://api.github.com/repos/heroku/api/pulls/789)
      - **api** pushed another fix

    # On-call alerts
      - [Pedro Belo paged: testing](http://heroku.pagerduty.com/incidents/PGLWM7J)

    # Support
      - No new tickets
      - Closed tickets:
        - [Can't make API calls...](https://support.heroku.com/tickets/123) by brandur@heroku.com
        - [Having trouble with my SSH key...](https://support.heroku.com/tickets/456) by pedro@heroku.com
