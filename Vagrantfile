# -*- mode: ruby -*-
# vi: set ft=ruby :

VAGRANTFILE_API_VERSION = "2"

$ruby_version = File.read(File.expand_path("../.ruby-version", __FILE__)).strip

$vhost = <<VHOST
<VirtualHost *:80>
  PassengerRuby /home/vagrant/.rvm/wrappers/ruby-2.1.2@onebody/ruby
  DocumentRoot /vagrant/public
  RailsEnv development
  <Directory /vagrant/public>
    AllowOverride all
    Options -MultiViews
    Require all granted
  </Directory>
</VirtualHost>
VHOST

$setup = <<SCRIPT
cd ~/
set -ex

# install prerequisites
apt-get update -qq
debconf-set-selections <<< 'mysql-server mysql-server/root_password password vagrant'
debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password vagrant'
apt-get install -q -y build-essential curl libcurl4-openssl-dev nodejs git mysql-server libmysqlclient-dev libaprutil1-dev libapr1-dev apache2 apache2-threaded-dev imagemagick

# setup db
mysql -u root -pvagrant -e "create database onebody_dev  default character set utf8 default collate utf8_general_ci; grant all on onebody_dev.*  to onebody@localhost identified by 'onebody';"
mysql -u root -pvagrant -e "create database onebody_test default character set utf8 default collate utf8_general_ci; grant all on onebody_test.* to onebody@localhost identified by 'onebody';"

user=$(cat <<USER
  set -ex

  # install rvm
  if [[ ! -d \\$HOME/.rvm ]]; then
    curl -sSL --insecure https://get.rvm.io | bash -s stable
    \\$HOME/.rvm/bin/rvm requirements
  fi
  source \\$HOME/.rvm/scripts/rvm
  rvm use --install #{$ruby_version}

  # bundle gems
  cd /vagrant
  gem install bundler --no-ri --no-rdoc
  if [[ ! -e config/database.yml ]]; then
    cp config/database.yml{.example,}
  fi
  bundle install

  # setup config and migrate db
  if [[ ! -e config/secrets.yml ]]; then
    secret=\\$(/home/vagrant/.rvm/gems/#{$ruby_version}@onebody/bin/rake -s secret)
    sed -e"s/SOMETHING_RANDOM_HERE/\\$secret/g" config/secrets.yml.example > config/secrets.yml
  fi
  \\$HOME/.rvm/gems/#{$ruby_version}@onebody/bin/rake db:migrate db:seed

  # install apache and passenger
  if [[ ! -e /etc/apache2/conf-available/passenger.conf ]]; then
    rvm use #{$ruby_version}@global
    # passenger 4.0.x doesn't like our git-sourced gems; use the previous version for now
    gem install passenger
    rvmsudo passenger-install-apache2-module -a
    rvmsudo passenger-install-apache2-module --snippet | sudo tee /etc/apache2/conf-available/passenger.conf
  fi
USER
)
su - vagrant -c "$user"

a2enconf passenger
a2enmod rewrite

if [[ ! -e /etc/apache2/sites-available/onebody.conf ]]; then
  echo -e "#{$vhost}" > /etc/apache2/sites-available/onebody.conf
  a2dissite 000-default
  a2ensite onebody
else
  echo -e "#{$vhost}" > /tmp/onebody.conf
  if diff /tmp/onebody.conf /etc/apache2/sites-available/onebody.conf > /dev/null
  then
    # the files are the same, do nothing
    echo "onebody.conf does not need to be updated"
  else
    # the files are different, update
    echo -e "#{$vhost}" > /etc/apache2/sites-available/onebody.conf
  fi
fi
service apache2 reload
SCRIPT

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = "phusion/ubuntu-14.04-amd64"
  config.vm.network "forwarded_port", guest: 80, host: 8080, auto_correct: true
  config.ssh.forward_agent = true

  config.vm.provision :shell, inline: $setup

  # apply local customizations
  custom_file = File.expand_path("../Vagrantfile.local", __FILE__)
  eval(File.read(custom_file)) if File.exists?(custom_file)

  # ...for example, you can give your box more ram by adding this to your Vagrantfile.local:
  #config.vm.provider :virtualbox do |vb|
  #  vb.customize ["modifyvm", :id, "--memory", "2048"]
  #end
end
