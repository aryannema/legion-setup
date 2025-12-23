# bash completion for setup-aryan

_setup_aryan_actions() {
  local actions_dir="/opt/aryan-setup/actions"
  if [[ -d "${actions_dir}" ]]; then
    ls -1 "${actions_dir}"/*.sh 2>/dev/null | xargs -r -n 1 basename | sed 's/\.sh$//' | sed '/^_/d'
  fi
}

_setup_aryan() {
  local cur prev
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "list run version --help -h $(_setup_aryan_actions)" -- "${cur}") )
    return 0
  fi

  if [[ "${COMP_WORDS[1]}" == "run" && ${COMP_CWORD} -eq 2 ]]; then
    COMPREPLY=( $(compgen -W "$(_setup_aryan_actions)" -- "${cur}") )
    return 0
  fi

  # Default: no further suggestions
  return 0
}

complete -F _setup_aryan setup-aryan
