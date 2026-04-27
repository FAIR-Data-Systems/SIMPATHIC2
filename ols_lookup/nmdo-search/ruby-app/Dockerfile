FROM ruby:3.3-slim

RUN apt-get update && apt-get install -y \
    build-essential \
    libxml2-dev \
    libxslt-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile .
RUN bundle install --jobs 4 --retry 3

COPY app.rb .

VOLUME ["/data"]
EXPOSE 4567

CMD ["ruby", "app.rb"]
