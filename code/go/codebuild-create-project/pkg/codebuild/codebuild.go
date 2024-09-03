package codebuild

import (
	gconf "codebuild-bitbucket/config"
	"context"
	"fmt"
	"log"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"

	// "github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/codebuild"
	"github.com/aws/aws-sdk-go-v2/service/codebuild/types"
)

var conf = gconf.LoadConfig()

func UpdateCodeBuildConfig() {
	cfg, err := config.LoadDefaultConfig(context.TODO())
	// cfg, err := config.LoadDefaultConfig(context.TODO(),
	// 	config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider("", "", "")),
	// 	config.WithRegion("ap-southeast-1"),
	// )
	if err != nil {
		log.Fatalf("Unable to load SDK config: %v", err)
	}

	svc := codebuild.NewFromConfig(cfg)

	if svc == nil {
		log.Fatalf("Unable to create Codebuild service")
	}
	projects, err := ListAllCodeBuildProjects(svc)
	if err != nil {
		log.Fatalf("Unable to list Codebuild projects")
	}
	fmt.Println(projects)
	for _, project := range projects {
		UpdateOrAddProjectTag(svc, project, conf.Tag)
	}
}

func separateTag(tag string) (string, string, error) {
	parts := strings.Split(tag, ":")
	if len(parts) != 2 {
		return "", "", fmt.Errorf("invalid tag format")
	}
	return parts[0], parts[1], nil
}

func UpdateOrAddProjectTag(svc *codebuild.Client, projectName string, tag string) {
	tagKey, tagValue, err := separateTag(tag)
	if err != nil {
		log.Fatalf("Failed to separate tag: %v", err)
	}

	input := &codebuild.UpdateProjectInput{
		Name: &projectName,
		Tags: []types.Tag{
			{
				Key:   aws.String("Name"),
				Value: aws.String(projectName),
			},
			{
				Key:   aws.String(tagKey),
				Value: aws.String(tagValue),
			},
		},
	}

	_, err = svc.UpdateProject(context.TODO(), input)
	if err != nil {
		log.Fatalf("Failed to update project tags: %v", err)
	}

	fmt.Printf("Successfully updated/added tag 'name:%s' to project '%s'\n", projectName, projectName)
}

func ListAllCodeBuildProjects(svc *codebuild.Client) ([]string, error) {
	var projects []string

	input := &codebuild.ListProjectsInput{}

	for {
		result, err := svc.ListProjects(context.TODO(), input)
		if err != nil {
			return nil, err
		}

		projects = append(projects, result.Projects...)

		if result.NextToken == nil {
			break
		}
		input.NextToken = result.NextToken
	}

	return projects, nil
}

func Codebuild(projects [][]string) {
	cfg, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		log.Fatalf("Unable to load SDK config: %v", err)
	}

	svc := codebuild.NewFromConfig(cfg)

	if svc == nil {
		log.Fatalf("Unable to create S3 service")
	}

	if conf.CleanUp == "true" {
		fmt.Println("Cleaning up all CodeBuild projects")
		deleteAllCodeBuildProjects(svc)
	} else {
		for _, project := range projects {
			createCodeBuildProject(svc, project)
		}
	}
}

func createCodeBuildProject(svc *codebuild.Client, project []string) {
	fmt.Println(project)

	input := &codebuild.CreateProjectInput{
		Name: aws.String(project[0]),
		Source: &types.ProjectSource{
			Type:      types.SourceType(conf.RepoSource),
			Location:  aws.String(project[2]),
			Buildspec: aws.String(conf.BuildSpec),
		},
		Environment: &types.ProjectEnvironment{
			ComputeType:    types.ComputeType(conf.ComputeType),
			Image:          aws.String(conf.Image),
			Type:           types.EnvironmentTypeLinuxContainer,
			PrivilegedMode: aws.Bool(true),
		},
		ServiceRole: aws.String(conf.ServiceRole),
		Artifacts: &types.ProjectArtifacts{
			Type: types.ArtifactsTypeNoArtifacts,
		},
	}

	ctx := context.TODO()

	result, err := svc.CreateProject(ctx, input)
	if err != nil {
		fmt.Println("Got an error creating project: ", err)
		return
	}

	fmt.Printf("Created CodeBuild project: %s\n", *result.Project.Name)
}

func deleteAllCodeBuildProjects(svc *codebuild.Client) {

	input := &codebuild.ListProjectsInput{}

	for {
		result, err := svc.ListProjects(context.TODO(), input)
		fmt.Println("Projects:", result.Projects)
		if err != nil {
			log.Fatalf("Failed to list projects, %v", err)
		}

		for _, projectName := range result.Projects {
			fmt.Println("Project Name:", projectName)
			deleteProjectInput := &codebuild.DeleteProjectInput{
				Name: aws.String(projectName),
			}
			_, err := svc.DeleteProject(context.TODO(), deleteProjectInput)
			if err != nil {
				fmt.Printf("Got error deleting project %s: %s\n", *aws.String(projectName), err)
			} else {
				fmt.Printf("Successfully deleted project %s\n", *aws.String(projectName))
			}
		}

		if result.NextToken == nil {
			break
		}
		input.NextToken = result.NextToken
	}
}
