#!/bin/zsh

echo 'source ~/klipper-configs/profile.zsh' >> ~/.zshrc
source ~/klipper-configs/profile.zsh
sudo apt update -y
sudo apt install -y snapd tmux
sudo snap install ruby --classic
gem install tmuxinator
tmuxinator doctor
cd ~
mkdir -p .config/tmuxinator
ln -s ~/klipper-configs/.tmuxinator.yml .config/tmuxinator/klippy.yml
