function prompt_shell_level() {
  if [[ $SHLVL -gt 1 ]]; then
    p10k segment -i '⚡' -f yellow -t "$SHLVL"
  fi
}
