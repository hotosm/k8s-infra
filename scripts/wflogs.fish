# Archived step logs for a finished Argo workflow.
#
# `argo logs` streams live pods only, so it returns nothing once podGC deletes
# them. These come from the artifact repository instead (see
# apps/scaleodm/helm/values.yaml -> argo.artifactRepository).
#
# Needs only kubectl and curl: the S3 credentials are the ones the workflow
# archived with, read from the cluster, so there is no aws CLI or local profile.
#
# Namespace defaults to the current kubectl context. Overrides:
# ARGO_LOGS_BUCKET, ARGO_LOGS_REGION.
#
#   ln -s (pwd)/scripts/wflogs.fish ~/.config/fish/functions/wflogs.fish
#   wflogs geotiff-dd4fd29b-17af-4608-a705-1e7939628119
#
# ./argo-workflow-logs.sh is the same thing for bash.

function wflogs --description 'Print archived Argo step logs for a finished workflow'
    if test (count $argv) -eq 0
        echo "usage: wflogs <workflow-name> [namespace]" >&2
        return 1
    end

    set -l bucket $ARGO_LOGS_BUCKET
    test -n "$bucket"; or set bucket hotosm-argo-logs
    set -l region $ARGO_LOGS_REGION
    test -n "$region"; or set region us-east-1

    set -l ns $argv[2]
    test -n "$ns"; or set ns (kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null)
    test -n "$ns"; or set ns oam-staging

    set -l creds (kubectl -n $ns get secret argo-logs-s3-creds \
        -o jsonpath='{.data.AWS_ACCESS_KEY_ID}{"\n"}{.data.AWS_SECRET_ACCESS_KEY}' 2>/dev/null)
    if test (count $creds) -lt 2
        echo "No argo-logs-s3-creds in namespace $ns" >&2
        return 1
    end
    # Passed to curl on stdin, not argv, so it stays out of ps.
    set -l config "user = \""(string join : (echo $creds[1] | base64 -d) (echo $creds[2] | base64 -d))"\""

    set -l sigv4 "aws:amz:$region:s3"
    set -l host "$bucket.s3.$region.amazonaws.com"
    set -l prefix "$ns/$argv[1]/"

    # Lexicographic from S3, which groups the steps by name.
    set -l listing (echo $config | curl -sS --aws-sigv4 $sigv4 -K - \
        "https://$host/?list-type=2&prefix=$prefix")
    set -l failure (string match -rg '<Code>([^<]+)</Code>' -- $listing)
    if test -n "$failure"
        echo "S3 refused the listing: $failure" >&2
        return 1
    end
    set -l keys (string match -rag '<Key>([^<]+)</Key>' -- $listing)
    if test (count $keys) -eq 0
        echo "No archived logs under s3://$bucket/$prefix" >&2
        echo "Check the namespace, or that log archiving was on for that run." >&2
        return 1
    end

    # One curl for every object, so the connection is reused; each URL is signed.
    set -l workdir (mktemp -d)
    set -l fetch
    for i in (seq (count $keys))
        set -a fetch "https://$host/$keys[$i]" -o "$workdir/$i"
    end
    echo $config | curl -sS --aws-sigv4 $sigv4 -K - $fetch

    for i in (seq (count $keys))
        set -l parts (string split / $keys[$i])
        echo "===== $parts[-2] ====="
        set -l body (cat $workdir/$i 2>/dev/null)
        set -l denied (string match -rg '<Code>([^<]+)</Code>' -- "$body")
        if test -n "$denied"
            echo "(S3 refused this object: $denied)" >&2
        else
            printf '%s\n' $body
        end
        echo
    end
    rm -rf $workdir
end
