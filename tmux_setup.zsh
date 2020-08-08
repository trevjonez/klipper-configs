sudo apt update
sudo apt install snapd
sudo snap install ruby --classic
echo "Make sure /snap/bin is on the path: $PATH"
gem install tmuxinator
echo "Make sure $HOME/.gem/bin is on the path: $PATH"
tmuxinator doctor

ln -s ~/klipper-configs/.tmuxinator.yml .config/tmuxinator/klippy.yml
