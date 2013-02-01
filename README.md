# Devdigest

A script to collect activity from Github and (attempt to) compose a daily digest of what happened in your team.


## Terms of use

DO NOT USE THIS TO MEASURE PERFORMANCE.

ALSO, DO NOT USE THIS TO MEASURE PERFORMANCE.

FINALLY, DO NOT USE THIS TO MEASURE PERFORMANCE.


## Usage

You'll need a [Github OAuth token](https://help.github.com/articles/creating-an-oauth-token-for-command-line-use).

    cp .env .env.sample
    vi .env.sample # fill in with the token and your team details
    foreman run ruby devdigest.rb


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
