package bitbucket

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

type Links struct {
	Html Link `json:"html"`
}

type Link struct {
	Href string `json:"href"`
}

type Repositories struct {
	Values []struct {
		Name string `json:"name"`
		Lang string `json:"language"`
		Link Links  `json:"links"`
	} `json:"values"`
}

type Pagination struct {
	Next string `json:"next"`
}

func FetchPage(url, user, password string) ([][]string, string, error) {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, "", fmt.Errorf("error creating request: %w", err)
	}

	req.SetBasicAuth(user, password)
	req.Header.Add("Content-Type", "application/json")

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, "", fmt.Errorf("error sending request to server: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, "", fmt.Errorf("error reading response body: %w", err)
	}

	var repos Repositories
	if err := json.Unmarshal(body, &repos); err != nil {
		return nil, "", fmt.Errorf("error unmarshaling repositories JSON: %w", err)
	}

	var pagination Pagination
	if err := json.Unmarshal(body, &pagination); err != nil {
		return nil, "", fmt.Errorf("error unmarshaling pagination JSON: %w", err)
	}

	var projects [][]string
	for _, repo := range repos.Values {

		// if repo.Lang == "" {
		// 	continue
		// }
		projects = append(projects, []string{repo.Name, repo.Lang, repo.Link.Html.Href})
	}

	return projects, pagination.Next, nil
}
