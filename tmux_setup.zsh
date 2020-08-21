echo 'source $HOME/klipper-configs/profile.zsh' >> ~/.zshrc
sudo apt update
sudo apt install snapd
sudo snap install ruby --classic
gem install tmuxinator
tmuxinator doctor

ln -s ~/klipper-configs/.tmuxinator.yml .config/tmuxinator/klippy.yml
