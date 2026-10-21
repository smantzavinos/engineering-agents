# Activation keeps runtime preferences, with declarative settings winning.
.[1] as $declarative
| (.[0] * $declarative)
| if $declarative.tuiMode == "fullscreen"
    and (($declarative.packages // []) | index("./packages/pi-powerline-footer") != null)
  then del(
    .powerline.fixedEditor,
    .powerline.mouseScroll,
    .powerlineShortcuts.scrollChatUp,
    .powerlineShortcuts.scrollChatDown
  )
  else .
  end
