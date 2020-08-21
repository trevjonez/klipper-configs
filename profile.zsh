function gcodeLoop() {
  clear
  while true; do
    gcode=""
    vared -p "klippy -> " -c gcode
    echo "$gcode" >> /tmp/printer;
  done
}

function klippyTraceback {
  grep -Hn -C 30 "Traceback" /tmp/klippy.log
}

export PATH="$PATH:/snap/bin:$HOME/.gem/bin"
