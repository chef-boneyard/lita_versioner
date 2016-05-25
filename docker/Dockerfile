FROM litaio/ruby:latest
MAINTAINER John Keiser <jkeiser@chef.io>

# Set up the machine
RUN apt-get -qq update
RUN apt-get -qy --force-yes install socat sudo git unzip vim
RUN sed -i.bkp -e 's/%sudo\s\+ALL=(ALL\(:ALL\)\?)\s\+ALL/%sudo ALL=NOPASSWD:ALL/g' /etc/sudoers

# Install lita
RUN gem update --system
RUN gem install bundler
RUN gem install lita lita-slack mixlib-shellout ffi-yajl bundler pry pry-byebug pry-stack_explorer rake rack-test rspec

# Create the lita user
RUN useradd -m -g sudo lita
USER lita

# Expose 8080 for ngrok
EXPOSE 8080
# Allow the user to mount their own stuff into /home/lita
VOLUME /home/lita
# Put lita-versioner itself in /opt/bumpbot
VOLUME /opt/bumpbot
WORKDIR /opt/bumpbot

CMD docker/script-start-lita
