package main

import (
	"net/http"
	
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
)

// Response represents the structure of our API response
type Response struct {
	Status  string `json:"status"`
	Message string `json:"message"`
	Version string `json:"version"`
}

const (
	apiVersion = "2.0.0"
)

func main() {
	// Create a new Echo instance
	e := echo.New()
	
	// Add middleware
	e.Use(middleware.Logger())
	e.Use(middleware.Recover())
	
	// Define routes
	e.GET("/status", getStatus)
	
	// Start server
	e.Logger.Fatal(e.Start(":8080"))
}

// getStatus handles the status endpoint
func getStatus(c echo.Context) error {
	response := Response{
		Status:  "success",
		Message: "API is running",
		Version: apiVersion,
	}
	
	return c.JSON(http.StatusOK, response)
}
