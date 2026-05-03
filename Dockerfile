FROM ruby:3.4-slim

ENV APP_HOME=/app \
    BUNDLE_WITHOUT="" \
    PORT=9292

WORKDIR $APP_HOME

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential libpq-dev pkg-config git \
  && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock* ./
RUN bundle install

COPY . .

EXPOSE 9292

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
