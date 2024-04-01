package main

import (
	"codebuild-bitbucket/config"
	"codebuild-bitbucket/pkg/bitbucket"
	"codebuild-bitbucket/pkg/codebuild"

	"fmt"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

// func main() {

// 	cfg := config.LoadConfig()
// 	baseUrl := fmt.Sprintf("https://api.bitbucket.org/2.0/repositories/%s/", cfg.Workspace)

// 	var allRepoNames [][]string

// 	for url := baseUrl; url != ""; {
// 		projects, next, err := bitbucket.FetchPage(url, cfg.User, cfg.Password)
// 		if err != nil {
// 			fmt.Println(err)
// 		}
// 		allRepoNames = append(allRepoNames, projects...)
// 		url = next
// 	}

// 	for i := 0; i < len(allRepoNames); i++ {
// 		for _, exclude := range cfg.ExcludeProjects {
// 			if allRepoNames[i][0] == exclude {
// 				allRepoNames = append(allRepoNames[:i], allRepoNames[i+1:]...)
// 				i--
// 				break
// 			}
// 		}
// 	}

// 	codebuild.Codebuild(allRepoNames)
// }

func main() {
	lambda.Start(handler)
}

func handler(request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	errorResponse := events.APIGatewayProxyResponse{
		Body:       "Error getting kube client\n",
		StatusCode: 500,
	}

	cfg := config.LoadConfig()
	baseUrl := fmt.Sprintf("https://api.bitbucket.org/2.0/repositories/%s/", cfg.Workspace)

	var allRepoNames [][]string

	for url := baseUrl; url != ""; {
		projects, next, err := bitbucket.FetchPage(url, cfg.User, cfg.Password)
		if err != nil {
			fmt.Println(err)
			return errorResponse, err
		}
		allRepoNames = append(allRepoNames, projects...)
		url = next
	}

	for i := 0; i < len(allRepoNames); i++ {
		for _, exclude := range cfg.ExcludeProjects {
			if allRepoNames[i][0] == exclude {
				allRepoNames = append(allRepoNames[:i], allRepoNames[i+1:]...)
				i--
				break
			}
		}
	}

	codebuild.Codebuild(allRepoNames)

	return events.APIGatewayProxyResponse{
		Body:       "Success\n",
		StatusCode: 200,
	}, nil
}
