function gcodeLoop() {
  cd ~/virtual_sdcard/gcodes
  # Run within the gcodes directory so we can tab complete file names
  clear
  while true; do
    gcode=""
    vared -p "klippy -> " -c gcode
    echo "$gcode" >> /tmp/printer;
  done
}

function klippyTraceback() {
  grep -Hn -C 30 "Traceback" /tmp/klippy.log
}

function klippyClearLog() {
  > /tmp/klippy.log
}

function klippyConsole() {
  tmuxinator start klippy
}

export EDITOR='vim'
export PATH="$PATH:/snap/bin:$HOME/.gem/bin"
