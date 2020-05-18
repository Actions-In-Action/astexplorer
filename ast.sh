#! /bin/bash

source "./assert.sh/assert.sh"

# check env
assert_not_empty "${SECRETS_PUSH_URL}"              "PUSH_URL"
assert_not_empty "${SECRETS_GITEE_USERNAME}"        "GITEE_USERNAME"
assert_not_empty "${SECRETS_GITEE_CLIENT_ID}"       "GITEE_CLIENT_ID"
assert_not_empty "${SECRETS_GITEE_CLIENT_SECRET}"   "GITEE_CLIENT_SECRET"
assert_not_empty "${SECRETS_GITEE_PASSWORD}"        "GITEE_PASSWORD"


echo "fetching the latest build commit of fkling/astexplorer"
# github_latest_commit=$(curl --silent "https://gitlab.com/fkling42/astexplorer/pipelines.json?scope=all&page=1" | jq ".pipelines[] | select(.flags.latest == true and .details.status.text == \"passed\") | .commit.id" | grep -oP "[a-f\d]+")
github_latest_commit=$(curl -s -H "accept: application/json" -H "travis-api-version: 3" "https://api.travis-ci.org/repo/3312963/builds?event_type=push%2Capi%2Ccron&repository_id=3312963&skip_count=true&include=build.commit%2Cbuild.branch%2Cbuild.request%2Cbuild.created_by%2Cbuild.repository" | jq ".builds | map(select(.state == \"passed\"))[0] | .commit.sha" | grep -oP "[a-f\d]+")
if [ -z "${github_latest_commit}" ]; then
    echo "fetch the latest build commit of fkling/astexplorer failed"

    exit 1
fi
echo "the latest build commit of fkling/astexplorer is ${github_latest_commit}"


echo "checking gitee tag"
if ! gitee_tag=$(curl --silent -X GET --header 'Content-Type: application/json;charset=UTF-8' "https://gitee.com/api/v5/repos/${SECRETS_GITEE_USERNAME}/ast/tags"); then
    echo "checking gitee tag failed"

    exit 1    
fi

if ! [[ "${gitee_tag}" =~ '"commit"' ]]; then
    echo "checking gitee tag failed"

    exit 1 
fi  

gitee_tag=$(echo "${gitee_tag}" | grep -oP "(?<=\")${github_latest_commit}(?=\")")
if [ "${gitee_tag}" = "${github_latest_commit}" ]; then
    echo "gitee tag ${gitee_tag} already synced"

    exit 0
fi
echo "begin to sync ${github_latest_commit}"


echo "cloning github repo"
git clone https://github.com/fkling/astexplorer --depth 100
git checkout "${github_latest_commit}"
echo "installing deps"
cd astexplorer/website || exit 1
yarn install
echo "building"
yarn run build
cd ../..


git config --global http.postbuffer 524288000

echo "cloning gitee repo"
git clone "https://gitee.com/${SECRETS_GITEE_USERNAME}/ast.git"
cd ast || exit 1

git config user.name "${SECRETS_GITEE_USERNAME}"

rm ./*.js
rm ./*.txt
rm ./*.svg
rm ./*.wasm
rm ./*.ttf
rm ./*.woff
rm ./*.woff2
rm ./*.css
rm ./*.eot
rm ./*.html
rm ./*.png

cp ../astexplorer/out/* ./

# log something to enable git push everytime...
echo "${github_latest_commit} $(date "+%Y-%m-%d %H:%M:%S")" >> mylog.log

git add .
git commit -m "${github_latest_commit}"


echo "git push to gitee"
if ! git push --repo "https://${SECRETS_GITEE_USERNAME}:${SECRETS_GITEE_PASSWORD}@gitee.com/${SECRETS_GITEE_USERNAME}/ast.git"; then
    echo "git push to gitee failed"

    exit 1
fi

echo "wait 5 seconds after push"
sleep 5


echo "requesting gitee access token"
SECRETS_GITEE_ACCESS_TOKEN=$(curl --silent -X POST --data-urlencode "grant_type=password" --data-urlencode "username=${SECRETS_GITEE_USERNAME}" --data-urlencode "password=${SECRETS_GITEE_PASSWORD}" --data-urlencode "client_id=${SECRETS_GITEE_CLIENT_ID}" --data-urlencode "client_secret=${SECRETS_GITEE_CLIENT_SECRET}" --data-urlencode "scope=projects" https://gitee.com/oauth/token |  grep -oP '(?<="access_token":")[\da-f]+(?=")')
if [ "${SECRETS_GITEE_ACCESS_TOKEN}" = "" ]; then
    echo "request gitee access token failed"

    exit 1
fi


echo "rebuilding gitee pages"
rebuild_result=$(curl --silent -X POST --header 'Content-Type: application/json;charset=UTF-8' "https://gitee.com/api/v5/repos/${SECRETS_GITEE_USERNAME}/ast/pages/builds" -d "{\"access_token\":\"${SECRETS_GITEE_ACCESS_TOKEN}\"}")
if [ "$(echo "${rebuild_result}"  | grep -oP "(?<=\")queued(?=\")")" != "queued" ]; then
    echo "rebuild gitee pages failed: ${rebuild_result}"

    exit 1         
fi


echo "git push new tag to gitee"
git tag -a "${github_latest_commit}" -m "${github_latest_commit}"
if ! git push --repo "https://${SECRETS_GITEE_USERNAME}:${SECRETS_GITEE_PASSWORD}@gitee.com/${SECRETS_GITEE_USERNAME}/ast.git" --tags; then
    echo "git push new tag to gitee failed"
  
    exit 1
fi


# notify me
echo -e "$(date "+%Y-%m-%d %H:%M:%S")\n\
${GITHUB_REPOSITORY}\n\
${github_latest_commit} sync done." | curl --silent -X POST "${SECRETS_PUSH_URL}" --data-binary @- 
