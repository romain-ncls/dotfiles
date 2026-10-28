if status is-interactive
    ############################################################################
    # Prompt, after the RobbyRussell theme

    # You can override some default options in your config.fish:
    #   set -g theme_display_git_untracked no

    function _git_branch_name
        echo (command git symbolic-ref HEAD 2> /dev/null | sed -e 's|^refs/heads/||')
    end

    function _is_git_dirty
        set -l show_untracked (git config --bool bash.showUntrackedFiles)
        set -l untracked
        if [ "$theme_display_git_untracked" = 'no' -o "$show_untracked" = 'false' ]
          set untracked '--untracked-files=no'
        end
        echo (command git status -s --ignore-submodules=dirty $untracked 2> /dev/null)
    end

    # Human-readable duration of the last command, only when it ran > 1s.
    # $CMD_DURATION is set by fish in milliseconds.
    function _cmd_duration
        test -z "$CMD_DURATION"; and return
        test "$CMD_DURATION" -lt 1000; and return

        set -l s (math "floor($CMD_DURATION / 1000)")
        if test $s -ge 3600
            echo (math "floor($s / 3600)")h(math "floor($s % 3600 / 60)")m
        else if test $s -ge 60
            echo (math "floor($s / 60)")m(math "$s % 60")s
        else
            echo (math --scale=1 "$CMD_DURATION / 1000")s
        end
    end

    function fish_prompt
        set -l last_status $status
        set -l cyan (set_color -o cyan)
        set -l yellow (set_color -o yellow)
        set -l red (set_color -o red)
        set -l blue (set_color -o blue)
        set -l green (set_color -o green)
        set -l normal (set_color normal)

        if test $last_status = 0
            set arrow "$green➜ "
        else
            set arrow "$red➜ "
        end
        set -l cwd $cyan(basename (prompt_pwd))

        if [ (_git_branch_name) ]
            set -l git_branch $red(_git_branch_name)
            set git_info "$blue git:($git_branch$blue)"

            if [ (_is_git_dirty) ]
                set -l dirty "$yellow ✗"
                set git_info "$git_info$dirty"
            end
        end

        # Set by kube (work module).
        if test -n "$KUBE_CONTEXT_NAME"
            set kube_context " $blue⎈[$red$KUBE_CONTEXT_NAME$blue]"
        end

        echo -n -s $arrow ' ' $cwd $kube_context $git_info $normal ' '
    end

    function fish_right_prompt
        set -l duration (_cmd_duration)
        test -z "$duration"; and return
        echo -n -s (set_color brblack) $duration (set_color normal)
    end

    set fish_greeting

    ############################################################################

    bind ctrl-c 'cancel-commandline' # see fish:4.0.0 patch notes
    bind alt-backspace backward-kill-word # see fish:4.1.0 patch notes
    bind alt-delete kill-word # see fish:4.1.0 patch notes

    set -x EDITOR "vim"
    set -x BROWSER "brave"
    fish_add_path --append ~/go/bin

    alias ll="eza -lg --sort name --group-directories-first"
    alias l="ll -a"
    alias tree="eza --tree --sort name --group-directories-first"

    alias cat="bat -Pp --theme TwoDark"
    alias bat="bat --paging=always --theme TwoDark"
    abbr hex hexdump -C
    abbr bin hexdump -C

    # This file is installed by lodestar: edit it in the repo.
    alias rc="code ~/dotfiles/modules/shell/home/.config/fish/config.fish"

    alias fzf-preview="fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'"
    alias vzf="vim \$(fzf-preview)"

    abbr doc docker compose

    # Konsole's colors back to normal after a session that changed them.
    function ssh
        command ssh -oPermitLocalCommand=yes $argv
        konsoleprofile colors=Nalthis
    end

    # A bare number is a host on the home network: `42` is ssh root@192.168.1.42.
    function fish_command_not_found
        if echo "$argv[1]" | string match -r '^[0-9]{0,3}$' > /dev/null
            ssh root@192.168.1.$argv[1]
        else
            echo "fish: Unknown command: $argv[1]" >&2
            return 127
        end
    end

    function rmknownhost
        if test -z "$argv[1]"
            echo "Usage: rmknownhost <host>"
            return 1
        end
        sed -i "/^$argv[1]/d" ~/.ssh/known_hosts
    end

    # Ask for a variable and export it; sreadenv doesn't echo what is typed.
    function readenv -a var
        read --global --export --prompt-str "$var: " $var
    end

    function sreadenv -a var
        read --global --export --silent --prompt-str "$var: " $var
    end

    # Unlock Bitwarden for this shell; locked again when the shell exits.
    function bwu
        function lock-bw-sessions --on-event fish_exit
            bw lock &>/dev/null &
        end

        set -gx BW_SESSION "$(bw unlock --raw)"
    end
end
