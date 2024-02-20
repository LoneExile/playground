package main

import (
	"context"
	"crypto"
	"fmt"
	"os"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/go-acme/lego/v4/certcrypto"
	"github.com/go-acme/lego/v4/certificate"
	"github.com/go-acme/lego/v4/challenge/dns01"
	"github.com/go-acme/lego/v4/lego"
	"github.com/go-acme/lego/v4/providers/dns/cloudflare"
	"github.com/go-acme/lego/v4/registration"
)

// Define a struct to implement the registration.User interface
type MyUser struct {
	Email        string
	Registration *registration.Resource
	Key          crypto.PrivateKey
}

func (u *MyUser) GetEmail() string {
	return u.Email
}

func (u MyUser) GetRegistration() *registration.Resource {
	return u.Registration
}

func (u *MyUser) GetPrivateKey() crypto.PrivateKey {
	return u.Key
}

func main() {
	lambda.Start(HandleRequest)
}

func HandleRequest(ctx context.Context) (string, error) {
	const domain = "" // Replace with your domain
	const email = ""  // Replace with your email

	privateKey, err := certcrypto.GeneratePrivateKey(certcrypto.RSA2048)
	if err != nil {
		return "", err
	}

	myUser := MyUser{Email: email, Key: privateKey}

	config := lego.NewConfig(&myUser)
	config.CADirURL = lego.LEDirectoryProduction
	config.Certificate.KeyType = certcrypto.RSA2048

	client, err := lego.NewClient(config)
	if err != nil {
		return "", err
	}

	reg, err := client.Registration.Register(registration.RegisterOptions{TermsOfServiceAgreed: true})
	if err != nil {
		return "", err
	}
	myUser.Registration = reg

	// Set up Cloudflare DNS provider
	cloudflareConfig := cloudflare.NewDefaultConfig()
	cloudflareConfig.AuthToken = os.Getenv("CLOUDFLARE_API_TOKEN") // Ensure this environment variable is set in your Lambda function
	provider, err := cloudflare.NewDNSProviderConfig(cloudflareConfig)
	if err != nil {
		return "", err
	}

	err = client.Challenge.SetDNS01Provider(provider,
		dns01.AddRecursiveNameservers([]string{"1.1.1.1:53", "1.0.0.1:53"}), // Use Cloudflare's nameservers for DNS resolution
	)
	if err != nil {
		return "", err
	}

	request := certificate.ObtainRequest{
		Domains: []string{domain},
		Bundle:  true,
	}
	certificates, err := client.Certificate.Obtain(request)
	if err != nil {
		return "", err
	}

	fmt.Printf("Certificate obtained: %+v\n", certificates)

	// Implement logic to use certificates (e.g., update Kubernetes secrets)

	return fmt.Sprintf("Successfully obtained certificate for %s", domain), nil
}
