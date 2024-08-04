# Elixir starter

## Installation

```bash
## Create a new project
mix new cards

## Run the tests
# iex stands for Interactive Elixir
# -S flag is used to run the mix tasks
iex -S mix
# Run the tests
> Cards.hello

```

## Add a new dependency

- [ExDoc](https://github.com/elixir-lang/ex_doc)

```bash
## Add a new dependency
# Add the dependency to the mix.exs file
defp deps do
  [
    {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    {:excoveralls, "~> 0.18", only: :test},
  ]
end

## Fetch the dependency
mix deps.get

## Generate the documentation
mix docs

## Run the tests
mix test
MIX_ENV=test mix coveralls
```
