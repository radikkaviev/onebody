FROM ubuntu:14.04

# install build tools
RUN apt-get update
RUN apt-get install -y -q wget vim build-essential curl libreadline-dev libcurl4-openssl-dev nodejs git libmysqlclient-dev imagemagick mysql-client
RUN apt-get clean

# install Ruby
RUN apt-get install -y software-properties-common
RUN apt-add-repository -y ppa:brightbox/ruby-ng
RUN apt-get update
RUN apt-get install -y ruby2.1 ruby2.1-dev
RUN gem install bundler --no-rdoc --no-ri

# set up user
RUN adduser --gecos "" --disabled-password --home=/home/onebody onebody
USER onebody
ENV HOME /home/onebody
ENV GEM_HOME /home/onebody/.gems

# set default rails env
ENV RAILS_ENV production

# add Gemfile first, then bundle install; this will make our builds cleaner
ADD .ruby-version /var/www/onebody/.ruby-version
ADD Gemfile /var/www/onebody/Gemfile
ADD config/database.yml /var/www/onebody/config/database.yml
ADD config/email.yml /var/www/onebody/config/email.yml
USER root
RUN chown -R onebody /var/www/onebody

# install gems
USER onebody
WORKDIR /var/www/onebody
RUN bundle install
RUN gem install thin --no-rdoc --no-ri

# add rest of source
USER root
ADD . /var/www/onebody
RUN chown -R onebody /var/www/onebody

# allow onebody user to run special 'chown_data' script as root
# workaround for volumes readonly to non-root users
RUN echo "ALL ALL=NOPASSWD: /var/www/onebody/script/docker/chown_data" > /etc/sudoers.d/chown_data

# copy scripts
RUN echo "#!/bin/bash\n\n/var/www/onebody/script/docker/server \$@"  > /server  && chmod +x /server
RUN echo "#!/bin/bash\n\n/var/www/onebody/script/docker/console \$@" > /console && chmod +x /console

# set up shared directories
USER onebody

# compile assets
WORKDIR /var/www/onebody
RUN bundle exec rake assets:precompile

# share port
EXPOSE 3000

# serve assets with rack
ENV SERVE_ASSETS true

CMD /server
