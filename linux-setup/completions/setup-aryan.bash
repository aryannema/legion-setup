# Bash completion for setup-aryan
# Install path (staged): /etc/bash_completion.d/setup-aryan

_setup_aryan_complete() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  local actions_dir="/usr/local/aryan-setup/actions"

  if [[ "${COMP_CWORD}" -eq 1 ]]; then
    local actions
    if [[ -d "${actions_dir}" ]]; then
      actions="$(command ls -1 "${actions_dir}" 2>/dev/null | sed 's/\.sh$//' | sort)"
    else
      actions=""
    fi
    COMPREPLY=( $(compgen -W "list ${actions}" -- "${cur}") )
    return 0
  fi

  COMPREPLY=()
  return 0
}

complete -F _setup_aryan_complete setup-aryan
