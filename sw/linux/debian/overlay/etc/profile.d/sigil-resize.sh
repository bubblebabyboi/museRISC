# Serial consoles (Sigil's ttyS0) do not carry the terminal size, so
# vim/htop/less would assume 80x24. Ask the terminal once at login;
# run `sigil-resize` again after resizing the window.
if [ -n "${BASH_VERSION:-}" ] && [ -t 0 ] && [ -t 1 ]; then
  sigil-resize() {
    local old rows cols
    old=$(stty -g) || return
    stty raw -echo min 0 time 10
    printf '\0337\033[r\033[999;999H\033[6n\0338' > /dev/tty
    IFS='[;' read -r -s -d R -t 2 _ rows cols < /dev/tty
    stty "$old"
    case "$rows$cols" in ''|*[!0-9]*) return 1 ;; esac
    stty rows "$rows" cols "$cols"
  }
  # agetty usually sets the size already; ask only if it is unknown.
  case $(tty) in
    /dev/ttyS*|/dev/hvc*) [ "$(stty size 2>/dev/null)" = "0 0" ] && sigil-resize ;;
  esac
fi
