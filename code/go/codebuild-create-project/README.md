# Lambda Create Codebuild Project

## Description

Get list of all projects in bitbucket and create codebuild project for each project

## Prerequisites

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "{ YOUR_SERVICE_ROLE }"
        }
    ]
}
```
