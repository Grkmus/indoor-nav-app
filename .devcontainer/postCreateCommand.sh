# install zsh and oh-my-zsh
apt update
apt install -y zsh
wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh || true

apt-get install -y postgresql-client