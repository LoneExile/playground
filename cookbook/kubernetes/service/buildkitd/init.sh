# git clone https://github.com/FiloSottile/mkcert && cd mkcert
# go build -ldflags "-X main.Version=$(git describe --tags)"
# sudo mv mkcert /usr/local/bin/mkcert
#
./create-certs.sh buildkitd
kuberctl apply -f buildkit-client-certs.yaml
kuberctl apply -f buildkit-daemon-certs.yaml
