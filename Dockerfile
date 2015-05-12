FROM heroku/cedar:14
MAINTAINER Andrew Gwozdziewycz <apg@heroku.com>

ADD . /app

ENV HOME=/app
ENV DEPLOY=docker
ENV LANG=${LANG:-en_US.UTF-8}
ENV GEM_PATH="$HOME/vendor/bundle/ruby/2.0.0:$GEM_PATH"
ENV PATH="$HOME/bin:$HOME/vendor/bundle/bin:$HOME/vendor/bundle/ruby/2.0.0/bin:$PATH"
ENV RACK_ENV=${RACK_ENV:-production}

WORKDIR /app

RUN mkdir -p /var/lib/buildpack /var/cache/buildpack \
    && curl https://codon-buildpacks.s3.amazonaws.com/buildpacks/heroku/ruby.tgz | tar xz -C /var/lib/buildpack
RUN BUNDLE_WITHOUT=NOTHING STACK=cedar-14 /var/lib/buildpack/bin/compile /app /var/cache/buildpack

