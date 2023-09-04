package main

import (
	"context"
	"fmt"
	"github.com/aws/aws-lambda-go/events"
	"github.com/google/go-github/v54/github"
	"regexp"
)

type Config struct {
	GithubClient *github.Client
}

func RouteHandlers(config Config) map[string]LambdaFunc {
	return map[string]LambdaFunc{
		// Download provider version
		// `/v1/providers/{namespace}/{type}/{version}/download/{os}/{arch}`
		"^/v1/providers/[^/]+/[^/]+/[^/]+/download/[^/]+/[^/]+$": downloadProviderVersion(config),

		// List provider versions
		// `/v1/providers/{namespace}/{type}`
		"^/v1/providers/[^/]+/[^/]+/versions$": listProviderVersions(config),
	}
}

func getRouteHandler(config Config, path string) LambdaFunc {
	// We will replace this with some sort of actual router (chi, gorilla, etc)
	// for now regex is fine
	for route, handler := range RouteHandlers(config) {
		if match, _ := regexp.MatchString(route, path); match {
			return handler
		}
	}
	return nil
}

func Router(config Config) LambdaFunc {
	return func(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
		fmt.Printf("Request: %+v\n", req)
		fmt.Printf("Path: %s\n", req.Path)
		handler := getRouteHandler(config, req.Path)
		if handler == nil {
			return events.APIGatewayProxyResponse{StatusCode: 404}, nil
		}

		return handler(ctx, req)
	}
}