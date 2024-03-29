package config

import (
	"os"
	"strings"
)

type Config struct {
	Workspace       string
	User            string
	Password        string
	ExcludeProjects []string
	ServiceRole     string
	RepoSource      string
	BuildSpec       string
	ComputeType     string
	Image           string
	Region          string
	CleanUp         string
}

func LoadConfig() *Config {
	return &Config{

		Workspace:       os.Getenv("WORKSPACE"),
		User:            os.Getenv("USER"),
		Password:        os.Getenv("PASSWORD"),
		ExcludeProjects: strings.Split(os.Getenv("EXCLUDE_PROJECTS"), ","),
		ServiceRole:     os.Getenv("SERVICE_ROLE"),
		RepoSource:      os.Getenv("REPO_SOURCE"),
		BuildSpec:       os.Getenv("BUILD_SPEC"),
		ComputeType:     os.Getenv("COMPUTE_TYPE"),
		Image:           os.Getenv("IMAGE"),
		Region:          os.Getenv("REGION"),
		CleanUp:         os.Getenv("CLEAN_UP"),
	}
}
