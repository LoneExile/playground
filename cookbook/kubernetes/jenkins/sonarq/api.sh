# https://sonarcloud.io/web_api/api/

TOKEN=""

curl -X POST --header "Authorization: Bearer $TOKEN" "https://sonar.apinant.dev/api/projects/create?project=hello&name=world"

curl -X GET --header "Authorization: Bearer $TOKEN" "https://sonar.apinant.dev/api/projects/search?projects=hello"
