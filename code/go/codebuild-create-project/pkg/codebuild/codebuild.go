package codebuild

import (
	"codebuild-bitbucket/config"
	"fmt"
	"os"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/codebuild"
)

func Codebuild(projects [][]string) {
	cfg := config.LoadConfig()

	options := session.Options{
		Config: aws.Config{Region: aws.String(cfg.Region)},
	}
	// options.Profile = "void"

	sess, err := session.NewSessionWithOptions(options)
	if err != nil {
		fmt.Println("Got error creating session: ", err)
		os.Exit(1)
	}

	svc := codebuild.New(sess)

	result, err := svc.ListProjects(
		&codebuild.ListProjectsInput{
			SortBy:    aws.String("NAME"),
			SortOrder: aws.String("ASCENDING")})

	if err != nil {
		fmt.Println("Got error listing projects: ", err)
		os.Exit(1)
	}

	for _, p := range result.Projects {
		fmt.Println(*p)
	}

	if cfg.CleanUp == "true" {
		fmt.Println("Cleaning up all CodeBuild projects")
		deleteAllCodeBuildProjects(sess)
	} else {
		for _, project := range projects {
			createCodeBuildProject(sess, project)
		}
	}
}

func createCodeBuildProject(sess *session.Session, project []string) {
	cfg := config.LoadConfig()
	svc := codebuild.New(sess)
	fmt.Println(project)

	input := &codebuild.CreateProjectInput{
		Name: aws.String(project[0]),
		Source: &codebuild.ProjectSource{
			Type:      aws.String(cfg.RepoSource),
			Location:  aws.String(project[2]),
			Buildspec: aws.String(cfg.BuildSpec),
		},
		Environment: &codebuild.ProjectEnvironment{
			ComputeType:    aws.String(cfg.ComputeType),
			Image:          aws.String(cfg.Image),
			Type:           aws.String("LINUX_CONTAINER"),
			PrivilegedMode: aws.Bool(true),
		},
		ServiceRole: aws.String(cfg.ServiceRole),
		Artifacts: &codebuild.ProjectArtifacts{
			Type: aws.String("NO_ARTIFACTS"),
		},
	}

	result, err := svc.CreateProject(input)
	if err != nil {
		fmt.Println("Got error creating project: ", err)
		os.Exit(1)
	}

	fmt.Printf("Created CodeBuild project: %s\n", *result.Project.Name)
}

func deleteAllCodeBuildProjects(sess *session.Session) {
	svc := codebuild.New(sess)

	listProjectsInput := &codebuild.ListProjectsInput{}
	projects, err := svc.ListProjects(listProjectsInput)
	if err != nil {
		fmt.Println("Got error retrieving CodeBuild projects:", err)
		os.Exit(1)
	}

	for _, projectName := range projects.Projects {
		fmt.Printf("Deleting project %s\n", *projectName)
		deleteProjectInput := &codebuild.DeleteProjectInput{
			Name: projectName,
		}
		_, err := svc.DeleteProject(deleteProjectInput)
		if err != nil {
			fmt.Printf("Got error deleting project %s: %s\n", *projectName, err)
		} else {
			fmt.Printf("Successfully deleted project %s\n", *projectName)
		}
	}
}
