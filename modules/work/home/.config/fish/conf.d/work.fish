if status is-interactive
    set -x PPROF_TMPDIR "/tmp/pprof"

    function tenants
        cd ~/git/infra
        just list-tenants $argv
        cd -
    end
    alias clients="tenants -e prod"
    alias demos="tenants -e dev/demo"

    alias mr="~/scripts/merge-request.ts"

    function deploy
        switch (pwd)
            case ~/git/soeman
                ./.gitlab/ci/deploy.sh $argv
            case ~/git/customFuncs
                ./deploy.sh $argv
            case ~/git/installerSH
                ./deploy.sh $argv
            case '*'
                echo "Unknown directory: (pwd)" >&2
                return 1
        end
    end

    set -x CLONE_TENANT_CONFIG ~/git/legacy-scripts/clone-tenant/config.json
    alias clone-tenant="~/git/legacy-scripts/clone-tenant/clone-tenant.ts"
    alias clone="clone-tenant"

    alias token="~/scripts/token.ts"

    function phpc
        docker run -it --rm -v (pwd):/app local/php bash
    end

    # A Markdown list from stdin to the clipboard, indented with tabs for a
    # mind map.
    function mdm
        set lines (cat)
        set lines (echo $lines | sed -e 's/    /\t/g')
        set lines (echo $lines | sed -e 's/- //g')
        echo $lines | wl-copy
    end
    alias mind="mdm"
    alias mindmd="mdm"
    alias mdmind="mdm"

    function next-ports
        echo "5173" (set_color brblack) "# frontend" (set_color normal)
        echo "3000" (set_color brblack) "# api" (set_color normal)
        echo "4433" (set_color brblack) "# kratos api" (set_color normal)
        echo "4455" (set_color brblack) "# kratos ui" (set_color normal)
        echo "5432" (set_color brblack) "# postgres" (set_color normal)
        echo "16686" (set_color brblack) "# jaeger" (set_color normal)
    end

    abbr k kubectl

    # A shell on a cluster, in its own Konsole colors: kube <context> [<colors>]
    # uses ~/.kube/configs/<context>.
    function kube -a config newColors
        set previousColors $KONSOLE_CURRENT_COLORS
        test -z "$previousColors" && set previousColors DarkOneNuanced
        test -z "$newColors" && set newColors DarkOneBlue

        if test -z "$config"
            echo "Usage: kube <context-name> [<konsole-color-profile>]" >&2
            return 1
        end

        set kubeConfigPath $HOME/.kube/configs/$config

        konsoleprofile colors=$newColors
        env KONSOLE_CURRENT_COLORS=$newColors KUBE_CONTEXT_NAME=$config KUBECONFIG=$kubeConfigPath fish
        konsoleprofile colors=$previousColors
    end
end
